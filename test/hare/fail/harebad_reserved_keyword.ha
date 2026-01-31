// ERROR: Cannot use reserved keyword 'offset' as identifier
// In Hare, 'offset' is a builtin and cannot be used as field/variable names
use rt;

// This struct uses 'offset' as a field name, which is invalid in Hare
type buffer = struct {
	data: *[*]u8,
	offset: size,  // ERROR: 'offset' is a reserved keyword
	len: size,
};

fn test_buffer() void = {
	let b = buffer {
		data = 0: *[*]u8,
		offset = 0,  // Also invalid here
		len = 100,
	};
	assert(b.len == 100);
};

export fn main() void = {
	test_buffer();
	rt::write(1, "Reserved keyword test\n": *[*]u8, 22);
};
