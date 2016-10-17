require 'surro-gate/version'
require 'surro-gate/proxy_error'
require 'surro-gate/proxy'

# A generic purpose TCP-to-TCP proxy
module SurroGate
  class << self
    # Initializes a new Proxy instance
    # @return [Proxy]
    def new
      Proxy.new
    end
  end
end
