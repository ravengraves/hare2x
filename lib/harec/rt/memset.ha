// Memory set - binding to lib/hare/rt.c

export @symbol("rt_memset") fn memset(dest: *opaque, val: u8, n: size) void;
