// ERROR: Can't have pointer to zero-sized type (void)
// Test complex pointer dereferencing patterns
// Hare auto-dereferences pointers for field access and array indexing

use rt;
use strings;

// Simple struct with pointer field
type inner = struct {
	value: int,
	next: nullable *inner,
};

// Struct with pointer to another struct
type outer = struct {
	name: str,
	data: *inner,
};

// Nested pointer chain
type node = struct {
	val: int,
	child: nullable *node,
};

type tree = struct {
	root: *node,
	count: int,
};

// Array inside struct
type container = struct {
	items: [4]int,
	count: size,
};

// Test 1: Basic pointer field access through variable
fn test_basic_ptr_field() void = {
	let i = inner { value = 42, next = null };
	let p: *inner = &i;

	// p.value should auto-deref: (*p).value
	assert(p.value == 42, "basic ptr field access failed");
};

// Test 2: Chained pointer field access
fn test_chained_ptr_field() void = {
	let n1 = node { val = 1, child = null };
	let n2 = node { val = 2, child = &n1 };
	let t = tree { root = &n2, count = 2 };
	let tp: *tree = &t;

	// tp.root.val should be: (*tp).root->val (two derefs)
	assert(tp.root.val == 2, "chained ptr field access failed");

	// tp.root.child is nullable *node
	// Access through it requires checking null first
	match (tp.root.child) {
	case let child: *node =>
		assert(child.val == 1, "triple chain ptr access failed");
	case null =>
		abort();
	};
};

// Test 3: Pointer from cast expression
fn test_cast_ptr_field() void = {
	let i = inner { value = 100, next = null };
	let raw: *void = &i;

	// Cast to pointer and access field
	let p = raw: *inner;
	assert(p.value == 100, "cast ptr field access failed");
};

// Test 4: Pointer from function return
fn make_inner(v: int) *inner = {
	static let storage: inner = inner { value = 0, next = null };
	storage.value = v;
	return &storage;
};

fn test_fn_return_ptr_field() void = {
	let p = make_inner(55);
	assert(p.value == 55, "fn return ptr field access failed");

	// Direct call chained access
	assert(make_inner(77).value == 77, "direct call ptr field failed");
};

// Test 5: Array access through pointer
fn test_ptr_array_access() void = {
	let c = container { items = [10, 20, 30, 40], count = 4 };
	let cp: *container = &c;

	// cp.items[1] should be: (*cp).items[1]
	assert(cp.items[1] == 20, "ptr array access failed");
};

// Test 6: Double pointer
fn test_double_ptr() void = {
	let i = inner { value = 999, next = null };
	let p1: *inner = &i;
	let p2: **inner = &p1;

	// p2.value should auto-deref twice: (**p2).value
	assert(p2.value == 999, "double ptr field access failed");
};

// Test 7: Pointer field pointing to another struct with pointer field
fn test_nested_ptr_chain() void = {
	let i1 = inner { value = 1, next = null };
	let i2 = inner { value = 2, next = &i1 };
	let i3 = inner { value = 3, next = &i2 };

	let p: *inner = &i3;

	// p.next is *inner, p.next.next is *inner
	match (p.next) {
	case let n1: *inner =>
		assert(n1.value == 2, "first next failed");
		match (n1.next) {
		case let n2: *inner =>
			assert(n2.value == 1, "second next failed");
		case null =>
			abort();
		};
	case null =>
		abort();
	};
};

// Test 8: Mixed pointer and non-pointer field access
fn test_mixed_access() void = {
	let i = inner { value = 42, next = null };
	let o = outer { name = "test", data = &i };
	let op: *outer = &o;

	// op.data.value: (*op).data->value
	assert(op.data.value == 42, "mixed ptr access failed");
};

export fn main() void = {
	test_basic_ptr_field();
	test_chained_ptr_field();
	test_cast_ptr_field();
	test_fn_return_ptr_field();
	test_ptr_array_access();
	test_double_ptr();
	test_nested_ptr_chain();
	test_mixed_access();

	rt::write(1, strings::toutf8("All pointer dereference tests passed!\n"): *[*]u8, 39);
};
