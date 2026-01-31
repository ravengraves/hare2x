// System calls - bindings to lib/hare/rt.c

export @symbol("rt_write") fn write(fd: int, buf: *const opaque, count: size) u64;
export @symbol("rt_read") fn read(fd: int, buf: *opaque, count: size) u64;
export @symbol("rt_exit") fn exit(status: int) never;
