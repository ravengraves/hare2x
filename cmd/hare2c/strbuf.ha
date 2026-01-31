// strbuf.ha - String builder for output generation
use strings;

// String buffer for building output
export type strbuf = struct {
	data: *[*]u8,
	length: size,
	cap: size,
	arena: *arena,
};

// Initial capacity for string buffers
def INITIAL_CAP: size = 256;

// Create a new string buffer
export fn strbuf_new(a: *arena) strbuf = {
	return strbuf {
		data = arena_alloc(a, INITIAL_CAP): *[*]u8,
		length = 0,
		cap = INITIAL_CAP,
		arena = a,
	};
};

// Ensure buffer has space for n more bytes
fn strbuf_ensure(sb: *strbuf, n: size) void = {
	if (sb.length + n <= sb.cap) return;

	// Grow to next power of 2 that fits
	let new_cap = sb.cap;
	for (new_cap < sb.length + n) {
		new_cap *= 2;
	};

	let new_data = arena_alloc(sb.arena, new_cap): *[*]u8;

	// Copy existing data
	for (let i = 0z; i < sb.length; i += 1) {
		new_data[i] = sb.data[i];
	};

	sb.data = new_data;
	sb.cap = new_cap;
};

// Append a string
export fn strbuf_append(sb: *strbuf, s: str) void = {
	strbuf_ensure(sb, len(s));
	let bytes = strings::toutf8(s): *[*]u8;
	for (let i = 0z; i < len(s); i += 1) {
		sb.data[sb.length] = bytes[i];
		sb.length += 1;
	};
};

// Append a single byte
export fn strbuf_append_byte(sb: *strbuf, b: u8) void = {
	strbuf_ensure(sb, 1);
	sb.data[sb.length] = b;
	sb.length += 1;
};

// Append bytes from pointer and length
export fn strbuf_append_bytes(sb: *strbuf, ptr: *u8, plen: size) void = {
	strbuf_ensure(sb, plen);
	let bytes = ptr: *[*]u8;
	for (let i = 0z; i < plen; i += 1) {
		sb.data[sb.length] = bytes[i];
		sb.length += 1;
	};
};

// Append an integer (base 10)
export fn strbuf_append_int(sb: *strbuf, n: i64) void = {
	if (n < 0) {
		strbuf_append_byte(sb, '-');
		n = -n;
	};

	if (n == 0) {
		strbuf_append_byte(sb, '0');
		return;
	};

	// Build digits in reverse
	let digits: [20]u8 = [0...];
	let count = 0z;

	for (n > 0) {
		let digit = (n % 10): u8;
		digits[count] = ('0' + digit): u8;
		count += 1;
		n /= 10;
	};

	// Append in correct order
	for (let i: size = count; i > 0; i -= 1) {
		strbuf_append_byte(sb, digits[i - 1]);
	};
};

// Append an unsigned integer (base 10)
export fn strbuf_append_uint(sb: *strbuf, n: u64) void = {
	if (n == 0) {
		strbuf_append_byte(sb, '0');
		return;
	};

	let digits: [20]u8 = [0...];
	let count = 0z;

	for (n > 0) {
		let digit = (n % 10): u8;
		digits[count] = ('0' + digit): u8;
		count += 1;
		n /= 10;
	};

	for (let i: size = count; i > 0; i -= 1) {
		strbuf_append_byte(sb, digits[i - 1]);
	};
};

// Append an unsigned integer in hex
export fn strbuf_append_hex(sb: *strbuf, n: u64) void = {
	strbuf_append(sb, "0x");

	if (n == 0) {
		strbuf_append_byte(sb, '0');
		return;
	};

	let digits: [16]u8 = [0...];
	let count = 0z;

	for (n > 0) {
		let d = (n & 0xf): u8;
		if (d < 10) {
			digits[count] = ('0' + d): u8;
		} else {
			digits[count] = ('a' + d - 10): u8;
		};
		count += 1;
		n >>= 4;
	};

	for (let i: size = count; i > 0; i -= 1) {
		strbuf_append_byte(sb, digits[i - 1]);
	};
};

// Append a byte as two hex digits (for string escape sequences)
export fn strbuf_append_hex_byte(sb: *strbuf, b: u8) void = {
	let hi: u32 = ((b >> 4) & 0xF): u32;
	let lo: u32 = (b & 0xF): u32;

	if (hi < 10) {
		strbuf_append_byte(sb, ('0' + hi): u8);
	} else {
		strbuf_append_byte(sb, ('a' + hi - 10): u8);
	};

	if (lo < 10) {
		strbuf_append_byte(sb, ('0' + lo): u8);
	} else {
		strbuf_append_byte(sb, ('a' + lo - 10): u8);
	};
};

// Get the built string as a pointer and length (caller makes str)
export fn strbuf_ptr(sb: *strbuf) *u8 = {
	return sb.data: *u8;
};

export fn strbuf_len(sb: *strbuf) size = {
	return sb.length;
};

// Clear the buffer (reuse capacity)
export fn strbuf_clear(sb: *strbuf) void = {
	sb.length = 0;
};

// Compare a raw pointer+length to a string literal
// Returns true if the bytes match the string exactly
// Uses first-class string comparison via rt_strcmp
export fn streq(ptr: *u8, plen: size, s: str) bool = {
	// Create a slice from the pointer and length
	let slice: []u8 = (ptr: *[*]u8)[..plen];
	// Convert to str using strings::fromutf8_unsafe
	let str_val = strings::fromutf8_unsafe(slice);
	// Use first-class string comparison
	return str_val == s;
};

// Check if a raw pointer+length starts with a string prefix
export fn strprefix(ptr: *u8, plen: size, prefix: str) bool = {
	if (plen < len(prefix)) {
		return false;
	};
	// Create a slice of just the prefix length
	let slice: []u8 = (ptr: *[*]u8)[..len(prefix)];
	// Convert to str and compare
	let str_val = strings::fromutf8_unsafe(slice);
	return str_val == prefix;
};

