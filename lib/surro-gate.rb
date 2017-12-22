require 'surro-gate/version'
require 'surro-gate/connection'
require 'surro-gate/proxy'

# A generic purpose TCP-to-TCP proxy
module SurroGate
  class << self
    # Initializes a new Proxy instance
    # @return [Proxy]
    def new(logger = nil)
      Proxy.new(logger)
    end
  end
end
