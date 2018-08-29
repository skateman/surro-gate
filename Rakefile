# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'surro-gate/version'

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new('surro-gate') do |ext|
  ext.name = 'surro-gate/selector_ext'
end

task :default => SurroGate::HAVE_EXT ? %i[compile spec] : %i[clean spec]

CLEAN.include '**/*.o', '**/*.so', 'pkg', 'tmp'
