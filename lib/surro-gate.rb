# frozen_string_literal: true

require 'surro-gate/version'

begin
  require 'surro-gate/selector_ext'
rescue LoadError, NameError # Fall back to IO#select if epoll isn't available
  require 'surro-gate/selector'
end

# A generic purrpose TCP-to-TCP proxy selector
module SurroGate
  class << self
    # Initializes a new Selector instance
    # @return [SurroGate::Selector]
    def new(logger = nil)
      SurroGate::Selector.new(logger)
    end
  end
end
