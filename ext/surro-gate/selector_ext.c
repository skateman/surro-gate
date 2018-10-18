#include "selector_ext.h"

static VALUE mSurroGate = Qnil;
static VALUE cSurroGate_Selector = Qnil;
static VALUE cSurroGate_Pair = Qnil;

void epoll_register(int *epoll, int socket, int ltr, int rtl) {
  struct epoll_event ev;
  ev.data.u64 = ((uint64_t)ltr) << 32 | rtl;
  ev.events = EPOLLONESHOT | EPOLLIN | EPOLLOUT;
  epoll_ctl(*epoll, EPOLL_CTL_ADD, socket, &ev);
}

void epoll_deregister(int *epoll, int socket) {
  epoll_ctl(*epoll, EPOLL_CTL_DEL, socket, NULL);
}

void epoll_rearm(int *epoll, int socket, int ltr, int rtl, int events) {
  struct epoll_event ev;
  ev.data.u64 = ((uint64_t)ltr) << 32 | rtl;
  ev.events = EPOLLONESHOT | events;
  epoll_ctl(*epoll, EPOLL_CTL_MOD, socket, &ev);
}

void* wait_func(void *ptr) {
  struct epoll_wait_args *args;
  args = (struct epoll_wait_args*) ptr;
  args->result = epoll_wait(args->epfd, args->events, args->maxevents, args->timeout);
  return NULL;
}

static VALUE pairing_compare(VALUE pair, VALUE sockets) {
  int i;
  VALUE left = rb_iv_get(pair, "@left");
  VALUE right = rb_iv_get(pair, "@right");

  for (i=0; i<RARRAY_LEN(sockets); i++) { // sockets.each
    VALUE item = rb_ary_entry(sockets, i);
    if (left == item || right == item) {
      return Qtrue;
    }
  }

  return Qnil;
};

static VALUE pairing_iterate(VALUE pair, VALUE self, int argc, VALUE *argv) {
  int *selector;
  VALUE inverse, inv_idx;

  // Yield only for the pairs that are ready
  if (rb_funcall(pair, rb_intern("ready?"), 0) == Qtrue) {
    rb_yield_values(2, rb_iv_get(pair, "@left"), rb_iv_get(pair, "@right")); // yield(pair.left, pair.right)

    inv_idx = rb_iv_get(pair, "@inverse");
    inverse = rb_funcall(rb_iv_get(self, "@pairing"), rb_intern("[]"), 1, inv_idx); // @pairing[inv_idx]

    rb_iv_set(pair, "@rd_rdy", Qfalse);
    rb_iv_set(pair, "@wr_rdy", Qfalse);

    Data_Get_Struct(self, int, selector);
    // Rearm left socket for reading and also writing if not ready for writing
    epoll_rearm(selector, SOCK_PTR(rb_iv_get(pair, "@left")), NUM2INT(inv_idx), NUM2INT(argv[1]), EPOLLIN | (IVAR_TRUE(inverse, "@wr_rdy") ? 0 : EPOLLOUT));
    // Rearm right socket for writing and also reading if not ready for reading
    epoll_rearm(selector, SOCK_PTR(rb_iv_get(pair, "@right")), NUM2INT(argv[1]), NUM2INT(inv_idx), EPOLLOUT | (IVAR_TRUE(inverse, "@rd_rdy") ? 0 : EPOLLIN));
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
  VALUE mConcurrent = rb_const_get(rb_cObject, rb_intern("Concurrent"));
  VALUE cArray = rb_const_get(mConcurrent, rb_intern("Array"));

  rb_iv_set(self, "@pairing", rb_class_new_instance(0, NULL, cArray)); // @pairing = Concurrent::Array.new
  rb_iv_set(self, "@logger", logger);

  return Qnil;
}

static VALUE SurroGate_Selector_push(VALUE self, VALUE left, VALUE right) {
  int index_ltr, index_rtl, *selector;

  VALUE pair_LTR[2] = {left, right};
  VALUE pair_RTL[2] = {right, left};
  VALUE left_to_right = rb_class_new_instance(2, pair_RTL, cSurroGate_Pair); // SurroGate::Pair.new(left, right)
  VALUE right_to_left = rb_class_new_instance(2, pair_LTR, cSurroGate_Pair); // SurroGate::Pair.new(right, left)

  VALUE pairing = rb_iv_get(self, "@pairing");

  Check_Type(left, T_FILE);
  Check_Type(right, T_FILE);

  // raise ArgumentError if @pairing.detect(&pairing_compare)
  if (rb_block_call(pairing, rb_intern("detect"), 0, NULL, pairing_compare, rb_ary_new_from_values(2, pair_LTR)) != Qnil) {
    rb_raise(rb_eArgError, "Socket already registered!");
  }

  Data_Get_Struct(self, int, selector);

  rb_funcall(pairing, rb_intern("push"), 2, left_to_right, right_to_left); // @pairing.push(left_to_right, right_to_left)
  index_ltr = NUM2INT(rb_funcall(pairing, rb_intern("index"), 1, left_to_right)); // @pairing.index(left_to_right)
  index_rtl = NUM2INT(rb_funcall(pairing, rb_intern("index"), 1, right_to_left)); // @pairing.index(right_to_left)

  rb_iv_set(left_to_right, "@inverse", INT2NUM(index_rtl));
  rb_iv_set(right_to_left, "@inverse", INT2NUM(index_ltr));

  epoll_register(selector, SOCK_PTR(left), index_ltr, index_rtl);
  epoll_register(selector, SOCK_PTR(right), index_rtl, index_ltr);

  return Qtrue;
}

static VALUE SurroGate_Selector_pop(VALUE self, VALUE sockets) {
  int i, *selector;

  VALUE pairing = rb_iv_get(self, "@pairing");
  rb_block_call(pairing, rb_intern("delete_if"), 0, NULL, pairing_compare, sockets); // @pairing.delete_if(&pairing_compare)

  Data_Get_Struct(self, int, selector);
  for (i=0; i<RARRAY_LEN(sockets); i++) {
    epoll_deregister(selector, SOCK_PTR(rb_ary_entry(sockets, i)));
  }

  return Qnil;
}

static VALUE SurroGate_Selector_select(VALUE self, VALUE timeout) {
  int i, *selector, source, target;
  struct epoll_event events[256];
  struct epoll_wait_args wait_args;
  VALUE read, write, socket;

  VALUE pairing = rb_iv_get(self, "@pairing");
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
    source = (int)((events[i].data.u64 & 0xFFFFFFFF00000000LL) >> 32);
    target = (int)(events[i].data.u64 & 0xFFFFFFFFLL);

    read = rb_funcall(pairing, rb_intern("[]"), 1, INT2NUM(target)); // @pairing[source]
    write = rb_funcall(pairing, rb_intern("[]"), 1, INT2NUM(source)); // @pairing[target]

    if (events[i].events & EPOLLIN && events[i].events & EPOLLOUT) {
      // Socket is both available for read and write
      rb_iv_set(read, "@rd_rdy", Qtrue); // read.rd_rdy = true
      rb_iv_set(write, "@wr_rdy", Qtrue); // write.wr_rdy = true
    } else if (events[i].events & EPOLLIN) {
      // Socket is available for read, reregister it for write if not writable
      rb_iv_set(read, "@rd_rdy", Qtrue); // read.rd_rdy = true
      if (rb_iv_get(write, "@wr_rdy") == Qfalse) { // if !write.wr_rdy
        socket = rb_iv_get(read, "@left"); // read.left
        epoll_rearm(selector, SOCK_PTR(socket), target, source, EPOLLOUT);
      }
    } else if (events[i].events & EPOLLOUT) {
      // Socket is available for write, reregister it for read if not readable
      rb_iv_set(write, "@wr_rdy", Qtrue); // write.wr_rdy = true
      if (rb_iv_get(write, "@rd_rdy") == Qfalse) { // if !source.rd_rdy
        socket = rb_iv_get(write, "@right"); // write.right
        epoll_rearm(selector, SOCK_PTR(socket), source, target, EPOLLIN);
      }
    }
  }

  return INT2NUM(wait_args.result);
}

static VALUE SurroGate_Selector_each_ready(VALUE self) {
  VALUE pairing = rb_iv_get(self, "@pairing");
  rb_need_block();
  return rb_block_call(pairing, rb_intern("each_with_index"), 0, NULL, pairing_iterate, self);
}

void Init_selector_ext() {
  rb_require("concurrent");
  rb_require("surro-gate/pair");

  mSurroGate = rb_define_module("SurroGate");
  cSurroGate_Selector = rb_define_class_under(mSurroGate, "Selector", rb_cObject);
  cSurroGate_Pair = rb_const_get(mSurroGate, rb_intern("Pair"));

  rb_define_alloc_func(cSurroGate_Selector, SurroGate_Selector_allocate);

  rb_define_method(cSurroGate_Selector, "initialize", SurroGate_Selector_initialize, 1);
  rb_define_method(cSurroGate_Selector, "push", SurroGate_Selector_push, 2);
  rb_define_method(cSurroGate_Selector, "pop", SurroGate_Selector_pop, -2);
  rb_define_method(cSurroGate_Selector, "select", SurroGate_Selector_select, 1);
  rb_define_method(cSurroGate_Selector, "each_ready", SurroGate_Selector_each_ready, 0);
}
