# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rake/extensiontask'
require 'surro-gate/version'

RSpec::Core::RakeTask.new(:spec)

if SurroGate::HAVE_EXT
  Rake::ExtensionTask.new('surro-gate') do |ext|
    ext.name = 'surro-gate/selector_ext'
  end

  task :default => %i[compile spec]
else
  task :default => %i[clean spec]
end

CLEAN.include '**/*.o', '**/*.so', 'pkg', 'tmp'
