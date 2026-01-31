// Example: Tuple Types
use rt;
use strings;

type coords = struct { x: int, y: int };

fn sum_tuple(t: (int, int)) int = {
	return t.0 + t.1;
};

fn make_tuple(a: int, b: int) (int, int) = {
	return (a, b);
};

export fn main() void = {
	// Anonymous struct literal
	let player1 = struct {
		x: int = 10,
		y: int = 20,
	};

	// Named struct literal
	let player2 = coords {
		y = 10,
		x = 20,
	};

	// Tuple type with tuple literal
	let player3: (int, int) = (42, 24);

	// Test struct access
	assert(player1.x == 10);
	assert(player1.y == 20);
	assert(player2.x == 20);
	assert(player2.y == 10);

	// Test tuple access
	assert(player3.0 == 42);
	assert(player3.1 == 24);

	// Test sum function
	assert(sum_tuple(player3) == 66);
	assert(sum_tuple((10, 20)) == 30);

	// Test make_tuple function
	let result = make_tuple(100, 200);
	assert(result.0 == 100);
	assert(result.1 == 200);

	// Nested tuple access
	let nested: ((int, int), int) = ((1, 2), 3);
	assert(nested.0.0 == 1);
	assert(nested.0.1 == 2);
	assert(nested.1 == 3);

	let msg: str = "Tuple tests passed!\n";
	rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
