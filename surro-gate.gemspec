# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'surro-gate/version'

Gem::Specification.new do |spec|
  spec.name          = 'surro-gate'
  spec.version       = SurroGate::VERSION
  spec.authors       = ['Dávid Halász']
  spec.email         = ['skateman@skateman.eu']

  spec.summary       = 'A general purrpose TCP-to-TCP proxy written in Ruby'
  spec.description   = 'A general purrpose TCP-to-TCP proxy written in Ruby'
  spec.homepage      = 'https://github.com/skateman/surro-gate'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'celluloid-io', '~> 0.17.3'

  spec.add_development_dependency 'bundler', '~> 1.13'
  spec.add_development_dependency 'codecov', '~> 0.1.0'
  spec.add_development_dependency 'nyan-cat-formatter', '~> 0.11'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'simplecov', '~> 0.12'
end
