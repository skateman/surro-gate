require 'nio'
require 'logger'

module SurroGate
  # This class is responsible for connecting TCP socket pairs and proxying between them.
  #
  # It uses a lazily-forked thread to handle the non blocking read and write operations.
  # If one of the sockets get closed, the proxy automatically cleans up by deregistering
  # and closing its pair. When the last socket pair gets cleaned up, the internal thread
  # is killed automatically.
  #
  # The proxy was designed to be highly reusable and it can handle multiple socket pairs.
  class Proxy
    def initialize(logger)
      @mutex = Mutex.new
      @reader = NIO::Selector.new
      @writer = NIO::Selector.new
      @selectors = [@reader, @writer]
      @log = logger || Logger.new(STDOUT)
    end

    # Registers a pair of socket for proxying.
    #
    # It also forks the internal thread if it is not running yet.
    #
    # @raise [ProxyError] when at least one of the pushed sockets is already registered
    # @param left [TCPSocket]
    # @param right [TCPSocket]
    # @yield The block responsible for additional cleanup
    # @return the registered socket pair as an array
    def push(left, right, &block)
      raise ProxyError, 'Socket already handled by the proxy' if includes?(left, right)

      @log.info("Connecting #{left} <-> #{right}")

      @mutex.synchronize do
        proxy(left, right, block)
      end

      [left, right]
    end

    # Blocking wait until the internal thread is doing something useful.
    def wait
      @thread.join if alive?
    end

    # Determine if the internal thread is currently running or not.
    def alive?
      !@thread.nil? && @thread.alive?
    end

    private

    def proxy(left, right, block = nil)
      # Register the proxying in both directions
      [[left, right], [right, left]].each do |rd, wr|
        # Set up monitors for read/write separately
        src = @reader.register(rd, :r)
        dst = @writer.register(wr, :w)

        # Set up handlers for the reader monitor
        src.value = proc do
          # Clean up the connection if one of the endpoints gets closed
          cleanup(src.io, dst.io, &block) if src.io.closed? || dst.io.closed?
          # Do the transmission and return with the bytes transferred
          transmit(src.io, dst.io, block) if src.readable? && dst.writable?
        end
      end

      thread_start unless @reader.empty? || @writer.empty?
    end

    def transmit(src, dst, block)
      dst.write_nonblock(src.read_nonblock(4096))
    rescue # Clean up both sockets if something bad happens
      @log.warn("Transmission failure between #{src} <-> #{dst}")
      cleanup(src, dst, &block)
    end

    def cleanup(*sockets)
      # Deregister and close the sockets
      sockets.each do |socket|
        @selectors.each { |selector| selector.deregister(socket) if selector.registered?(socket) }
        socket.close unless socket.closed?
      end

      @log.info("Disconnecting #{sockets.join(' <-> ')}")

      yield if block_given?

      # Make sure that the internal thread is stopped if no sockets remain
      thread_stop if @reader.empty? && @writer.empty?
    end

    def thread_start
      @log.debug('Starting the internal thread')
      @thread ||= Thread.new do
        loop do
          reactor
        end
      end
    end

    def thread_stop
      return if @thread.nil?
      @log.debug('Stopping the internal thread')
      thread = @thread
      @thread = nil
      thread.kill
    end

    def reactor
      # Atomically get an array of readable monitors while also polling for writables
      monitors = @mutex.synchronize do
        @writer.select(0.1)
        @reader.select(0.1) || []
      end
      # Call each transmission proc and collect the results
      monitors.map { |m| m.value.call }
    end

    def includes?(*sockets)
      sockets.any? do |socket|
        @selectors.any? { |selector| selector.registered?(socket) }
      end
    end
  end
end
