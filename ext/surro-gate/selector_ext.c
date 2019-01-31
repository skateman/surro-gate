#include "selector_ext.h"

static VALUE mSurroGate = Qnil;
static VALUE cSurroGate_Selector = Qnil;
static VALUE cSurroGate_Pair = Qnil;
static VALUE cSurroGate_Scoreboard = Qnil;

void epoll_register(int *epoll, VALUE socket) {
  struct epoll_event ev;
  ev.data.u64 = (uint64_t) socket;
  ev.events = EPOLLONESHOT | EPOLLIN | EPOLLOUT;
  epoll_ctl(*epoll, EPOLL_CTL_ADD, SOCK_PTR(socket), &ev);
}

void epoll_deregister(int *epoll, VALUE socket) {
  epoll_ctl(*epoll, EPOLL_CTL_DEL, SOCK_PTR(socket), NULL);
}

void epoll_rearm(int *epoll, VALUE socket, int events) {
  struct epoll_event ev;
  ev.data.u64 = (uint64_t) socket;
  ev.events = EPOLLONESHOT | events;
  epoll_ctl(*epoll, EPOLL_CTL_MOD, SOCK_PTR(socket), &ev);
}

void* wait_func(void *ptr) {
  struct epoll_wait_args *args;
  args = (struct epoll_wait_args*) ptr;
  args->result = epoll_wait(args->epfd, args->events, args->maxevents, args->timeout);
  return NULL;
}

static VALUE scoreboard_iterate(VALUE pair, VALUE self, int argc, VALUE *argv) {
  int *selector;
  VALUE inverse;

  VALUE scoreboard = rb_iv_get(self, "@scoreboard");
  Data_Get_Struct(self, int, selector);

  // Yield only for the pairs that are ready
  if (rb_funcall(pair, rb_intern("ready?"), 0) == Qtrue) {
    rb_yield_values(2, rb_iv_get(pair, "@left"), rb_iv_get(pair, "@right")); // yield(pair.left, pair.right)

    // Unmark the readiness of the socket pair
    rb_funcall(pair, rb_intern("unmark"), 0);
    // Get the inverse socket pairing of the current one
    inverse = rb_funcall(scoreboard, rb_intern("inverse"), 1, pair);
    // Rearm left socket for reading and also writing if not ready for writing
    epoll_rearm(selector, rb_iv_get(pair, "@left"), EPOLLIN | (IVAR_TRUE(inverse, "@wr_rdy") ? 0 : EPOLLOUT));
    // Rearm right socket for writing and also reading if not ready for reading
    epoll_rearm(selector, rb_iv_get(pair, "@right"), EPOLLOUT | (IVAR_TRUE(inverse, "@rd_rdy") ? 0 : EPOLLIN));
  }
  return Qnil;
}

static VALUE SurroGate_Selector_allocate(VALUE self) {
  int *selector = malloc(sizeof(int));

  if (selector != NULL) {
    *selector = epoll_create1(0);
    if (*selector > 0) {
      return Data_Wrap_Struct(self, NULL, SurroGate_Selector_free, selector);
    } else {
      xfree(selector);
    }
  }

  rb_raise(rb_eRuntimeError, "Allocation failed!");
  return Qnil;
}

static void SurroGate_Selector_free(int *selector) {
  close(*selector);
  xfree(selector);
}

static VALUE SurroGate_Selector_initialize(VALUE self, VALUE logger) {
  rb_iv_set(self, "@scoreboard", rb_class_new_instance(0, NULL, cSurroGate_Scoreboard)); // @scoreboard = Scoreboard.new
  rb_iv_set(self, "@logger", logger);

  return Qnil;
}

static VALUE SurroGate_Selector_push(VALUE self, VALUE left, VALUE right) {
  int *selector;
  VALUE scoreboard = rb_iv_get(self, "@scoreboard");

  // Check the arguments for the correct type
  Check_Type(left, T_FILE);
  Check_Type(right, T_FILE);

  // raise ArgumentError if a socket is already registered
  if (rb_funcall(scoreboard, rb_intern("include?"), 1, left) == Qtrue || rb_funcall(scoreboard, rb_intern("include?"), 1, right) == Qtrue) {
    rb_raise(rb_eArgError, "Socket already registered!");
  }

  Data_Get_Struct(self, int, selector);
  rb_funcall(scoreboard, rb_intern("push"), 2, left, right);

  epoll_register(selector, left);
  epoll_register(selector, right);

  return Qtrue;
}

static VALUE SurroGate_Selector_pop(VALUE self, VALUE left, VALUE right) {
  int *selector;

  VALUE scoreboard = rb_iv_get(self, "@scoreboard");
  rb_funcall(scoreboard, rb_intern("pop"), 2, left, right);

  Data_Get_Struct(self, int, selector);
  epoll_deregister(selector, left);
  epoll_deregister(selector, right);

  return Qnil;
}

static VALUE SurroGate_Selector_select(VALUE self, VALUE timeout) {
  int i, *selector;
  struct epoll_event events[256];
  struct epoll_wait_args wait_args;
  VALUE socket;

  VALUE scoreboard = rb_iv_get(self, "@scoreboard");
  Data_Get_Struct(self, int, selector);

  // The code after the comments has the same result as the code below, but with GVL
  // args.result = epoll_wait(*selector, events, 256, NUM2INT(timeout));
  wait_args.epfd = *selector;
  wait_args.events = events;
  wait_args.maxevents = 256;
  wait_args.timeout = NUM2INT(timeout);
  wait_args.result = 0;
  rb_thread_call_without_gvl(wait_func, &wait_args, NULL, NULL);

  for (i=0; i<wait_args.result; i++) {
    socket = (VALUE) events[i].data.u64;

    if (events[i].events & EPOLLIN && events[i].events & EPOLLOUT) {
      // Socket is both available for read and write
      rb_funcall(scoreboard, rb_intern("mark_rd"), 1, socket);
      rb_funcall(scoreboard, rb_intern("mark_wr"), 1, socket);
    } else if (events[i].events & EPOLLIN) {
      // Socket is available for read, reregister it for write if not writable
      rb_funcall(scoreboard, rb_intern("mark_rd"), 1, socket);
      if (rb_funcall(scoreboard, rb_intern("marked_wr?"), 1, socket) == Qfalse) {
        epoll_rearm(selector, socket, EPOLLOUT);
      }
    } else if (events[i].events & EPOLLOUT) {
      // Socket is available for write, reregister it for read if not readable
      rb_funcall(scoreboard, rb_intern("mark_wr"), 1, socket);
      if (rb_funcall(scoreboard, rb_intern("marked_rd?"), 1, socket) == Qfalse) {
        epoll_rearm(selector, socket, EPOLLIN);
      }
    }
  }

  return INT2NUM(wait_args.result);
}

static VALUE SurroGate_Selector_each_ready(VALUE self) {
  VALUE scoreboard = rb_iv_get(self, "@scoreboard");
  rb_need_block();
  return rb_block_call(scoreboard, rb_intern("each"), 0, NULL, scoreboard_iterate, self);
}

void Init_selector_ext() {
  rb_require("surro-gate/pair");
  rb_require("surro-gate/scoreboard");

  mSurroGate = rb_define_module("SurroGate");
  cSurroGate_Selector = rb_define_class_under(mSurroGate, "Selector", rb_cObject);
  cSurroGate_Pair = rb_const_get(mSurroGate, rb_intern("Pair"));
  cSurroGate_Scoreboard = rb_const_get(mSurroGate, rb_intern("Scoreboard"));

  rb_define_alloc_func(cSurroGate_Selector, SurroGate_Selector_allocate);

  rb_define_method(cSurroGate_Selector, "initialize", SurroGate_Selector_initialize, 1);
  rb_define_method(cSurroGate_Selector, "push", SurroGate_Selector_push, 2);
  rb_define_method(cSurroGate_Selector, "pop", SurroGate_Selector_pop, 2);
  rb_define_method(cSurroGate_Selector, "select", SurroGate_Selector_select, 1);
  rb_define_method(cSurroGate_Selector, "each_ready", SurroGate_Selector_each_ready, 0);
}
