require 'nio'

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
    def initialize
      @mutex = Mutex.new
      @selector = NIO::Selector.new
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
      # Pass boths sockets to the Nio4r selector
      monitors = [left, right].map { |socket| @selector.register(socket, :rw) }

      # Set up handlers for both monitors
      monitors.each do |src|
        # Get the destination paired with the source
        dst = monitors.reject { |m| m == src }.first
        # Set up a proc for future transmissions
        src.value = proc do
          # Clean up the connection if one of the endpoints gets closed
          cleanup(src.io, dst.io, &block) if src.io.closed? || dst.io.closed?
          # Do the transmission and return with the bytes transferred
          transmit(src.io, dst.io, block) if src.readable? && dst.writable?
        end
      end

      # Make sure that the internal thread is started
      thread_start unless @selector.empty?
    end

    def transmit(src, dst, block)
      dst.write_nonblock(src.read_nonblock(4096))
    rescue # Clean up both sockets if something bad happens
      cleanup(src, dst, &block)
    end

    def cleanup(*sockets)
      # Deregister and close the sockets
      sockets.each do |socket|
        @selector.deregister(socket) if @selector.registered?(socket)
        socket.close unless socket.closed?
      end

      yield if block_given?

      # Make sure that the internal thread is stopped if no sockets remain
      thread_stop if @selector.empty?
    end

    def thread_start
      @thread ||= Thread.new do
        loop do
          reactor
        end
      end
    end

    def thread_stop
      return if @thread.nil?
      thread = @thread
      @thread = nil
      thread.kill
    end

    def reactor
      # Atomically get an array of readable/writable monitors
      monitors = @mutex.synchronize { @selector.select(0.1) || [] }
      # Call each transmission proc and collect the results
      callers = monitors.map { |m| m.value.call }
      # Sleep for a short time if there was no transmission
      sleep(0.1) if callers.none? && monitors.any?
    end

    def includes?(*sockets)
      sockets.map { |socket| @selector.registered?(socket) }.any?
    end
  end
end
