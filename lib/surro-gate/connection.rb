require 'celluloid/current'
require 'celluloid/io'

module SurroGate
  class Connection
    include Celluloid::IO

    def initialize(socket, blocksize = 4096)
      @socket = TCPSocket.new(socket)
      @bs = blocksize
    end

    def read
      @socket.readpartial(@bs)
    end

    def write(data)
      @socket.write(data)
    end

    def close
      @socket.close
    end

    def closed?
      @socket.closed?
    end
  end
end
