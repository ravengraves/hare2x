export fn main() void = {
	let b: u8 = 0;
	let p: *u8 = &b;
	// ERROR Can only index into array or slice object, but got u8
	let x = p[0];
};
