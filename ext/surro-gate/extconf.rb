require 'mkmf'

require_relative '../../lib/surro-gate/version.rb'
if SurroGate::HAVE_EXT
  have_header 'sys/epoll.h'
  create_makefile 'surro-gate/selector_ext'
else
  rslt = dummy_makefile('.')
  IO.write('Makefile', rslt.join("\n"))
end
