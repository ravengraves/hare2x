// ast.ha - AST node types

// Node kind enum - must come before node struct
export type node_kind = enum u8 {
	// Literals
	N_INT = 0,
	N_FLOAT,
	N_STR,
	N_RUNE,
	N_BOOL,
	N_NULL,
	N_VOID,      // void expression (for tagged union void variant)

	// Expressions
	N_ID,        // Identifier
	N_BIN,       // Binary operation
	N_UN,        // Unary operation
	N_CALL,      // Function call
	N_CAST,      // Type cast
	N_IDX,       // Array/slice index
	N_FLD,       // Field access
	N_SLICE,     // Slice expression
	N_ARR_LIT,   // Array literal [1, 2, 3]
	N_STRUCT_LIT, // Struct literal Name { x = 1 }
	N_ANON_STRUCT_LIT, // Anonymous struct literal struct { x: int = 1 }
	N_ANON_FIELD,      // Anonymous struct field: name: type = value
	N_TUPLE_LIT, // Tuple literal (expr, expr, ...)
	N_ASSERT,    // Assert builtin
	N_LEN,       // len() builtin
	N_IS,        // Type test: expr is type
	N_PROP,      // Error propagation: expr?
	N_UNWRAP,    // Error unwrap: expr!
	N_ALLOC,     // alloc(expr) builtin
	N_FREE,      // free(ptr) builtin
	N_APPEND,    // append(slice, val) builtin
	N_INSERT,    // insert(slice[idx], val) builtin
	N_DELETE,    // delete(slice[idx]) builtin

	// Statements
	N_LET,       // Variable declaration
	N_RET,       // Return
	N_IF,        // If expression
	N_FOR,       // For loop
	N_FOREACH,   // For-each by value: for (let x .. slice)
	N_FOREACH_REF, // For-each by reference: for (let x &.. slice)
	N_FOREACH_ITER, // For-each iterator: for (let x => iter())
	N_BLOCK,     // Block of statements
	N_ASGN,      // Assignment
	N_EXPR,      // Expression statement
	N_BREAK,
	N_CONT,
	N_SWITCH,    // Switch statement
	N_CASE,      // Switch case
	N_YIELD,     // Yield expression
	N_MATCH,     // Match expression
	N_MCASE,     // Match case
	N_DEFER,     // Defer statement
	N_ABORT,     // abort() builtin

	// Declarations
	N_FN,        // Function definition
	N_TYPEDEF,   // Type definition
	N_DEF,       // Constant definition
	N_GLOBAL,    // Global variable

	// Types
	N_TPRIM,     // Primitive type
	N_TPTR,      // Pointer type
	N_TSLICE,    // Slice type
	N_TARR,      // Array type
	N_TSTRUCT,   // Struct type
	N_TUNION,    // Union type
	N_TENUM,     // Enum type
	N_TTAGGED,   // Tagged union type
	N_TTUPLE,    // Tuple type (T1, T2, ...)
	N_TFUNC,     // Function type
	N_TALIAS,    // Type alias/name
	N_TERR,      // Error type !T
	N_TNOMEM,    // nomem error type

	// Other
	N_UNIT,      // Compilation unit
	N_PARAM,     // Function parameter
	N_FIELD,     // Struct field
	N_FIELD_INIT, // Field initializer in struct literal
	N_ENUM_MEMBER, // Enum member
	N_USE,       // Use statement
};

// AST node - uses data pointer cast to appropriate type based on kind
export type node = struct {
	kind: node_kind,
	data: *opaque,  // Cast based on kind
	line: u32,
	col: u16,
};

// Integer literal
export type n_int_data = struct {
	val: i64,
	suffix: u8,  // 0=none, 'i'=signed, 'u'=unsigned, 'z'=size
};

// String/identifier data (pointer into source)
export type n_str_data = struct {
	ptr: *u8,
	length: size,
	is_raw: bool,  // true for backtick strings (no escape processing)
};

// Identifier (same as string)
export type n_id_data = struct {
	ptr: *u8,
	length: size,
};

// Binary operation
export type n_bin_data = struct {
	op: token_kind,  // Operator token
	left: *node,
	right: *node,
};

// Unary operation
export type n_un_data = struct {
	op: token_kind,
	operand: *node,
};

// Function call
export type n_call_data = struct {
	func: *node,
	args: *[*]*node,
	nargs: size,
	has_spread: bool,  // True if last arg has ... (variadic spread)
};

// Type cast
export type n_cast_data = struct {
	expr: *node,
	target: *node,  // Type node
};

// Type test (is operator)
export type n_is_data = struct {
	expr: *node,
	typ: *node,  // Type to test against
};

// Error propagation (?) or unwrap (!) - holds the operand
export type n_prop_data = struct {
	expr: *node,
};

// Alloc builtin: alloc(expr), alloc(expr...), or alloc(expr, capacity)
export type n_alloc_data = struct {
	expr: *node,
	capacity: nullable *node,  // Optional capacity for slices
	is_copy: bool,             // True for alloc(expr...) slice copy syntax
};

// Abort builtin: abort() or abort("message")
export type n_abort_data = struct {
	msg: nullable *node,       // Optional message (string literal)
};

// Free builtin: free(ptr)
export type n_free_data = struct {
	expr: *node,
};

// Append builtin: append(slice, val) or static append(slice, val)
export type n_append_data = struct {
	slice: *node,
	value: *node,
	is_static: bool,
};

// Insert builtin: insert(slice[idx], val) or static insert(slice[idx], val)
export type n_insert_data = struct {
	slice: *node,      // The slice expression
	index: *node,      // The index
	value: *node,      // Value to insert
	is_static: bool,
};

// Delete builtin: delete(slice[idx]) or static delete(slice[idx])
export type n_delete_data = struct {
	slice: *node,      // The slice expression
	index: *node,      // The index to delete
	is_static: bool,
};

// Index expression
export type n_idx_data = struct {
	base: *node,
	index: *node,
};

// Field access
export type n_fld_data = struct {
	base: *node,
	field_ptr: *u8,
	field_len: size,
};

// Slice expression (arr[start..end])
export type n_slice_data = struct {
	base: *node,
	start: nullable *node,  // null = 0
	end: nullable *node,    // null = len
};

// Array literal [1, 2, 3]
export type n_arr_lit_data = struct {
	elems: *[*]*node,
	nelems: size,
	fill: nullable *node,  // For [val...] syntax
};

// Struct literal Name { x = 1 }
export type n_struct_lit_data = struct {
	type_name_ptr: nullable *u8,    // Type name (null for anonymous)
	type_name_len: size,
	fields: *[*]*node,     // Field initializers (N_FIELD_INIT)
	nfields: size,
};

// Tuple literal (expr, expr, ...)
export type n_tuple_lit_data = struct {
	elems: *[*]*node,
	nelems: size,
	type_name_ptr: nullable *u8,    // Generated type name (set during transform)
	type_name_len: size,
};

// Field initializer in struct literal
export type n_field_init_data = struct {
	name_ptr: *u8,
	name_len: size,
	value: *node,
};

// Anonymous struct field with type: name: type = value
export type n_anon_field_data = struct {
	name_ptr: *u8,
	name_len: size,
	typ: *node,
	value: *node,
};

// Anonymous struct literal: struct { x: int = 1, y: int = 2 }
export type n_anon_struct_lit_data = struct {
	fields: *[*]*node,     // N_ANON_FIELD nodes
	nfields: size,
};

// Let statement
export type n_let_data = struct {
	name_ptr: *u8,
	name_len: size,
	typ: nullable *node,  // Optional type annotation
	init: nullable *node, // Optional initializer
	is_mut: bool,
	is_static: bool,
};

// Return statement
export type n_ret_data = struct {
	expr: nullable *node,
};

// If expression
export type n_if_data = struct {
	cond: *node,
	then_branch: *node,
	else_branch: nullable *node,
};

// For loop
export type n_for_data = struct {
	init: nullable *node,
	cond: nullable *node,
	step: nullable *node,
	body: *node,
};

// For-each loop
export type n_foreach_data = struct {
	name_ptr: *u8,
	name_len: size,
	iterable: *node,
	body: *node,
};

// Block
export type n_block_data = struct {
	stmts: *[*]*node,
	nstmts: size,
};

// Assignment
export type n_asgn_data = struct {
	target: *node,
	op: token_kind,  // =, +=, -=, etc.
	value: *node,
};

// Switch statement
export type n_switch_data = struct {
	expr: *node,
	cases: *[*]*node,
	ncases: size,
};

// Switch case
export type n_case_data = struct {
	values: *[*]*node,  // null for default case
	nvalues: size,
	body: *node,
};

// Yield expression
export type n_yield_data = struct {
	expr: nullable *node,
};

// Defer statement
export type n_defer_data = struct {
	expr: *node,  // The expression to execute on scope exit
};

// Match expression
export type n_match_data = struct {
	expr: *node,
	cases: *[*]*node,
	ncases: size,
};

// Match case
export type n_mcase_data = struct {
	typ: nullable *node,     // Type to match (null for catch-all)
	bind_ptr: nullable *u8,  // Binding name pointer (null if no binding)
	bind_len: size,          // Binding name length
	body: *node,
};

// Function definition
export type n_fn_data = struct {
	name_ptr: *u8,
	name_len: size,
	params: *[*]*node,
	nparams: size,
	ret_type: nullable *node,
	body: nullable *node,
	exported: bool,
	is_init: bool,    // @init attribute
	is_fini: bool,    // @fini attribute
	is_test: bool,    // @test attribute
	symbol_ptr: nullable *u8,  // @symbol("name") - custom symbol name (null if not set)
	symbol_len: size,
};

// Type definition
export type n_typedef_data = struct {
	name_ptr: *u8,
	name_len: size,
	typ: *node,
	exported: bool,
};

// Pointer type
export type n_tptr_data = struct {
	inner: *node,
	is_nullable: bool,
	is_const: bool,
};

// Array type
export type n_tarr_data = struct {
	elem: *node,
	length: nullable *node,  // null for unbounded or inferred
	inferred: bool,          // true for [_]T (infer size from initializer)
};

// Struct type
export type n_tstruct_data = struct {
	fields: *[*]*node,
	nfields: size,
};

// Enum type
export type n_tenum_data = struct {
	members: *[*]*node,   // N_ENUM_MEMBER nodes
	nmembers: size,
	base_type: nullable *node,  // Optional base type (e.g., u8)
};

// Enum member
export type n_enum_member_data = struct {
	name_ptr: *u8,
	name_len: size,
	value: nullable *node,  // Optional explicit value
};

// Tagged union type
export type n_ttagged_data = struct {
	variants: *[*]*node,   // Array of type nodes
	nvariants: size,
	spread_mask: u32,      // Bit i=1 means variants[i] is a spread type (...T)
};

// Error type (!T)
export type n_terr_data = struct {
	inner: *node,
};

// Function type fn(params) ret
export type n_tfunc_data = struct {
	params: *[*]*node,     // N_PARAM nodes (name, type pairs)
	nparams: size,
	ret_type: *node,       // Return type
};

// Parameter/field
export type n_param_data = struct {
	name_ptr: *u8,
	name_len: size,
	typ: *node,
	is_variadic: bool,       // true for T... variadic parameters
	default_value: nullable *node,  // default value expression (for optional params)
};

// Compilation unit
export type n_unit_data = struct {
	decls: *[*]*node,
	ndecls: size,
};

// Use statement
export type n_use_data = struct {
	module_ptr: *u8,   // Full module path (e.g., "rt", "math::trig")
	module_len: size,
	alias_ptr: *u8,    // Alias name (e.g., "t" for explicit, "trig" for implicit)
	alias_len: size,
};

// Helper: allocate a node with data
export fn node_new(a: *arena, kind: node_kind, data_size: size, line: u32, col: u16) *node = {
	let n = arena_alloc(a, size(node)): *node;
	n.kind = kind;
	n.line = line;
	n.col = col;
	// Always allocate at least 1 byte to avoid null assignment
	if (data_size > 0) {
		n.data = arena_calloc(a, data_size);
	} else {
		n.data = arena_calloc(a, 1);
	};
	return n;
};

// Helper: allocate node array (always returns valid pointer, even for count=0)
export fn node_array(a: *arena, count: size) *[*]*node = {
	// Always allocate at least 8 bytes to ensure non-null pointer
	let alloc_size = count * size(*node);
	if (alloc_size < 8) {
		alloc_size = 8;
	};
	return arena_alloc(a, alloc_size): *[*]*node;
};

// Helper: check if node is a type node
export fn is_type_node(n: *node) bool = {
	let k = n.kind;
	return k == node_kind::N_TPRIM || k == node_kind::N_TPTR ||
	       k == node_kind::N_TSLICE || k == node_kind::N_TARR ||
	       k == node_kind::N_TSTRUCT || k == node_kind::N_TENUM ||
	       k == node_kind::N_TFUNC || k == node_kind::N_TALIAS;
};

// Node creation helpers - reduce boilerplate in parser

// Create integer literal node
export fn make_int(a: *arena, val: i64, line: u32, col: u16) *node = {
	let n = node_new(a, node_kind::N_INT, size(n_int_data), line, col);
	let d = n.data: *n_int_data;
	d.val = val;
	d.suffix = 0;
	return n;
};

// Create identifier node
export fn make_id(a: *arena, ptr: *u8, length: size, line: u32, col: u16) *node = {
	let n = node_new(a, node_kind::N_ID, size(n_id_data), line, col);
	let d = n.data: *n_id_data;
	d.ptr = ptr;
	d.length = length;
	return n;
};

// Create binary operation node
export fn make_bin(a: *arena, op: token_kind, left: *node, right: *node, line: u32, col: u16) *node = {
	let n = node_new(a, node_kind::N_BIN, size(n_bin_data), line, col);
	let d = n.data: *n_bin_data;
	d.op = op;
	d.left = left;
	d.right = right;
	return n;
};

// Create unary operation node
export fn make_un(a: *arena, op: token_kind, operand: *node, line: u32, col: u16) *node = {
	let n = node_new(a, node_kind::N_UN, size(n_un_data), line, col);
	let d = n.data: *n_un_data;
	d.op = op;
	d.operand = operand;
	return n;
};

// Create function call node
export fn make_call(a: *arena, func: *node, args: *[*]*node, nargs: size) *node = {
	let n = node_new(a, node_kind::N_CALL, size(n_call_data), func.line, func.col);
	let d = n.data: *n_call_data;
	d.func = func;
	d.args = args;
	d.nargs = nargs;
	return n;
};

// Create null literal node
export fn make_null(a: *arena, line: u32, col: u16) *node = {
	return node_new(a, node_kind::N_NULL, 0, line, col);
};

// Create void node
export fn make_void(a: *arena, line: u32, col: u16) *node = {
	return node_new(a, node_kind::N_VOID, 0, line, col);
};

// Create bool literal node
export fn make_bool(a: *arena, val: bool, line: u32, col: u16) *node = {
	let n = node_new(a, node_kind::N_BOOL, size(n_int_data), line, col);
	let d = n.data: *n_int_data;
	d.val = 0;
	if (val) { d.val = 1; };
	return n;
};

// Unwrap nullable pointer - returns non-null pointer or aborts
export fn unwrap(n: nullable *node) *node = {
	match (n) {
	case let nn: *node =>
		return nn;
	case null =>
		die("ast.ha: unwrap() - unexpected null node");
		abort();
	};
};

// Unwrap nullable u8 pointer
export fn unwrap_u8(p: nullable *u8) *u8 = {
	match (p) {
	case let pp: *u8 =>
		return pp;
	case null =>
		die("ast.ha: unwrap_u8() - unexpected null pointer");
		abort();
	};
};
