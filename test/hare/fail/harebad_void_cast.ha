export fn main() void = {
	let b: u8 = 0;
	let p: *u8 = &b;
	// ERROR Invalid cast from *u8 to void
	p: void;
};
