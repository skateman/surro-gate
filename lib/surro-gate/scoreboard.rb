require 'thread'

module SurroGate
  class Scoreboard
    def initialize
      @rd = {}
      @wr = {}

      @lock = Mutex.new
    end

    def push(left, right)
      left_to_right = Pair.new(left, right)
      right_to_left = Pair.new(right, left)

      @lock.synchronize do
        @rd[left] = left_to_right
        @wr[right] = left_to_right

        @rd[right] = right_to_left
        @wr[left] = right_to_left
      end

      [left, right]
    end

    def pop(left, right)
      @lock.synchronize do
        @rd.delete(left)
        @rd.delete(right)
        @wr.delete(left)
        @wr.delete(right)
      end

      [left, right]
    end

    def mark_rd(sock)
      @rd[sock].mark_rd
    end

    def mark_wr(sock)
      @wr[sock].mark_wr
    end

    def marked_rd?(sock)
      @rd[sock].marked_rd?
    end

    def marked_wr?(sock)
      @wr[sock].marked_wr?
    end

    def unmark(sock)
      @rd[sock].unmark
    end

    def include?(sock)
      @rd.key?(sock) || @wr.key?(sock)
    end

    def each(&block)
      @rd.values.each(&block)
    end

    def inverse(pair)
      @wr[pair.left]
    end
  end
end
