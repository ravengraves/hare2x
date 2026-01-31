// Memory move - binding to lib/hare/rt.c

export @symbol("rt_memmove") fn memmove(dest: *opaque, src: *opaque, n: size) void;
