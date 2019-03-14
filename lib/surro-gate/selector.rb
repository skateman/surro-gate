# frozen_string_literal: true

require 'surro-gate/pair'
require 'concurrent'

module SurroGate
  class Selector
    def initialize(logger)
      @logger = logger

      @pairing = Concurrent::Array.new
      @sockets = Concurrent::Array.new
      @reads = Concurrent::Array.new
      @writes = Concurrent::Array.new

      @mutex = Mutex.new
    end

    def push(left, right)
      raise TypeError unless left.is_a?(IO) && right.is_a?(IO)
      raise ArgumentError if @pairing.detect { |pair| [left, right].include?(pair.left) || [left, right].include?(pair.right) }

      left_to_right = SurroGate::Pair.new(left, right)
      right_to_left = SurroGate::Pair.new(right, left)

      # The method can be called from a different thread
      @mutex.synchronize do
        @pairing.push(left_to_right, right_to_left)

        @sockets.push(left, right)
        @reads.push(left, right)
        @writes.push(left, right)
      end

      true
    end

    def pop(*sockets)
      [@sockets, @reads, @writes].each do |arr|
        arr.delete_if { |sock| sockets.include?(sock) }
      end

      @pairing.delete_if { |pair| pairing_compare(pair, sockets) }

      nil
    end

    def select(timeout)
      begin
        read, write, error = @mutex.synchronize { IO.select(@reads, @writes, @sockets, timeout * 0.001) }
      rescue IOError
        # One of the sockets is closed, Pair#ready? will catch it
      end

      error.to_a.each do
        ltr = find_pairing(sock, :left)
        rtl = find_pairing(sock, :right)

        [ltr, rtl].each do |pair|
          %i[@rd_rdy @wr_rdy].each do |ivar|
            pair.instance_variable_set(ivar, true)
          end
        end
      end

      read.to_a.each do |sock|
        @reads.delete(sock)
        find_pairing(sock, :left).instance_variable_set(:@rd_rdy, true)
      end

      write.to_a.each do |sock|
        @writes.delete(sock)
        find_pairing(sock, :right).instance_variable_set(:@wr_rdy, true)
      end

      read.to_a.length + write.to_a.length
    end

    def each_ready
      @pairing.each do |pair|
        next unless pair.ready?

        yield(pair.left, pair.right)

        pair.instance_variable_set(:@rd_rdy, false)
        pair.instance_variable_set(:@wr_rdy, false)

        @reads.push(pair.left)
        @writes.push(pair.right)
      end
    end

    private

    def find_pairing(sock, direction)
      @pairing.find { |pair| pair.send(direction) == sock }
    end

    def pairing_compare(pair, sockets)
      sockets.any? do |sock|
        pair.left == sock || pair.right == sock
      end
    end
  end
end
