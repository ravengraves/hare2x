// Error type !void handling and match behavior
use rt;

type err = !void;
type err_alias = err;

type u32_box = struct {
	v: u32,
};

type number = (i32 | u32_box | err);

type mix = (err_alias | u32_box);

fn to_i32_alias(n: number) i32 = {
	match (n) {
	case i32 => return n: i32;
	case u32_box => return (n: u32_box).v: i32;
	case err => return -1;
	};
};

fn to_i32_void(n: number) i32 = {
	match (n) {
	case i32 => return n: i32;
	case u32_box => return (n: u32_box).v: i32;
	case !void => return -1;
	};
};

fn is_err_via_alias(m: mix) bool = {
	match (m) {
	case err_alias => return true;
	case u32_box => return false;
	};
};

fn is_err_via_void(m: mix) bool = {
	match (m) {
	case !void => return true;
	case u32_box => return false;
	};
};

export fn main() void = {
	let a: number = 42;
	let b: number = u32_box { v = 7u32 };
	let c: err = err;
	let d: err_alias = err_alias;
	let e: number = c: number;
	let f: mix = d: mix;

	assert(to_i32_alias(a) == 42);
	assert(to_i32_alias(b) == 7);
	assert(to_i32_alias(e) == -1);

	assert(to_i32_void(a) == 42);
	assert(to_i32_void(b) == 7);
	assert(to_i32_void(e) == -1);

	assert(is_err_via_alias(f) == true);
	assert(is_err_via_void(f) == true);
};
