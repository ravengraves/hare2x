// Hare compile check: alias-to-void in a tagged union.

type err1 = void;
type mytype = (u32 | err1);
type mytype2 = (u32 | void);

export fn main() void = {
	let a: mytype = 7u32: mytype;
	let e: mytype = (void: err1): mytype;

	match (a) {
	case u32 => void;
	case err1 => void;
	};

	match (e) {
	case u32 => void;
	case err1 => void;
	};
};
