# frozen_string_literal: true

module SurroGate
  class Pair
    attr_reader :left, :right

    def initialize(left, right)
      @left = left
      @right = right
      unmark
    end

    def ready?
      @rd_rdy && @wr_rdy || @left.closed? || @right.closed?
    end

    def marked_rd?
      @rd_rdy
    end

    def marked_wr?
      @wr_rdy
    end

    def mark_rd
      @rd_rdy = true
    end

    def mark_wr
      @wr_rdy = true
    end

    def unmark
      @rd_rdy = @wr_rdy = false
    end
  end
end
