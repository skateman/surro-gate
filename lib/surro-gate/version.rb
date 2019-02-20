# frozen_string_literal: true

module SurroGate
  VERSION = '1.0.5'.freeze
  HAVE_EXT = RUBY_PLATFORM =~ /linux/ && !defined?(JRUBY_VERSION) && !ENV['SURRO_GATE_NOEXT']
end
