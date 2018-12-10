# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'surro-gate/version'

Gem::Specification.new do |spec|
  spec.name          = 'surro-gate'
  spec.version       = SurroGate::VERSION
  spec.authors       = ['Dávid Halász']
  spec.email         = ['skateman@skateman.eu']

  spec.summary       = 'A generic purrpose TCP-to-TCP proxy in Ruby'
  spec.description   = 'A generic purrpose TCP-to-TCP proxy for Ruby implemented using epoll'
  spec.homepage      = 'https://github.com/skateman/surro-gate'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.extensions    = ['ext/surro-gate/extconf.rb']
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'concurrent-ruby'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rake-compiler'
  spec.add_development_dependency 'rspec'
end
