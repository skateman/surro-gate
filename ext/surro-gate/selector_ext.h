#ifndef SELECTOR_EXT_H
#define SELECTOR_EXT_H

#include "ruby.h"
#include "ruby/io.h"
#include "ruby/thread.h"
#include "stdlib.h"
#include "sys/epoll.h"

#define SOCK_PTR(X) RFILE(X)->fptr->fd
#define IVAR_TRUE(X, Y) rb_iv_get(X, Y) == Qtrue

struct epoll_wait_args {
  unsigned int epfd;
  struct epoll_event *events;
  int maxevents;
  int timeout;

  int result;
};

static VALUE SurroGate_Selector_allocate(VALUE self);
static VALUE SurroGate_Selector_initialize(VALUE self, VALUE logger);
static VALUE SurroGate_Selector_push(VALUE self, VALUE left, VALUE right);
static VALUE SurroGate_Selector_select(VALUE self, VALUE timeout);
static VALUE SurroGate_Selector_each_ready(VALUE self);

static void SurroGate_Selector_free(int *epoll);
static VALUE scoreboard_iterate(VALUE pair, VALUE self, int argc, VALUE *argv);

#endif
