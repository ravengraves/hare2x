// ERROR: Invalid function pointer syntax
// Example: Function pointers
use rt;
use strings;

// Basic arithmetic functions
fn add(x: int, y: int) int = x + y;
fn sub(x: int, y: int) int = x - y;
fn mul(x: int, y: int) int = x * y;

// Function that takes no args and returns int
fn get_value() int = 42;

// Function that takes a function pointer and applies it
fn apply(func: *fn(int, int) int, a: int, b: int) int = {
	return func(a, b);
};

// Higher-order function: returns a function pointer
fn get_operation(op: int) *fn(int, int) int = {
	if (op == 0) {
		return &add;
	} else if (op == 1) {
		return &sub;
	};
	return &mul;
};

// Struct containing a function pointer
type calculator = struct {
	op: *fn(int, int) int,
	name: str,
};

// Function that uses a function pointer from a struct
fn calc_apply(c: *calculator, a: int, b: int) int = {
	return c.op(a, b);
};

// Array of function pointers
fn sum_with_ops(ops: [3]*fn(int, int) int, a: int, b: int) int = {
	let result: int = 0;
	for (let i: int = 0; i < 3; i += 1) {
		result += ops[i](a, b);
	};
	return result;
};

export fn main() void = {
	// Test 1: Basic function pointer assignment and call
	const f: *fn(int, int) int = &add;
	assert(f(3, 4) == 7);

	// Test 2: Reassigning function pointer
	let g: *fn(int, int) int = &add;
	assert(g(10, 5) == 15);
	g = &sub;
	assert(g(10, 5) == 5);
	g = &mul;
	assert(g(10, 5) == 50);

	// Test 3: Passing function pointer to another function
	assert(apply(&add, 6, 7) == 13);
	assert(apply(&sub, 10, 3) == 7);
	assert(apply(&mul, 4, 5) == 20);

	// Test 4: Function returning a function pointer
	let op0: *fn(int, int) int = get_operation(0);
	let op1: *fn(int, int) int = get_operation(1);
	let op2: *fn(int, int) int = get_operation(2);
	assert(op0(8, 2) == 10);  // add
	assert(op1(8, 2) == 6);   // sub
	assert(op2(8, 2) == 16);  // mul

	// Test 5: Function pointer in struct
	let calc: calculator = calculator {
		op = &mul,
		name = "multiply",
	};
	assert(calc.op(7, 6) == 42);

	// Test 6: Change function pointer in struct
	calc.op = &add;
	assert(calc.op(7, 6) == 13);

	// Test 7: Pass struct with function pointer to function
	calc.op = &sub;
	assert(calc_apply(&calc, 20, 8) == 12);

	// Test 8: Array of function pointers
	let ops: [3]*fn(int, int) int = [&add, &sub, &mul];
	assert(ops[0](5, 3) == 8);
	assert(ops[1](5, 3) == 2);
	assert(ops[2](5, 3) == 15);

	// Test 9: Sum using array of function pointers
	// add(2,3) + sub(2,3) + mul(2,3) = 5 + (-1) + 6 = 10
	assert(sum_with_ops(ops, 2, 3) == 10);

	// Test 10: Function pointer to zero-arg function
	const getter: *fn() int = &get_value;
	assert(getter() == 42);

	// Test 11: Nested function pointer calls
	let op_a: *fn(int, int) int = &add;
	let op_m: *fn(int, int) int = &mul;
	assert(op_m(op_a(2, 3), 4) == 20);  // (2+3) * 4 = 20

	let msg: str = "Function pointer tests passed!\n";
	rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
