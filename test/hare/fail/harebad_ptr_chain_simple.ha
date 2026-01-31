// ERROR: Argument type null is not assignable to parameter type *str
// Minimal test for chained pointer field access
use rt;
use strings;

type inner = struct {
	val: int,
};

type outer = struct {
	ptr: *inner,
};

export fn main() void = {
	let i = inner { val = 42 };
	let o = outer { ptr = &i };
	let op: *outer = &o;

	// op.ptr.val should dereference op, then dereference ptr
	let result = op.ptr.val;
	if (result != 42) {
		rt::abort_fixed(null, 0, 0, 6);
	};

	rt::write(1, strings::toutf8("OK\n"): *[*]u8, 3);
};
