// Test file to verify abort codegen
use rt;
use strings;

type myerror = !void;

// Test error propagation and unwrap
fn maybe_fail(x: int) (int | myerror) = {
	if (x < 0) {
		return myerror;
	};
	return x * 2;
};

// Test assertion without message - should use rt_abort_fixed index 6
fn test_assert_fixed() void = {
	let x = 5;
	assert(x > 0);
};

// Test assertion with message - should use rt_abort
fn test_assert_msg() void = {
	let x = 5;
	assert(x > 0, "x must be positive");
};

// Test bounds checking - should use rt_abort_fixed index 0
fn test_bounds() void = {
	let arr: [3]int = [1, 2, 3];
	let i: size = 1;
	let v = arr[i]; // bounds check
};

// Test error unwrap - should use rt_abort_fixed index 7
fn test_unwrap() void = {
	let result = maybe_fail(5)!;  // Should succeed
};

// Test explicit abort - should use rt_abort with "abort" message
fn will_abort() void = {
	abort();
};

// Test abort with message - should use rt_abort with custom message
fn will_abort_msg() void = {
	abort("custom abort message");
};

export fn main() void = {
	// Run successful tests
	test_assert_fixed();
	test_assert_msg();
	test_bounds();
	test_unwrap();

	// Print success message
	let msg: str = "All abort tests passed!\n";
	rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
