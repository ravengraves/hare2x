// transform.ha - AST to C code transformation
use rt;
use strings;

// Capacity limits - adjust these for larger codebases
def MAX_TRACKED_VARS: size = 128;      // Per-function variable trackers (str_vars, slice_vars, etc.)
def MAX_VARIANT_BINDINGS: size = 128;  // Match case bindings
def MAX_LOOP_DEFERS: size = 32;        // Defers in a single loop
def MAX_FN_DEFERS: size = 64;          // Defers in a single function
def MAX_TUPLE_TYPES: size = 32;        // Distinct tuple types
def MAX_TYPEDEFS: size = 256;          // Type definitions
def MAX_VAR_TYPES: size = 512;         // Variable type tracking (per function)
def MAX_FUNCTIONS: size = 1024;        // Function registry (return types, info)
def MAX_ALIASES: size = 64;            // Module aliases (use t = path)

// Simple variable tracking
export type var_tracker = struct {
	names: [MAX_TRACKED_VARS]*u8,
	lengths: [MAX_TRACKED_VARS]size,
	count: size,
};

// Module alias tracking (alias -> full path)
export type alias_map = struct {
	names: [MAX_ALIASES]*u8,
	lens: [MAX_ALIASES]size,
	path_ptrs: [MAX_ALIASES]*u8,
	path_lens: [MAX_ALIASES]size,
	count: size,
};

// Check if name is in tracker
export fn is_tracked_var(vt: *var_tracker, ptr: *u8, plen: size) bool = {
	let ptr_bytes = ptr: *[*]u8;
	for (let i = 0z; i < vt.count; i += 1) {
		if (vt.lengths[i] == plen) {
			let matched = true;
			let name_bytes = vt.names[i]: *[*]u8;
			for (let j = 0z; j < plen; j += 1) {
				if (name_bytes[j] != ptr_bytes[j]) {
					matched = false;
				};
			};
			if (matched) return true;
		};
	};
	return false;
};

// Add a variable to tracker
export fn add_tracked_var(vt: *var_tracker, ptr: *u8, plen: size) void = {
	if (vt.count < MAX_TRACKED_VARS) {
		vt.names[vt.count] = ptr;
		vt.lengths[vt.count] = plen;
		vt.count += 1;
	};
};

// Clear all tracked variables
export fn clear_tracked_vars(vt: *var_tracker) void = {
	vt.count = 0;
};

// Variant binding tracker - stores (var_name, type_name) pairs
export type variant_binding_tracker = struct {
	var_names: [MAX_VARIANT_BINDINGS]*u8,
	var_lengths: [MAX_VARIANT_BINDINGS]size,
	type_names: [MAX_VARIANT_BINDINGS]*u8,
	type_lengths: [MAX_VARIANT_BINDINGS]size,
	count: size,
};

// Get variant type for a variable (returns null if not found)
export fn get_variant_type(vt: *variant_binding_tracker, ptr: *u8, plen: size) nullable *u8 = {
	let ptr_bytes = ptr: *[*]u8;
	for (let i = 0z; i < vt.count; i += 1) {
		if (vt.var_lengths[i] == plen) {
			let matched = true;
			let name_bytes = vt.var_names[i]: *[*]u8;
			for (let j = 0z; j < plen; j += 1) {
				if (name_bytes[j] != ptr_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return vt.type_names[i];
			};
		};
	};
	return null;
};

// Get variant type length for a variable (returns 0 if not found)
export fn get_variant_type_len(vt: *variant_binding_tracker, ptr: *u8, plen: size) size = {
	let ptr_bytes = ptr: *[*]u8;
	for (let i = 0z; i < vt.count; i += 1) {
		if (vt.var_lengths[i] == plen) {
			let matched = true;
			let name_bytes = vt.var_names[i]: *[*]u8;
			for (let j = 0z; j < plen; j += 1) {
				if (name_bytes[j] != ptr_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return vt.type_lengths[i];
			};
		};
	};
	return 0;
};

// Add a variant binding
export fn add_variant_binding(vt: *variant_binding_tracker, var_ptr: *u8, var_len: size, type_ptr: *u8, type_len: size) void = {
	if (vt.count < MAX_VARIANT_BINDINGS) {
		vt.var_names[vt.count] = var_ptr;
		vt.var_lengths[vt.count] = var_len;
		vt.type_names[vt.count] = type_ptr;
		vt.type_lengths[vt.count] = type_len;
		vt.count += 1;
	};
};

// Clear variant bindings
export fn clear_variant_bindings(vt: *variant_binding_tracker) void = {
	vt.count = 0;
};

// Helper functions for string variable tracking (using var_tracker)
fn is_str_var(sv: *var_tracker, ptr: *u8, plen: size) bool = is_tracked_var(sv, ptr, plen);
fn add_str_var(sv: *var_tracker, ptr: *u8, plen: size) void = add_tracked_var(sv, ptr, plen);

// Transformation context - passed during transformation
export type transform_ctx = struct {
	arena: *arena,
	output: *strbuf,
	str_vars: var_tracker,
	slice_vars: var_tracker,  // Track slice variables for proper indexing
	arr_vars: var_tracker,    // Track array variables for slice conversion
	arr_elem_types: variant_binding_tracker,  // Track array variable element types
	slice_elem_types: variant_binding_tracker,  // Track slice variable element types
	ptr_vars: var_tracker,    // Track pointer variables for -> field access
	ptr_uarr_vars: var_tracker, // Track *[*]T variables for pointer indexing
	tagged_types: var_tracker, // Track tagged union type names
	enum_types: var_tracker,  // Track enum type names (to detect match on enum)
	ptr_fns: var_tracker,     // Track functions that return pointers
	void_success_types: var_tracker,  // Track tagged union type names with void as success type
	void_result_fns: var_tracker,  // Track functions returning tagged unions with void success
	local_vars: var_tracker,  // Track all local variables (params + let bindings)
	global_vars: var_tracker, // Track global variables for shadowing check
	variant_bindings: variant_binding_tracker,  // Track match case bindings with their types
	// Current function return type (for tagged union returns)
	ret_type: nullable *node,
	ret_name_ptr: *u8,
	ret_name_len: size,
	// Current function name for inline tagged union returns
	cur_fn_name_ptr: *u8,
	cur_fn_name_len: size,
	// Expected slice element type (for alloc with array literal)
	expected_slice_elem: nullable *node,
	// Flag to track if we're expecting an f32 value (for float literal suffix)
	expecting_f32: bool,
	// Defers in current loop scope (for break/continue)
	loop_defers: [MAX_LOOP_DEFERS]*node,
	loop_defer_count: size,
	// All defers in current function scope (for return)
	fn_defers: [MAX_FN_DEFERS]*node,
	fn_defer_count: size,
	// Tuple types (for typedef generation)
	tuple_types: [MAX_TUPLE_TYPES]*node,
	tuple_count: size,
	// Typedef tracker for spread type expansion
	typedef_names: [MAX_TYPEDEFS]*u8,
	typedef_lens: [MAX_TYPEDEFS]size,
	typedef_nodes: [MAX_TYPEDEFS]*node,
	typedef_count: size,
	// Variable type tracker (maps var names to their type nodes)
	var_type_names: [MAX_VAR_TYPES]*u8,
	var_type_lens: [MAX_VAR_TYPES]size,
	var_type_nodes: [MAX_VAR_TYPES]*node,
	var_type_count: size,
	// Global variable type tracker (maps global var names to their type nodes)
	global_var_type_names: [MAX_VAR_TYPES]*u8,
	global_var_type_lens: [MAX_VAR_TYPES]size,
	global_var_type_nodes: [MAX_VAR_TYPES]*node,
	global_var_type_count: size,
	// Function return type tracker (maps fn names to return type nodes)
	fn_ret_names: [MAX_FUNCTIONS]*u8,
	fn_ret_lens: [MAX_FUNCTIONS]size,
	fn_ret_nodes: [MAX_FUNCTIONS]*node,
	fn_ret_count: size,
	// Function info tracker (for variadic calls and defaults)
	fn_info_names: [MAX_FUNCTIONS]*u8,
	fn_info_lens: [MAX_FUNCTIONS]size,
	fn_info_nodes: [MAX_FUNCTIONS]*node,  // The N_FN node
	fn_info_count: size,
	// @symbol name tracker (maps symbol names to check for invalid calls)
	symbol_names: [MAX_FUNCTIONS]*u8,
	symbol_lens: [MAX_FUNCTIONS]size,
	symbol_count: size,
	// Flag: are we processing an expression that will be returned?
	in_return_expr: bool,
	// Flag: are we emitting an lvalue (assignment target)?
	in_lvalue: bool,
	// Error tracking for compile-time checks
	has_errors: bool,
	error_count: size,
	// Track narrowed nullable pointer (for match case bodies)
	narrowed_nullable_ptr: *u8,
	narrowed_nullable_len: size,
	// Track imported modules
	use_strings: bool,
	// Prefix for exported function names (-p flag)
	prefix_ptr: *u8,
	prefix_len: size,
	// Flag: is the result of an expression used? (for match/switch __r emission)
	result_used: bool,
	// Module alias tracking (maps alias -> full path)
	aliases: alias_map,
};

// Look up a typedef by name (returns null if not found)
export fn find_typedef(ctx: *transform_ctx, name_ptr: *u8, name_len: size) nullable *node = {
	let name_bytes = name_ptr: *[*]u8;
	for (let i = 0z; i < ctx.typedef_count; i += 1) {
		if (ctx.typedef_lens[i] == name_len) {
			let matched = true;
			let typedef_bytes = ctx.typedef_names[i]: *[*]u8;
			for (let j = 0z; j < name_len; j += 1) {
				if (typedef_bytes[j] != name_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return ctx.typedef_nodes[i];
			};
		};
	};
	return null;
};

// Add a typedef to the tracker
export fn add_typedef(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: *node) void = {
	if (ctx.typedef_count < MAX_TYPEDEFS) {
		ctx.typedef_names[ctx.typedef_count] = name_ptr;
		ctx.typedef_lens[ctx.typedef_count] = name_len;
		ctx.typedef_nodes[ctx.typedef_count] = typ;
		ctx.typedef_count += 1;
	};
};

// Track a variable's type
export fn add_var_type(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: *node) void = {
	if (ctx.var_type_count < MAX_VAR_TYPES) {
		ctx.var_type_names[ctx.var_type_count] = name_ptr;
		ctx.var_type_lens[ctx.var_type_count] = name_len;
		ctx.var_type_nodes[ctx.var_type_count] = typ;
		ctx.var_type_count += 1;
	};
};

// Track a global variable's type
export fn add_global_var_type(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: *node) void = {
	if (ctx.global_var_type_count < MAX_VAR_TYPES) {
		ctx.global_var_type_names[ctx.global_var_type_count] = name_ptr;
		ctx.global_var_type_lens[ctx.global_var_type_count] = name_len;
		ctx.global_var_type_nodes[ctx.global_var_type_count] = typ;
		ctx.global_var_type_count += 1;
	};
};

// Look up a variable's type (returns null if not found)
export fn find_var_type(ctx: *transform_ctx, name_ptr: *u8, name_len: size) nullable *node = {
	let name_bytes = name_ptr: *[*]u8;
	let i = ctx.var_type_count;
	for (i > 0) {
		i -= 1;
		if (ctx.var_type_lens[i] == name_len) {
			let matched = true;
			let var_bytes = ctx.var_type_names[i]: *[*]u8;
			for (let j = 0z; j < name_len; j += 1) {
				if (var_bytes[j] != name_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return ctx.var_type_nodes[i];
			};
		};
	};
	// Fall back to global variables
	i = ctx.global_var_type_count;
	for (i > 0) {
		i -= 1;
		if (ctx.global_var_type_lens[i] == name_len) {
			let matched = true;
			let var_bytes = ctx.global_var_type_names[i]: *[*]u8;
			for (let j = 0z; j < name_len; j += 1) {
				if (var_bytes[j] != name_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return ctx.global_var_type_nodes[i];
			};
		};
	};
	return null;
};

// Clear variable types (at function scope boundaries)
export fn clear_var_types(ctx: *transform_ctx) void = {
	ctx.var_type_count = 0;
};

// Emit a compile-time error message to stderr with optional location
fn emit_error_at(ctx: *transform_ctx, line: u32, col: u16, msg: str) void = {
	if (line > 0 && col > 0) {
		write_int(line);
		rt::write(2, strings::toutf8(":"): *[*]u8, 1);
		write_int(col: u32);
		rt::write(2, strings::toutf8(": error: "): *[*]u8, 9);
		rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
		rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
		write_error_context(line, col);
	} else {
		rt::write(2, strings::toutf8("error: "): *[*]u8, 7);
		rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
		rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
	};
	ctx.has_errors = true;
	ctx.error_count += 1;
};

// Emit a compile-time error with variable name context and optional location
fn emit_error_with_name_at(ctx: *transform_ctx, line: u32, col: u16, prefix: str, name_ptr: *u8, name_len: size, suffix: str) void = {
	if (line > 0 && col > 0) {
		write_int(line);
		rt::write(2, strings::toutf8(":"): *[*]u8, 1);
		write_int(col: u32);
		rt::write(2, strings::toutf8(": error: "): *[*]u8, 9);
	} else {
		rt::write(2, strings::toutf8("error: "): *[*]u8, 7);
	};
	rt::write(2, strings::toutf8(prefix): *[*]u8, len(prefix));
	rt::write(2, strings::toutf8("'"): *[*]u8, 1);
	rt::write(2, name_ptr, name_len);
	rt::write(2, strings::toutf8("'"): *[*]u8, 1);
	rt::write(2, strings::toutf8(suffix): *[*]u8, len(suffix));
	rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
	if (line > 0 && col > 0) {
		write_error_context(line, col);
	};
	ctx.has_errors = true;
	ctx.error_count += 1;
};

// Emit a compile-time error message to stderr
export fn emit_error(ctx: *transform_ctx, msg: str) void = {
	emit_error_at(ctx, 0, 0, msg);
};

export fn emit_error_at_node(ctx: *transform_ctx, n: *node, msg: str) void = {
	emit_error_at(ctx, n.line, n.col, msg);
};

export fn emit_error_at_optional(ctx: *transform_ctx, n_nullable: nullable *node, msg: str) void = {
	match (n_nullable) {
	case let n: *node =>
		emit_error_at(ctx, n.line, n.col, msg);
	case null =>
		emit_error_at(ctx, 0, 0, msg);
	};
};

// Emit a compile-time error with variable name context
export fn emit_error_with_name(ctx: *transform_ctx, prefix: str, name_ptr: *u8, name_len: size, suffix: str) void = {
	emit_error_with_name_at(ctx, 0, 0, prefix, name_ptr, name_len, suffix);
};

export fn emit_error_with_name_at_node(ctx: *transform_ctx, n: *node, prefix: str, name_ptr: *u8, name_len: size, suffix: str) void = {
	emit_error_with_name_at(ctx, n.line, n.col, prefix, name_ptr, name_len, suffix);
};

export fn emit_error_with_name_at_optional(ctx: *transform_ctx, n_nullable: nullable *node, prefix: str, name_ptr: *u8, name_len: size, suffix: str) void = {
	match (n_nullable) {
	case let n: *node =>
		emit_error_with_name_at(ctx, n.line, n.col, prefix, name_ptr, name_len, suffix);
	case null =>
		emit_error_with_name_at(ctx, 0, 0, prefix, name_ptr, name_len, suffix);
	};
};

// Emit a compile-time warning message to stderr (non-fatal)
export fn emit_warning(ctx: *transform_ctx, msg: str) void = {
	ctx.error_count += 0;  // Reserve ctx usage for future warning tracking.
	rt::write(2, strings::toutf8("warning: "): *[*]u8, 9);
	rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
	rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
};

// Count pointer depth of a type node (for auto-dereference in field access)
// Returns 0 for non-pointer types, 1 for *T, 2 for **T, etc.
export fn count_ptr_depth(typ: nullable *node) size = {
	match (typ) {
	case let t: *node =>
		let cur = t;
		let depth = 0z;
		for (cur.kind == node_kind::N_TPTR) {
			depth += 1;
			let pd = cur.data: *n_tptr_data;
			cur = pd.inner;
		};
		return depth;
	case null =>
		return 0z;
	};
};

// Get compile-time array length for a tracked array variable (null if not found)
export fn get_arr_len(ctx: *transform_ctx, ptr: *u8, plen: size) nullable *node = {
	if (!is_tracked_var(&ctx.arr_vars, ptr, plen)) {
		return null;
	};
	let t = find_var_type(ctx, ptr, plen);
	match (t) {
	case let tnode: *node =>
		if (tnode.kind != node_kind::N_TARR) {
			return null;
		};
		let ad = tnode.data: *n_tarr_data;
		return ad.length;
	case null =>
		return null;
	};
};

// Get the inner type of a pointer (unwrap one level of pointer)
fn unwrap_ptr(typ: *node) nullable *node = {
	if (typ.kind == node_kind::N_TPTR) {
		let pd = typ.data: *n_tptr_data;
		return pd.inner;
	};
	return null;
};

// Look up a struct field's type by name
// Returns null if struct not found or field not found
fn get_struct_field_type(ctx: *transform_ctx, struct_type: *node, field_ptr: *u8, field_len: size) nullable *node = {
	let t = struct_type;

	// If it's a type name (N_TPRIM for user-defined types), resolve it via typedef
	if (t.kind == node_kind::N_TPRIM) {
		let ad = t.data: *n_id_data;
		let resolved = find_typedef(ctx, ad.ptr, ad.length);
		match (resolved) {
		case let r: *node =>
			t = r;
		case null =>
			return null;
		};
	};

	// If it's a type alias (N_TALIAS), also resolve it
	if (t.kind == node_kind::N_TALIAS) {
		let ad = t.data: *n_id_data;
		let resolved = find_typedef(ctx, ad.ptr, ad.length);
		match (resolved) {
		case let r: *node =>
			t = r;
		case null =>
			return null;
		};
	};

	// Must be a struct type
	if (t.kind != node_kind::N_TSTRUCT) {
		return null;
	};

	let field_bytes = field_ptr: *[*]u8;
	let sd = t.data: *n_tstruct_data;
	for (let i = 0z; i < sd.nfields; i += 1) {
		let field = sd.fields[i];
		// Fields are N_FIELD nodes with n_param_data (name + type)
		if (field.kind == node_kind::N_FIELD) {
			let fd = field.data: *n_param_data;
			if (fd.name_len == field_len) {
				let matched = true;
				let name_bytes = fd.name_ptr: *[*]u8;
				for (let j = 0z; j < field_len; j += 1) {
					if (name_bytes[j] != field_bytes[j]) {
						matched = false;
					};
				};
				if (matched) {
					return fd.typ;
				};
			};
		};
	};
	return null;
};

// Infer the type of an expression
// Used for determining if field access needs pointer dereference
export fn infer_expr_type(ctx: *transform_ctx, n: *node) nullable *node = {
	let k = n.kind;

	// Variable reference - look up tracked type
	if (k == node_kind::N_ID) {
		let id = n.data: *n_id_data;
		return find_var_type(ctx, id.ptr, id.length);
	};

	// Cast expression - type is the target type
	if (k == node_kind::N_CAST) {
		let cd = n.data: *n_cast_data;
		return cd.target;
	};

	// Function call - look up return type
	if (k == node_kind::N_CALL) {
		let cd = n.data: *n_call_data;
		if (cd.func.kind == node_kind::N_ID) {
			let func_id = cd.func.data: *n_id_data;
			return find_fn_ret_type(ctx, func_id.ptr, func_id.length);
		};
		return null;
	};

	// Field access - get base type, unwrap pointers, look up field type
	if (k == node_kind::N_FLD) {
		let fd = n.data: *n_fld_data;
		let base_type = infer_expr_type(ctx, fd.base);
		match (base_type) {
		case let t: *node =>
			// Unwrap pointer levels
			let cur = t;
			for (cur.kind == node_kind::N_TPTR) {
				let pd = cur.data: *n_tptr_data;
				cur = pd.inner;
			};
			// Look up field type in struct
			return get_struct_field_type(ctx, cur, fd.field_ptr, fd.field_len);
		case null =>
			return null;
		};
	};

	// Index expression - get element type
	if (k == node_kind::N_IDX) {
		let id = n.data: *n_idx_data;
		let base_type = infer_expr_type(ctx, id.base);
		match (base_type) {
		case let bt: *node =>
			// Array type - element is at elem field
			if (bt.kind == node_kind::N_TARR) {
				let ad = bt.data: *n_tarr_data;
				return ad.elem;
			};
			// Slice type - uses same data as array (n_tarr_data)
			if (bt.kind == node_kind::N_TSLICE) {
				let sd = bt.data: *n_tarr_data;
				return sd.elem;
			};
			// Pointer type - could be *[*]T or just *T
			if (bt.kind == node_kind::N_TPTR) {
				let pd = bt.data: *n_tptr_data;
				// Check if pointing to unbounded array
				if (pd.inner.kind == node_kind::N_TARR) {
					let ad = pd.inner.data: *n_tarr_data;
					if (ad.length == null) {
						// *[*]T - return element type T
						return ad.elem;
					};
				};
				// Just *T - return T
				return pd.inner;
			};
		case null => void;
		};
	};

	// Unary operators
	if (k == node_kind::N_UN) {
		let ud = n.data: *n_un_data;
		if (ud.op == token_kind::AMP) {
			// Handle &(expr: *T) as if the cast applied to &expr (parser precedence)
			// This avoids inferring **T for patterns like &arr: *[*]T.
			if (ud.operand.kind == node_kind::N_CAST) {
				let cd = ud.operand.data: *n_cast_data;
				if (cd.target.kind == node_kind::N_TPTR) {
					return cd.target;
				};
			};
			// &expr - create a new pointer type node wrapping the operand's type
			let inner_type = infer_expr_type(ctx, ud.operand);
			match (inner_type) {
			case let it: *node =>
				// Create a new N_TPTR node
				let ptr_node = node_new(ctx.arena, node_kind::N_TPTR, size(n_tptr_data), 0, 0);
				let pd = ptr_node.data: *n_tptr_data;
				pd.inner = it;
				pd.is_nullable = false;
				pd.is_const = false;
				return ptr_node;
			case null => void;
			};
			return null;
		};
		if (ud.op == token_kind::STAR) {
			// *expr - unwrap pointer
			let inner_type = infer_expr_type(ctx, ud.operand);
			match (inner_type) {
			case let it: *node =>
				return unwrap_ptr(it);
			case null => void;
			};
		};
	};

	// Error propagation/unwrap - use non-error variant when possible
	if (k == node_kind::N_PROP || k == node_kind::N_UNWRAP) {
		let pd = n.data: *n_prop_data;
		let inner_type = infer_expr_type(ctx, pd.expr);
		match (inner_type) {
		case let it: *node =>
			match (get_error_result_variant(ctx, it)) {
			case let rt: *node => return rt;
			case null => return it;
			};
		case null => return null;
		};
	};

	return null;
};

// Resolve a type alias to its underlying definition when available.
fn resolve_type_alias(ctx: *transform_ctx, typ: *node) *node = {
	if (typ.kind == node_kind::N_TPRIM || typ.kind == node_kind::N_TALIAS) {
		let td = typ.data: *n_id_data;
		if (typ.kind == node_kind::N_TPRIM && is_prim_type_name(td.ptr, td.length)) {
			return typ;
		};
		let resolved = find_typedef(ctx, td.ptr, td.length);
		match (resolved) {
		case let r: *node => return unwrap(r);
		case null => void;
		};
	};
	return typ;
};

// Resolve a tagged union type from an alias or return null if not tagged.
fn resolve_tagged_type(ctx: *transform_ctx, typ: *node) nullable *node = {
	let resolved = resolve_type_alias(ctx, typ);
	if (resolved.kind == node_kind::N_TTAGGED) {
		return resolved;
	};
	return null;
};

// Check whether a variant represents an error type.
fn is_error_variant(ctx: *transform_ctx, variant: *node) bool = {
	if (variant.kind == node_kind::N_TERR || variant.kind == node_kind::N_TNOMEM) {
		return true;
	};
	let resolved = resolve_type_alias(ctx, variant);
	return resolved.kind == node_kind::N_TERR || resolved.kind == node_kind::N_TNOMEM;
};

// Check if a type node represents void (including aliases).
fn is_void_type_node(ctx: *transform_ctx, typ: *node) bool = {
	let resolved = resolve_type_alias(ctx, typ);
	if (resolved.kind != node_kind::N_TPRIM) return false;
	let td = resolved.data: *n_id_data;
	return type_name_is(td.ptr, td.length, "void");
};

// Get the non-error result variant of a tagged union type (if any).
fn get_error_result_variant(ctx: *transform_ctx, typ: nullable *node) nullable *node = {
	match (typ) {
	case let t: *node =>
		match (resolve_tagged_type(ctx, t)) {
		case let tagged: *node =>
			let td = tagged.data: *n_ttagged_data;
			let fallback: nullable *node = null;
			for (let i = 0z; i < td.nvariants; i += 1) {
				let variant = td.variants[i];
				if (is_error_variant(ctx, variant)) {
					continue;
				};
				if (fallback == null) {
					fallback = variant;
				};
				if (!is_void_type_node(ctx, variant)) {
					return variant;
				};
			};
			return fallback;
		case null => return null;
		};
	case null => return null;
	};
};

// Track a function's return type
export fn add_fn_ret_type(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: *node) void = {
	if (ctx.fn_ret_count < MAX_FUNCTIONS) {
		ctx.fn_ret_names[ctx.fn_ret_count] = name_ptr;
		ctx.fn_ret_lens[ctx.fn_ret_count] = name_len;
		ctx.fn_ret_nodes[ctx.fn_ret_count] = typ;
		ctx.fn_ret_count += 1;
	};
};

// Look up a function's return type (returns null if not found)
export fn find_fn_ret_type(ctx: *transform_ctx, name_ptr: *u8, name_len: size) nullable *node = {
	let name_bytes = name_ptr: *[*]u8;
	for (let i = 0z; i < ctx.fn_ret_count; i += 1) {
		if (ctx.fn_ret_lens[i] == name_len) {
			let matched = true;
			let fn_bytes = ctx.fn_ret_names[i]: *[*]u8;
			for (let j = 0z; j < name_len; j += 1) {
				if (fn_bytes[j] != name_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return ctx.fn_ret_nodes[i];
			};
		};
	};
	return null;
};

// Track a function's full info (for variadic calls and defaults)
export fn add_fn_info(ctx: *transform_ctx, name_ptr: *u8, name_len: size, fn_node: *node) void = {
	if (ctx.fn_info_count < MAX_FUNCTIONS) {
		ctx.fn_info_names[ctx.fn_info_count] = name_ptr;
		ctx.fn_info_lens[ctx.fn_info_count] = name_len;
		ctx.fn_info_nodes[ctx.fn_info_count] = fn_node;
		ctx.fn_info_count += 1;
	};
};

// Look up a function's info node (returns null if not found)
export fn find_fn_info(ctx: *transform_ctx, name_ptr: *u8, name_len: size) nullable *node = {
	let name_bytes = name_ptr: *[*]u8;
	for (let i = 0z; i < ctx.fn_info_count; i += 1) {
		if (ctx.fn_info_lens[i] == name_len) {
			let matched = true;
			let fn_bytes = ctx.fn_info_names[i]: *[*]u8;
			for (let j = 0z; j < name_len; j += 1) {
				if (fn_bytes[j] != name_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return ctx.fn_info_nodes[i];
			};
		};
	};
	return null;
};

// Track a @symbol name (to detect invalid calls by symbol name)
export fn add_symbol_name(ctx: *transform_ctx, symbol_ptr: *u8, symbol_len: size) void = {
	if (ctx.symbol_count < MAX_FUNCTIONS) {
		ctx.symbol_names[ctx.symbol_count] = symbol_ptr;
		ctx.symbol_lens[ctx.symbol_count] = symbol_len;
		ctx.symbol_count += 1;
	};
};

// Check if a name is a known @symbol name (returns true if it's a symbol name)
export fn is_symbol_name(ctx: *transform_ctx, name_ptr: *u8, name_len: size) bool = {
	let name_bytes = name_ptr: *[*]u8;
	for (let i = 0z; i < ctx.symbol_count; i += 1) {
		if (ctx.symbol_lens[i] == name_len) {
			let matched = true;
			let symbol_bytes = ctx.symbol_names[i]: *[*]u8;
			for (let j = 0z; j < name_len; j += 1) {
				if (symbol_bytes[j] != name_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				return true;
			};
		};
	};
	return false;
};

// Add a module alias (use t = path;)
export fn add_alias(ctx: *transform_ctx, alias_ptr: *u8, alias_len: size, path_ptr: *u8, path_len: size) void = {
	if (ctx.aliases.count < MAX_ALIASES) {
		ctx.aliases.names[ctx.aliases.count] = alias_ptr;
		ctx.aliases.lens[ctx.aliases.count] = alias_len;
		ctx.aliases.path_ptrs[ctx.aliases.count] = path_ptr;
		ctx.aliases.path_lens[ctx.aliases.count] = path_len;
		ctx.aliases.count += 1;
	};
};

// Find full path for an alias (returns path_ptr, path_len or null if not found)
export fn find_alias_path(
	ctx: *transform_ctx,
	alias_ptr: *u8,
	alias_len: size,
	out_len: *size
) nullable *u8 = {
	let alias_bytes = alias_ptr: *[*]u8;
	for (let i = 0z; i < ctx.aliases.count; i += 1) {
		if (ctx.aliases.lens[i] == alias_len) {
			let matched = true;
			let stored_bytes = ctx.aliases.names[i]: *[*]u8;
			for (let j = 0z; j < alias_len; j += 1) {
				if (stored_bytes[j] != alias_bytes[j]) {
					matched = false;
				};
			};
			if (matched) {
				*out_len = ctx.aliases.path_lens[i];
				return ctx.aliases.path_ptrs[i];
			};
		};
	};
	*out_len = 0;
	return null;
};

// Check if a name matches module_member, considering namespace aliases.
export fn name_matches_module_member(
	ctx: *transform_ctx,
	name_ptr: *u8,
	name_len: size,
	module: str,
	member: str
) bool = {
	let module_len = len(module);
	let member_len = len(member);
	let name_bytes = name_ptr: *[*]u8;
	let module_bytes = strings::toutf8(module): *[*]u8: *u8;
	let member_bytes = strings::toutf8(member): *[*]u8: *u8;

	// Direct match: module_member
	if (name_len == module_len + 1 + member_len) {
		if (bytes_eq(name_ptr, module_bytes, module_len) &&
			name_bytes[module_len] == '_' &&
			bytes_eq((name_ptr: uintptr + module_len + 1: uintptr): *u8, member_bytes, member_len)) {
			return true;
		};
	};

	// Alias match: alias_member where alias -> module
	let underscore_pos: size = 0;
	for (underscore_pos < name_len && name_bytes[underscore_pos] != '_') {
		underscore_pos += 1;
	};
	if (underscore_pos < name_len) {
		let path_len: size = 0;
		let path_ptr = find_alias_path(ctx, name_ptr, underscore_pos, &path_len);
		match (path_ptr) {
		case let pp: *u8 =>
			if (!streq(pp, path_len, module)) { return false; };
			if (name_len - underscore_pos != 1 + member_len) { return false; };
			if (!bytes_eq((name_ptr: uintptr + underscore_pos + 1: uintptr): *u8, member_bytes, member_len)) {
				return false;
			};
			return true;
		case null => void;
		};
	};

	return false;
};

// Check if two types are structurally equivalent
// Returns true if actual type can be assigned to expected type
export fn types_assignable(ctx: *transform_ctx, expected: nullable *node, actual: nullable *node) bool = {
	// Handle null cases
	match (expected) {
	case null => return true;  // void expected, anything assignable
	case let e: *node => {
		match (actual) {
		case null => return true;  // void actual to void expected
		case let a: *node => {
			// Both non-null, compare types
			// If kinds differ, check special cases
			if (e.kind != a.kind) {
				// Special case: null can be assigned to nullable pointer
				if (a.kind == node_kind::N_NULL && e.kind == node_kind::N_TPTR) {
					let pd = e.data: *n_tptr_data;
					return pd.is_nullable;
				};
				// Special case: tagged union expected, variant actual
				// e.g., (int | void) expected, int actual
				if (e.kind == node_kind::N_TTAGGED) {
					let td = e.data: *n_ttagged_data;
					// Check if actual is one of the variants
					for (let i = 0z; i < td.nvariants; i += 1) {
						if (types_assignable(ctx, td.variants[i], actual)) {
							return true;
						};
					};
					return false;
				};
				// Primitive types might be aliases - resolve them
				if (e.kind == node_kind::N_TALIAS) {
					let ed = e.data: *n_id_data;
					let resolved = find_typedef(ctx, ed.ptr, ed.length);
					if (resolved != null) {
						return types_assignable(ctx, resolved, actual);
					};
				};
				if (a.kind == node_kind::N_TALIAS) {
					let ad = a.data: *n_id_data;
					let resolved = find_typedef(ctx, ad.ptr, ad.length);
					if (resolved != null) {
						return types_assignable(ctx, expected, resolved);
					};
				};
				// If we can't determine compatibility, be lenient
				// (unknown types should not cause errors)
				return true;
			};

			// Same kind - check based on type kind
			if (e.kind == node_kind::N_TPRIM) {
				// Primitive types - check name
				let ed = e.data: *n_id_data;
				let ad = a.data: *n_id_data;
				// First try exact match
				let names_match = true;
				if (ed.length != ad.length) {
					names_match = false;
				} else {
					let ed_bytes = ed.ptr: *[*]u8;
					let ad_bytes = ad.ptr: *[*]u8;
					for (let i = 0z; i < ed.length; i += 1) {
						if (ed_bytes[i] != ad_bytes[i]) {
							names_match = false;
						};
					};
				};
				if (names_match) {
					return true;
				};
				// Names don't match - check if expected is a typedef (user-defined type)
				// that resolves to a tagged union containing actual as a variant
				let resolved = find_typedef(ctx, ed.ptr, ed.length);
				if (resolved != null) {
					return types_assignable(ctx, resolved, actual);
				};
				// Also try resolving actual (e.g., actual might be a type alias)
				let resolved_a = find_typedef(ctx, ad.ptr, ad.length);
				if (resolved_a != null) {
					return types_assignable(ctx, expected, resolved_a);
				};
				// Types don't match and couldn't resolve
				return false;
			};

			if (e.kind == node_kind::N_TPTR) {
				// Pointer types - check inner type
				let ed = e.data: *n_tptr_data;
				let ad = a.data: *n_tptr_data;
				// Non-nullable expected, nullable actual = error
				// (handled elsewhere by check_nonnull_assignment)
				// Check inner types recursively
				return types_assignable(ctx, ed.inner, ad.inner);
			};

			if (e.kind == node_kind::N_TARR) {
				// Array types - must match element type AND length
				let ed = e.data: *n_tarr_data;
				let ad = a.data: *n_tarr_data;
				// Check if both are unbounded or both have same length
				if (ed.length == null && ad.length != null) {
					return false;  // Expected [*]T, got [N]T
				};
				if (ed.length != null && ad.length == null) {
					return false;  // Expected [N]T, got [*]T
				};
				// Check element type
				return types_assignable(ctx, ed.elem, ad.elem);
			};

			if (e.kind == node_kind::N_TSLICE) {
				// Slice types - check element type
				let ed = e.data: *n_tarr_data;  // N_TSLICE uses n_tarr_data
				let ad = a.data: *n_tarr_data;
				return types_assignable(ctx, ed.elem, ad.elem);
			};

			// For other types, assume compatible
			return true;
		};
		};
	};
	};
};

// Check if actual type can be assigned to expected, emit error if not
// Returns true if types are compatible
export fn check_type_assignable(ctx: *transform_ctx, expected: nullable *node, actual: nullable *node, context_msg: str) bool = {
	if (!types_assignable(ctx, expected, actual)) {
		emit_error(ctx, context_msg);
		return false;
	};
	return true;
};

// Find tag index for a variant in a tagged union type
// Returns -1 if not found or if type is not a tagged union
fn find_variant_tag_in_type(tagged_type: *node, variant_ptr: *u8, variant_len: size) i64 = {
	if (tagged_type.kind != node_kind::N_TTAGGED) {
		return -1;
	};
	let variant_bytes = variant_ptr: *[*]u8;
	let td = tagged_type.data: *n_ttagged_data;
	for (let i = 0z; i < td.nvariants; i += 1) {
		let variant = td.variants[i];
		if (variant.kind == node_kind::N_TPRIM) {
			let vd = variant.data: *n_id_data;
			if (vd.length == variant_len) {
				let matched = true;
				let vd_bytes = vd.ptr: *[*]u8;
				for (let j = 0z; j < variant_len; j += 1) {
					if (vd_bytes[j] != variant_bytes[j]) {
						matched = false;
					};
				};
				if (matched) {
					return i: i64;
				};
			};
		} else if (variant.kind == node_kind::N_TALIAS) {
			let vd = variant.data: *n_id_data;
			if (vd.length == variant_len) {
				let matched = true;
				let vd_bytes = vd.ptr: *[*]u8;
				for (let j = 0z; j < variant_len; j += 1) {
					if (vd_bytes[j] != variant_bytes[j]) {
						matched = false;
					};
				};
				if (matched) {
					return i: i64;
				};
			};
		} else if (variant.kind == node_kind::N_VOID) {
			// Check if we're looking for "void"
			let variant_str = strings::fromutf8_unsafe((variant_ptr: *[*]u8)[..variant_len]);
			if (variant_str == "void") {
				return i: i64;
			};
		};
	};
	return -1;
};

// Helper to check if a byte sequence equals a string constant
fn type_name_is(ptr: *u8, plen: size, key: str) bool = {
	let s = strings::fromutf8_unsafe((ptr: *[*]u8)[..plen]);
	return s == key;
};

// Check if a type name is a primitive type (int, str, bool, etc.)
fn is_prim_type_name(ptr: *u8, plen: size) bool = {
	return type_name_is(ptr, plen, "int") ||
	       type_name_is(ptr, plen, "uint") ||
	       type_name_is(ptr, plen, "i8") ||
	       type_name_is(ptr, plen, "i16") ||
	       type_name_is(ptr, plen, "i32") ||
	       type_name_is(ptr, plen, "i64") ||
	       type_name_is(ptr, plen, "u8") ||
	       type_name_is(ptr, plen, "u16") ||
	       type_name_is(ptr, plen, "u32") ||
	       type_name_is(ptr, plen, "u64") ||
	       type_name_is(ptr, plen, "f32") ||
	       type_name_is(ptr, plen, "f64") ||
	       type_name_is(ptr, plen, "bool") ||
	       type_name_is(ptr, plen, "str") ||
	       type_name_is(ptr, plen, "rune") ||
	       type_name_is(ptr, plen, "char") ||
	       type_name_is(ptr, plen, "void") ||
	       type_name_is(ptr, plen, "done") ||
	       type_name_is(ptr, plen, "size") ||
	       type_name_is(ptr, plen, "uintptr");
};

// Emit an argument with f32 context for float literals when needed.
fn emit_call_arg(ctx: *transform_ctx, arg: *node, param_type: nullable *node) void = {
	let want_f32 = false;
	let slice_elem: nullable *node = null;
	let slice_type: nullable *node = null;
	let slice_elem_f32 = false;
	let param_tagged: nullable *node = null;
	let param_name_ptr: nullable *u8 = null;
	let param_name_len: size = 0;
	match (param_type) {
	case let t: *node =>
		let resolved = resolve_type_alias(ctx, t);
		if (resolved.kind == node_kind::N_TTAGGED) {
			param_tagged = resolved;
			if (t.kind == node_kind::N_TPRIM || t.kind == node_kind::N_TALIAS) {
				let td = t.data: *n_id_data;
				param_name_ptr = td.ptr;
				param_name_len = td.length;
			};
		};
		if (resolved.kind == node_kind::N_TPRIM) {
			let td = resolved.data: *n_id_data;
			if (type_name_is(td.ptr, td.length, "f32")) {
				want_f32 = true;
			};
		};
		if (resolved.kind == node_kind::N_TSLICE) {
			let sd = resolved.data: *n_tarr_data;
			slice_elem = sd.elem;
			slice_type = resolved;
			let elem_resolved = resolve_type_alias(ctx, sd.elem);
			if (elem_resolved.kind == node_kind::N_TPRIM) {
				let ed = elem_resolved.data: *n_id_data;
				if (type_name_is(ed.ptr, ed.length, "f32")) {
					slice_elem_f32 = true;
				};
			};
		};
	case null => void;
	};
	if (param_tagged != null && param_name_ptr != null) {
		let arg_type = infer_expr_type(ctx, arg);
		let arg_is_tagged = false;
		match (arg_type) {
		case let at: *node =>
			let resolved = resolve_type_alias(ctx, at);
			if (resolved.kind == node_kind::N_TTAGGED) {
				arg_is_tagged = true;
			};
		case null => void;
		};
		if (!arg_is_tagged) {
			let tag_idx: i64 = -1;
			if (arg.kind == node_kind::N_VOID) {
				let void_name: str = "void";
				tag_idx = find_variant_tag_in_type(unwrap(param_tagged),
					strings::toutf8(void_name): *[*]u8: *u8, 4);
			} else if (arg.kind == node_kind::N_STRUCT_LIT) {
				let sld = arg.data: *n_struct_lit_data;
				if (sld.type_name_len > 0) {
					let type_ptr = unwrap_u8(sld.type_name_ptr);
					tag_idx = find_variant_tag_in_type(unwrap(param_tagged), type_ptr, sld.type_name_len);
				};
			} else if (arg_type != null) {
				let at = unwrap(arg_type);
				if (at.kind == node_kind::N_TPRIM || at.kind == node_kind::N_TALIAS) {
					let td = at.data: *n_id_data;
					tag_idx = find_variant_tag_in_type(unwrap(param_tagged), td.ptr, td.length);
				} else if (at.kind == node_kind::N_TERR) {
					let td = unwrap(param_tagged).data: *n_ttagged_data;
					let cd = at.data: *n_terr_data;
					for (let i = 0z; i < td.nvariants; i += 1) {
						let variant = td.variants[i];
						let resolved = resolve_type_alias(ctx, variant);
						if (resolved.kind == node_kind::N_TERR) {
							let vd = resolved.data: *n_terr_data;
							if (types_assignable(ctx, cd.inner, vd.inner) &&
							    types_assignable(ctx, vd.inner, cd.inner)) {
								tag_idx = i: i64;
								break;
							};
						};
					};
				};
			} else if (arg.kind == node_kind::N_ID) {
				let id = arg.data: *n_id_data;
				if (find_var_type(ctx, id.ptr, id.length) == null &&
				    find_typedef(ctx, id.ptr, id.length) != null) {
					tag_idx = find_variant_tag_in_type(unwrap(param_tagged), id.ptr, id.length);
				};
			};
			if (tag_idx >= 0) {
				let td = unwrap(param_tagged).data: *n_ttagged_data;
				let variant = td.variants[tag_idx];
				let sb = ctx.output;
				strbuf_append_bytes(sb, unwrap_u8(param_name_ptr), param_name_len);
				strbuf_append(sb, "_from_");
				emit_type_tag(sb, variant);
				strbuf_append(sb, "(");
				if (!(is_void_type_node(ctx, variant) || variant.kind == node_kind::N_TNOMEM)) {
					emit_node(ctx, arg);
				};
				strbuf_append(sb, ")");
				return;
			};
		};
	};
	if (slice_elem != null && slice_type != null && arg.kind == node_kind::N_ARR_LIT) {
		let ad = arg.data: *n_arr_lit_data;
		if (ad.fill == null) {
			let sb = ctx.output;
			if (ad.nelems == 0) {
				strbuf_append(sb, "((");
				emit_type(ctx, unwrap(slice_type));
				strbuf_append(sb, "){.data = NULL, .len = 0, .cap = 0})");
				return;
			};
			strbuf_append(sb, "((");
			emit_type(ctx, unwrap(slice_type));
			strbuf_append(sb, "){.data = (");
			emit_type(ctx, unwrap(slice_elem));
			strbuf_append(sb, "[]){");
			let prev_expect = ctx.expecting_f32;
			if (slice_elem_f32) {
				ctx.expecting_f32 = true;
			};
			for (let i = 0z; i < ad.nelems; i += 1) {
				if (i > 0) {
					strbuf_append(sb, ", ");
				};
				emit_node(ctx, ad.elems[i]);
			};
			ctx.expecting_f32 = prev_expect;
			strbuf_append(sb, "}, .len = ");
			strbuf_append_uint(sb, ad.nelems);
			strbuf_append(sb, ", .cap = ");
			strbuf_append_uint(sb, ad.nelems);
			strbuf_append(sb, "})");
			return;
		};
	};
	let prev_expect = ctx.expecting_f32;
	if (want_f32) {
		ctx.expecting_f32 = true;
	};
	emit_node(ctx, arg);
	ctx.expecting_f32 = prev_expect;
};

// Emit C type name from Hare type name (for slice types)
fn emit_c_type_name(sb: *strbuf, ptr: *u8, plen: size) void = {
	if (type_name_is(ptr, plen, "u8")) {
		strbuf_append(sb, "uint8_t");
	} else if (type_name_is(ptr, plen, "u16")) {
		strbuf_append(sb, "uint16_t");
	} else if (type_name_is(ptr, plen, "u32")) {
		strbuf_append(sb, "uint32_t");
	} else if (type_name_is(ptr, plen, "u64")) {
		strbuf_append(sb, "uint64_t");
	} else if (type_name_is(ptr, plen, "i8")) {
		strbuf_append(sb, "int8_t");
	} else if (type_name_is(ptr, plen, "i16")) {
		strbuf_append(sb, "int16_t");
	} else if (type_name_is(ptr, plen, "i32")) {
		strbuf_append(sb, "int32_t");
	} else if (type_name_is(ptr, plen, "i64")) {
		strbuf_append(sb, "int64_t");
	} else if (type_name_is(ptr, plen, "int")) {
		strbuf_append(sb, "intptr_t");
	} else if (type_name_is(ptr, plen, "uint")) {
		strbuf_append(sb, "uintptr_t");
	} else if (type_name_is(ptr, plen, "size")) {
		strbuf_append(sb, "size_t");
	} else if (type_name_is(ptr, plen, "uintptr")) {
		strbuf_append(sb, "uintptr_t");
	} else if (type_name_is(ptr, plen, "f32")) {
		strbuf_append(sb, "float");
	} else if (type_name_is(ptr, plen, "f64")) {
		strbuf_append(sb, "double");
	} else {
		// Custom type - emit the name directly
		strbuf_append_bytes(sb, ptr, plen);
	};
};

// Check if a type node represents the 'str' primitive (for transform.ha use)
fn is_str_type_node(t: nullable *node) bool = {
	match (t) {
	case let typ: *node =>
		if (typ.kind == node_kind::N_TPRIM) {
			let d = typ.data: *n_id_data;
			let d_bytes = d.ptr: *[*]u8;
			// Check if it's "str"
			if (d.length == 3 && d_bytes[0] == 's' && d_bytes[1] == 't' && d_bytes[2] == 'r') {
				return true;
			};
		};
	case null => void;
	};
	return false;
};

// Check if an expression is a string type (for string comparison)
export fn is_string_expr(ctx: *transform_ctx, n: *node) bool = {
	let k = n.kind;
	// String literal
	if (k == node_kind::N_STR) {
		return true;
	};
	// String variable
	if (k == node_kind::N_ID) {
		let id = n.data: *n_id_data;
		if (is_tracked_var(&ctx.str_vars, id.ptr, id.length)) {
			return true;
		};
	};
	// Check inferred type for function calls, field accesses, etc.
	let expr_type = infer_expr_type(ctx, n);
	if (is_str_type_node(expr_type)) {
		return true;
	};
	return false;
};

// Check if a node produces a void result (for match case handling)
export fn is_void_result(n: *node) bool = {
	let k = n.kind;

	// Direct abort/assert nodes
	if (k == node_kind::N_ABORT || k == node_kind::N_ASSERT) {
		return true;
	};

	// Expression statement wrapping abort/assert
	if (k == node_kind::N_EXPR) {
		let ed = n.data: *n_ret_data;
		match (ed.expr) {
		case let expr_node: *node =>
			return is_void_result(expr_node);
		case null =>
			return false;
		};
	};

	// Function call to abort/assert (may be parsed as N_CALL)
	if (k == node_kind::N_CALL) {
		let cd = n.data: *n_call_data;
		if (cd.func.kind == node_kind::N_ID) {
			let id = cd.func.data: *n_id_data;
			// Check if it's abort or assert
			let fn_name = strings::fromutf8_unsafe((id.ptr: *[*]u8)[..id.length]);
			if (fn_name == "abort" || fn_name == "assert") {
				return true;
			};
		};
	};

	return false;
};

// Get the yield expression from a nullable match case body
// Returns null if no yield expression found
fn get_case_yield_expr(body: *node) nullable *node = {
	if (body.kind == node_kind::N_YIELD) {
		let yd = body.data: *n_yield_data;
		match (yd.expr) {
		case let e: *node =>
			return e;
		case null =>
			return null;
		};
	};
	if (body.kind == node_kind::N_BLOCK) {
		let bd = body.data: *n_block_data;
		// Check last statement for yield
		if (bd.nstmts > 0) {
			let last_stmt = bd.stmts[bd.nstmts - 1];
			if (last_stmt.kind == node_kind::N_YIELD) {
				let yd = last_stmt.data: *n_yield_data;
				match (yd.expr) {
				case let e: *node =>
					return e;
				case null =>
					return null;
				};
			};
		};
	};
	// Not a yield - might be a direct expression
	if (body.kind != node_kind::N_BLOCK &&
	    body.kind != node_kind::N_RET &&
	    body.kind != node_kind::N_ASGN &&
	    body.kind != node_kind::N_LET) {
		return body;
	};
	return null;
};

// Helper: check if a character is a hex digit
fn is_hex_digit(c: u8) bool = {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
};

// Helper: parse a hex digit to its value (0-15)
fn hex_digit_value(c: u8) u32 = {
	if (c >= '0' && c <= '9') return (c - '0'): u32;
	if (c >= 'a' && c <= 'f') return (c - 'a' + 10): u32;
	if (c >= 'A' && c <= 'F') return (c - 'A' + 10): u32;
	return 0;
};

fn strbuf_append_bytes_no_underscore(sb: *strbuf, bytes: *[*]u8, length: size) void = {
	for (let i = 0z; i < length; i += 1) {
		let c = bytes[i];
		if (c == '_') { continue; };
		strbuf_append_byte(sb, c);
	};
};

// Helper: encode UTF-8 bytes for a Unicode code point and emit to strbuf
fn emit_utf8(sb: *strbuf, codepoint: u32) size = {
	if (codepoint <= 0x7F) {
		// 1 byte: 0xxxxxxx
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, codepoint: u8);
		return 1;
	} else if (codepoint <= 0x7FF) {
		// 2 bytes: 110xxxxx 10xxxxxx
		let b1 = (0xC0 | (codepoint >> 6)): u8;
		let b2 = (0x80 | (codepoint & 0x3F)): u8;
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b1);
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b2);
		return 2;
	} else if (codepoint <= 0xFFFF) {
		// 3 bytes: 1110xxxx 10xxxxxx 10xxxxxx
		let b1 = (0xE0 | (codepoint >> 12)): u8;
		let b2 = (0x80 | ((codepoint >> 6) & 0x3F)): u8;
		let b3 = (0x80 | (codepoint & 0x3F)): u8;
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b1);
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b2);
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b3);
		return 3;
	} else {
		// 4 bytes: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
		let b1 = (0xF0 | (codepoint >> 18)): u8;
		let b2 = (0x80 | ((codepoint >> 12) & 0x3F)): u8;
		let b3 = (0x80 | ((codepoint >> 6) & 0x3F)): u8;
		let b4 = (0x80 | (codepoint & 0x3F)): u8;
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b1);
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b2);
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b3);
		strbuf_append(sb, "\\x");
		strbuf_append_hex_byte(sb, b4);
		return 4;
	};
};

// Direct dispatch for code generation - no pattern matching needed
export fn emit_node(ctx: *transform_ctx, n_nullable: nullable *node) void = {
	if (n_nullable == null) {
		return;
	};
	let n = unwrap(n_nullable);
	let k = n.kind;

	// Integer literal - emit with appropriate suffix/cast for type safety
	if (k == node_kind::N_INT) {
		let d = n.data: *n_int_data;
		let sb = ctx.output;
		// Apply cast for typed literals to ensure correct C type
		if (d.suffix == 'z') {
			strbuf_append(sb, "(size_t)");
			strbuf_append_int(sb, d.val);
		} else if (d.suffix == 'i') {
			strbuf_append(sb, "(intptr_t)");
			strbuf_append_int(sb, d.val);
		} else if (d.suffix == 'u') {
			strbuf_append(sb, "(uintptr_t)");
			strbuf_append_int(sb, d.val);
		} else {
			// Unsuffixed - just emit the value
			strbuf_append_int(sb, d.val);
		};
		return;
	};

	// Expression statement (N_EXPR) - emit the inner expression
	if (k == node_kind::N_EXPR) {
		let d = n.data: *n_ret_data;
		match (d.expr) {
		case let expr_node: *node => {
			emit_node(ctx, expr_node);
		};
		case null => void;
		};
		return;
	};

	// String literal - emit as hare_str compound literal
	if (k == node_kind::N_STR) {
		let d = n.data: *n_str_data;
		let d_bytes = d.ptr: *[*]u8;
		let sb = ctx.output;
		strbuf_append(sb, "(hare_str){.data = (uint8_t*)\"");

		// Track actual runtime length
		let runtime_len = 0z;

		if (d.is_raw) {
			// Raw string - escape backslashes and quotes for C
			// Runtime length = source length (no escape processing)
			for (let i = 0z; i < d.length; i += 1) {
				let c = d_bytes[i];
				if (c == '\\') {
					strbuf_append(sb, "\\\\");
				} else if (c == '"') {
					strbuf_append(sb, "\\\"");
				} else if (c == '\n') {
					strbuf_append(sb, "\\n");
				} else if (c == '\r') {
					strbuf_append(sb, "\\r");
				} else if (c == '\t') {
					strbuf_append(sb, "\\t");
				} else {
					strbuf_append_byte(sb, c);
				};
				runtime_len += 1;
			};
		} else {
			// Regular string - process escape sequences
			// Track runtime length by counting escapes
			let i = 0z;
			for (i < d.length) {
				let c = d_bytes[i];
				if (c == '\\' && i + 1 < d.length) {
					// Escape sequence - counts as 1 runtime char
					let next = d_bytes[i + 1];
					if (next == 'n' || next == 't' || next == 'r' ||
					    next == '\\' || next == '"' || next == '\'' ||
					    next == '0') {
						// Standard escape - output as-is for C
						strbuf_append_byte(sb, c);
						strbuf_append_byte(sb, next);
						i += 2;
						runtime_len += 1;
					} else if (next == 'x') {
						// Hex escape \xNN - 1 runtime char
						i += 2;
						let hex_start: size = i;
						let hex_count = 0z;
						for (i < d.length && hex_count < 2 && is_hex_digit(d_bytes[i])) {
							hex_count += 1;
							i += 1;
						};
						// Emit hex escape, split if followed by hex digit
						strbuf_append(sb, "\\x");
						for (let j: size = hex_start; j < i; j += 1z) {
							strbuf_append_byte(sb, d_bytes[j]);
						};
						if (i < d.length && is_hex_digit(d_bytes[i])) {
							strbuf_append(sb, "\" \"");
						};
						runtime_len += 1;
					} else if (next == 'o') {
						// Octal escape \oNNNN - variable UTF-8 bytes
						i += 2;
						let codepoint: u32 = 0;
						for (let j = 0z;
							j < 4 && i < d.length &&
							d_bytes[i] >= '0' && d_bytes[i] <= '7';
							j += 1) {
							codepoint = (codepoint << 3) | ((d_bytes[i] - '0'): u32);
							i += 1;
						};
						runtime_len += emit_utf8(sb, codepoint);
						if (i < d.length && is_hex_digit(d_bytes[i])) {
							strbuf_append(sb, "\" \"");
						};
					} else if (next == 'O') {
						// Octal escape \ONNNNNNNN - variable UTF-8 bytes
						i += 2;
						let codepoint: u32 = 0;
						for (let j = 0z;
							j < 8 && i < d.length &&
							d_bytes[i] >= '0' && d_bytes[i] <= '7';
							j += 1) {
							codepoint = (codepoint << 3) | ((d_bytes[i] - '0'): u32);
							i += 1;
						};
						runtime_len += emit_utf8(sb, codepoint);
						if (i < d.length && is_hex_digit(d_bytes[i])) {
							strbuf_append(sb, "\" \"");
						};
					} else if (next == 'u') {
						// Unicode escape \uNNNN - variable UTF-8 bytes
						i += 2;
						let codepoint: u32 = 0;
						for (let j = 0z; j < 4 && i < d.length && is_hex_digit(d_bytes[i]); j += 1) {
							codepoint = (codepoint << 4) | hex_digit_value(d_bytes[i]);
							i += 1;
						};
						runtime_len += emit_utf8(sb, codepoint);
						if (i < d.length && is_hex_digit(d_bytes[i])) {
							strbuf_append(sb, "\" \"");
						};
					} else if (next == 'U') {
						// Unicode escape \UNNNNNNNN - variable UTF-8 bytes
						i += 2;
						let codepoint: u32 = 0;
						for (let j = 0z; j < 8 && i < d.length && is_hex_digit(d_bytes[i]); j += 1) {
							codepoint = (codepoint << 4) | hex_digit_value(d_bytes[i]);
							i += 1;
						};
						runtime_len += emit_utf8(sb, codepoint);
						if (i < d.length && is_hex_digit(d_bytes[i])) {
							strbuf_append(sb, "\" \"");
						};
					} else {
						// Unknown escape - pass through
						strbuf_append_byte(sb, c);
						i += 1;
						runtime_len += 1;
					};
				} else if (c == '\n') {
					// Literal newline in source - still 1 char
					strbuf_append(sb, "\\n");
					i += 1;
					runtime_len += 1;
				} else if (c == '\r') {
					strbuf_append(sb, "\\r");
					i += 1;
					runtime_len += 1;
				} else if (c == '\t') {
					strbuf_append(sb, "\\t");
					i += 1;
					runtime_len += 1;
				} else {
					strbuf_append_byte(sb, c);
					i += 1;
					runtime_len += 1;
				};
			};
		};
		strbuf_append(sb, "\", .len = ");
		strbuf_append_uint(sb, runtime_len);
		strbuf_append(sb, "}");
		return;
	};

	// Boolean
	if (k == node_kind::N_BOOL) {
		let d = n.data: *n_int_data;
		if (d.val != 0) {
			strbuf_append(ctx.output, "1");
		} else {
			strbuf_append(ctx.output, "0");
		};
		return;
	};

	// Null
	if (k == node_kind::N_NULL) {
		strbuf_append(ctx.output, "NULL");
		return;
	};

	// Abort builtin
	if (k == node_kind::N_ABORT) {
		let d = n.data: *n_abort_data;
		let sb = ctx.output;
		match (d.msg) {
		case let msg_node: *node =>
			// Custom message: rt_abort(&__hare_file,line,col,msg_expr)
			strbuf_append(sb, "rt_abort(&__hare_file,");
			strbuf_append_uint(sb, n.line: u64);
			strbuf_append(sb, ",");
			strbuf_append_uint(sb, n.col: u64);
			strbuf_append(sb, ",");
			emit_node(ctx, msg_node);
			strbuf_append(sb, ")");
		case null =>
			// No message: use default "abort" message
			strbuf_append(sb, "rt_abort(&__hare_file,");
			strbuf_append_uint(sb, n.line: u64);
			strbuf_append(sb, ",");
			strbuf_append_uint(sb, n.col: u64);
			strbuf_append(sb, ",(hare_str){.data=(uint8_t*)\"abort\",.len=5})");
		};
		return;
	};

	// Alloc builtin - returns tagged union (*T | nomem) when not unwrapped
	if (k == node_kind::N_ALLOC) {
		let d = n.data: *n_alloc_data;
		let sb = ctx.output;
		let expr: *node = d.expr;

		// For struct literals: allocate and initialize, return tagged union
		if (expr.kind == node_kind::N_STRUCT_LIT) {
			let sl = expr.data: *n_struct_lit_data;
			let type_ptr = unwrap_u8(sl.type_name_ptr);
			// Emit: ({ Type* __p = rt_malloc(sizeof(Type));
			//          struct{uint32_t tag; union{Type* _ptr; char _nomem;} value;} __r;
			//          if (__p) { *__p = (Type){...}; __r.tag = 0U; __r.value._ptr = __p; }
			//          else { __r.tag = HARE_ERROR_TAG_BASE; }
			//          __r; })
			strbuf_append(sb, "({ ");
			strbuf_append_bytes(sb, type_ptr, sl.type_name_len);
			strbuf_append(sb, "* __p = rt_malloc(sizeof(");
			strbuf_append_bytes(sb, type_ptr, sl.type_name_len);
			strbuf_append(sb, ")); struct{uint32_t tag; union{");
			strbuf_append_bytes(sb, type_ptr, sl.type_name_len);
			strbuf_append(sb, "* _ptr; char _nomem;} value;} __r; ");
			strbuf_append(sb, "if (__p) { *__p = ");
			emit_node(ctx, expr);
			strbuf_append(sb, "; __r.tag = 0U; __r.value._ptr = __p; } ");
			strbuf_append(sb, "else { __r.tag = HARE_ERROR_TAG_BASE; } __r; })");
		} else {
			// Generic alloc - return tagged union with ptr_int variant
			// Emit: ({ intptr_t __v = (expr); intptr_t* __p = rt_malloc(sizeof(intptr_t));
			//          struct{uint32_t tag; union{intptr_t* _ptr_int; char _nomem;} value;} __r;
			//          if (__p) { *__p = __v; __r.tag = 0U; __r.value._ptr_int = __p; }
			//          else { __r.tag = HARE_ERROR_TAG_BASE; }
			//          __r; })
			strbuf_append(sb, "({ intptr_t __v = (");
			emit_node(ctx, expr);
			strbuf_append(sb, "); intptr_t* __p = rt_malloc(sizeof(intptr_t)); ");
			strbuf_append(sb, "struct{uint32_t tag; union{intptr_t* _ptr_int; char _nomem;} value;} __r; ");
			strbuf_append(sb, "if (__p) { *__p = __v; __r.tag = 0U; __r.value._ptr_int = __p; } ");
			strbuf_append(sb, "else { __r.tag = HARE_ERROR_TAG_BASE; } __r; })");
		};
		return;
	};

	// Void expression (for tagged union void variant)
	if (k == node_kind::N_VOID) {
		strbuf_append(ctx.output, "(void)0");
		return;
	};

	// Free builtin: free(ptr) -> rt_free(ptr) or rt_free(slice.data)
	if (k == node_kind::N_FREE) {
		let d = n.data: *n_free_data;
		let sb = ctx.output;
		let expr: *node = d.expr;

		// Check if freeing a slice variable (need to free .data)
		let is_slice = false;
		if (expr.kind == node_kind::N_ID) {
			let id = expr.data: *n_id_data;
			is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
		};

		strbuf_append(sb, "rt_free(");
		if (is_slice) {
			strbuf_append(sb, "(");
			emit_node(ctx, expr);
			strbuf_append(sb, ").data");
		} else {
			emit_node(ctx, expr);
		};
		strbuf_append(sb, ")");
		return;
	};

	// Append builtin: append(slice, val) -> rt_append(&slice, val)
	if (k == node_kind::N_APPEND) {
		let d = n.data: *n_append_data;
		let sb = ctx.output;
		if (d.is_static) {
			strbuf_append(sb, "rt_static_append(&");
		} else {
			strbuf_append(sb, "rt_append(&");
		};
		emit_node(ctx, d.slice);
		strbuf_append(sb, ", ");
		emit_node(ctx, d.value);
		strbuf_append(sb, ")");
		return;
	};

	// Insert builtin: insert(slice[idx], val) -> rt_insert(&slice, idx, val)
	if (k == node_kind::N_INSERT) {
		let d = n.data: *n_insert_data;
		let sb = ctx.output;
		if (d.is_static) {
			strbuf_append(sb, "rt_static_insert(&");
		} else {
			strbuf_append(sb, "rt_insert(&");
		};
		emit_node(ctx, d.slice);
		strbuf_append(sb, ", ");
		emit_node(ctx, d.index);
		strbuf_append(sb, ", ");
		emit_node(ctx, d.value);
		strbuf_append(sb, ")");
		return;
	};

	// Delete builtin: delete(slice[idx]) -> rt_delete(&slice, idx, idx+1)
	if (k == node_kind::N_DELETE) {
		let d = n.data: *n_delete_data;
		let sb = ctx.output;
		if (d.is_static) {
			strbuf_append(sb, "rt_static_delete(&");
		} else {
			strbuf_append(sb, "rt_delete(&");
		};
		emit_node(ctx, d.slice);
		strbuf_append(sb, ", ");
		emit_node(ctx, d.index);
		strbuf_append(sb, ", (");
		emit_node(ctx, d.index);
		strbuf_append(sb, ")+1)");
		return;
	};

	// Identifier
	if (k == node_kind::N_ID) {
		let d = n.data: *n_id_data;
		// Check if this identifier is a non-void error type alias used as a literal
		// e.g., type invalid = !int; ... let err = invalid;  // invalid needs a value
		let td = find_typedef(ctx, d.ptr, d.length);
		match (td) {
		case let tdef: *node =>
			let resolved = resolve_type_alias(ctx, tdef);
			if (resolved.kind == node_kind::N_TERR) {
				let terr = resolved.data: *n_terr_data;
				let inner: *node = terr.inner;
				// Check if inner type is NOT void (void is N_TPRIM with name "void")
				let is_void = false;
				if (inner.kind == node_kind::N_TPRIM) {
					let pd = inner.data: *n_id_data;
					is_void = streq(pd.ptr, pd.length, "void");
				};
				if (!is_void) {
					emit_error_at_node(ctx, n, "cannot use non-void error type alias as literal (needs a value)");
				} else {
					// Emit !void error literal as a zero value
					strbuf_append(ctx.output, "((");
					strbuf_append_bytes(ctx.output, d.ptr, d.length);
					strbuf_append(ctx.output, ")0)");
					return;
				};
			};
		case null => void;
		};
		// Check for namespace alias expansion (e.g., t_sin -> math_trig_sin)
		// Parser combines t::sin to t_sin, so look for first underscore
		let d_bytes = d.ptr: *[*]u8;
		let underscore_pos: size = 0;
		for (underscore_pos < d.length && d_bytes[underscore_pos] != '_') {
			underscore_pos += 1;
		};
		if (underscore_pos < d.length) {
			// Found underscore - check if prefix is an alias
			let path_len: size = 0;
			let path_ptr = find_alias_path(ctx, d.ptr, underscore_pos, &path_len);
			match (path_ptr) {
			case let pp: *u8 =>
				// Expand alias: emit path (with :: -> _), then rest of identifier
				let path_bytes = pp: *[*]u8;
				for (let i = 0z; i < path_len; i += 1) {
					if (path_bytes[i] == ':' && i + 1 < path_len && path_bytes[i + 1] == ':') {
						strbuf_append_byte(ctx.output, '_');
						i += 1;  // Skip second colon
					} else {
						strbuf_append_byte(ctx.output, path_bytes[i]);
					};
				};
				// Emit rest: _suffix (from underscore_pos onward)
				strbuf_append_bytes(ctx.output, (d.ptr: uintptr + underscore_pos: uintptr): *u8, d.length - underscore_pos);
				return;
			case null => void;
			};
		};
		strbuf_append_bytes(ctx.output, d.ptr, d.length);
		return;
	};

	// Binary expression
	if (k == node_kind::N_BIN) {
		let d = n.data: *n_bin_data;
		let op = d.op;

		// String comparison: use rt_strcmp
		if (op == token_kind::EQEQ || op == token_kind::NEQ) {
			if (is_string_expr(ctx, d.left) || is_string_expr(ctx, d.right)) {
				// For !=, negate the result
				if (op == token_kind::NEQ) {
					strbuf_append(ctx.output, "!");
				};
				strbuf_append(ctx.output, "rt_strcmp(");
				emit_node(ctx, d.left);
				strbuf_append(ctx.output, ", ");
				emit_node(ctx, d.right);
				strbuf_append(ctx.output, ")");
				return;
			};
		};

		// Don't wrap comparison operators in parentheses - avoids -Wparentheses-equality warning
		// in if conditions like if ((x == 0)). C precedence handles comparisons correctly.
		let is_comparison = (op == token_kind::EQEQ || op == token_kind::NEQ ||
		                     op == token_kind::LT || op == token_kind::GT ||
		                     op == token_kind::LE || op == token_kind::GE);
		if (!is_comparison) {
			strbuf_append(ctx.output, "(");
		};
		emit_node(ctx, d.left);
		strbuf_append(ctx.output, " ");
		emit_binop(ctx.output, op);
		strbuf_append(ctx.output, " ");
		emit_node(ctx, d.right);
		if (!is_comparison) {
			strbuf_append(ctx.output, ")");
		};
		return;
	};

	// Unary expression
	if (k == node_kind::N_UN) {
		let d = n.data: *n_un_data;
		let operand: *node = d.operand;

		// Check for dereference of nullable pointer (compile-time safety check)
		if (d.op == token_kind::STAR) {
			let expr_ty = infer_expr_type(ctx, operand);
			if (is_nullable_ptr_type(expr_ty)) {
				// Skip error if this variable has been narrowed in a match case
				let is_narrowed = false;
				if (operand.kind == node_kind::N_ID && ctx.narrowed_nullable_len > 0) {
					let id = operand.data: *n_id_data;
					if (id.length == ctx.narrowed_nullable_len) {
						is_narrowed = true;
						let id_bytes = id.ptr: *[*]u8;
						let narrowed_bytes = ctx.narrowed_nullable_ptr: *[*]u8;
						for (let i = 0z; i < id.length; i += 1) {
							if (id_bytes[i] != narrowed_bytes[i]) {
								is_narrowed = false;
								break;
							};
						};
					};
				};
				if (!is_narrowed) {
					// Get variable name if it's an identifier for better error message
					if (operand.kind == node_kind::N_ID) {
						let id = operand.data: *n_id_data;
						emit_error_with_name_at_node(ctx, operand, "cannot dereference nullable pointer ", id.ptr, id.length, " (use match to narrow type)");
					} else {
						emit_error_at_node(ctx, operand, "cannot dereference nullable pointer (use match to narrow type)");
					};
				};
			};
		};

		// Special case: &(expr: *T) should generate (T*)(&expr) not &(T*)(expr)
		// The latter is invalid C - can't take address of cast result
		// BUT: &(slice: *[*]T) should extract slice.data instead of &slice
		if (d.op == token_kind::AMP && operand.kind == node_kind::N_CAST) {
			let cd = operand.data: *n_cast_data;
			let target = cd.target;
			// Only rearrange for pointer type casts
			if (target.kind == node_kind::N_TPTR) {
				let pd = target.data: *n_tptr_data;
				let inner_type: *node = pd.inner;

				// Check for *[*]T - pointer to unbounded array
				if (inner_type.kind == node_kind::N_TARR) {
					let ad = inner_type.data: *n_tarr_data;
					if (ad.length == null) {
						// Target is *[*]T - check if source is a slice
						let inner_expr = cd.expr;
						let expr_type = infer_expr_type(ctx, inner_expr);
						let is_slice = is_slice_type(expr_type);
						if (!is_slice && inner_expr.kind == node_kind::N_ID) {
							let id = inner_expr.data: *n_id_data;
							is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
						};
						if (is_slice) {
							// Emit: ((target_type)(slice.data))
							strbuf_append(ctx.output, "((");
							emit_type(ctx, target);
							strbuf_append(ctx.output, ")(");
							emit_node(ctx, inner_expr);
							strbuf_append(ctx.output, ".data))");
							return;
						};
					};
				};

				// General pointer cast: emit (T*)(&expr)
				strbuf_append(ctx.output, "(");
				emit_type(ctx, target);
				strbuf_append(ctx.output, ")(&");
				emit_node(ctx, cd.expr);
				strbuf_append(ctx.output, ")");
				return;
			};
		};

		// Special case: &slice[i] or &arr[i] needs bounds check emitted separately
		// since comma expression result can't be address-of operand
		if (d.op == token_kind::AMP && operand.kind == node_kind::N_IDX) {
			let idx_d = operand.data: *n_idx_data;
			let idx_base = idx_d.base;
			if (idx_base.kind == node_kind::N_ID) {
				let bid = idx_base.data: *n_id_data;
				if (is_tracked_var(&ctx.slice_vars, bid.ptr, bid.length)) {
					// Emit: ((void)(check), &slice.data[i])
					strbuf_append(ctx.output, "((void)((size_t)(");
					emit_node(ctx, idx_d.index);
					strbuf_append(ctx.output, ")>=(size_t)((");
					emit_node(ctx, idx_base);
					strbuf_append(ctx.output, ").len)?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0), &((");
					emit_node(ctx, idx_base);
					strbuf_append(ctx.output, ").data[");
					emit_node(ctx, idx_d.index);
					strbuf_append(ctx.output, "]))");
					return;
				};
				// Check for array case
				let arr_len = get_arr_len(ctx, bid.ptr, bid.length);
				match (arr_len) {
				case let al: *node =>
					strbuf_append(ctx.output, "((void)((size_t)(");
					emit_node(ctx, idx_d.index);
					strbuf_append(ctx.output, ")>=(size_t)(");
					emit_node(ctx, al);
					strbuf_append(ctx.output, ")?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0), &(");
					emit_node(ctx, idx_base);
					strbuf_append(ctx.output, ")[");
					emit_node(ctx, idx_d.index);
					strbuf_append(ctx.output, "])");
					return;
				case null => void;
				};
			};
		};

		emit_unop(ctx.output, d.op);
		emit_node(ctx, operand);
		return;
	};

	// Function call
	if (k == node_kind::N_CALL) {
		let d = n.data: *n_call_data;
		let sb = ctx.output;

		// Try to get function info for variadic/default handling
		let fn_info: nullable *node = null;
		let is_variadic = false;
		let n_fixed_params: size = 0;
		let total_params: size = 0;

		// Get function name if it's a simple identifier
		if (d.func.kind == node_kind::N_ID) {
			let fn_id = d.func.data: *n_id_data;
			fn_info = find_fn_info(ctx, fn_id.ptr, fn_id.length);
			// Check if calling by @symbol name instead of Hare function name
			if (fn_info == null && is_symbol_name(ctx, fn_id.ptr, fn_id.length)) {
				emit_error_at_node(ctx, d.func, "unknown object (calling function by @symbol name instead of Hare name)");
			};
			// Check for strings_ functions without 'use strings;'
			if (!ctx.use_strings && fn_id.length >= 8) {
				let prefix = strings::fromutf8_unsafe((fn_id.ptr: *[*]u8)[..8]);
				if (prefix == "strings_") {
					emit_error_at_node(ctx, d.func, "must 'use strings;' to use strings module functions");
					return;
				};
			};
			// Check for null passed to rt_abort_fixed or rt_abort (first param is non-nullable *str)
			let is_rt_abort = fn_id.length == 14 && streq(fn_id.ptr, fn_id.length, "rt_abort_fixed");
			let is_rt_abort2 = fn_id.length == 8 && streq(fn_id.ptr, fn_id.length, "rt_abort");
			if ((is_rt_abort || is_rt_abort2) && d.nargs > 0) {
				if (d.args[0].kind == node_kind::N_NULL) {
					emit_error_at_node(ctx, d.args[0], "cannot pass null to non-nullable pointer parameter");
				};
			};
		};

		// Check if function is variadic
		match (fn_info) {
		case let fi: *node =>
			let fd = fi.data: *n_fn_data;
			total_params = fd.nparams;
			// Check if last param is variadic
			if (total_params > 0) {
				let last_param = fd.params[total_params - 1];
				let pd = last_param.data: *n_param_data;
				if (pd.is_variadic) {
					is_variadic = true;
					n_fixed_params = total_params - 1;
				};
			};
		case null => void;
		};

		// NOTE: Argument type checking disabled - types_assignable needs more work
		// to handle all valid Hare type combinations without false positives

		// Emit function name - use @symbol name if available, apply prefix for exported
		match (fn_info) {
		case let fi: *node =>
			let fd = fi.data: *n_fn_data;
			if (fd.symbol_len > 0) {
				// Use @symbol("name") for the call
				let symbol_ptr = unwrap_u8(fd.symbol_ptr);
				strbuf_append_bytes(sb, symbol_ptr, fd.symbol_len);
			} else {
				// Apply prefix to exported function calls (except main)
				let is_main = streq(fd.name_ptr, fd.name_len, "main");
				if (fd.exported && !is_main && ctx.prefix_len > 0) {
					strbuf_append_bytes(sb, ctx.prefix_ptr, ctx.prefix_len);
					strbuf_append(sb, "_");
				};
				emit_node(ctx, d.func);
			};
		case null =>
			emit_node(ctx, d.func);
		};
		strbuf_append(sb, "(");

		if (is_variadic) {
			match (fn_info) {
			case let fi: *node =>
				let fd = fi.data: *n_fn_data;

				// Emit fixed arguments
				for (let i = 0z; i < n_fixed_params; i += 1) {
					if (i > 0) {
						strbuf_append(sb, ", ");
					};
					let param = fd.params[i];
					let pd = param.data: *n_param_data;
					if (i < d.nargs) {
						// Check for null to non-nullable parameter
						if (d.args[i].kind == node_kind::N_NULL) {
							if (pd.typ.kind == node_kind::N_TPTR) {
								let ptype = pd.typ.data: *n_tptr_data;
								if (!ptype.is_nullable) {
									emit_error_at_node(ctx, d.args[i], "cannot pass null to non-nullable pointer parameter");
								};
							};
						};
						emit_call_arg(ctx, d.args[i], pd.typ);
					} else {
						// Use default value
						match (pd.default_value) {
						case let def_val: *node =>
							emit_call_arg(ctx, def_val, pd.typ);
						case null => void;
						};
					};
				};

				// Separator before variadic slice
				if (n_fixed_params > 0) {
					strbuf_append(sb, ", ");
				};

				// Variadic part - build slice
				let var_args_start = n_fixed_params;
				let n_var_args = 0z;
				if (d.nargs > var_args_start) {
					n_var_args = d.nargs - var_args_start;
				};

				// Get variadic element type for slice
				let var_param = fd.params[total_params - 1];
				let vpd = var_param.data: *n_param_data;

				if (d.has_spread && n_var_args == 1) {
					// Spread a slice: func(slice...)
					emit_node(ctx, d.args[var_args_start]);
				} else if (n_var_args > 0) {
					// Build inline slice: (hare_slice_T){.data = (T[]){args}, .len = N, .cap = N}
					strbuf_append(sb, "((hare_slice_");
					emit_type(ctx, vpd.typ);
					strbuf_append(sb, "){.data = (");
					emit_type(ctx, vpd.typ);
					strbuf_append(sb, "[]){");
					for (let i: size = var_args_start; i < d.nargs; i += 1) {
						if (i > var_args_start) {
							strbuf_append(sb, ", ");
						};
						emit_call_arg(ctx, d.args[i], vpd.typ);
					};
					strbuf_append(sb, "}, .len = ");
					strbuf_append_uint(sb, n_var_args);
					strbuf_append(sb, ", .cap = ");
					strbuf_append_uint(sb, n_var_args);
					strbuf_append(sb, "})");
				} else {
					// Empty variadic: pass empty slice
					strbuf_append(sb, "((hare_slice_");
					emit_type(ctx, vpd.typ);
					strbuf_append(sb, "){.data = NULL, .len = 0, .cap = 0})");
				};
			case null => void;
			};
		} else {
			match (fn_info) {
			case let fi: *node =>
				// Not variadic but may have default parameters
				let fd = fi.data: *n_fn_data;

				for (let i = 0z; i < total_params; i += 1) {
					if (i > 0) {
						strbuf_append(sb, ", ");
					};
					if (i < d.nargs) {
						// Check for null to non-nullable parameter
						if (d.args[i].kind == node_kind::N_NULL) {
							let param = fd.params[i];
							let pd = param.data: *n_param_data;
							if (pd.typ.kind == node_kind::N_TPTR) {
							let ptype = pd.typ.data: *n_tptr_data;
							if (!ptype.is_nullable) {
								emit_error_at_node(ctx, d.args[i], "cannot pass null to non-nullable pointer parameter");
							};
						};
					};
					let param = fd.params[i];
						let pd = param.data: *n_param_data;
						emit_call_arg(ctx, d.args[i], pd.typ);
					} else {
						// Use default value
						let param = fd.params[i];
						let pd = param.data: *n_param_data;
						match (pd.default_value) {
						case let def_val: *node =>
							emit_call_arg(ctx, def_val, pd.typ);
						case null => void;
						};
					};
				};
			case null =>
				// No function info - simple call
				for (let i = 0z; i < d.nargs; i += 1) {
					if (i > 0) {
						strbuf_append(sb, ", ");
					};
					emit_node(ctx, d.args[i]);
				};
			};
		};

		strbuf_append(sb, ")");
		return;
	};

	// Array/slice index with bounds checking
	// Note: address-of (&arr[i]) handled in N_UN; assignment bounds check emitted in N_ASGN
	if (k == node_kind::N_IDX) {
		let d = n.data: *n_idx_data;
		let sb = ctx.output;

		// Check if base is a tracked slice or array variable
		let is_slice = false;
		let arr_len: nullable *node = null;
		if (d.base.kind == node_kind::N_ID) {
			let id = d.base.data: *n_id_data;
			is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
			if (!is_slice) {
				arr_len = get_arr_len(ctx, id.ptr, id.length);
			};
		};

		if (is_slice) {
			if (ctx.in_lvalue) {
				// Lvalue: simple indexing (bounds check emitted by caller)
				strbuf_append(sb, "((");
				emit_node(ctx, d.base);
				strbuf_append(sb, ").data[");
				emit_node(ctx, d.index);
				strbuf_append(sb, "])");
			} else {
				// Rvalue: bounds check via comma expression
				strbuf_append(sb, "((void)((size_t)(");
				emit_node(ctx, d.index);
				strbuf_append(sb, ")>=(size_t)((");
				emit_node(ctx, d.base);
				strbuf_append(sb, ").len)?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0), ((");
				emit_node(ctx, d.base);
				strbuf_append(sb, ").data[");
				emit_node(ctx, d.index);
				strbuf_append(sb, "]))");
			};
		} else {
			match (arr_len) {
			case let al: *node =>
				// Array with known size
				if (ctx.in_lvalue) {
					strbuf_append(sb, "(");
					emit_node(ctx, d.base);
					strbuf_append(sb, ")[");
					emit_node(ctx, d.index);
					strbuf_append(sb, "]");
				} else {
					strbuf_append(sb, "((void)((size_t)(");
					emit_node(ctx, d.index);
					strbuf_append(sb, ")>=(size_t)(");
					emit_node(ctx, al);
					strbuf_append(sb, ")?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0), (");
					emit_node(ctx, d.base);
					strbuf_append(sb, ")[");
					emit_node(ctx, d.index);
					strbuf_append(sb, "])");
				};
			case null =>
				// Unknown array/pointer access: check for pointer-to-array type
				let base_type = infer_expr_type(ctx, d.base);
				if (base_type != null) {
					let bt = unwrap(base_type);
					// Count pointer depth
					let ptr_depth: size = 0;
					let cur = bt;
					for (cur.kind == node_kind::N_TPTR) {
						ptr_depth += 1;
						let pd = cur.data: *n_tptr_data;
						cur = pd.inner;
					};
					// Check if innermost is a fixed-size array
					if (ptr_depth > 0 && cur.kind == node_kind::N_TARR) {
						let ad = cur.data: *n_tarr_data;
						if (ad.length != null) {
							// Pointer to array: emit (*...*base)[index]
							strbuf_append(sb, "(");
							for (let i = 0z; i < ptr_depth; i += 1) {
								strbuf_append(sb, "*");
							};
							strbuf_append(sb, "(");
							emit_node(ctx, d.base);
							strbuf_append(sb, "))[");
							emit_node(ctx, d.index);
							strbuf_append(sb, "]");
							return;
						};
					};
					// Check if base is a slice type (from function call, etc.)
					if (bt.kind == node_kind::N_TSLICE) {
						// Slice: emit (base).data[index] with bounds check
						if (ctx.in_lvalue) {
							strbuf_append(sb, "((");
							emit_node(ctx, d.base);
							strbuf_append(sb, ").data[");
							emit_node(ctx, d.index);
							strbuf_append(sb, "])");
						} else {
							strbuf_append(sb, "((void)((size_t)(");
							emit_node(ctx, d.index);
							strbuf_append(sb, ")>=(size_t)((");
							emit_node(ctx, d.base);
							strbuf_append(sb, ").len)?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0), ((");
							emit_node(ctx, d.base);
							strbuf_append(sb, ").data[");
							emit_node(ctx, d.index);
							strbuf_append(sb, "]))");
						};
						return;
					};

					// Disallow indexing into plain pointers (must be array, slice, or *[*]T)
					if (bt.kind == node_kind::N_TPTR) {
						let allow_uarr = false;
						if (d.base.kind == node_kind::N_ID) {
							let id = d.base.data: *n_id_data;
							allow_uarr = is_tracked_var(&ctx.ptr_uarr_vars, id.ptr, id.length);
						};
						if (!allow_uarr) {
							let pd = bt.data: *n_tptr_data;
							if (pd.inner.kind != node_kind::N_TARR) {
								emit_error_at_node(ctx, n, "cannot index pointer to non-array type");
							};
						};
					};
				};
				// Simple indexing (no bounds check)
				strbuf_append(sb, "(");
				emit_node(ctx, d.base);
				strbuf_append(sb, ")[");
				emit_node(ctx, d.index);
				strbuf_append(sb, "]");
			};
		};
		return;
	};

	// Slice expression: arr[start..end]
	if (k == node_kind::N_SLICE) {
		let d = n.data: *n_slice_data;
		let sb = ctx.output;
		let base: *node = d.base;

		// Check if base is an array (not a slice) and get element type
		let is_array = false;
		let elem_type_ptr: nullable *u8 = null;
		let elem_type_len: size = 0;
		if (base.kind == node_kind::N_ID) {
			let id = base.data: *n_id_data;
			is_array = is_tracked_var(&ctx.arr_vars, id.ptr, id.length);
			if (is_array) {
				elem_type_ptr = get_variant_type(&ctx.arr_elem_types, id.ptr, id.length);
				elem_type_len = get_variant_type_len(&ctx.arr_elem_types, id.ptr, id.length);
			};
		};

		if (is_array) {
			// Array to slice: {.data = (type*)arr + start, .len = end - start, .cap = len - start}
			// Use correct slice type based on element type
			strbuf_append(sb, "((hare_slice_");
			match (elem_type_ptr) {
			case let ptr: *u8 =>
				emit_c_type_name(sb, ptr, elem_type_len);
			case null =>
				strbuf_append(sb, "intptr_t");
			};
			strbuf_append(sb, "){.data = (");
			match (elem_type_ptr) {
			case let ptr: *u8 =>
				emit_c_type_name(sb, ptr, elem_type_len);
			case null =>
				strbuf_append(sb, "intptr_t");
			};
			strbuf_append(sb, "*)(");
			emit_node(ctx, base);
			strbuf_append(sb, ") + ");
			match (d.start) {
			case let start_node: *node =>
				emit_node(ctx, start_node);
			case null =>
				strbuf_append(sb, "0");
			};
			strbuf_append(sb, ", .len = ");
			match (d.end) {
			case let end_node: *node =>
				emit_node(ctx, end_node);
			case null =>
				// Full array length
				strbuf_append(sb, "(sizeof(");
				emit_node(ctx, base);
				strbuf_append(sb, ")/sizeof((");
				emit_node(ctx, base);
				strbuf_append(sb, ")[0]))");
			};
			strbuf_append(sb, " - ");
			match (d.start) {
			case let start_node: *node =>
				emit_node(ctx, start_node);
			case null =>
				strbuf_append(sb, "0");
			};
			strbuf_append(sb, ", .cap = (sizeof(");
			emit_node(ctx, base);
			strbuf_append(sb, ")/sizeof((");
			emit_node(ctx, base);
			strbuf_append(sb, ")[0])) - ");
			match (d.start) {
			case let start_node: *node =>
				emit_node(ctx, start_node);
			case null =>
				strbuf_append(sb, "0");
			};
			strbuf_append(sb, "})");
		} else {
			// Check if base is a slice variable
			let is_slice = false;
			let slice_elem_type_ptr: nullable *u8 = null;
			let slice_elem_type_len: size = 0;
			if (base.kind == node_kind::N_ID) {
				let id = base.data: *n_id_data;
				is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
				if (is_slice) {
					slice_elem_type_ptr = get_variant_type(&ctx.slice_elem_types, id.ptr, id.length);
					slice_elem_type_len = get_variant_type_len(&ctx.slice_elem_types, id.ptr, id.length);
				};
			};

			if (is_slice) {
				// Slice from slice: {.data = base.data + start, .len = end - start, .cap = base.cap - start}
				// Try type inference as fallback for element type
				let inferred_elem: nullable *node = null;
				if (slice_elem_type_ptr == null) {
					let base_type = infer_expr_type(ctx, base);
					match (base_type) {
					case let bt: *node =>
						if (bt.kind == node_kind::N_TSLICE) {
							let sd = bt.data: *n_tarr_data;
							inferred_elem = sd.elem;
						};
					case null => void;
					};
				};
				strbuf_append(sb, "((hare_slice_");
				match (slice_elem_type_ptr) {
				case let ptr: *u8 =>
					emit_c_type_name(sb, ptr, slice_elem_type_len);
				case null =>
					match (inferred_elem) {
					case let elem: *node =>
						if (elem.kind == node_kind::N_TPRIM) {
							let ed = elem.data: *n_id_data;
							emit_c_type_name(sb, ed.ptr, ed.length);
						} else {
							strbuf_append(sb, "intptr_t");
						};
					case null =>
						strbuf_append(sb, "intptr_t");
					};
				};
				strbuf_append(sb, "){.data = (");
				emit_node(ctx, base);
				strbuf_append(sb, ").data + ");
				match (d.start) {
				case let start_node: *node =>
					emit_node(ctx, start_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, ", .len = ");
				match (d.end) {
				case let end_node: *node =>
					emit_node(ctx, end_node);
				case null =>
					strbuf_append(sb, "(");
					emit_node(ctx, base);
					strbuf_append(sb, ").len");
				};
				strbuf_append(sb, " - ");
				match (d.start) {
				case let start_node: *node =>
					emit_node(ctx, start_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, ", .cap = (");
				emit_node(ctx, base);
				strbuf_append(sb, ").cap - ");
				match (d.start) {
				case let start_node: *node =>
					emit_node(ctx, start_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, "})");
			} else {
				// Pointer to unbounded array: {.data = ptr + start, .len = end - start, .cap = end - start}
				// Capacity equals length since we don't know the true size
				// Try to infer element type from base expression
				let ptr_elem_type: nullable *node = null;
				let base_type = infer_expr_type(ctx, base);
				match (base_type) {
				case let bt: *node =>
					// If it's *[*]T (pointer to array with null length), unwrap to get T
					if (bt.kind == node_kind::N_TPTR) {
						let pd = bt.data: *n_tptr_data;
						if (pd.inner.kind == node_kind::N_TARR) {
							let ad = pd.inner.data: *n_tarr_data;
							// Check if it's unbounded (length is null)
							if (ad.length == null) {
								ptr_elem_type = ad.elem;
							};
						};
					};
				case null => void;
				};

				strbuf_append(sb, "((hare_slice_");
				match (ptr_elem_type) {
				case let et: *node =>
					if (et.kind == node_kind::N_TPRIM) {
						let etd = et.data: *n_id_data;
						emit_c_type_name(sb, etd.ptr, etd.length);
					} else {
						strbuf_append(sb, "intptr_t");
					};
				case null =>
					strbuf_append(sb, "intptr_t");
				};
				strbuf_append(sb, "){.data = (");
				match (ptr_elem_type) {
				case let et: *node =>
					if (et.kind == node_kind::N_TPRIM) {
						let etd = et.data: *n_id_data;
						emit_c_type_name(sb, etd.ptr, etd.length);
					} else {
						strbuf_append(sb, "intptr_t");
					};
				case null =>
					strbuf_append(sb, "intptr_t");
				};
				strbuf_append(sb, "*)(");
				emit_node(ctx, base);
				strbuf_append(sb, ") + ");
				match (d.start) {
				case let start_node: *node =>
					emit_node(ctx, start_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, ", .len = ");
				match (d.end) {
				case let end_node: *node =>
					emit_node(ctx, end_node);
				case null =>
					// No end means we need the length somewhere - error case
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, " - ");
				match (d.start) {
				case let start_node: *node =>
					emit_node(ctx, start_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, ", .cap = ");
				match (d.end) {
				case let end_node: *node =>
					emit_node(ctx, end_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, " - ");
				match (d.start) {
				case let start_node: *node =>
					emit_node(ctx, start_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, "})");
			};
		};
		return;
	};

	// Field access - with proper auto-dereference for any pointer depth
	if (k == node_kind::N_FLD) {
		let d = n.data: *n_fld_data;
		let sb = ctx.output;
		let base: *node = d.base;

		// Use infer_expr_type to get base type and count pointer depth
		// This handles all cases: variables, casts, calls, chained field access
		let base_type = infer_expr_type(ctx, base);
		let ptr_depth = count_ptr_depth(base_type);
		if (ptr_depth == 0 && base.kind == node_kind::N_ID) {
			let id = base.data: *n_id_data;
			if (is_tracked_var(&ctx.ptr_vars, id.ptr, id.length)) {
				ptr_depth = 1;
			};
		};
		if (ptr_depth == 0 && base.kind == node_kind::N_CALL) {
			let cd = base.data: *n_call_data;
			if (cd.func.kind == node_kind::N_ID) {
				let fid = cd.func.data: *n_id_data;
				if (is_tracked_var(&ctx.ptr_fns, fid.ptr, fid.length)) {
					ptr_depth = 1;
				};
			};
		};

		// Generate appropriate dereferences: (*...*base).field
		if (ptr_depth > 0) {
			strbuf_append(sb, "(");
			for (let i = 0z; i < ptr_depth; i += 1) {
				strbuf_append(sb, "*");
			};
			strbuf_append(sb, "(");
			emit_node(ctx, base);
			strbuf_append(sb, ")).");
		} else {
			strbuf_append(sb, "(");
			emit_node(ctx, base);
			strbuf_append(sb, ").");
		};

		// Check if field name is numeric (tuple access .0, .1, etc.)
		// If so, prepend underscore to make ._0, ._1
		let field_bytes = d.field_ptr: *[*]u8;
		if (d.field_len > 0 && field_bytes[0] >= '0' && field_bytes[0] <= '9') {
			strbuf_append(sb, "_");
		};
		strbuf_append_bytes(sb, d.field_ptr, d.field_len);
		return;
	};

	// Type cast
	if (k == node_kind::N_CAST) {
		let d = n.data: *n_cast_data;
		let sb = ctx.output;
		let target = d.target;
		let expr: *node = d.expr;

		// Reject casts to void (invalid in Hare), except void literal
		if (is_void_type_node(ctx, target)) {
			if (expr.kind != node_kind::N_VOID) {
				emit_error_at_node(ctx, n, "cannot cast to void");
			};
		};

		// Reject integer literal -> pointer casts (e.g., 0: *u8)
		if (target.kind == node_kind::N_TPTR && expr.kind == node_kind::N_INT) {
			emit_error_at_node(ctx, expr, "invalid cast from integer literal to pointer");
		};

		// Nullable pointer safety check: cannot cast nullable to non-nullable
		if (is_nonnull_ptr_type(target)) {
			// Check if source is null literal
			if (is_null_lit(expr)) {
				emit_error_at_node(ctx, expr, "cannot cast nullable pointer to non-nullable (use match instead)");
			} else {
				// Check if source expression type is nullable
				let src_type = infer_expr_type(ctx, expr);
				if (is_nullable_ptr_type(src_type)) {
					// Skip error if this variable has been narrowed in a match case
					let is_narrowed = false;
					if (expr.kind == node_kind::N_ID && ctx.narrowed_nullable_len > 0) {
						let id = expr.data: *n_id_data;
						if (id.length == ctx.narrowed_nullable_len) {
							is_narrowed = true;
							let id_bytes = id.ptr: *[*]u8;
							let narrowed_bytes = ctx.narrowed_nullable_ptr: *[*]u8;
							for (let i = 0z; i < id.length; i += 1) {
								if (id_bytes[i] != narrowed_bytes[i]) {
									is_narrowed = false;
									break;
								};
							};
						};
					};
					if (!is_narrowed) {
						emit_error_at_node(ctx, expr, "cannot cast nullable pointer to non-nullable (use match instead)");
					};
				};
			};
		};

		// Check for invalid cast from fixed array to pointer to unbounded array
		// e.g., arr: *[*]i32 where arr is [5]i32 is invalid
		if (target.kind == node_kind::N_TPTR) {
			let tptr = target.data: *n_tptr_data;
			if (tptr.inner.kind == node_kind::N_TARR) {
				let tarr = tptr.inner.data: *n_tarr_data;
				// Target is *[*]T (pointer to unbounded array)
				if (tarr.length == null) {
					// Check if source is a fixed array
					let src_type = infer_expr_type(ctx, expr);
					match (src_type) {
					case let st: *node =>
						if (st.kind == node_kind::N_TARR) {
							let sarr = st.data: *n_tarr_data;
							// Source is [N]T with explicit length
							if (sarr.length != null) {
								emit_error_at_node(ctx, expr, "invalid cast from [N]T to *[*]T (use &arr instead)");
							};
						};
					case null => void;
					};
				};
			};
		};

		// Check if target is a tagged union type (casting TO tagged union)
		// e.g., v: number where number = (i32 | f32)
		if (target.kind == node_kind::N_TPRIM || target.kind == node_kind::N_TALIAS) {
			let td = target.data: *n_id_data;
			if (is_tracked_var(&ctx.tagged_types, td.ptr, td.length)) {
				// Casting to a tagged union - use from_X helper function
				// Infer source type from expression
				let src_type = infer_expr_type(ctx, expr);
				strbuf_append_bytes(sb, td.ptr, td.length);
				strbuf_append(sb, "_from_");
				let type_emitted = false;
				match (src_type) {
				case let st_node: *node =>
					if (st_node.kind == node_kind::N_TPRIM) {
						let st = st_node.data: *n_id_data;
						strbuf_append_bytes(sb, st.ptr, st.length);
						type_emitted = true;
					};
				case null => void;
				};
				if (!type_emitted) {
					if (expr.kind == node_kind::N_STRUCT_LIT) {
						let sld = expr.data: *n_struct_lit_data;
						if (sld.type_name_len > 0) {
							let type_ptr = unwrap_u8(sld.type_name_ptr);
							strbuf_append_bytes(sb, type_ptr, sld.type_name_len);
							type_emitted = true;
						};
					} else if (expr.kind == node_kind::N_ID) {
						let id = expr.data: *n_id_data;
						if (find_typedef(ctx, id.ptr, id.length) != null) {
							strbuf_append_bytes(sb, id.ptr, id.length);
							type_emitted = true;
						};
					};
				};
				if (!type_emitted) {
					if (expr.kind == node_kind::N_VOID) {
						strbuf_append(sb, "void");
					} else if (expr.kind == node_kind::N_INT) {
						strbuf_append(sb, "i32");
					} else if (expr.kind == node_kind::N_FLOAT) {
						strbuf_append(sb, "f32");
					} else if (expr.kind == node_kind::N_BOOL) {
						strbuf_append(sb, "bool");
					} else {
						strbuf_append(sb, "int");
					};
				};
				strbuf_append(sb, "(");
				if (expr.kind != node_kind::N_VOID) {
					emit_node(ctx, expr);
				};
				strbuf_append(sb, ")");
				return;
			};
		};

		// Check if source is a tagged union type (casting FROM tagged union)
		// e.g., n: i32 where n is of type number = (i32 | f32)
		let src_type = infer_expr_type(ctx, expr);
		match (src_type) {
		case let st: *node =>
			// Check if source is a tagged union type alias
			if (st.kind == node_kind::N_TPRIM || st.kind == node_kind::N_TALIAS) {
				let std = st.data: *n_id_data;
				if (is_tracked_var(&ctx.tagged_types, std.ptr, std.length)) {
					// Extracting from tagged union - use .value._varianttype
					strbuf_append(sb, "(");
					emit_node(ctx, expr);
					strbuf_append(sb, ").value._");
					if (target.kind == node_kind::N_TPRIM) {
						let ttd = target.data: *n_id_data;
						strbuf_append_bytes(sb, ttd.ptr, ttd.length);
					} else {
						strbuf_append(sb, "int");
					};
					return;
				};
			};
		case null => void;
		};

		// Check if casting to *[*]T (pointer to unbounded array)
		if (target.kind == node_kind::N_TPTR) {
			let pd = target.data: *n_tptr_data;
			let inner: *node = pd.inner;
			if (inner.kind == node_kind::N_TARR) {
				let ad = inner.data: *n_tarr_data;
				if (ad.length == null) {
					// Target is *[*]T - check source type
					// Special case: (&slice): *[*]T should extract slice.data
					if (expr.kind == node_kind::N_UN) {
						let ud = expr.data: *n_un_data;
						if (ud.op == token_kind::AMP) {
							let inner_expr: *node = ud.operand;
							// Check if the inner expression is a slice
							let inner_type = infer_expr_type(ctx, inner_expr);
							let is_slice = is_slice_type(inner_type);
							if (!is_slice && inner_expr.kind == node_kind::N_ID) {
								let id = inner_expr.data: *n_id_data;
								is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
							};
							if (is_slice) {
								// Emit: ((target_type)(slice.data))
								strbuf_append(sb, "((");
								emit_type(ctx, target);
								strbuf_append(sb, ")(");
								emit_node(ctx, inner_expr);
								strbuf_append(sb, ".data))");
								return;
							};
						};
					};

					let src_type = infer_expr_type(ctx, expr);

					// Handle str → *[*]u8 casts (add .data suffix)
					let is_str_cast = is_str_type(src_type) || expr.kind == node_kind::N_STR;

					// Check for strings::toutf8() call (returns []u8)
					let is_str_to_bytes_call = false;
					if (expr.kind == node_kind::N_CALL) {
						let cd = expr.data: *n_call_data;
						if (cd.func.kind == node_kind::N_ID) {
							let id = cd.func.data: *n_id_data;
							is_str_to_bytes_call = name_matches_module_member(ctx, id.ptr, id.length, "strings", "toutf8");
						};
					};

					// ENABLE: []T → *[*]T casts using compound expression
					// Use for confirmed slice types OR strings::toutf8() calls
					// Also check if expr is an identifier that's a tracked slice variable
					let expr_is_slice_var = false;
					if (expr.kind == node_kind::N_ID) {
						let id = expr.data: *n_id_data;
						expr_is_slice_var = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
					};
					if (!is_str_cast && (is_slice_type(src_type) || is_str_to_bytes_call || expr_is_slice_var)) {
						// Emit: ({ __auto_type __s = expr; (target_type)(__s.data); })
						strbuf_append(sb, "({ __auto_type __s = ");
						emit_node(ctx, expr);
						strbuf_append(sb, "; (");
						emit_type(ctx, target);
						strbuf_append(sb, ")(__s.data); })");
						return;  // Done - skip normal cast emission below
					};

					// Disallow direct str → *[*]u8 casts (loses length info)
					if (is_str_cast) {
						emit_error_at_node(ctx, expr, "cannot cast str to *[*]u8 - use strings::toutf8() instead");
						return;
					};
					// Non-str, non-slice cast to *[*]T - fall through to normal cast
				};
			};
		};

		// Normal cast emission (for non-pointer-to-unbounded-array cases)
		strbuf_append(sb, "(");
		emit_type(ctx, target);
		strbuf_append(sb, ")(");
		emit_node(ctx, expr);
		strbuf_append(sb, ")");
		return;
	};

	// Float literal
	if (k == node_kind::N_FLOAT) {
		let d = n.data: *n_str_data;  // Float stored as string
		let ptr = d.ptr;
		let ptr_bytes = ptr: *[*]u8;
		let slen = d.length;
		let sb = ctx.output;

		// Check if literal has f32 or f64 suffix
		let has_f32_suffix = slen >= 3 && ptr_bytes[slen - 3] == 'f' && ptr_bytes[slen - 2] == '3' && ptr_bytes[slen - 1] == '2';
		let has_f64_suffix = slen >= 3 && ptr_bytes[slen - 3] == 'f' && ptr_bytes[slen - 2] == '6' && ptr_bytes[slen - 1] == '4';

		// Check if we're expecting f32 from context
		let want_f32 = ctx.expecting_f32;
		if (!want_f32) {
			match (ctx.expected_slice_elem) {
			case let elem: *node =>
				if (elem.kind == node_kind::N_TPRIM) {
					let td = elem.data: *n_id_data;
					let type_name = strings::fromutf8_unsafe((td.ptr: *[*]u8)[..td.length]);
					want_f32 = (type_name == "f32");
				};
			case null => void;
			};
		};

		let base_len = slen;
		if (has_f32_suffix || has_f64_suffix) { base_len = slen - 3; };
		let has_dot = false;
		let has_exp = false;
		for (let i = 0z; i < base_len; i += 1) {
			if (ptr_bytes[i] == '.') { has_dot = true; };
			if (ptr_bytes[i] == 'e' || ptr_bytes[i] == 'E') { has_exp = true; };
		};
		let need_dot = !has_dot && !has_exp;

		if (has_f32_suffix) {
			// Emit without f32 suffix, add C-style f suffix
			strbuf_append_bytes_no_underscore(sb, ptr_bytes, base_len);
			if (need_dot) { strbuf_append(sb, ".0"); };
			strbuf_append(sb, "f");
		} else if (has_f64_suffix) {
			// Emit without f64 suffix (C defaults to double)
			strbuf_append_bytes_no_underscore(sb, ptr_bytes, base_len);
			if (need_dot) { strbuf_append(sb, ".0"); };
		} else if (want_f32) {
			// Add f suffix for f32 context
			strbuf_append_bytes_no_underscore(sb, ptr_bytes, slen);
			strbuf_append(sb, "f");
		} else {
			// No suffix needed
			strbuf_append_bytes_no_underscore(sb, ptr_bytes, slen);
		};
		return;
	};

	// Rune literal (character) - handle escape sequences
	if (k == node_kind::N_RUNE) {
		let d = n.data: *n_int_data;
		let sb = ctx.output;
		let val = d.val: u8;
		strbuf_append(sb, "'");
		if (val == 10) { strbuf_append(sb, "\\n"); }
		else if (val == 9) { strbuf_append(sb, "\\t"); }
		else if (val == 13) { strbuf_append(sb, "\\r"); }
		else if (val == 0) { strbuf_append(sb, "\\0"); }
		else if (val == 39) { strbuf_append(sb, "\\'"); }
		else if (val == 92) { strbuf_append(sb, "\\\\"); }
		else { strbuf_append_byte(sb, val); };
		strbuf_append(sb, "'");
		return;
	};

	// Return
	if (k == node_kind::N_RET) {
		let d = n.data: *n_ret_data;
		let sb = ctx.output;
		strbuf_append(sb, "return");
		match (d.expr) {
		case let expr: *node =>
			strbuf_append(sb, " ");
			// Check if we need to wrap for tagged union return
			if (ctx.ret_name_len > 0 && expr.kind == node_kind::N_ID) {
				let ed = expr.data: *n_id_data;
				// Check if returning a variant binding (match case variable)
				let vtype_ptr = get_variant_type(&ctx.variant_bindings, ed.ptr, ed.length);
				let vtype_len = get_variant_type_len(&ctx.variant_bindings, ed.ptr, ed.length);
				match (vtype_ptr) {
				case let vtp: *u8 =>
					// Wrap with the variant type using type-prefixed TAG
					strbuf_append(sb, "(");
					strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
					strbuf_append(sb, "){.tag = ");
					strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
					strbuf_append(sb, "_TAG_");
					strbuf_append_bytes(sb, vtp, vtype_len);
					strbuf_append(sb, ", .value._");
					strbuf_append_bytes(sb, vtp, vtype_len);
					strbuf_append(sb, " = ");
					emit_node(ctx, expr);
					strbuf_append(sb, "}");
				case null =>
					emit_node(ctx, expr);
				};
			} else {
				emit_node(ctx, expr);
			};
		case null => void;
		};
		strbuf_append(sb, ";");
		return;
	};

	// Block
	if (k == node_kind::N_BLOCK) {
		let d = n.data: *n_block_data;
		strbuf_append(ctx.output, "{\n");
		for (let i = 0z; i < d.nstmts; i += 1) {
			strbuf_append(ctx.output, "    ");
			emit_node(ctx, d.stmts[i]);
			strbuf_append(ctx.output, "\n");
		};
		strbuf_append(ctx.output, "}");
		return;
	};

	// Assert
	if (k == node_kind::N_ASSERT) {
		let d = n.data: *n_un_data;
		let sb = ctx.output;
		// Inline assert with line:col: do { if (!(cond)) rt_abort_fixed(&__hare_file,line,col,6); } while(0)
		strbuf_append(sb, "do { if (!(");
		emit_node(ctx, d.operand);
		strbuf_append(sb, ")) rt_abort_fixed(&__hare_file,");
		strbuf_append_uint(sb, n.line: u64);
		strbuf_append(sb, ",");
		strbuf_append_uint(sb, n.col: u64);
		strbuf_append(sb, ",6); } while(0)");
		return;
	};

	// Len or Size builtin
	if (k == node_kind::N_LEN) {
		let d = n.data: *n_un_data;
		let sb = ctx.output;
		let operand: *node = d.operand;

		// Check if this is size() builtin (takes a type)
		if (d.op == token_kind::SIZE) {
			strbuf_append(sb, "sizeof(");
			emit_type(ctx, operand);
			strbuf_append(sb, ")");
			return;
		};

		// len() builtin - check if operand is a string or slice
		let is_string = false;
		let is_slice = false;
		if (operand.kind == node_kind::N_STR) {
			is_string = true;
		} else if (operand.kind == node_kind::N_ID) {
			let id = operand.data: *n_id_data;
			is_string = is_str_var(&ctx.str_vars, id.ptr, id.length);
			is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
		};

		if (is_string || is_slice) {
			strbuf_append(sb, "(");
			emit_node(ctx, operand);
			strbuf_append(sb, ").len");
		} else {
			// For arrays, use sizeof
			strbuf_append(sb, "(sizeof(");
			emit_node(ctx, operand);
			strbuf_append(sb, ")/sizeof((");
			emit_node(ctx, operand);
			strbuf_append(sb, ")[0]))");
		};
		return;
	};

	// Array literal
	if (k == node_kind::N_ARR_LIT) {
		let d = n.data: *n_arr_lit_data;
		let sb = ctx.output;
		strbuf_append(sb, "{");
		match (d.fill) {
		case let fill_node: *node =>
			// Fill syntax [val...] - emit single value
			emit_node(ctx, fill_node);
		case null =>
			for (let i = 0z; i < d.nelems; i += 1) {
				if (i > 0) {
					strbuf_append(sb, ", ");
				};
				emit_node(ctx, d.elems[i]);
			};
		};
		strbuf_append(sb, "}");
		return;
	};

	// Struct literal
	if (k == node_kind::N_STRUCT_LIT) {
		let d = n.data: *n_struct_lit_data;
		let sb = ctx.output;
		// Emit as (TypeName){.field = val, ...}
		strbuf_append(sb, "(");
		if (d.type_name_len > 0) {
			let type_ptr = unwrap_u8(d.type_name_ptr);
			strbuf_append_bytes(sb, type_ptr, d.type_name_len);
		} else {
			strbuf_append(sb, "struct");
		};
		strbuf_append(sb, "){");
		if (d.nfields == 0) {
			// C11 requires at least one initializer, use {0}
			strbuf_append(sb, "0}");
		} else {
			for (let i = 0z; i < d.nfields; i += 1) {
				if (i > 0) {
					strbuf_append(sb, ", ");
				};
				let f: *node = d.fields[i];
				let fd = f.data: *n_field_init_data;
				strbuf_append(sb, ".");
				strbuf_append_bytes(sb, fd.name_ptr, fd.name_len);
				strbuf_append(sb, " = ");
				emit_node(ctx, fd.value);
			};
			strbuf_append(sb, "}");
		};
		return;
	};

	// Anonymous struct literal: struct { x: int = 10 } => (struct { intptr_t x; }){ .x = 10 }
	if (k == node_kind::N_ANON_STRUCT_LIT) {
		let d = n.data: *n_anon_struct_lit_data;
		let sb = ctx.output;
		// Emit as (struct { type field; ... }){.field = val, ...}
		strbuf_append(sb, "(struct { ");
		// First emit the struct type definition
		for (let i = 0z; i < d.nfields; i += 1) {
			let f: *node = d.fields[i];
			let fd = f.data: *n_anon_field_data;
			emit_type(ctx, fd.typ);
			strbuf_append(sb, " ");
			strbuf_append_bytes(sb, fd.name_ptr, fd.name_len);
			strbuf_append(sb, "; ");
		};
		strbuf_append(sb, "}){ ");
		// Now emit the field initializers
		for (let i = 0z; i < d.nfields; i += 1) {
			if (i > 0) {
				strbuf_append(sb, ", ");
			};
			let f: *node = d.fields[i];
			let fd = f.data: *n_anon_field_data;
			strbuf_append(sb, ".");
			strbuf_append_bytes(sb, fd.name_ptr, fd.name_len);
			strbuf_append(sb, " = ");
			emit_node(ctx, fd.value);
		};
		strbuf_append(sb, " }");
		return;
	};

	// Tuple literal - emit as (__hare_tuple_N){ ._0 = v0, ._1 = v1, ... }
	if (k == node_kind::N_TUPLE_LIT) {
		let d = n.data: *n_tuple_lit_data;
		let sb = ctx.output;
		// Find a matching tuple type by element structure (not just count)
		// For nested tuples, we need to match element types, not just count
		let tuple_idx: i64 = -1;
		for (let i = 0z; i < ctx.tuple_count; i += 1) {
			let tt = ctx.tuple_types[i];
			let td = tt.data: *n_ttagged_data;
			if (td.nvariants == d.nelems) {
				// Check if this tuple type matches our literal's structure
				let matches = true;
				for (let j = 0z; j < d.nelems; j += 1) {
					let elem: *node = d.elems[j];
					let type_variant: *node = td.variants[j];
					// If literal element is a tuple, type variant should be a tuple
					// If literal element is not a tuple, type variant should not be a tuple
					let elem_is_tuple = elem.kind == node_kind::N_TUPLE_LIT;
					let type_is_tuple = type_variant.kind == node_kind::N_TTUPLE;
					if (elem_is_tuple != type_is_tuple) {
						matches = false;
						break;
					};
					// For nested tuple elements, recursively check structure
					if (elem_is_tuple) {
						let nested_lit = elem.data: *n_tuple_lit_data;
						let nested_type = type_variant.data: *n_ttagged_data;
						if (nested_lit.nelems != nested_type.nvariants) {
							matches = false;
							break;
						};
					};
				};
				if (matches) {
					tuple_idx = i: i64;
					break;
				};
			};
		};
		strbuf_append(sb, "(__hare_tuple_");
		strbuf_append_int(sb, tuple_idx);
		strbuf_append(sb, "){ ");
		for (let i = 0z; i < d.nelems; i += 1) {
			if (i > 0) {
				strbuf_append(sb, ", ");
			};
			strbuf_append(sb, "._");
			strbuf_append_int(sb, i: i64);
			strbuf_append(sb, " = ");
			emit_node(ctx, d.elems[i]);
		};
		strbuf_append(sb, " }");
		return;
	};

	// Error propagation: expr?
	// Check if error (tag != 0), return if so, otherwise continue with value
	if (k == node_kind::N_PROP) {
		let d = n.data: *n_prop_data;
		let sb = ctx.output;
		let expr: *node = d.expr;

		// Slice operations (append, insert, delete) in our C implementation either
		// succeed or abort - they don't return error unions, so ! is a no-op
		if (expr.kind == node_kind::N_APPEND ||
		    expr.kind == node_kind::N_INSERT ||
		    expr.kind == node_kind::N_DELETE) {
			emit_node(ctx, expr);
			return;
		};

		// Special case: alloc()? - extract pointer from tagged union result
		if (expr.kind == node_kind::N_ALLOC) {
			let ad = expr.data: *n_alloc_data;
			// Generate: ({ __auto_type __e = (alloc_expr); if (__e.tag != 0) { defers...; return <error>; } __e.value._ptr_X; })
			// Note: we return a compatible error struct, not __e directly (type might differ)
			strbuf_append(sb, "({ __auto_type __e = (");
			emit_node(ctx, expr);
			strbuf_append(sb, "); if (__e.tag != 0) { ");
			// Emit defers in reverse order (LIFO) before returning error
			let idx = ctx.fn_defer_count;
			for (idx > 0) {
				idx -= 1;
				emit_node(ctx, ctx.fn_defers[idx]);
				strbuf_append(sb, "; ");
			};
			strbuf_append(sb, "return (");
			// Emit return type name if available
			if (ctx.ret_name_len > 0) {
				strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
			} else {
				strbuf_append(sb, "__auto_type");
			};
			strbuf_append(sb, "){.tag = HARE_ERROR_TAG_BASE}; } __e.value.");
			// Use _ptr for struct literals, _ptr_int for others
			if (ad.expr.kind == node_kind::N_STRUCT_LIT) {
				strbuf_append(sb, "_ptr; })");
			} else {
				strbuf_append(sb, "_ptr_int; })");
			};
			return;
		};

		// General case: tagged union error handling
		// Generate: ({ __auto_type __e = (expr); if (__e.tag != 0) { defers...; return (RetType){.tag = __e.tag}; } result_expr; })
		// result_expr is (void)0 for void-success types, __e.value._int otherwise
		// Note: uses function's return type to handle type conversion between compatible tagged unions

		// Determine success variant for tagged unions (fallback to void-result tracking)
		let result_variant: nullable *node = null;
		let has_result_variant = false;
		let is_void_result = false;
		match (get_error_result_variant(ctx, infer_expr_type(ctx, expr))) {
		case let rv: *node =>
			result_variant = rv;
			has_result_variant = true;
			is_void_result = is_void_type_node(ctx, rv);
		case null =>
			if (expr.kind == node_kind::N_CALL) {
				let cd = expr.data: *n_call_data;
				if (cd.func.kind == node_kind::N_ID) {
					let func_id = cd.func.data: *n_id_data;
					is_void_result = is_tracked_var(&ctx.void_result_fns, func_id.ptr, func_id.length);
				};
			};
		};

		strbuf_append(sb, "({ __auto_type __e = (");
		emit_node(ctx, expr);
		strbuf_append(sb, "); if (__e.tag != 0) { ");
		// Emit defers in reverse order (LIFO) before returning error
		let idx = ctx.fn_defer_count;
		for (idx > 0) {
			idx -= 1;
			emit_node(ctx, ctx.fn_defers[idx]);
			strbuf_append(sb, "; ");
		};
		strbuf_append(sb, "return ");
		// Use return type if available for type conversion
		if (ctx.ret_name_len > 0) {
			strbuf_append(sb, "(");
			strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
			strbuf_append(sb, "){.tag = __e.tag}");
		} else {
			strbuf_append(sb, "__e");
		};
		strbuf_append(sb, "; } ");
		// Use (void)0 for void-success types, success variant field when known
		if (is_void_result) {
			strbuf_append(sb, "(void)0; })");
		} else if (has_result_variant) {
			strbuf_append(sb, "__e.value._");
			emit_type_tag(sb, unwrap(result_variant));
			strbuf_append(sb, "; })");
		} else {
			strbuf_append(sb, "__e.value._int; })");
		};
		return;
	};

	// Error unwrap: expr!
	// Check if error (tag != 0), abort if so, otherwise continue with value
	if (k == node_kind::N_UNWRAP) {
		let d = n.data: *n_prop_data;
		let sb = ctx.output;
		let expr: *node = d.expr;

		// Slice operations (append, insert, delete) in our C implementation either
		// succeed or abort - they don't return error unions, so ! is a no-op
		if (expr.kind == node_kind::N_APPEND ||
		    expr.kind == node_kind::N_INSERT ||
		    expr.kind == node_kind::N_DELETE) {
			emit_node(ctx, expr);
			return;
		};

		// Special case: alloc()! - check tagged union result and extract pointer
		if (expr.kind == node_kind::N_ALLOC) {
			let ad = expr.data: *n_alloc_data;
			// Generate: ({ __auto_type __e = (alloc_expr); if (__e.tag != 0) { defers...; rt_abort_msg("out of memory"); } __e.value._ptr_X; })
			strbuf_append(sb, "({ __auto_type __e = (");
			emit_node(ctx, expr);
			strbuf_append(sb, "); if (__e.tag != 0) { ");
			// Emit defers in reverse order (LIFO) before aborting
			let idx = ctx.fn_defer_count;
			for (idx > 0) {
				idx -= 1;
				emit_node(ctx, ctx.fn_defers[idx]);
				strbuf_append(sb, "; ");
			};
			strbuf_append(sb, "rt_abort_fixed(&__hare_file,0,0,2); } __e.value.");
			// Use _ptr for struct literals, _ptr_int for others
			if (ad.expr.kind == node_kind::N_STRUCT_LIT) {
				strbuf_append(sb, "_ptr; })");
			} else {
				strbuf_append(sb, "_ptr_int; })");
			};
			return;
		};

		// General case: tagged union error handling
		// Generate: ({ __auto_type __e = (expr); if (__e.tag != 0) { defers...; rt_abort_msg(__hare_error_msg); } result_expr; })
		// result_expr is (void)0 for void-success types, __e.value._int otherwise

		// Determine success variant for tagged unions (fallback to void-result tracking)
		let result_variant: nullable *node = null;
		let has_result_variant = false;
		let is_void_result = false;
		match (get_error_result_variant(ctx, infer_expr_type(ctx, expr))) {
		case let rv: *node =>
			result_variant = rv;
			has_result_variant = true;
			is_void_result = is_void_type_node(ctx, rv);
		case null =>
			if (expr.kind == node_kind::N_CALL) {
				let cd = expr.data: *n_call_data;
				if (cd.func.kind == node_kind::N_ID) {
					let func_id = cd.func.data: *n_id_data;
					is_void_result = is_tracked_var(&ctx.void_result_fns, func_id.ptr, func_id.length);
				};
			};
		};

		strbuf_append(sb, "({ __auto_type __e = (");
		emit_node(ctx, expr);
		strbuf_append(sb, "); if (__e.tag != 0) { ");
		// Emit defers in reverse order (LIFO) before aborting
		let idx = ctx.fn_defer_count;
		for (idx > 0) {
			idx -= 1;
			emit_node(ctx, ctx.fn_defers[idx]);
			strbuf_append(sb, "; ");
		};
		strbuf_append(sb, "rt_abort_fixed(&__hare_file,0,0,7); } ");
		// Use (void)0 for void-success types, success variant field when known
		if (is_void_result) {
			strbuf_append(sb, "(void)0; })");
		} else if (has_result_variant) {
			strbuf_append(sb, "__e.value._");
			emit_type_tag(sb, unwrap(result_variant));
			strbuf_append(sb, "; })");
		} else {
			strbuf_append(sb, "__e.value._int; })");
		};
		return;
	};

	// Type test (is operator)
	// For tagged unions: expr.tag == INDEX
	// For null checks: expr == NULL
	if (k == node_kind::N_IS) {
		let d = n.data: *n_is_data;
		let sb = ctx.output;
		let typ: *node = d.typ;

		// Check for null test
		if (typ.kind == node_kind::N_TPRIM) {
			let td = typ.data: *n_id_data;
			if (type_is(td.ptr, td.length, "null")) {
				strbuf_append(sb, "((");
				emit_node(ctx, d.expr);
				strbuf_append(sb, ") == NULL)");
				return;
			};
		};

		// Try to get the variant name being tested against
		let variant_ptr: nullable *u8 = null;
		let variant_len: size = 0;
		if (typ.kind == node_kind::N_TPRIM || typ.kind == node_kind::N_TALIAS) {
			let td = typ.data: *n_id_data;
			variant_ptr = td.ptr;
			variant_len = td.length;
		};

		// Check if expr is a variable with a tracked type
		if (d.expr.kind == node_kind::N_ID) {
			match (variant_ptr) {
			case let vp: *u8 =>
				let expr_id = d.expr.data: *n_id_data;
				let var_type = find_var_type(ctx, expr_id.ptr, expr_id.length);
				match (var_type) {
				case let vt: *node =>
					// Resolve type alias to actual tagged union
					let resolved_vt = vt;
					if (vt.kind == node_kind::N_TALIAS) {
						let td = vt.data: *n_id_data;
						let resolved = find_typedef(ctx, td.ptr, td.length);
						match (resolved) {
						case let r: *node =>
							resolved_vt = r;
						case null => void;
						};
					} else if (vt.kind == node_kind::N_TPRIM) {
						// Check if this is a user-defined type (not a built-in primitive)
						let td = vt.data: *n_id_data;
						if (!is_prim_type_name(td.ptr, td.length)) {
							let resolved = find_typedef(ctx, td.ptr, td.length);
							match (resolved) {
							case let r: *node =>
								resolved_vt = r;
							case null => void;
							};
						};
					};
					if (resolved_vt.kind == node_kind::N_TTAGGED) {
						if (typ.kind == node_kind::N_TERR) {
							// Match !T against error variants
							let td = resolved_vt.data: *n_ttagged_data;
							let cd = typ.data: *n_terr_data;
							let tag_idx: i64 = -1;
							for (let j = 0z; j < td.nvariants; j += 1) {
								let variant = td.variants[j];
								let resolved = resolve_type_alias(ctx, variant);
								if (resolved.kind == node_kind::N_TERR) {
									let vd = resolved.data: *n_terr_data;
									if (types_assignable(ctx, cd.inner, vd.inner) &&
										types_assignable(ctx, vd.inner, cd.inner)) {
										tag_idx = j: i64;
										break;
									};
								};
							};
							if (tag_idx >= 0) {
								strbuf_append(sb, "((");
								emit_node(ctx, d.expr);
								strbuf_append(sb, ").tag == ");
								strbuf_append_int(sb, tag_idx);
								strbuf_append(sb, "U)");
								return;
							};
						} else {
							// Found the variable's tagged union type - compute exact tag index
							let tag_idx = find_variant_tag_in_type(resolved_vt, vp, variant_len);
							if (tag_idx >= 0) {
								strbuf_append(sb, "((");
								emit_node(ctx, d.expr);
								strbuf_append(sb, ").tag == ");
								strbuf_append_int(sb, tag_idx);
								strbuf_append(sb, "U)");
								return;
							};
						};
					};
				case null => void;
				};
			case null => void;
			};
		};

		// Fallback: emit tag index 0 with a warning comment
		// This happens when we can't determine the exact type
		strbuf_append(sb, "((");
		emit_node(ctx, d.expr);
		strbuf_append(sb, ").tag == 0U /* WARNING: could not resolve type for '");
		emit_type_tag(sb, typ);
		strbuf_append(sb, "' */)");
		return;
	};

	// Match expression
	if (k == node_kind::N_MATCH) {
		let d = n.data: *n_match_data;
		let sb = ctx.output;

		// Check if match expression type is an enum (should use switch instead)
		let match_expr_type = infer_expr_type(ctx, d.expr);
		match (match_expr_type) {
		case let mt: *node =>
			if (mt.kind == node_kind::N_TPRIM) {
				let mtd = mt.data: *n_id_data;
				if (is_tracked_var(&ctx.enum_types, mtd.ptr, mtd.length)) {
					emit_error_at_node(ctx, d.expr, "cannot match on enum type (use switch instead)");
				};
			};
		case null => void;
		};

		// Check if this is a nullable pointer match
		// 1. Check for explicit case null =>
		// 2. Check if match expression type is nullable *T
		let is_nullable_match = false;
		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_mcase_data;
			match (cd.typ) {
			case let typ_node: *node =>
				if (typ_node.kind == node_kind::N_NULL) {
					is_nullable_match = true;
					break;
				};
			case null => void;
			};
		};
		// Also check if the matched expression is a nullable pointer
		if (!is_nullable_match) {
			let expr_type = infer_expr_type(ctx, d.expr);
			match (expr_type) {
			case let et: *node =>
				if (et.kind == node_kind::N_TPTR) {
					let pd = et.data: *n_tptr_data;
					if (pd.is_nullable) {
						is_nullable_match = true;
					};
				};
			case null => void;
			};
		};

		if (is_nullable_match) {
			// Nullable pointer match - emit if-else on NULL check
			// First, find null case, non-null case, and catch-all case
			let null_case: nullable *node = null;
			let nonnull_case: nullable *node = null;
			let catchall_case: nullable *node = null;
			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_mcase_data;
				match (cd.typ) {
				case null =>
					// Catch-all case (handles null in nullable match)
					catchall_case = c;
				case let ct: *node =>
					if (ct.kind == node_kind::N_NULL) {
						// Explicit null case
						null_case = c;
					} else {
						// Non-null case (pointer type)
						nonnull_case = c;
					};
				};
			};

			strbuf_append(sb, "({\n");
			strbuf_append(sb, "    __auto_type __m = (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ");\n");
			strbuf_append(sb, "    ");
			// Use type from non-null case for __r, or ret_type in return context
			let emitted_type = false;
			if (ctx.in_return_expr) {
				match (ctx.ret_type) {
				case let ret_t: *node =>
					if (!is_void_type_node(ctx, ret_t)) {
						emit_type(ctx, ret_t);
						emitted_type = true;
					};
				case null => void;
				};
			};
			if (!emitted_type) {
				// Determine __r type based on what's yielded:
				// - If yield is the bound variable directly, use pointer type
				// - Otherwise, infer type from yield expression
				let type_emitted = false;
				match (nonnull_case) {
				case let c: *node =>
					let cd = c.data: *n_mcase_data;
					let yield_expr = get_case_yield_expr(cd.body);
					match (yield_expr) {
					case let ye: *node =>
						// Check if yield is the bound variable name
						let is_bound_var = false;
						if (ye.kind == node_kind::N_ID) {
							match (cd.bind_ptr) {
							case let bp: *u8 =>
								let yid = ye.data: *n_id_data;
								if (yid.length == cd.bind_len) {
									is_bound_var = true;
									let yid_bytes = yid.ptr: *[*]u8;
									let bp_bytes = bp: *[*]u8;
									for (let j = 0z; j < yid.length; j += 1) {
										if (yid_bytes[j] != bp_bytes[j]) {
											is_bound_var = false;
											break;
										};
									};
								};
							case null => void;
							};
						};
						if (is_bound_var) {
							// Use case type for bound variable
							match (cd.typ) {
							case let ct: *node =>
								emit_type(ctx, ct);
								type_emitted = true;
							case null => void;
							};
						} else {
							// Infer type from yield expression (e.g. function call)
							let saved_var_count = ctx.var_type_count;
							if (cd.bind_len > 0 && cd.typ != null) {
								match (cd.bind_ptr) {
								case let bind_ptr: *u8 =>
									add_var_type(ctx, bind_ptr, cd.bind_len, unwrap(cd.typ));
								case null => void;
								};
							};
							let inferred = infer_expr_type(ctx, ye);
							ctx.var_type_count = saved_var_count;
							match (inferred) {
							case let it: *node =>
								emit_type(ctx, it);
								type_emitted = true;
							case null => void;
							};
						};
					case null => void;
					};
				case null => void;
				};
				if (!type_emitted) {
					strbuf_append(sb, "intptr_t");
				};
			};
			strbuf_append(sb, " __r = {0};\n");

			// Emit if (__m != NULL) for non-null case, else for null/catch-all
			strbuf_append(sb, "    if (__m != NULL) {\n");
			match (nonnull_case) {
			case let c: *node =>
				let cd = c.data: *n_mcase_data;
				// Emit binding if present
				if (cd.bind_ptr != null && cd.bind_len > 0) {
					match (cd.typ) {
					case let ct: *node =>
						match (cd.bind_ptr) {
						case let bind_ptr: *u8 =>
							strbuf_append(sb, "        ");
							emit_type(ctx, ct);
							strbuf_append(sb, " __attribute__((unused)) ");
							strbuf_append_bytes(sb, bind_ptr, cd.bind_len);
							strbuf_append(sb, " = __m;\n");
							// Track pointer binding for auto-dereference
							add_var_type(ctx, bind_ptr, cd.bind_len, ct);
						case null =>
							void;
						};
					case null => void;
					};
				};
				// Track narrowed nullable pointer for dereference safety check
				// If the match expression is an identifier, track it as narrowed
				let prev_narrowed_ptr = ctx.narrowed_nullable_ptr;
				let prev_narrowed_len = ctx.narrowed_nullable_len;
				if (d.expr.kind == node_kind::N_ID) {
					let matched_id = d.expr.data: *n_id_data;
					ctx.narrowed_nullable_ptr = matched_id.ptr;
					ctx.narrowed_nullable_len = matched_id.length;
				};
				// Emit body
				emit_nullable_case_body(ctx, cd.body, sb);
				// Restore narrowed nullable tracking
				ctx.narrowed_nullable_ptr = prev_narrowed_ptr;
				ctx.narrowed_nullable_len = prev_narrowed_len;
			case null => void;
			};
			strbuf_append(sb, "    } else {\n");
			// Emit null case body (either explicit null case or catch-all)
			match (null_case) {
			case let c: *node =>
				let cd = c.data: *n_mcase_data;
				emit_nullable_case_body(ctx, cd.body, sb);
			case null =>
				match (catchall_case) {
				case let c: *node =>
					let cd = c.data: *n_mcase_data;
					emit_nullable_case_body(ctx, cd.body, sb);
				case null => void;
				};
			};
			strbuf_append(sb, "    }\n");
			if (ctx.result_used) {
				strbuf_append(sb, "    __r;\n");
			} else {
				strbuf_append(sb, "    (void)0;\n");
			};
			strbuf_append(sb, "})");
			return;
		};

		// Check if this is an enum match (case types contain underscore like color_RED)
		let is_enum_match = false;
		let match_is_tagged = false;
		match (infer_expr_type(ctx, d.expr)) {
		case let mt: *node =>
			if (resolve_tagged_type(ctx, mt) != null) {
				match_is_tagged = true;
			};
		case null => void;
		};
		if (!match_is_tagged && d.ncases > 0) {
			let first_case: *node = d.cases[0];
			let fcd = first_case.data: *n_mcase_data;
			match (fcd.typ) {
			case let typ: *node =>
				if (typ.kind == node_kind::N_TPRIM) {
					let td = typ.data: *n_id_data;
					let td_bytes = td.ptr: *[*]u8;
					// Check if name contains underscore (enum_MEMBER pattern)
					for (let i = 0z; i < td.length; i += 1) {
						if (td_bytes[i] == '_') {
							is_enum_match = true;
							break;
						};
					};
				};
			case null => void;
			};
		};

		if (is_enum_match) {
			// Enum match - simple switch on the enum value
			strbuf_append(sb, "({\n");
			strbuf_append(sb, "    __auto_type __m = (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ");\n");
			strbuf_append(sb, "    ");
			// Use ret_type when in return expression context (non-void)
			let enum_emitted_type = false;
			if (ctx.in_return_expr) {
				match (ctx.ret_type) {
				case let ret_t: *node =>
					if (!is_void_type_node(ctx, ret_t)) {
						emit_type(ctx, ret_t);
						enum_emitted_type = true;
					};
				case null => void;
				};
			};
			if (!enum_emitted_type) {
				strbuf_append(sb, "intptr_t");
			};
			strbuf_append(sb, " __r = {0};\n");
			strbuf_append(sb, "    switch (__m) {\n");

			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_mcase_data;

				match (cd.typ) {
				case null =>
					strbuf_append(sb, "    default: {\n");
				case let typ: *node =>
					// Emit case with enum constant name
					strbuf_append(sb, "    case ");
					let td = typ.data: *n_id_data;
					strbuf_append_bytes(sb, td.ptr, td.length);
					strbuf_append(sb, ": {\n");
				};

				// Emit body
				let body: *node = cd.body;
				if (body.kind == node_kind::N_BLOCK) {
					let bd = body.data: *n_block_data;
					for (let j = 0z; j < bd.nstmts; j += 1) {
						let stmt: *node = bd.stmts[j];
						strbuf_append(sb, "        ");
						if (stmt.kind == node_kind::N_YIELD) {
							let yd = stmt.data: *n_yield_data;
							strbuf_append(sb, "__r = ");
							match (yd.expr) {
							case let expr_node: *node =>
								emit_node(ctx, expr_node);
							case null =>
								strbuf_append(sb, "0");
							};
							strbuf_append(sb, ";");
						} else if (stmt.kind == node_kind::N_EXPR) {
							let ed = stmt.data: *n_ret_data;
							let expr = unwrap(ed.expr);
							if (ctx.result_used && !is_void_result(expr)) {
								strbuf_append(sb, "__r = ");
								emit_node(ctx, expr);
								strbuf_append(sb, ";");
							} else {
								strbuf_append(sb, "(void)(");
								emit_node(ctx, expr);
								strbuf_append(sb, ");");
							};
						} else if (stmt.kind == node_kind::N_EXPR) {
							let ed = stmt.data: *n_ret_data;
							let expr = unwrap(ed.expr);
							if (ctx.result_used && !is_void_result(expr)) {
								strbuf_append(sb, "__r = ");
								emit_node(ctx, expr);
								strbuf_append(sb, ";");
							} else {
								strbuf_append(sb, "(void)(");
								emit_node(ctx, expr);
								strbuf_append(sb, ");");
							};
						} else {
							emit_node(ctx, stmt);
							strbuf_append(sb, ";");
						};
						strbuf_append(sb, "\n");
					};
				} else if (body.kind == node_kind::N_YIELD) {
					let yd = body.data: *n_yield_data;
					strbuf_append(sb, "        __r = ");
					match (yd.expr) {
					case let expr_node: *node =>
						emit_node(ctx, expr_node);
					case null =>
						strbuf_append(sb, "0");
					};
					strbuf_append(sb, ";\n");
				} else {
					strbuf_append(sb, "        __r = ");
					emit_node(ctx, body);
					strbuf_append(sb, ";\n");
				};
				strbuf_append(sb, "    } break;\n");
			};
			strbuf_append(sb, "    }\n");
			if (ctx.result_used) {
				strbuf_append(sb, "    __r;\n");
			} else {
				strbuf_append(sb, "    (void)0;\n");
			};
			strbuf_append(sb, "})");
			return;
		};

		// Regular tagged union match - generates switch on tag
		strbuf_append(sb, "({\n");
		strbuf_append(sb, "    __auto_type __m = (");
		emit_node(ctx, d.expr);
		strbuf_append(sb, ");\n");
		strbuf_append(sb, "    ");
		// Use ret_type when in return expression context (non-void)
		let tagged_emitted_type = false;
		if (ctx.in_return_expr) {
			match (ctx.ret_type) {
			case let ret_t: *node =>
				if (!is_void_type_node(ctx, ret_t)) {
					emit_type(ctx, ret_t);
					tagged_emitted_type = true;
				};
			case null => void;
			};
		};
		if (!tagged_emitted_type) {
			// Default to intptr_t if no return type known
			strbuf_append(sb, "intptr_t");
		};
		strbuf_append(sb, " __r = {0};\n");
		strbuf_append(sb, "    switch (__m.tag) {\n");

		// Get the tagged union type for proper tag index lookup
		let matched_type: nullable *node = null;
		let match_expr: *node = d.expr;
		if (match_expr.kind == node_kind::N_ID) {
			let id = match_expr.data: *n_id_data;
			let var_type = find_var_type(ctx, id.ptr, id.length);
			match (var_type) {
			case let vt: *node =>
				if (vt.kind == node_kind::N_TALIAS) {
					let td = vt.data: *n_id_data;
					let resolved = find_typedef(ctx, td.ptr, td.length);
					matched_type = resolved;  // Already nullable
				} else if (vt.kind == node_kind::N_TTAGGED) {
					matched_type = vt;
				} else if (vt.kind == node_kind::N_TPRIM) {
					// Check if this is a user-defined type (not a built-in primitive)
					let td = vt.data: *n_id_data;
					if (!is_prim_type_name(td.ptr, td.length)) {
						let resolved = find_typedef(ctx, td.ptr, td.length);
						matched_type = resolved;  // Already nullable
					};
				};
			case null => void;
			};
		};

		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_mcase_data;

			match (cd.typ) {
			case null =>
				// Catch-all case
				strbuf_append(sb, "    default: {\n");
			case let case_type: *node =>
				// Regular case - use numeric literal with comment
				let tag_idx: i64 = -1;

				// Get variant name for tag lookup
				if (case_type.kind == node_kind::N_TPRIM || case_type.kind == node_kind::N_TALIAS) {
					let td = case_type.data: *n_id_data;
					match (matched_type) {
					case let mt: *node =>
						tag_idx = find_variant_tag_in_type(mt, td.ptr, td.length);
					case null => void;
					};
				} else if (case_type.kind == node_kind::N_VOID) {
					// void variant - look up "void" in tagged union
					match (matched_type) {
					case let mt: *node =>
						let void_name: str = "void";
						tag_idx = find_variant_tag_in_type(mt, strings::toutf8(void_name): *[*]u8: *u8, 4);
					case null => void;
					};
				};

				if (tag_idx >= 0) {
					strbuf_append(sb, "    case ");
					strbuf_append_int(sb, tag_idx);
					strbuf_append(sb, "U: /* ");
					emit_type_tag(sb, case_type);
					strbuf_append(sb, " */ {\n");
				} else {
					// Fallback if we couldn't resolve the type
					strbuf_append(sb, "    case ");
					strbuf_append_int(sb, i: i64);
					strbuf_append(sb, "U: /* ");
					emit_type_tag(sb, case_type);
					strbuf_append(sb, " */ {\n");
				};

				// Emit binding if present
				if (cd.bind_ptr != null && cd.bind_len > 0) {
					match (cd.bind_ptr) {
					case let bind_ptr: *u8 =>
						strbuf_append(sb, "        ");
						emit_type(ctx, case_type);
						strbuf_append(sb, " __attribute__((unused)) ");
						strbuf_append_bytes(sb, bind_ptr, cd.bind_len);
						strbuf_append(sb, " = __m.value._");
						emit_type_tag(sb, case_type);
						strbuf_append(sb, ";\n");

						// Track this binding with its variant type for return wrapping
						// Clear any previous binding for same name (scope the binding to this case)
						clear_variant_bindings(&ctx.variant_bindings);
						// Also add to local_vars so return handling checks variant bindings
						add_tracked_var(&ctx.local_vars, bind_ptr, cd.bind_len);
						// Track binding type for auto-dereference in field access
						add_var_type(ctx, bind_ptr, cd.bind_len, case_type);
						// Only track non-primitive types as variant bindings (error types, custom types)
						if (case_type.kind == node_kind::N_TPRIM) {
							let td = case_type.data: *n_id_data;
							// Track string variables for len() to use .len instead of sizeof
							if (type_name_is(td.ptr, td.length, "str")) {
								add_str_var(&ctx.str_vars, bind_ptr, cd.bind_len);
							};
							// Skip primitives like int, str, bool - they don't need wrapping
							if (!is_prim_type_name(td.ptr, td.length)) {
								add_variant_binding(&ctx.variant_bindings, bind_ptr, cd.bind_len, td.ptr, td.length);
							};
						};
					case null =>
						void;
					};
				};
			};

			// Emit body - check for yield or block
			let body: *node = cd.body;
			if (body.kind == node_kind::N_BLOCK) {
				let bd = body.data: *n_block_data;
				for (let j = 0z; j < bd.nstmts; j += 1) {
					let stmt: *node = bd.stmts[j];
					strbuf_append(sb, "        ");
					// Handle yield specially
					if (stmt.kind == node_kind::N_YIELD) {
						let yd = stmt.data: *n_yield_data;
						// Check if yielding a variant binding that needs direct return
						let emit_direct = false;
						match (yd.expr) {
						case let expr_node: *node =>
							if (expr_node.kind == node_kind::N_ID) {
								let yid = expr_node.data: *n_id_data;
								let vtype_ptr = get_variant_type(&ctx.variant_bindings, yid.ptr, yid.length);
								let vtype_len = get_variant_type_len(&ctx.variant_bindings, yid.ptr, yid.length);
								if (ctx.ret_name_len > 0) {
									match (vtype_ptr) {
									case let vtp: *u8 =>
										// Yield variant binding - emit direct return with type-prefixed TAG
										strbuf_append(sb, "return (");
										strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
										strbuf_append(sb, "){.tag = ");
										strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
										strbuf_append(sb, "_TAG_");
										strbuf_append_bytes(sb, vtp, vtype_len);
										strbuf_append(sb, ", .value._");
										strbuf_append_bytes(sb, vtp, vtype_len);
										strbuf_append(sb, " = ");
										emit_node(ctx, expr_node);
										strbuf_append(sb, "};");
										emit_direct = true;
									case null => void;
									};
								};
							};
						case null => void;
						};
						if (!emit_direct) {
							strbuf_append(sb, "__r = ");
							match (yd.expr) {
							case let expr_node: *node =>
								emit_node(ctx, expr_node);
							case null =>
								strbuf_append(sb, "0");
							};
							strbuf_append(sb, ";");
						};
					} else if (stmt.kind == node_kind::N_EXPR) {
						let ed = stmt.data: *n_ret_data;
						let expr = unwrap(ed.expr);
						if (ctx.result_used && !is_void_result(expr)) {
							strbuf_append(sb, "__r = ");
							emit_node(ctx, expr);
							strbuf_append(sb, ";");
						} else {
							strbuf_append(sb, "(void)(");
							emit_node(ctx, expr);
							strbuf_append(sb, ");");
						};
					} else if (stmt.kind == node_kind::N_EXPR) {
						let ed = stmt.data: *n_ret_data;
						let expr = unwrap(ed.expr);
						if (ctx.result_used && !is_void_result(expr)) {
							strbuf_append(sb, "__r = ");
							emit_node(ctx, expr);
							strbuf_append(sb, ";");
						} else {
							strbuf_append(sb, "(void)(");
							emit_node(ctx, expr);
							strbuf_append(sb, ");");
						};
					} else {
						emit_node(ctx, stmt);
						strbuf_append(sb, ";");
					};
					strbuf_append(sb, "\n");
				};
			} else if (body.kind == node_kind::N_YIELD) {
				// Direct yield
				let yd = body.data: *n_yield_data;
				// Check if yielding a variant binding that needs direct return
				let emit_direct = false;
				match (yd.expr) {
				case let expr_node: *node =>
					if (expr_node.kind == node_kind::N_ID) {
						let yid = expr_node.data: *n_id_data;
						let vtype_ptr = get_variant_type(&ctx.variant_bindings, yid.ptr, yid.length);
						let vtype_len = get_variant_type_len(&ctx.variant_bindings, yid.ptr, yid.length);
						if (ctx.ret_name_len > 0) {
							match (vtype_ptr) {
							case let vtp: *u8 =>
								// Yield variant binding - emit direct return with type-prefixed TAG
								strbuf_append(sb, "        return (");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_");
								strbuf_append_bytes(sb, vtp, vtype_len);
								strbuf_append(sb, ", .value._");
								strbuf_append_bytes(sb, vtp, vtype_len);
								strbuf_append(sb, " = ");
								emit_node(ctx, expr_node);
								strbuf_append(sb, "};\n");
								emit_direct = true;
							case null => void;
							};
						};
					};
				case null => void;
				};
				if (!emit_direct) {
					strbuf_append(sb, "        __r = ");
					match (yd.expr) {
					case let expr_node: *node =>
						emit_node(ctx, expr_node);
					case null =>
						strbuf_append(sb, "0");
					};
					strbuf_append(sb, ";\n");
				};
			} else {
				// Check if body returns void (abort, assert) - don't assign to __r
				let is_void_expr = is_void_result(body);

				if (is_void_expr) {
					strbuf_append(sb, "        ");
					emit_node(ctx, body);
					strbuf_append(sb, ";\n");
				} else {
					strbuf_append(sb, "        __r = ");
					emit_node(ctx, body);
					strbuf_append(sb, ";\n");
				};
			};
			strbuf_append(sb, "    } break;\n");
		};

		strbuf_append(sb, "    }\n");
		if (ctx.result_used) {
			strbuf_append(sb, "    __r;\n");
		} else {
			strbuf_append(sb, "    (void)0;\n");
		};
		strbuf_append(sb, "})");
		return;
	};

	// Switch expression (when used as value, not statement)
	if (k == node_kind::N_SWITCH) {
		let d = n.data: *n_switch_data;
		let sb = ctx.output;

		// Check if this is a string switch
		let is_str_switch = is_string_expr(ctx, d.expr);

		if (is_str_switch) {
			// String switch - emit as if-else chain with rt_strcmp
			// First, determine if the result type is string or int by checking case bodies
			let result_is_str = false;
			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_case_data;
				let body: *node = cd.body;
				// Check body for string result
				if (body.kind == node_kind::N_STR) {
					result_is_str = true;
					break;
				};
				if (body.kind == node_kind::N_BLOCK) {
					let bd = body.data: *n_block_data;
					for (let j = 0z; j < bd.nstmts; j += 1) {
						let stmt: *node = bd.stmts[j];
						if (stmt.kind == node_kind::N_YIELD) {
							let yd = stmt.data: *n_yield_data;
							match (yd.expr) {
							case let expr_node: *node =>
								if (expr_node.kind == node_kind::N_STR) {
									result_is_str = true;
									break;
								};
							case null => void;
							};
						};
					};
					if (result_is_str) {
						break;
					};
				} else if (body.kind == node_kind::N_YIELD) {
					let yd = body.data: *n_yield_data;
					match (yd.expr) {
					case let expr_node: *node =>
						if (expr_node.kind == node_kind::N_STR) {
							result_is_str = true;
							break;
						};
					case null => void;
					};
				};
			};

			strbuf_append(sb, "({\n");
			strbuf_append(sb, "    __auto_type __sw = (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ");\n");
			let str_emitted_type = false;
			if (ctx.in_return_expr) {
				match (ctx.ret_type) {
				case let ret_t: *node =>
					if (!is_void_type_node(ctx, ret_t)) {
						strbuf_append(sb, "    ");
						emit_type(ctx, ret_t);
						strbuf_append(sb, " __r = {0};\n");
						str_emitted_type = true;
					};
				case null => void;
				};
			};
			if (!str_emitted_type) {
				if (result_is_str) {
					strbuf_append(sb, "    hare_str __r = (hare_str){0};\n");
				} else {
					strbuf_append(sb, "    intptr_t __r = 0;\n");
				};
			};

			let first = true;
			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_case_data;

				if (cd.nvalues == 0) {
					// Default case - emit as else
					strbuf_append(sb, "    else {\n");
				} else {
					// Regular case(s) - emit as if with rt_strcmp
					if (first) {
						strbuf_append(sb, "    if (");
						first = false;
					} else {
						strbuf_append(sb, "    else if (");
					};

					for (let j = 0z; j < cd.nvalues; j += 1) {
						if (j > 0) {
							strbuf_append(sb, " || ");
						};
						strbuf_append(sb, "rt_strcmp(__sw, ");
						emit_node(ctx, cd.values[j]);
						strbuf_append(sb, ")");
					};
					strbuf_append(sb, ") {\n");
				};

				// Emit body
				let body: *node = cd.body;
				if (body.kind == node_kind::N_BLOCK) {
					let bd = body.data: *n_block_data;
					for (let j = 0z; j < bd.nstmts; j += 1) {
						let stmt: *node = bd.stmts[j];
						strbuf_append(sb, "        ");
						if (stmt.kind == node_kind::N_YIELD) {
							let yd = stmt.data: *n_yield_data;
							strbuf_append(sb, "__r = ");
							match (yd.expr) {
							case let expr_node: *node =>
								emit_node(ctx, expr_node);
							case null =>
								if (result_is_str) {
									strbuf_append(sb, "(hare_str){0}");
								} else {
									strbuf_append(sb, "0");
								};
							};
							strbuf_append(sb, ";");
						} else {
							emit_node(ctx, stmt);
							strbuf_append(sb, ";");
						};
						strbuf_append(sb, "\n");
					};
				} else if (body.kind == node_kind::N_YIELD) {
					let yd = body.data: *n_yield_data;
					strbuf_append(sb, "        __r = ");
					match (yd.expr) {
					case let expr_node: *node =>
						emit_node(ctx, expr_node);
					case null =>
						if (result_is_str) {
							strbuf_append(sb, "(hare_str){0}");
						} else {
							strbuf_append(sb, "0");
						};
					};
					strbuf_append(sb, ";\n");
				} else {
					strbuf_append(sb, "        __r = ");
					emit_node(ctx, body);
					strbuf_append(sb, ";\n");
				};
				strbuf_append(sb, "    }\n");
			};

			if (ctx.result_used) {
				strbuf_append(sb, "    __r;\n");
			} else {
				strbuf_append(sb, "    (void)0;\n");
			};
			strbuf_append(sb, "})");
			return;
		};

		// Regular switch expression generates a compound expression
		// First, determine result type by checking case bodies
		let result_is_str = false;
		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_case_data;
			let body: *node = cd.body;
			// Check body for string result
			if (body.kind == node_kind::N_STR) {
				result_is_str = true;
				break;
			};
			if (body.kind == node_kind::N_BLOCK) {
				let bd = body.data: *n_block_data;
				for (let j = 0z; j < bd.nstmts; j += 1) {
					let stmt: *node = bd.stmts[j];
					if (stmt.kind == node_kind::N_YIELD) {
						let yd = stmt.data: *n_yield_data;
						match (yd.expr) {
						case let expr_node: *node =>
							if (expr_node.kind == node_kind::N_STR) {
								result_is_str = true;
								break;
							};
						case null => void;
						};
					};
				};
				if (result_is_str) {
					break;
				};
			} else if (body.kind == node_kind::N_YIELD) {
				let yd = body.data: *n_yield_data;
				match (yd.expr) {
				case let expr_node: *node =>
					if (expr_node.kind == node_kind::N_STR) {
						result_is_str = true;
						break;
					};
				case null => void;
				};
			};
		};

		strbuf_append(sb, "({\n");
		strbuf_append(sb, "    __auto_type __s = (");
		emit_node(ctx, d.expr);
		strbuf_append(sb, ");\n");
		let switch_emitted_type = false;
		if (ctx.in_return_expr) {
			match (ctx.ret_type) {
			case let ret_t: *node =>
				if (!is_void_type_node(ctx, ret_t)) {
					strbuf_append(sb, "    ");
					emit_type(ctx, ret_t);
					strbuf_append(sb, " __r = {0};\n");
					switch_emitted_type = true;
				};
			case null => void;
			};
		};
		if (!switch_emitted_type) {
			if (result_is_str) {
				strbuf_append(sb, "    hare_str __r = (hare_str){0};\n");
			} else {
				strbuf_append(sb, "    intptr_t __r = 0;\n");
			};
		};
		strbuf_append(sb, "    switch (__s) {\n");

		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_case_data;

			if (cd.nvalues == 0) {
				// Default case
				strbuf_append(sb, "    default: {\n");
			} else {
				// Regular case(s)
				for (let j = 0z; j < cd.nvalues; j += 1) {
					strbuf_append(sb, "    case ");
					emit_node(ctx, cd.values[j]);
					strbuf_append(sb, ":");
					if (j + 1 < cd.nvalues) {
						strbuf_append(sb, "\n");
					};
				};
				strbuf_append(sb, " {\n");
			};

			// Emit body - check for yield or block
			let body: *node = cd.body;
			if (body.kind == node_kind::N_BLOCK) {
				let bd = body.data: *n_block_data;
				for (let j = 0z; j < bd.nstmts; j += 1) {
					let stmt: *node = bd.stmts[j];
					strbuf_append(sb, "        ");
					// Handle yield specially
					if (stmt.kind == node_kind::N_YIELD) {
						let yd = stmt.data: *n_yield_data;
						strbuf_append(sb, "__r = ");
						match (yd.expr) {
						case let expr_node: *node =>
							emit_node(ctx, expr_node);
						case null =>
							if (result_is_str) {
								strbuf_append(sb, "(hare_str){0}");
							} else {
								strbuf_append(sb, "0");
							};
						};
						strbuf_append(sb, ";");
					} else {
						emit_node(ctx, stmt);
						strbuf_append(sb, ";");
					};
					strbuf_append(sb, "\n");
				};
			} else if (body.kind == node_kind::N_YIELD) {
				// Direct yield
				let yd = body.data: *n_yield_data;
				strbuf_append(sb, "        __r = ");
				match (yd.expr) {
				case let expr_node: *node =>
					emit_node(ctx, expr_node);
				case null =>
					if (result_is_str) {
						strbuf_append(sb, "(hare_str){0}");
					} else {
						strbuf_append(sb, "0");
					};
				};
				strbuf_append(sb, ";\n");
			} else if (body.kind == node_kind::N_RET) {
				// Direct return statement - emit without __r assignment
				strbuf_append(sb, "        ");
				emit_stmt(ctx, body);
			} else if (body.kind == node_kind::N_EXPR) {
				// Check if N_EXPR wraps a statement (return, assignment)
				let ed = body.data: *n_ret_data;
				match (ed.expr) {
				case let inner: *node =>
					if (inner.kind == node_kind::N_RET ||
					    inner.kind == node_kind::N_ASGN) {
						// Statement - emit directly without __r
						strbuf_append(sb, "        ");
						emit_stmt(ctx, body);
					} else {
						// Expression - assign to __r
						strbuf_append(sb, "        __r = ");
						emit_node(ctx, inner);
						strbuf_append(sb, ";\n");
					};
				case null =>
					// No expression - just emit empty block
					void;
				};
			} else {
				strbuf_append(sb, "        __r = ");
				emit_node(ctx, body);
				strbuf_append(sb, ";\n");
			};
			strbuf_append(sb, "    } break;\n");
		};

		strbuf_append(sb, "    }\n");
		if (ctx.result_used) {
			strbuf_append(sb, "    __r;\n");
		} else {
			strbuf_append(sb, "    (void)0;\n");
		};
		strbuf_append(sb, "})");
		return;
	};

	// If expression (used as value, emits ternary)
	if (k == node_kind::N_IF) {
		let d = n.data: *n_if_data;
		let sb = ctx.output;
		strbuf_append(sb, "((");
		emit_node(ctx, d.cond);
		strbuf_append(sb, ") ? (");
		emit_node(ctx, d.then_branch);
		strbuf_append(sb, ") : (");
		match (d.else_branch) {
		case let else_node: *node =>
			emit_node(ctx, else_node);
		case null =>
			strbuf_append(sb, "0");
		};
		strbuf_append(sb, "))");
		return;
	};

	// Default: emit comment
	strbuf_append(ctx.output, "/* unhandled */");
};

// Helper to emit body of a nullable match case
fn emit_nullable_case_body(ctx: *transform_ctx, body: *node, sb: *strbuf) void = {
	if (body.kind == node_kind::N_BLOCK) {
		let bd = body.data: *n_block_data;
		for (let j = 0z; j < bd.nstmts; j += 1) {
			let stmt: *node = bd.stmts[j];
			strbuf_append(sb, "        ");
			if (stmt.kind == node_kind::N_YIELD) {
				let yd = stmt.data: *n_yield_data;
				strbuf_append(sb, "__r = ");
				match (yd.expr) {
				case let expr_node: *node =>
					emit_node(ctx, expr_node);
				case null =>
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, ";");
			} else if (stmt.kind == node_kind::N_RET) {
				// Handle return inside match case
				emit_stmt(ctx, stmt);
			} else {
				// Use emit_stmt for statements like N_LET, N_FOR, etc.
				emit_stmt(ctx, stmt);
			};
			strbuf_append(sb, "\n");
		};
	} else if (body.kind == node_kind::N_YIELD) {
		let yd = body.data: *n_yield_data;
		strbuf_append(sb, "        __r = ");
		match (yd.expr) {
		case let expr_node: *node =>
			emit_node(ctx, expr_node);
		case null =>
			strbuf_append(sb, "0");
		};
		strbuf_append(sb, ";\n");
	} else if (body.kind == node_kind::N_RET) {
		// Handle return as the body
		strbuf_append(sb, "        ");
		emit_stmt(ctx, body);
		strbuf_append(sb, "\n");
	} else {
		let is_void_expr = is_void_result(body);
		if (is_void_expr) {
			strbuf_append(sb, "        ");
			emit_node(ctx, body);
			strbuf_append(sb, ";\n");
		} else {
			strbuf_append(sb, "        __r = ");
			emit_node(ctx, body);
			strbuf_append(sb, ";\n");
		};
	};
};

// Emit binary operator
fn emit_binop(sb: *strbuf, op: token_kind) void = {
	if (op == token_kind::PLUS) { strbuf_append(sb, "+"); return; };
	if (op == token_kind::MINUS) { strbuf_append(sb, "-"); return; };
	if (op == token_kind::STAR) { strbuf_append(sb, "*"); return; };
	if (op == token_kind::SLASH) { strbuf_append(sb, "/"); return; };
	if (op == token_kind::PERCENT) { strbuf_append(sb, "%"); return; };
	if (op == token_kind::AMP) { strbuf_append(sb, "&"); return; };
	if (op == token_kind::PIPE) { strbuf_append(sb, "|"); return; };
	if (op == token_kind::CARET) { strbuf_append(sb, "^"); return; };
	if (op == token_kind::EQEQ) { strbuf_append(sb, "=="); return; };
	if (op == token_kind::NEQ) { strbuf_append(sb, "!="); return; };
	if (op == token_kind::LT) { strbuf_append(sb, "<"); return; };
	if (op == token_kind::GT) { strbuf_append(sb, ">"); return; };
	if (op == token_kind::LE) { strbuf_append(sb, "<="); return; };
	if (op == token_kind::GE) { strbuf_append(sb, ">="); return; };
	if (op == token_kind::LAND) { strbuf_append(sb, "&&"); return; };
	if (op == token_kind::LOR) { strbuf_append(sb, "||"); return; };
	if (op == token_kind::XOR) { strbuf_append(sb, "!="); return; };  // Boolean XOR
	if (op == token_kind::LSHIFT) { strbuf_append(sb, "<<"); return; };
	if (op == token_kind::RSHIFT) { strbuf_append(sb, ">>"); return; };
	strbuf_append(sb, "?op?");
};

// Emit unary operator
fn emit_unop(sb: *strbuf, op: token_kind) void = {
	if (op == token_kind::MINUS) { strbuf_append(sb, "-"); return; };
	if (op == token_kind::BANG) { strbuf_append(sb, "!"); return; };
	if (op == token_kind::TILDE) { strbuf_append(sb, "~"); return; };
	if (op == token_kind::STAR) { strbuf_append(sb, "*"); return; };
	if (op == token_kind::AMP) { strbuf_append(sb, "&"); return; };
	strbuf_append(sb, "?op?");
};
