require 'celluloid/current'
require 'celluloid/io'
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
    include Celluloid::IO

    def initialize(logger)
      @log = logger || ::Logger.new(STDOUT)
    end

    # Registers a pair of socket for proxying.
    #
    # It also forks the internal thread if it is not running yet.
    #
    # @param left [SurroGate::Connection]
    # @param right [SurroGate::Connection]
    # @yield The block responsible for additional cleanup
    # @return the registered socket pair as an array
    def push(left, right, &block)
      @log.info("Connecting #{left} <-> #{right}")

      async.proxy(left, right)
      async.proxy(right, left, block)
    end

    private

    def proxy(left, right, block = nil)
      loop { left.write(right.read) }
    rescue EOFError
      @log.info("Disconnection between #{left} <-> #{right}")
      cleanup(left, right, &block)
    rescue => ex
      @log.error(ex)
      cleanup(left, right, &block)
    end

    def cleanup(*sockets)
      # Close the sockets and call the cleanup block
      sockets.each { |socket| socket.close unless socket.closed? }
      yield if block_given?
    end
  end
end
