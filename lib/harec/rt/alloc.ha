// Allocation functions - bindings to lib/hare/rt.c

export type slice = struct {
	data: nullable *opaque,
	length: size,
	capacity: size,
};

export @symbol("rt_malloc") fn malloc(n: size) nullable *opaque;
export @symbol("rt_free") fn free_(p: nullable *opaque) void;
export @symbol("rt_realloc") fn realloc(p: nullable *opaque, n: size) nullable *opaque;
export @symbol("rt_ensure") fn ensure(s: *slice, membsz: size) void;
export @symbol("rt_unensure") fn unensure(s: *slice, membsz: size) void;
