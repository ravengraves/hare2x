// ERROR: Unknown object 'custom_multiply' - missing function
// Comprehensive test for the following features
// 1. @symbol attribute
// 2. Error handling (? and !)
// 3. Nullable pointers
// 4. RT module functions
use rt;
use strings;

// === @symbol attribute ===
@symbol("custom_multiply") fn multiply(a: int, b: int) int = a * b;

// === Error types (simple) ===
type myerror = !void;
type result = (int | myerror);

// Function that can fail
fn parse_int(s: str, fallback: int) result = {
	if (len(s) == 0) {
		return myerror;
	};
	return fallback;
};

// Error propagation with ?
fn double_parsed(s: str) result = {
	let val = parse_int(s, 42)?;
	return val * 2;
};

// Error assertion with !
fn must_parse(s: str) int = {
	return parse_int(s, 100)!;
};

// === Nullable pointers ===
type item = struct {
	value: int,
};

fn get_value(ptr: nullable *item) int = {
	match (ptr) {
	case null =>
		return -1;
	case let p: *item =>
		return p.value;
	};
};

fn find_first_positive(arr: []int) nullable *int = {
	for (let i = 0z; i < len(arr); i += 1) {
		if (arr[i] > 0) {
			return &arr[i];
		};
	};
	return null;
};

// === RT module ===
fn test_rt_functions() void = {
	let src: [4]u8 = [1, 2, 3, 4];
	let dst: [4]u8 = [0, 0, 0, 0];
	
	rt::memcpy(&dst, &src, 4);
	assert(dst[0] == 1);
	
	rt::memset(&dst, 0, 4);
	assert(dst[0] == 0);
	
	let s1: str = "test";
	let s2: str = "test";
	assert(rt::strcmp(s1, s2) == true);
};

export fn main() void = {
	// Test @symbol
	let product = custom_multiply(6, 7);
	assert(product == 42);
	
	// Test error handling
	let r1 = double_parsed("valid");
	match (r1) {
	case let v: int =>
		assert(v == 84);
	case myerror =>
		abort();
	};
	
	let v2 = must_parse("test");
	assert(v2 == 100);
	
	// Test nullable pointers
	let it = item { value = 42 };
	let val1 = get_value(&it);
	assert(val1 == 42);
	
	let val2 = get_value(null);
	assert(val2 == -1);
	
	let arr: [4]int = [-1, -2, 3, -4];
	let found = find_first_positive(arr[..]);
	match (found) {
	case null =>
		abort();
	case let p: *int =>
		assert(*p == 3);
	};
	
	// Test RT functions
	test_rt_functions();
	
	// Print success message
	let msg: str = "All comprehensive tests passed!\n";
	rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};

