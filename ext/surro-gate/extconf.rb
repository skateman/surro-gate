require 'mkmf'

if RUBY_PLATFORM =~ /linux/ && !defined?(JRUBY_VERSION) && !ENV['SURRO_GATE_NOEXT']
  have_header 'sys/epoll.h'
  create_makefile 'surro-gate/selector_ext'
end
