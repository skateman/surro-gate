# frozen_string_literal: true

module SurroGate
  class Pair
    attr_reader :left, :right

    def initialize(left, right)
      @left = left
      @right = right
      @rd_rdy = @wr_rdy = false
    end

    def ready?
      @rd_rdy && @wr_rdy || @left.closed? || @right.closed?
    end
  end
end
