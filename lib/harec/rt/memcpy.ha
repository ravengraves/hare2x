// Memory copy - binding to lib/hare/rt.c

export @symbol("rt_memcpy") fn memcpy(dest: *opaque, src: *opaque, n: size) void;
