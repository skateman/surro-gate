require 'mkmf'

have_header 'sys/epoll.h'
create_makefile 'surro-gate/selector_ext'
