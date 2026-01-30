// rules.ha - Hare to C transformation rules
use rt;
use strings;

def STRINGS_DUP_TYPE_NAME: str = "__hare_strings_dup_result";
def STRINGS_DUP_TYPE_NAME_LEN: size = 25;

// Helper: check if name matches a key string
fn type_is(ptr: *u8, plen: size, key: str) bool = {
	return plen == len(key) && bytes_eq(ptr, (strings::toutf8(key): *[*]u8): *u8, plen);
};

// Check if a name is the built-in done type.
fn is_done_name(ptr: *u8, plen: size) bool = {
	return type_is(ptr, plen, "done");
};

// Emit identifier with namespace alias expansion (t_foo -> module_path_foo)
fn emit_alias_expanded_name(ctx: *transform_ctx, ptr: *u8, plen: size) bool = {
	let name_bytes = ptr: *[*]u8;
	let underscore_pos: size = 0;
	for (underscore_pos < plen && name_bytes[underscore_pos] != '_') {
		underscore_pos += 1;
	};
	if (underscore_pos < plen) {
		let path_len: size = 0;
		let path_ptr = find_alias_path(ctx, ptr, underscore_pos, &path_len);
		match (path_ptr) {
		case let pp: *u8 =>
			let path_bytes = pp: *[*]u8;
			for (let i = 0z; i < path_len; i += 1) {
				if (path_bytes[i] == ':' && i + 1 < path_len && path_bytes[i + 1] == ':') {
					strbuf_append_byte(ctx.output, '_');
					i += 1;
				} else {
					strbuf_append_byte(ctx.output, path_bytes[i]);
				};
			};
			// Emit rest: _suffix (from underscore_pos onward)
			strbuf_append_bytes(ctx.output,
				(ptr: uintptr + underscore_pos: uintptr): *u8,
				plen - underscore_pos);
			return true;
		case null => void;
		};
	};
	return false;
};

// Check if a type name is a built-in primitive type
fn is_primitive_type(ptr: *u8, plen: size) bool = {
	return type_is(ptr, plen, "int") ||
	       type_is(ptr, plen, "uint") ||
	       type_is(ptr, plen, "void") ||
	       type_is(ptr, plen, "done") ||
	       type_is(ptr, plen, "bool") ||
	       type_is(ptr, plen, "size") ||
	       type_is(ptr, plen, "i8") ||
	       type_is(ptr, plen, "i16") ||
	       type_is(ptr, plen, "i32") ||
	       type_is(ptr, plen, "i64") ||
	       type_is(ptr, plen, "u8") ||
	       type_is(ptr, plen, "u16") ||
	       type_is(ptr, plen, "u32") ||
	       type_is(ptr, plen, "u64") ||
	       type_is(ptr, plen, "f32") ||
	       type_is(ptr, plen, "f64") ||
	       type_is(ptr, plen, "str") ||
	       type_is(ptr, plen, "rune") ||
	       type_is(ptr, plen, "uintptr") ||
	       type_is(ptr, plen, "intptr") ||
	       type_is(ptr, plen, "opaque") ||
	       type_is(ptr, plen, "never");
};

// Primitive types that can be safely cast in return expressions.
fn is_scalar_prim_name(ptr: *u8, plen: size) bool = {
	return type_is(ptr, plen, "int") ||
	       type_is(ptr, plen, "uint") ||
	       type_is(ptr, plen, "size") ||
	       type_is(ptr, plen, "i8") ||
	       type_is(ptr, plen, "i16") ||
	       type_is(ptr, plen, "i32") ||
	       type_is(ptr, plen, "i64") ||
	       type_is(ptr, plen, "u8") ||
	       type_is(ptr, plen, "u16") ||
	       type_is(ptr, plen, "u32") ||
	       type_is(ptr, plen, "u64") ||
	       type_is(ptr, plen, "f32") ||
	       type_is(ptr, plen, "f64") ||
	       type_is(ptr, plen, "bool") ||
	       type_is(ptr, plen, "rune") ||
	       type_is(ptr, plen, "uintptr") ||
	       type_is(ptr, plen, "intptr");
};

// Integer-like primitive names (for tagged union int literal selection).
fn is_int_like_name(ptr: *u8, plen: size) bool = {
	return type_is(ptr, plen, "int") ||
	       type_is(ptr, plen, "uint") ||
	       type_is(ptr, plen, "size") ||
	       type_is(ptr, plen, "i8") ||
	       type_is(ptr, plen, "i16") ||
	       type_is(ptr, plen, "i32") ||
	       type_is(ptr, plen, "i64") ||
	       type_is(ptr, plen, "u8") ||
	       type_is(ptr, plen, "u16") ||
	       type_is(ptr, plen, "u32") ||
	       type_is(ptr, plen, "u64") ||
	       type_is(ptr, plen, "uintptr") ||
	       type_is(ptr, plen, "intptr");
};

fn is_strings_dup_call(ctx: *transform_ctx, n: *node) bool = {
	if (n.kind != node_kind::N_CALL) return false;
	let cd = n.data: *n_call_data;
	if ((*(cd.func)).kind != node_kind::N_ID) return false;
	let fn_id = (*(cd.func)).data: *n_id_data;
	return name_matches_module_member(ctx, fn_id.ptr, fn_id.length, "strings", "dup");
};

fn is_tagged_union_type(ctx: *transform_ctx, typ: *node) bool = {
	if (typ.kind == node_kind::N_TTAGGED) return true;
	if (typ.kind == node_kind::N_TPRIM || typ.kind == node_kind::N_TALIAS) {
		let td = typ.data: *n_id_data;
		if (!is_primitive_type(td.ptr, td.length)) {
			let resolved = find_typedef(ctx, td.ptr, td.length);
			if (resolved != null && (*unwrap(resolved)).kind == node_kind::N_TTAGGED) {
				return true;
			};
		};
	};
	return false;
};

// Build a primitive type node from a name.
fn make_prim_type(ctx: *transform_ctx, name: str) *node = {
	let n = node_new(ctx.arena, node_kind::N_TPRIM, size(n_id_data), 0, 0);
	let d = n.data: *n_id_data;
	let bytes = strings::toutf8(name);
	d.ptr = bytes: *[*]u8: *u8;
	d.length = len(name);
	return n;
};

// Build the tagged union type for strings_dup (str | !void).
fn make_strings_dup_result_type(ctx: *transform_ctx) *node = {
	let t_str = make_prim_type(ctx, "str");
	let t_void = make_prim_type(ctx, "void");
	let t_err = node_new(ctx.arena, node_kind::N_TERR, size(n_terr_data), 0, 0);
	let ed = t_err.data: *n_terr_data;
	ed.inner = t_void;

	let tagged = node_new(ctx.arena, node_kind::N_TTAGGED, size(n_ttagged_data), 0, 0);
	let td = tagged.data: *n_ttagged_data;
	td.nvariants = 2;
	td.spread_mask = 0;
	let arr = node_array(ctx.arena, 2);
	arr[0] = t_str;
	arr[1] = t_err;
	td.variants = arr;
	return tagged;
};

// Ensure the strings_dup result type is registered for typedef lookup and tagged-union handling.
fn ensure_strings_dup_type(ctx: *transform_ctx) void = {
	let name_ptr = strings::toutf8(STRINGS_DUP_TYPE_NAME): *[*]u8: *u8;
	let name_len = STRINGS_DUP_TYPE_NAME_LEN;
	if (find_typedef(ctx, name_ptr, name_len) != null) {
		return;
	};
	let tagged = make_strings_dup_result_type(ctx);
	add_typedef(ctx, name_ptr, name_len, tagged);
	add_tracked_var(&ctx.tagged_types, name_ptr, name_len);
};

// Register strings_dup return type for inference.
fn register_strings_dup_fn(ctx: *transform_ctx) void = {
	ensure_strings_dup_type(ctx);
	let fn_ptr = strings::toutf8("strings_dup"): *[*]u8: *u8;
	let fn_len = len("strings_dup");
	let ret_type = make_prim_type(ctx, STRINGS_DUP_TYPE_NAME);
	add_fn_ret_type(ctx, fn_ptr, fn_len, ret_type);
};

// Check if type name is an invalid/non-existent type (like C's char)
fn is_invalid_type_name(ptr: *u8, plen: size) bool = {
	// 'char' doesn't exist in Hare - use u8 or rune instead
	return type_is(ptr, plen, "char") ||
	       type_is(ptr, plen, "short") ||
	       type_is(ptr, plen, "long") ||
	       type_is(ptr, plen, "double") ||
	       type_is(ptr, plen, "float");
};

// Check if a node is the null literal
export fn is_null_lit(n: nullable *node) bool = {
	match (n) {
	case let node: *node =>
		return node.kind == node_kind::N_NULL;
	case null =>
		return false;
	};
};

// Check if a type node is a nullable pointer type
export fn is_nullable_ptr_type(typ: nullable *node) bool = {
	match (typ) {
	case let t: *node =>
		if (t.kind == node_kind::N_TPTR) {
			let d = t.data: *n_tptr_data;
			return d.is_nullable;
		};
		return false;
	case null =>
		return false;
	};
};

// Check if a type node is a non-nullable pointer type
export fn is_nonnull_ptr_type(typ: nullable *node) bool = {
	match (typ) {
	case let t: *node =>
		if (t.kind == node_kind::N_TPTR) {
			let d = t.data: *n_tptr_data;
			return !d.is_nullable;
		};
		return false;
	case null =>
		return false;
	};
};

// Check if a type node is the str primitive type
fn is_str_type(typ: nullable *node) bool = {
	match (typ) {
	case let t: *node =>
		if (t.kind == node_kind::N_TPRIM) {
			let d = t.data: *n_id_data;
			return type_is(d.ptr, d.length, "str");
		};
		return false;
	case null =>
		return false;
	};
};

// Check if a type node is a slice type []T
fn is_slice_type(typ: nullable *node) bool = {
	match (typ) {
	case let t: *node =>
		return t.kind == node_kind::N_TSLICE;
	case null =>
		return false;
	};
};

// Track variables that are pointers to unbounded arrays (*[*]T)
fn track_ptr_uarr_var(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: nullable *node) void = {
	match (typ) {
	case let t: *node =>
		if (t.kind == node_kind::N_TPTR) {
			let pd = t.data: *n_tptr_data;
			if ((*(pd.inner)).kind == node_kind::N_TARR) {
				let ad = (*(pd.inner)).data: *n_tarr_data;
				if (ad.length == null) {
					if (!is_tracked_var(&ctx.ptr_uarr_vars, name_ptr, name_len)) {
						add_tracked_var(&ctx.ptr_uarr_vars, name_ptr, name_len);
					};
				};
			};
		};
	case null =>
		void;
	};
};

// Check nonnull pointer assignment safety - emits error if invalid
export fn check_nonnull_assignment(ctx: *transform_ctx, target_ty: nullable *node, val: nullable *node, name_ptr: nullable *u8, name_len: size) void = {
	// Only check if target is a non-nullable pointer
	if (!is_nonnull_ptr_type(target_ty)) {
		return;
	};

	// Check for null literal assignment
	if (is_null_lit(val)) {
		match (name_ptr) {
		case let np: *u8 =>
			emit_error_with_name_at_optional(ctx, val, "cannot assign null to non-nullable pointer ", np, name_len, "");
		case null =>
			emit_error_at_optional(ctx, val, "cannot assign null to non-nullable pointer");
		};
		return;
	};

	// Check for nullable pointer assignment
	match (val) {
	case let v: *node =>
		let val_type = infer_expr_type(ctx, v);
			if (is_nullable_ptr_type(val_type)) {
				match (name_ptr) {
				case let np: *u8 =>
					emit_error_with_name_at_optional(ctx, val, "cannot assign nullable pointer to non-nullable ", np, name_len, "");
				case null =>
					emit_error_at_optional(ctx, val, "cannot assign nullable pointer to non-nullable");
				};
			};
		case null => void;
		};
};

// C type mapping for primitive types
fn emit_prim_type(ctx: *transform_ctx, name_ptr: *u8, name_len: size) void = {
	let sb = ctx.output;
	if (type_is(name_ptr, name_len, "int")) { strbuf_append(sb, "intptr_t"); return; };
	if (type_is(name_ptr, name_len, "uint")) { strbuf_append(sb, "uintptr_t"); return; };
	if (type_is(name_ptr, name_len, "void")) { strbuf_append(sb, "void"); return; };
	if (type_is(name_ptr, name_len, "done")) { strbuf_append(sb, "int"); return; };
	if (type_is(name_ptr, name_len, "bool")) { strbuf_append(sb, "_Bool"); return; };
	if (type_is(name_ptr, name_len, "size")) { strbuf_append(sb, "size_t"); return; };
	if (type_is(name_ptr, name_len, "i8")) { strbuf_append(sb, "int8_t"); return; };
	if (type_is(name_ptr, name_len, "i16")) { strbuf_append(sb, "int16_t"); return; };
	if (type_is(name_ptr, name_len, "i32")) { strbuf_append(sb, "int32_t"); return; };
	if (type_is(name_ptr, name_len, "i64")) { strbuf_append(sb, "int64_t"); return; };
	if (type_is(name_ptr, name_len, "u8")) { strbuf_append(sb, "uint8_t"); return; };
	if (type_is(name_ptr, name_len, "u16")) { strbuf_append(sb, "uint16_t"); return; };
	if (type_is(name_ptr, name_len, "u32")) { strbuf_append(sb, "uint32_t"); return; };
	if (type_is(name_ptr, name_len, "u64")) { strbuf_append(sb, "uint64_t"); return; };
	if (type_is(name_ptr, name_len, "f32")) { strbuf_append(sb, "float"); return; };
	if (type_is(name_ptr, name_len, "f64")) { strbuf_append(sb, "double"); return; };
	if (type_is(name_ptr, name_len, "str")) { strbuf_append(sb, "hare_str"); return; };
	if (type_is(name_ptr, name_len, "rune")) { strbuf_append(sb, "uint32_t"); return; };
	if (type_is(name_ptr, name_len, "char")) { strbuf_append(sb, "char"); return; };
	if (type_is(name_ptr, name_len, "uintptr")) { strbuf_append(sb, "uintptr_t"); return; };
	if (type_is(name_ptr, name_len, "opaque")) { strbuf_append(sb, "void"); return; };
	// Unknown - emit as-is (with namespace alias expansion)
	if (emit_alias_expanded_name(ctx, name_ptr, name_len)) {
		return;
	};
	strbuf_append_bytes(sb, name_ptr, name_len);
};

// Emit a type node as C type
export fn emit_type(ctx: *transform_ctx, n_nullable: nullable *node) void = {
	if (n_nullable == null) {
		strbuf_append(ctx.output, "void");
		return;
	};
	let n = unwrap(n_nullable);
	let k = n.kind;

	// Primitive type
	if (k == node_kind::N_TPRIM) {
		let d = n.data: *n_id_data;
		// Check for invalid type names (like C's 'char')
		if (is_invalid_type_name(d.ptr, d.length)) {
			emit_error_at_node(ctx, n, "unresolvable identifier (invalid type name)");
		};
		emit_prim_type(ctx, d.ptr, d.length);
		return;
	};

	// Pointer type
	if (k == node_kind::N_TPTR) {
		let d = n.data: *n_tptr_data;
		let inner: *node = d.inner;
		// Check for *void - should use *opaque instead in Hare
		if (inner.kind == node_kind::N_TPRIM) {
			let pd = inner.data: *n_id_data;
			if (streq(pd.ptr, pd.length, "void")) {
				emit_error_at_node(ctx, inner, "cannot have pointer to zero-sized type (use *opaque instead)");
			};
		};
		// *[*]T (pointer to unbounded array) is the same as [*]T in C (just T*)
		if (inner.kind == node_kind::N_TARR) {
			let ad = inner.data: *n_tarr_data;
			if (ad.length == null) {
				// Unbounded - just emit T*, not T**
				emit_type(ctx, ad.elem);
				strbuf_append(ctx.output, "*");
				return;
			};
		};
		// *fn(params) ret -> ret_type (*)(param_types)
		if (inner.kind == node_kind::N_TFUNC) {
			let fd = inner.data: *n_tfunc_data;
			emit_type(ctx, fd.ret_type);
			strbuf_append(ctx.output, " (*)(");
			if (fd.nparams == 0) {
				strbuf_append(ctx.output, "void");
			} else {
				for (let i = 0z; i < fd.nparams; i += 1) {
					if (i > 0) {
						strbuf_append(ctx.output, ", ");
					};
					let param = fd.params[i];
					let pd = param.data: *n_param_data;
					// Check that function type parameters have names in Hare
					if (pd.name_len == 0) {
						emit_error_at_node(ctx, param, "function type parameters must have names (use '_' for unnamed, e.g., *fn(_: int) int)");
					};
					emit_type(ctx, pd.typ);
				};
			};
			strbuf_append(ctx.output, ")");
			return;
		};
		emit_type(ctx, inner);
		strbuf_append(ctx.output, "*");
		return;
	};

	// Slice type - becomes hare_slice_<elem>
	if (k == node_kind::N_TSLICE) {
		let d = n.data: *n_tarr_data;
		let elem: *node = d.elem;
		// Special handling for slice of arrays: [][N]T
		// Use typedef name hare_slice_arr{size}_{elemtype}
		if (elem.kind == node_kind::N_TARR) {
			let ad = elem.data: *n_tarr_data;
			if (ad.length != null) {
				// Get array size
				let arr_size: i64 = 0;
				let len_node = unwrap(ad.length);
				if (len_node.kind == node_kind::N_INT) {
					let id = len_node.data: *n_int_data;
					arr_size = id.val;
				};
				strbuf_append(ctx.output, "hare_slice_arr");
				strbuf_append_int(ctx.output, arr_size);
				strbuf_append(ctx.output, "_");
				emit_type(ctx, ad.elem);
				return;
			};
		};
		strbuf_append(ctx.output, "hare_slice_");
		emit_type(ctx, elem);
		return;
	};

	// Array type (including unbounded [*]T)
	if (k == node_kind::N_TARR) {
		let d = n.data: *n_tarr_data;
		if (d.length == null) {
			// Unbounded array [*]T -> T*
			emit_type(ctx, d.elem);
			strbuf_append(ctx.output, "*");
		} else {
			// Fixed array [N]T -> T[N] (for sizeof and other contexts)
			emit_type(ctx, d.elem);
			strbuf_append(ctx.output, "[");
			emit_node(ctx, d.length);
			strbuf_append(ctx.output, "]");
		};
		return;
	};

	// Type alias (named type)
	if (k == node_kind::N_TALIAS) {
		let d = n.data: *n_id_data;
		strbuf_append_bytes(ctx.output, d.ptr, d.length);
		return;
	};

	// Error type !T - emit as the inner type for now
	// (error semantics are handled at tagged union level)
	if (k == node_kind::N_TERR) {
		let d = n.data: *n_terr_data;
		// For simple error types like !void, emit a word-sized type
		let inner: *node = d.inner;
		if (is_void_type(ctx, inner)) {
			strbuf_append(ctx.output, "intptr_t");
			return;
		};
		// For other error types, just emit the inner type
		emit_type(ctx, inner);
		return;
	};

	// nomem error type - emit as a marker struct
	if (k == node_kind::N_TNOMEM) {
		strbuf_append(ctx.output, "struct{char __nomem;}");
		return;
	};

	// Function type (bare) - emit as function pointer type
	// fn(params) ret -> ret_type (*)(param_types)
	if (k == node_kind::N_TFUNC) {
		let fd = n.data: *n_tfunc_data;
		emit_type(ctx, fd.ret_type);
		strbuf_append(ctx.output, " (*)(");
		if (fd.nparams == 0) {
			strbuf_append(ctx.output, "void");
		} else {
			for (let i = 0z; i < fd.nparams; i += 1) {
				if (i > 0) {
					strbuf_append(ctx.output, ", ");
				};
				let param = fd.params[i];
				let pd = param.data: *n_param_data;
				// Check that function type parameters have names in Hare
				if (pd.name_len == 0) {
					emit_error_at_node(ctx, param, "function type parameters must have names (use '_' for unnamed, e.g., *fn(_: int) int)");
				};
				emit_type(ctx, pd.typ);
			};
		};
		strbuf_append(ctx.output, ")");
		return;
	};

	// Tuple type - emit typedef name __hare_tuple_N
	if (k == node_kind::N_TTUPLE) {
		// Find matching tuple type by structure
		let found: i64 = -1;
		for (let i = 0z; i < ctx.tuple_count; i += 1) {
			if (tuple_tuple_types_equal(ctx.tuple_types[i], n)) {
				found = i: i64;
				break;
			};
		};
		if (found < 0) {
			// Register new tuple type
			if (ctx.tuple_count < 32) {
				found = ctx.tuple_count: i64;
				ctx.tuple_types[ctx.tuple_count] = n;
				ctx.tuple_count += 1;
			};
		};
		strbuf_append(ctx.output, "__hare_tuple_");
		strbuf_append_int(ctx.output, found);
		return;
	};

	// Struct type
	if (k == node_kind::N_TSTRUCT) {
		let d = n.data: *n_tstruct_data;
		strbuf_append(ctx.output, "struct { ");
		for (let i = 0z; i < d.nfields; i += 1) {
			let field: *node = d.fields[i];
			let fd = field.data: *n_param_data;
			// Use emit_param_decl to handle array types correctly
			emit_param_decl(ctx, fd.typ, fd.name_ptr, fd.name_len);
			strbuf_append(ctx.output, "; ");
		};
		strbuf_append(ctx.output, "}");
		return;
	};

	// Union type
	if (k == node_kind::N_TUNION) {
		let d = n.data: *n_tstruct_data;  // Reuses struct data layout
		strbuf_append(ctx.output, "union { ");
		for (let i = 0z; i < d.nfields; i += 1) {
			let field: *node = d.fields[i];
			let fd = field.data: *n_param_data;
			emit_param_decl(ctx, fd.typ, fd.name_ptr, fd.name_len);
			strbuf_append(ctx.output, "; ");
		};
		strbuf_append(ctx.output, "}");
		return;
	};

	// Inline tagged union type - emit as struct { uint32_t tag; union { ... } value; }
	if (k == node_kind::N_TTAGGED) {
		let d = n.data: *n_ttagged_data;
		strbuf_append(ctx.output, "struct { uint32_t tag; union { ");
		for (let i = 0z; i < d.nvariants; i += 1) {
			let variant = d.variants[i];
			if (is_void_type(ctx, variant)) {
				continue;
			};
			emit_type(ctx, variant);
			strbuf_append(ctx.output, " _");
			emit_type_tag(ctx.output, variant);
			strbuf_append(ctx.output, "; ");
		};
		strbuf_append(ctx.output, "} value; }");
		return;
	};

	// Default
	strbuf_append(ctx.output, "void");
};

// Emit inferred type for an expression (used for let without explicit type)
// Returns true if a type was emitted, false if __auto_type should be used
fn emit_inferred_type(ctx: *transform_ctx, n: *node) bool = {
	let sb = ctx.output;
	let k = n.kind;

	// Integer literal
	if (k == node_kind::N_INT) {
		let d = n.data: *n_int_data;
		if (d.suffix == 'z') {
			strbuf_append(sb, "size_t");
		} else if (d.suffix == 'i') {
			strbuf_append(sb, "intptr_t");
		} else if (d.suffix == 'u') {
			strbuf_append(sb, "uintptr_t");
		} else {
			// Default to intptr_t for unsuffixed int literals
			strbuf_append(sb, "intptr_t");
		};
		return true;
	};

	// Float literal
	if (k == node_kind::N_FLOAT) {
		strbuf_append(sb, "double");
		return true;
	};

	// Bool literal
	if (k == node_kind::N_BOOL) {
		strbuf_append(sb, "_Bool");
		return true;
	};

	// String literal
	if (k == node_kind::N_STR) {
		strbuf_append(sb, "hare_str");
		return true;
	};

	// Struct literal - use the type name from the literal
	if (k == node_kind::N_STRUCT_LIT) {
		let d = n.data: *n_struct_lit_data;
		if (d.type_name_len > 0) {
			match (d.type_name_ptr) {
			case let ptr: *u8 =>
				strbuf_append_bytes(sb, ptr, d.type_name_len);
				return true;
			case null =>
				void;
			};
		};
	};

	// Function call - look up the return type
	if (k == node_kind::N_CALL) {
		let cd = n.data: *n_call_data;
		if ((*(cd.func)).kind == node_kind::N_ID) {
			let id = (*(cd.func)).data: *n_id_data;
			let ret = find_fn_ret_type(ctx, id.ptr, id.length);
			if (ret != null) {
				// For inline tagged union return types, use the function's typedef name
				if ((*unwrap(ret)).kind == node_kind::N_TTAGGED) {
					strbuf_append(sb, "__ret_");
					strbuf_append_bytes(sb, id.ptr, id.length);
					strbuf_append(sb, "_t");
					return true;
				};
				// For pointer-to-array types, use __auto_type - the special syntax
				// T (*name)[N] can't be emitted by emit_type alone
				if ((*unwrap(ret)).kind == node_kind::N_TPTR) {
					let pd = (*unwrap(ret)).data: *n_tptr_data;
					if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TARR) {
						return false;  // Let caller use __auto_type
					};
				};
				emit_type(ctx, unwrap(ret));
				return true;
			};
		};
	};

	// Identifier - look up in var_type tracker
	if (k == node_kind::N_ID) {
		let id = n.data: *n_id_data;
		let id_bytes = id.ptr: *[*]u8;
		let typ = find_var_type(ctx, id.ptr, id.length);
		if (typ != null) {
			emit_type(ctx, unwrap(typ));
			return true;
		};
		// Enum constant: EnumName_MEMBER -> infer EnumName
		for (let i = 0z; i < ctx.enum_types.count; i += 1) {
			let enum_ptr = ctx.enum_types.names[i];
			let enum_bytes = enum_ptr: *[*]u8;
			let enum_len = ctx.enum_types.lengths[i];
			if (id.length > enum_len + 1 && id_bytes[enum_len] == '_') {
				let matched = true;
				for (let j = 0z; j < enum_len; j += 1) {
					if (id_bytes[j] != enum_bytes[j]) {
						matched = false;
					};
				};
				if (matched) {
					strbuf_append_bytes(sb, enum_ptr, enum_len);
					return true;
				};
			};
		};
	};

	// Address-of expression - emit pointer to operand type
	if (k == node_kind::N_UN) {
		let d = n.data: *n_un_data;
		if (d.op == token_kind::AMP) {
			// Special case: &(expr: *T) is reordered to (T*)(&expr) by codegen
			// So the result type is T, not T*
			let operand: *node = d.operand;
			if (operand.kind == node_kind::N_CAST) {
				let cd = operand.data: *n_cast_data;
				let target: *node = cd.target;
				if (target.kind == node_kind::N_TPTR) {
					// Emit the cast's target type directly (no extra *)
					emit_type(ctx, target);
					return true;
				};
			};
			// Normal case: try to infer operand type and add *
			if (emit_inferred_type(ctx, operand)) {
				strbuf_append(sb, "*");
				return true;
			};
		};
	};

	// Cast expression - use the target type
	if (k == node_kind::N_CAST) {
		let d = n.data: *n_cast_data;
		emit_type(ctx, d.target);
		return true;
	};

	// len() and size() builtins return size_t
	if (k == node_kind::N_LEN) {
		strbuf_append(sb, "size_t");
		return true;
	};

	// Field access on slices - .len and .cap are size_t
	if (k == node_kind::N_FLD) {
		let d = n.data: *n_fld_data;
		// Check if the field is "len" or "cap" - these are size_t on slices
		let field_str = strings::fromutf8_unsafe((d.field_ptr: *[*]u8)[..d.field_len]);
		let is_len = (field_str == "len");
		let is_cap = (field_str == "cap");
		if (is_len || is_cap) {
			strbuf_append(sb, "size_t");
			return true;
		};
	};

	// Binary arithmetic/comparison on size_t values - result is typically size_t
	if (k == node_kind::N_BIN) {
		let d = n.data: *n_bin_data;
		let op = d.op;
		// Check if this is arithmetic or comparison (not logical)
		let is_arith = (op == token_kind::PLUS || op == token_kind::MINUS ||
		                op == token_kind::STAR || op == token_kind::SLASH ||
		                op == token_kind::PERCENT);
		if (is_arith) {
			// Try to infer left operand type - if it's size_t, result is size_t
			let left: *node = d.left;
			if (left.kind == node_kind::N_LEN) {
				// len() is size_t
				strbuf_append(sb, "size_t");
				return true;
			};
			if (left.kind == node_kind::N_FLD) {
				let fd = left.data: *n_fld_data;
				if (type_is(fd.field_ptr, fd.field_len, "len") ||
				    type_is(fd.field_ptr, fd.field_len, "cap")) {
					strbuf_append(sb, "size_t");
					return true;
				};
				let fld_type = infer_expr_type(ctx, left);
				match (fld_type) {
				case let ft: *node =>
					if (ft.kind == node_kind::N_TPRIM) {
						let td = ft.data: *n_id_data;
						if (type_is(td.ptr, td.length, "size")) {
							strbuf_append(sb, "size_t");
							return true;
						};
					};
				case null => void;
				};
			};
			if (left.kind == node_kind::N_ID) {
				// Check if the identifier has a known size_t type
				let id = left.data: *n_id_data;
				let typ = find_var_type(ctx, id.ptr, id.length);
				if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPRIM) {
					let td = (*unwrap(typ)).data: *n_id_data;
					// Check if it's size or size_t
					let type_str = strings::fromutf8_unsafe((td.ptr: *[*]u8)[..td.length]);
					let is_size = (type_str == "size");
					if (is_size) {
						strbuf_append(sb, "size_t");
						return true;
					};
				};
			};
		};
	};

	return false;
};

// Infer element type for an array literal when no explicit type is provided.
fn infer_arr_lit_elem_type(ctx: *transform_ctx, arr: *n_arr_lit_data) nullable *node = {
	if (arr.nelems == 0) {
		return null;
	};
	let elem = arr.elems[0];
	if (elem.kind == node_kind::N_STR) {
		return make_prim_type(ctx, "str");
	};
	if (elem.kind == node_kind::N_BOOL) {
		return make_prim_type(ctx, "bool");
	};
	if (elem.kind == node_kind::N_INT) {
		let d = elem.data: *n_int_data;
		if (d.suffix == 'z') {
			return make_prim_type(ctx, "size");
		} else if (d.suffix == 'u') {
			return make_prim_type(ctx, "uint");
		};
		return make_prim_type(ctx, "int");
	};
	if (elem.kind == node_kind::N_FLOAT) {
		return make_prim_type(ctx, "f64");
	};
	if (elem.kind == node_kind::N_CAST) {
		let cd = elem.data: *n_cast_data;
		return cd.target;
	};
	return infer_expr_type(ctx, elem);
};

// Emit a parameter declaration (handles array types specially)
// In C, array params are declared as "type name[size]" not "type[size] name"
fn emit_param_decl(ctx: *transform_ctx, typ: *node, name_ptr: *u8, name_len: size) void = {
	emit_param_decl_variadic(ctx, typ, name_ptr, name_len, false);
};

// Emit parameter declaration with variadic handling
fn emit_param_decl_variadic(ctx: *transform_ctx, typ: *node, name_ptr: *u8, name_len: size, is_variadic: bool) void = {
	let sb = ctx.output;

	// Variadic parameters become slice types
	if (is_variadic) {
		// Emit slice type for variadic param: T... -> hare_slice_T
		strbuf_append(sb, "hare_slice_");
		emit_type(ctx, typ);
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, name_ptr, name_len);
		return;
	};

	// Special handling for function pointer types: *fn(params) ret -> ret (*name)(params)
	if (typ.kind == node_kind::N_TPTR) {
		let pd = typ.data: *n_tptr_data;
		if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TFUNC) {
			let fd = (*(pd.inner)).data: *n_tfunc_data;
			// Emit: ret_type (*name)(param_types)
			emit_type(ctx, fd.ret_type);
			strbuf_append(sb, " (* ");
			strbuf_append_bytes(sb, name_ptr, name_len);
			strbuf_append(sb, ")(");
			if (fd.nparams == 0) {
				strbuf_append(sb, "void");
			} else {
				for (let i = 0z; i < fd.nparams; i += 1) {
					if (i > 0) {
						strbuf_append(sb, ", ");
					};
					let param = fd.params[i];
					let fpd = param.data: *n_param_data;
					// Check that function type parameters have names in Hare
					if (fpd.name_len == 0) {
						emit_error_at_node(ctx, param, "function type parameters must have names (use '_' for unnamed, e.g., *fn(_: int) int)");
					};
					emit_type(ctx, fpd.typ);
				};
			};
			strbuf_append(sb, ")");
			return;
		};
	};

	// Special handling for array of function pointers: [N]*fn(params) ret -> ret (*name[N])(params)
	if (typ.kind == node_kind::N_TARR) {
		let ad = typ.data: *n_tarr_data;
		if (ad.elem != null && (*(ad.elem)).kind == node_kind::N_TPTR) {
			let pd = (*(ad.elem)).data: *n_tptr_data;
			if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TFUNC) {
				let fd = (*(pd.inner)).data: *n_tfunc_data;
				// Emit: ret_type (*name[N])(param_types)
				emit_type(ctx, fd.ret_type);
				strbuf_append(sb, " (* ");
				strbuf_append_bytes(sb, name_ptr, name_len);
				strbuf_append(sb, "[");
				if (ad.length != null) {
					emit_node(ctx, unwrap(ad.length));
				};
				strbuf_append(sb, "])(");
				if (fd.nparams == 0) {
					strbuf_append(sb, "void");
				} else {
					for (let i = 0z; i < fd.nparams; i += 1) {
						if (i > 0) {
							strbuf_append(sb, ", ");
						};
						let param = fd.params[i];
						let fpd = param.data: *n_param_data;
						emit_type(ctx, fpd.typ);
					};
				};
				strbuf_append(sb, ")");
				return;
			};
		};
	};

	// Special handling for pointer-to-array types: *[N]T -> T (*name)[N]
	// Also handles multi-dimensional: *[M][N]T -> T (*name)[M][N]
	// BUT: *[*]T (pointer to unbounded array) should be T* name (simple pointer)
	if (typ.kind == node_kind::N_TPTR) {
		let pd = typ.data: *n_tptr_data;
		if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TARR) {
			// Check if first dimension is unbounded - if so, emit as simple pointer
			let first_arr = (*(pd.inner)).data: *n_tarr_data;
			if (first_arr.length == null) {
				// *[*]T -> T* name (simple pointer, not array syntax)
				emit_type(ctx, first_arr.elem);
				strbuf_append(sb, "* ");
				strbuf_append_bytes(sb, name_ptr, name_len);
				return;
			};

			// Collect all array dimensions
			let dims: [8]nullable *node = [null...];
			let ndims: size = 0;
			let cur = pd.inner;
			for (ndims < 8 && cur.kind == node_kind::N_TARR) {
				let ad = cur.data: *n_tarr_data;
				dims[ndims] = ad.length;
				ndims += 1;
				cur = ad.elem;
			};

			// Emit: T (*name)[N] or T (*name)[M][N]...
			emit_type(ctx, cur);
			strbuf_append(sb, " (* ");
			strbuf_append_bytes(sb, name_ptr, name_len);
			strbuf_append(sb, ")");

			// Emit all dimensions
			for (let i = 0z; i < ndims; i += 1) {
				strbuf_append(sb, "[");
				if (dims[i] != null) {
					emit_node(ctx, unwrap(dims[i]));
				};
				strbuf_append(sb, "]");
			};
			return;
		};
	};

	// Special handling for array types (including multi-dimensional)
	if (typ.kind == node_kind::N_TARR) {
		// Collect all array dimensions
		let dims: [8]nullable *node = [null...];
		let unbounded: [8]bool = [false...];
		let ndims: size = 0;
		let cur = typ;
		for (ndims < 8 && cur.kind == node_kind::N_TARR) {
			let ad = cur.data: *n_tarr_data;
			dims[ndims] = ad.length;
			unbounded[ndims] = ad.length == null;
			ndims += 1;
			cur = ad.elem;
		};

		// Emit element type (innermost type)
		emit_type(ctx, cur);
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, name_ptr, name_len);

		// Emit all dimensions
		for (let i = 0z; i < ndims; i += 1) {
			strbuf_append(sb, "[");
			if (!unbounded[i] && dims[i] != null) {
				emit_node(ctx, unwrap(dims[i]));
			};
			strbuf_append(sb, "]");
		};
		return;
	};

	// Normal case
	emit_type(ctx, typ);
	// Only emit name if it's not empty (anonymous unions have empty names)
	if (name_len > 0) {
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, name_ptr, name_len);
	};
};

// Determine if function should have static linkage
fn should_be_static(d: *n_fn_data) bool = {
	// Exported functions are public
	if (d.exported) {
		return false;
	};

	// Functions with @symbol attribute are public
	if (d.symbol_len > 0) {
		return false;
	};

	// All other functions (including @init/@fini/@test) are static
	return true;
};

// Emit function name with optional prefix for exported functions
fn emit_fn_name(ctx: *transform_ctx, d: *n_fn_data) void = {
	let sb = ctx.output;

	// Use @symbol("name") value if provided - no prefix applied
	if (d.symbol_len > 0) {
		match (d.symbol_ptr) {
		case let ptr: *u8 =>
			strbuf_append_bytes(sb, ptr, d.symbol_len);
			return;
		case null =>
			void;
		};
	};

	let is_main = streq(d.name_ptr, d.name_len, "main");

	// Prefix 'main' with _ for runtime entry point
	if (is_main && d.exported) {
		strbuf_append(sb, "_");
	};

	// Apply -p prefix to exported functions (except main)
	if (d.exported && !is_main && ctx.prefix_len > 0) {
		strbuf_append_bytes(sb, ctx.prefix_ptr, ctx.prefix_len);
		strbuf_append(sb, "_");
	};

	strbuf_append_bytes(sb, d.name_ptr, d.name_len);
};

// Emit function forward declaration
fn emit_fn_decl(ctx: *transform_ctx, n: *node) void = {
	let d = n.data: *n_fn_data;
	let sb = ctx.output;

	// Check for pointer-to-array return type: *[N]T -> T (*func(params))[N]
	let is_ptr_to_arr = false;
	let ptr_arr_elem: nullable *node = null;
	let ptr_arr_len: nullable *node = null;

	// Check for function pointer return type: *fn(p1, p2) R -> R (*func(params))(p1, p2)
	let is_fn_ptr_ret = false;
	let fn_ptr_data: nullable *n_tfunc_data = null;

	if (d.ret_type != null) {
		let rt = unwrap(d.ret_type);
		if (rt.kind == node_kind::N_TPTR) {
			let pd = rt.data: *n_tptr_data;
			if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TARR) {
				let ad = (*(pd.inner)).data: *n_tarr_data;
				if (ad.length != null) {
					is_ptr_to_arr = true;
					ptr_arr_elem = ad.elem;
					ptr_arr_len = ad.length;
				};
			} else if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TFUNC) {
				is_fn_ptr_ret = true;
				fn_ptr_data = (*(pd.inner)).data: *n_tfunc_data;
			};
		};
	};

	// Add static prefix for non-exported functions
	if (should_be_static(d)) {
		strbuf_append(sb, "static ");
	};

	// Return type (or element type for pointer-to-array/function pointer)
	if (is_ptr_to_arr) {
		emit_type(ctx, unwrap(ptr_arr_elem));
		strbuf_append(sb, " (*");
	} else if (is_fn_ptr_ret) {
		match (fn_ptr_data) {
		case let fd: *n_tfunc_data =>
			emit_type(ctx, fd.ret_type);
		case null =>
			strbuf_append(sb, "void");
		};
		strbuf_append(sb, " (*");
	} else if (d.ret_type != null) {
		emit_type(ctx, unwrap(d.ret_type));
		strbuf_append(sb, " ");
	} else {
		strbuf_append(sb, "void ");
	};

	// Function name with optional prefix
	emit_fn_name(ctx, d);

	// Parameters
	strbuf_append(sb, "(");
	for (let i = 0z; i < d.nparams; i += 1) {
		if (i > 0) {
			strbuf_append(sb, ", ");
		};
		let param = d.params[i];
		let pd = param.data: *n_param_data;
		emit_param_decl_variadic(ctx, pd.typ, pd.name_ptr, pd.name_len, pd.is_variadic);
	};
	if (d.nparams == 0) {
		strbuf_append(sb, "void");
	};
	strbuf_append(sb, ")");

	// Array dimension for pointer-to-array return type
	if (is_ptr_to_arr) {
		strbuf_append(sb, ")[");
		emit_node(ctx, unwrap(ptr_arr_len));
		strbuf_append(sb, "]");
	};

	// Function pointer parameter types for function pointer return type
	if (is_fn_ptr_ret) {
		match (fn_ptr_data) {
		case let fd: *n_tfunc_data =>
			strbuf_append(sb, ")(");
			if (fd.nparams == 0) {
				strbuf_append(sb, "void");
			} else {
				for (let i = 0z; i < fd.nparams; i += 1) {
					if (i > 0) {
						strbuf_append(sb, ", ");
					};
					let param = fd.params[i];
					let fpd = param.data: *n_param_data;
					// Check that function type parameters have names in Hare
					if (fpd.name_len == 0) {
						emit_error_at_node(ctx, param, "function type parameters must have names (use '_' for unnamed, e.g., *fn(_: int) int)");
					};
					emit_type(ctx, fpd.typ);
				};
			};
			strbuf_append(sb, ")");
		case null => void;
		};
	};

	strbuf_append(sb, ";\n");
};

// Emit complete function definition
export fn emit_fn(ctx: *transform_ctx, n: *node) void = {
	let d = n.data: *n_fn_data;
	let sb = ctx.output;

	// Reset function-level defer tracking
	ctx.fn_defer_count = 0;

	// Clear variable types from previous functions (prevents cross-function leakage)
	clear_var_types(ctx);

	// Register function parameters with their types for type inference
	// This enables auto-dereference detection on parameter field access
	for (let i = 0z; i < d.nparams; i += 1) {
		let param = d.params[i];
		let pd = param.data: *n_param_data;
		if (pd.typ != null) {
			add_var_type(ctx, pd.name_ptr, pd.name_len, pd.typ);
			// Track pointer parameters for -> field access
			if ((*(pd.typ)).kind == node_kind::N_TPTR) {
				add_tracked_var(&ctx.ptr_vars, pd.name_ptr, pd.name_len);
			};
			// Track slice parameters
			if ((*(pd.typ)).kind == node_kind::N_TSLICE) {
				add_tracked_var(&ctx.slice_vars, pd.name_ptr, pd.name_len);
			};
		};
	};

	// Track current function name for inline tagged union returns
	ctx.cur_fn_name_ptr = d.name_ptr;
	ctx.cur_fn_name_len = d.name_len;

	// Track return type for tagged union wrapping
	// Save previous values (for nested functions if any)
	let prev_ret_type = ctx.ret_type;
	let prev_ret_name_ptr = ctx.ret_name_ptr;
	let prev_ret_name_len = ctx.ret_name_len;

	// Set current function's return type info
	// Track return type for ALL functions (needed for match result types)
	if (d.ret_type != null) {
		let rt = unwrap(d.ret_type);
		// Track function return type for variable type inference
		add_fn_ret_type(ctx, d.name_ptr, d.name_len, rt);
		// Always set ret_type so match/switch expressions can use correct result type
		ctx.ret_type = rt;
		// Type aliases (named types) might be tagged unions - track name
		if (rt.kind == node_kind::N_TPRIM) {
			let rtd = rt.data: *n_id_data;
			// Check if it's not a primitive type AND it's a known tagged union type
			if (!is_primitive_type(rtd.ptr, rtd.length) &&
			    is_tracked_var(&ctx.tagged_types, rtd.ptr, rtd.length)) {
				ctx.ret_name_ptr = rtd.ptr;
				ctx.ret_name_len = rtd.length;
			};
		};
		// Inline tagged union return types
		if (rt.kind == node_kind::N_TTAGGED) {
			// Store function name for building unique typedef name
			ctx.cur_fn_name_ptr = d.name_ptr;
			ctx.cur_fn_name_len = d.name_len;
			// ret_name_len stays 0 - indicates inline tagged union
			// For inline tagged unions, we use numeric literals for tag values
			// via find_variant_tag_*() functions, so we don't need to emit
			// global TAG macros. The typedef handles type naming.
			// Note: Type-prefixed TAGs like __ret_funcname_t_TAG_void are
			// generated in emit_tagged_typedef() when the typedef is emitted.
			// Emit file-scope typedef BEFORE function signature
			strbuf_append(sb, "typedef ");
			emit_type(ctx, rt);
			strbuf_append(sb, " __ret_");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			strbuf_append(sb, "_t;\n");
		};
	};

	// Check for pointer-to-array return type: *[N]T -> T (*func(params))[N]
	let is_ptr_to_arr = false;
	let ptr_arr_elem: nullable *node = null;
	let ptr_arr_len: nullable *node = null;

	// Check for function pointer return type: *fn(p1, p2) R -> R (*func(params))(p1, p2)
	let is_fn_ptr_ret = false;
	let fn_ptr_data: nullable *n_tfunc_data = null;

	if (d.ret_type != null) {
		let rt = unwrap(d.ret_type);
		if (rt.kind == node_kind::N_TPTR) {
			let pd = rt.data: *n_tptr_data;
			if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TARR) {
				let ad = (*(pd.inner)).data: *n_tarr_data;
				if (ad.length != null) {
					is_ptr_to_arr = true;
					ptr_arr_elem = ad.elem;
					ptr_arr_len = ad.length;
				};
			} else if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TFUNC) {
				is_fn_ptr_ret = true;
				fn_ptr_data = (*(pd.inner)).data: *n_tfunc_data;
			};
		};
	};

	// Add static prefix for non-exported functions
	if (should_be_static(d)) {
		strbuf_append(sb, "static ");
	};

	// Return type (or element type for pointer-to-array/function pointer)
	// Check for inline tagged union return type
	let has_inline_tagged_ret = d.ret_type != null &&
		(*(unwrap(d.ret_type))).kind == node_kind::N_TTAGGED;
	if (is_ptr_to_arr) {
		emit_type(ctx, unwrap(ptr_arr_elem));
		strbuf_append(sb, " (*");
	} else if (is_fn_ptr_ret) {
		match (fn_ptr_data) {
		case let fd: *n_tfunc_data =>
			emit_type(ctx, fd.ret_type);
		case null =>
			strbuf_append(sb, "void");
		};
		strbuf_append(sb, " (*");
	} else if (has_inline_tagged_ret) {
		// Use the file-scope typedef we emitted earlier
		strbuf_append(sb, "__ret_");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_t ");
	} else if (d.ret_type != null) {
		emit_type(ctx, unwrap(d.ret_type));
		strbuf_append(sb, " ");
	} else {
		strbuf_append(sb, "void ");
	};

	// Function name with optional prefix
	emit_fn_name(ctx, d);

	// Parameters
	strbuf_append(sb, "(");
	for (let i = 0z; i < d.nparams; i += 1) {
		if (i > 0) {
			strbuf_append(sb, ", ");
		};
		let param = d.params[i];
		let pd = param.data: *n_param_data;
		emit_param_decl_variadic(ctx, pd.typ, pd.name_ptr, pd.name_len, pd.is_variadic);
	};
	if (d.nparams == 0) {
		strbuf_append(sb, "void");
	};
	strbuf_append(sb, ")");

	// Array dimension for pointer-to-array return type
	if (is_ptr_to_arr) {
		strbuf_append(sb, ")[");
		emit_node(ctx, unwrap(ptr_arr_len));
		strbuf_append(sb, "]");
	};

	// Function pointer parameter types for function pointer return type
	if (is_fn_ptr_ret) {
		match (fn_ptr_data) {
		case let fd: *n_tfunc_data =>
			strbuf_append(sb, ")(");
			if (fd.nparams == 0) {
				strbuf_append(sb, "void");
			} else {
				for (let i = 0z; i < fd.nparams; i += 1) {
					if (i > 0) {
						strbuf_append(sb, ", ");
					};
					let param = fd.params[i];
					let fpd = param.data: *n_param_data;
					// Check that function type parameters have names in Hare
					if (fpd.name_len == 0) {
						emit_error_at_node(ctx, param, "function type parameters must have names (use '_' for unnamed, e.g., *fn(_: int) int)");
					};
					emit_type(ctx, fpd.typ);
				};
			};
			strbuf_append(sb, ")");
		case null => void;
		};
	};

	// Body
	if (d.body != null) {
		strbuf_append(sb, " ");

		// Clear and set up variable trackers for this function
		clear_tracked_vars(&ctx.str_vars);
		clear_tracked_vars(&ctx.slice_vars);
		clear_tracked_vars(&ctx.arr_vars);
		clear_variant_bindings(&ctx.arr_elem_types);
		clear_tracked_vars(&ctx.ptr_vars);
		clear_tracked_vars(&ctx.ptr_uarr_vars);
		clear_tracked_vars(&ctx.local_vars);

		// Track function parameters with special types (str, slice, ptr, variadic)
		for (let i = 0z; i < d.nparams; i += 1) {
			let param = d.params[i];
			let pd = param.data: *n_param_data;
			// Track all parameters as local variables
			add_tracked_var(&ctx.local_vars, pd.name_ptr, pd.name_len);
			// Variadic parameters are slices
			if (pd.is_variadic) {
				add_tracked_var(&ctx.slice_vars, pd.name_ptr, pd.name_len);
			};
			if (pd.typ != null) {
				let pt = pd.typ;
				// Track parameter types for match expression type lookup
				add_var_type(ctx, pd.name_ptr, pd.name_len, pt);
				// Track str parameters
				if (pt.kind == node_kind::N_TPRIM) {
					let ptd = pt.data: *n_id_data;
					if (streq(ptd.ptr, ptd.length, "str")) {
						add_str_var(&ctx.str_vars, pd.name_ptr, pd.name_len);
					};
				};
				// Track slice parameters
				if (pt.kind == node_kind::N_TSLICE) {
					add_tracked_var(&ctx.slice_vars, pd.name_ptr, pd.name_len);
				};
				// Track pointer parameters
				if (pt.kind == node_kind::N_TPTR) {
					add_tracked_var(&ctx.ptr_vars, pd.name_ptr, pd.name_len);
				};
				track_ptr_uarr_var(ctx, pd.name_ptr, pd.name_len, pt);
			};
		};

		let body: *node = unwrap(d.body);
		// Check if this is an inline tagged union return with void success type
		let has_void_success = false;
		if (d.ret_type != null && (*(unwrap(d.ret_type))).kind == node_kind::N_TTAGGED) {
			let td = (*(unwrap(d.ret_type))).data: *n_ttagged_data;
			for (let i = 0z; i < td.nvariants; i += 1) {
				if (is_void_type(ctx, td.variants[i])) {
					has_void_success = true;
				};
			};
		};
		// Expression bodies (not blocks) need wrapping
		if (body.kind != node_kind::N_BLOCK) {
			strbuf_append(sb, "{ return ");
			emit_node(ctx, body);
			strbuf_append(sb, "; }");
		} else {
			// For inline tagged unions with void success, emit custom block handling
			if (has_void_success) {
				// Emit block contents without the closing brace
				let bd = body.data: *n_block_data;
				strbuf_append(sb, "{\n");
				for (let i = 0z; i < bd.nstmts; i += 1) {
					emit_stmt(ctx, bd.stmts[i]);
					strbuf_append(sb, "\n");
				};
				// Add implicit return void before closing brace
				let void_tag = find_variant_tag_void(ctx, unwrap(d.ret_type));
				strbuf_append(sb, "return (__ret_");
				strbuf_append_bytes(sb, d.name_ptr, d.name_len);
				strbuf_append(sb, "_t){.tag = ");
				strbuf_append_int(sb, void_tag);
				strbuf_append(sb, "};\n}");
			} else {
				// Check if function has non-void return type and block ends with expression
				let needs_implicit_return = false;
				let bd = body.data: *n_block_data;
				if (d.ret_type != null && bd.nstmts > 0) {
					let rt = unwrap(d.ret_type);
					// Check if return type is not void
					let is_void_ret = false;
					if (rt.kind == node_kind::N_TPRIM) {
						let rtd = rt.data: *n_id_data;
						is_void_ret = streq(rtd.ptr, rtd.length, "void");
					};
					if (!is_void_ret) {
						// Check if last statement is an expression type
						let last_stmt = bd.stmts[bd.nstmts - 1];
						let lk = last_stmt.kind;
						// Expression-producing statements that need implicit return
						// Note: N_IF excluded because if-statements with explicit returns
						// don't need implicit return wrapping
						if (lk == node_kind::N_EXPR) {
							let ed = last_stmt.data: *n_ret_data;
							if (ed.expr != null) {
								if ((*unwrap(ed.expr)).kind != node_kind::N_ABORT) {
									needs_implicit_return = true;
								};
							};
						} else if (lk == node_kind::N_SWITCH ||
						           lk == node_kind::N_MATCH ||
						           lk == node_kind::N_CALL ||
						           lk == node_kind::N_BIN ||
						           lk == node_kind::N_UN ||
						           lk == node_kind::N_INT ||
						           lk == node_kind::N_ID) {
							needs_implicit_return = true;
						};
					};
				};

				if (needs_implicit_return) {
					// Emit block with explicit return for last statement
					strbuf_append(sb, "{\n");
					for (let i = 0z; i < bd.nstmts - 1; i += 1) {
						emit_stmt(ctx, bd.stmts[i]);
						strbuf_append(sb, "\n");
					};
					// Wrap last statement in return
					// Set flag so match expressions use ret_type
					let prev_in_return = ctx.in_return_expr;
					ctx.in_return_expr = true;
					strbuf_append(sb, "return ");
					let did_cast = false;
					match (ctx.ret_type) {
					case let rt: *node =>
						if (rt.kind == node_kind::N_TPRIM) {
							let rtd = rt.data: *n_id_data;
							if (is_scalar_prim_name(rtd.ptr, rtd.length)) {
								strbuf_append(sb, "(");
								emit_type(ctx, rt);
								strbuf_append(sb, ")(");
								emit_node(ctx, bd.stmts[bd.nstmts - 1]);
								strbuf_append(sb, ")");
								did_cast = true;
							};
						};
					case null => void;
					};
					if (!did_cast) {
						emit_node(ctx, bd.stmts[bd.nstmts - 1]);
					};
					strbuf_append(sb, ";\n}");
					ctx.in_return_expr = prev_in_return;
				} else {
					emit_stmt(ctx, body);
				};
			};
		};
	} else {
		strbuf_append(sb, ";");
	};

	// Emit section attributes for @init, @fini, @test
	if (d.is_init) {
		strbuf_append(sb, "\n__attribute__((used, section(\"hare_init\"))) static void (*__hare_init_");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ")(void) = ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ";");
	};
	if (d.is_fini) {
		strbuf_append(sb, "\n__attribute__((used, section(\"hare_fini\"))) static void (*__hare_fini_");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ")(void) = ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ";");
	};
	if (d.is_test) {
		strbuf_append(sb, "\n__attribute__((used, section(\"hare_test\"))) static void (*__hare_test_");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ")(void) = ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ";");
	};

	// Restore previous return type context
	ctx.ret_type = prev_ret_type;
	ctx.ret_name_ptr = prev_ret_name_ptr;
	ctx.ret_name_len = prev_ret_name_len;
};

fn emit_init_expr(ctx: *transform_ctx, init: *node, typ: nullable *node) void = {
	if (typ != null &&
	    (init.kind == node_kind::N_MATCH || init.kind == node_kind::N_SWITCH)) {
		let prev_in_return = ctx.in_return_expr;
		let prev_ret_type = ctx.ret_type;
		ctx.in_return_expr = true;
		ctx.ret_type = typ;
		emit_node(ctx, init);
		ctx.ret_type = prev_ret_type;
		ctx.in_return_expr = prev_in_return;
	} else {
		emit_node(ctx, init);
	};
};

// Emit a statement
export fn emit_stmt(ctx: *transform_ctx, n: *node) void = {
	let k = n.kind;
	let sb = ctx.output;

	// Block
	if (k == node_kind::N_BLOCK) {
		let d = n.data: *n_block_data;
		strbuf_append(sb, "{\n");

		// Save current fn_defer_count to restore after block
		let prev_fn_defer_count = ctx.fn_defer_count;

		// Collect defer positions (indices) for block-end emission
		let defer_indices: [64]size = [0...];
		let defer_count = 0z;

		// Emit statements in order, collecting defers as we go
		// Defers only get added to fn_defers when we process them
		for (let i = 0z; i < d.nstmts; i += 1) {
			let stmt: *node = d.stmts[i];
			if (stmt.kind == node_kind::N_DEFER) {
				// Add defer to function-level tracking
				let dd = stmt.data: *n_defer_data;
				if (ctx.fn_defer_count < 64) {
					ctx.fn_defers[ctx.fn_defer_count] = dd.expr;
					ctx.fn_defer_count += 1;
				};
				// Also track for block-end emission
				if (defer_count < 64) {
					defer_indices[defer_count] = i;
					defer_count += 1;
				};
			} else {
				strbuf_append(sb, "    ");
				emit_stmt(ctx, stmt);
				strbuf_append(sb, "\n");
			};
		};

		// Emit defers for normal block exit (in reverse order of collection)
		if (defer_count > 0) {
			let idx = defer_count;
			for (idx > 0) {
				idx -= 1;
				let stmt_idx = defer_indices[idx];
				let dd = d.stmts[stmt_idx].data: *n_defer_data;
				strbuf_append(sb, "    ");
				emit_node(ctx, dd.expr);
				strbuf_append(sb, ";\n");
			};
		};

		// Restore fn_defer_count (defers from this block are done)
		ctx.fn_defer_count = prev_fn_defer_count;

		strbuf_append(sb, "}");
		return;
	};

	// Return - emit all function-level defers before returning
	if (k == node_kind::N_RET) {
		let d = n.data: *n_ret_data;

		// Type check return value against function return type
			if (d.expr != null && ctx.ret_type != null) {
				let ret_expr = unwrap(d.expr);
				let expr_type = infer_expr_type(ctx, ret_expr);
				if (!types_assignable(ctx, ctx.ret_type, expr_type)) {
					emit_error_at_node(ctx, ret_expr, "return type is not assignable to function result type");
				};
			};

		// If there are defers, wrap in block and emit them
		if (ctx.fn_defer_count > 0) {
			strbuf_append(sb, "{ ");
			if (d.expr != null) {
				// Save return value, emit defers, then return
				strbuf_append(sb, "__auto_type __ret_tmp = ");
				let expr: *node = unwrap(d.expr);
				// Check if we need to wrap for tagged union return
				if (ctx.ret_type != null && ctx.ret_name_len > 0) {
					if (expr.kind == node_kind::N_VOID) {
						strbuf_append(sb, "(");
						strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
						strbuf_append(sb, "){.tag = ");
						strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
						strbuf_append(sb, "_TAG_void}");
					} else if (expr.kind == node_kind::N_ID) {
						let ed = expr.data: *n_id_data;
						// Check if returning a type variant (not a local var)
						if (ed.length > 1 && (!is_primitive_type(ed.ptr, ed.length) || is_done_name(ed.ptr, ed.length)) &&
						    !is_tracked_var(&ctx.local_vars, ed.ptr, ed.length)) {
							let is_zero_variant = is_done_name(ed.ptr, ed.length);
							let is_error_alias = false;
							let type_def = find_typedef(ctx, ed.ptr, ed.length);
							match (type_def) {
							case let tdef: *node =>
								let resolved = resolve_type_alias(ctx, tdef);
								if (is_void_type(ctx, tdef) || is_nomem_type(tdef)) {
									is_zero_variant = true;
								};
								if (resolved.kind == node_kind::N_TERR) {
									let terr = resolved.data: *n_terr_data;
									let inner: *node = terr.inner;
									let is_void_err = false;
									if (inner.kind == node_kind::N_TPRIM) {
										let pd = inner.data: *n_id_data;
										is_void_err = streq(pd.ptr, pd.length, "void");
									};
									if (!is_void_err) {
										emit_error_at_node(ctx, expr, "cannot use non-void error type alias as literal (needs a value)");
									} else {
										is_error_alias = true;
									};
								};
							case null => void;
							};
							strbuf_append(sb, "(");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							strbuf_append(sb, "){.tag = ");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							strbuf_append(sb, "_TAG_");
							strbuf_append_bytes(sb, ed.ptr, ed.length);
							if (!is_zero_variant) {
								strbuf_append(sb, ", .value._");
								strbuf_append_bytes(sb, ed.ptr, ed.length);
								strbuf_append(sb, " = ");
								if (is_error_alias) {
									strbuf_append(sb, "((");
									strbuf_append_bytes(sb, ed.ptr, ed.length);
									strbuf_append(sb, ")0)}");
								} else {
									strbuf_append(sb, "(");
									strbuf_append_bytes(sb, ed.ptr, ed.length);
									strbuf_append(sb, "){0}}");
								};
							} else {
								strbuf_append(sb, "}");
							};
						} else {
							// Returning a local variable value
							strbuf_append(sb, "(");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							// Check if this is a variant binding (match case variable)
							let variant_type_ptr = get_variant_type(&ctx.variant_bindings, ed.ptr, ed.length);
							let variant_type_len = get_variant_type_len(&ctx.variant_bindings, ed.ptr, ed.length);
							if (variant_type_ptr != null) {
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_");
								strbuf_append_bytes(sb, unwrap_u8(variant_type_ptr), variant_type_len);
								strbuf_append(sb, ", .value._");
								strbuf_append_bytes(sb, unwrap_u8(variant_type_ptr), variant_type_len);
								strbuf_append(sb, " = (");
							} else if (is_tracked_var(&ctx.ptr_vars, ed.ptr, ed.length)) {
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_ptr_int, .value._ptr_int = (");
							} else {
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_int, .value._int = (");
							};
							emit_node(ctx, expr);
							strbuf_append(sb, ")}");
						};
					} else {
						// Returning a value - try to match the variant by inferred type
						let tag_idx: i64 = -1;
						let tag_variant: nullable *node = null;
						let expr_type = infer_expr_type(ctx, expr);
						match (expr_type) {
						case let et: *node =>
							let ttd = unwrap(ctx.ret_type).data: *n_ttagged_data;
							for (let vi = 0z; vi < ttd.nvariants; vi += 1) {
								let vnode = ttd.variants[vi];
								if (types_assignable(ctx, vnode, et) &&
								    types_assignable(ctx, et, vnode)) {
									tag_idx = vi: i64;
									tag_variant = vnode;
									vi = ttd.nvariants;
								};
							};
						case null => void;
						};
					if (tag_idx >= 0 && tag_variant != null) {
						let is_zero_variant = false;
						let tv = unwrap(tag_variant);
						if (tv.kind == node_kind::N_TPRIM) {
							let vtd = tv.data: *n_id_data;
							if (type_is(vtd.ptr, vtd.length, "int")) {
								let int_tag = find_variant_tag_int(unwrap(ctx.ret_type));
								if (int_tag < 0) {
									let ttd = unwrap(ctx.ret_type).data: *n_ttagged_data;
									if (ttd.nvariants > 0) {
										tv = ttd.variants[0];
										tag_idx = 0;
									};
								};
							};
						};
						if (is_void_type(ctx, tv) || is_nomem_type(tv)) {
							is_zero_variant = true;
						} else if (tv.kind == node_kind::N_TPRIM) {
								let vtd = tv.data: *n_id_data;
								if (is_done_name(vtd.ptr, vtd.length)) {
									is_zero_variant = true;
								};
							};
							strbuf_append(sb, "(");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							strbuf_append(sb, "){.tag = ");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							strbuf_append(sb, "_TAG_");
							emit_type_tag(sb, tv);
							if (!is_zero_variant) {
								strbuf_append(sb, ", .value._");
								emit_type_tag(sb, tv);
								strbuf_append(sb, " = (");
								emit_node(ctx, expr);
								strbuf_append(sb, ")}");
							} else {
								strbuf_append(sb, "}");
							};
						} else {
							let ttd = unwrap(ctx.ret_type).data: *n_ttagged_data;
							if (ttd.nvariants > 0) {
								let vnode = ttd.variants[0];
								let is_zero_variant = false;
								if (is_void_type(ctx, vnode) || is_nomem_type(vnode)) {
									is_zero_variant = true;
								} else if (vnode.kind == node_kind::N_TPRIM) {
									let vnd = vnode.data: *n_id_data;
									if (is_done_name(vnd.ptr, vnd.length)) {
										is_zero_variant = true;
									};
								};
								strbuf_append(sb, "(");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_");
								emit_type_tag(sb, vnode);
								if (!is_zero_variant) {
									strbuf_append(sb, ", .value._");
									emit_type_tag(sb, vnode);
									strbuf_append(sb, " = (");
									emit_node(ctx, expr);
									strbuf_append(sb, ")}");
								} else {
									strbuf_append(sb, "}");
								};
							} else {
								strbuf_append(sb, "(");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_int, .value._int = (");
								emit_node(ctx, expr);
								strbuf_append(sb, ")}");
							};
						};
					};
				} else {
					// Set in_return_expr so match expressions use ret_type
					let prev_in_return = ctx.in_return_expr;
					ctx.in_return_expr = true;
					let did_cast = false;
					match (ctx.ret_type) {
					case let rt: *node =>
						if (rt.kind == node_kind::N_TPRIM) {
							let rtd = rt.data: *n_id_data;
							if (is_scalar_prim_name(rtd.ptr, rtd.length)) {
								strbuf_append(sb, "(");
								emit_type(ctx, rt);
								strbuf_append(sb, ")(");
								emit_node(ctx, expr);
								strbuf_append(sb, ")");
								did_cast = true;
							};
						};
					case null => void;
					};
					if (!did_cast) {
						emit_node(ctx, expr);
					};
					ctx.in_return_expr = prev_in_return;
				};
				strbuf_append(sb, "; ");
			};
			// Emit defers in reverse order
			let idx = ctx.fn_defer_count;
			for (idx > 0) {
				idx -= 1;
				emit_node(ctx, ctx.fn_defers[idx]);
				strbuf_append(sb, "; ");
			};
			if (d.expr != null) {
				strbuf_append(sb, "return __ret_tmp; }");
			} else {
				strbuf_append(sb, "return; }");
			};
		} else {
			// No defers - simple return
			strbuf_append(sb, "return");
			if (d.expr != null) {
				strbuf_append(sb, " ");
				let expr: *node = unwrap(d.expr);
				// Check if we need to wrap for inline tagged union return
				let rt = ctx.ret_type;
				if (rt != null && ctx.ret_name_len == 0 && (*unwrap(rt)).kind == node_kind::N_TTAGGED) {
					// Inline tagged union return - use unique typedef name and literal tag values
					strbuf_append(sb, "(__ret_");
					strbuf_append_bytes(sb, ctx.cur_fn_name_ptr, ctx.cur_fn_name_len);
					strbuf_append(sb, "_t)");
					if (expr.kind == node_kind::N_VOID) {
						let tag_idx = find_variant_tag_void(ctx, unwrap(rt));
						strbuf_append(sb, "{.tag = ");
						strbuf_append_int(sb, tag_idx);
						strbuf_append(sb, "}");
					} else if (expr.kind == node_kind::N_ID) {
						let ed = expr.data: *n_id_data;
						if (ed.length > 1 && (!is_primitive_type(ed.ptr, ed.length) || is_done_name(ed.ptr, ed.length)) &&
						    !is_tracked_var(&ctx.local_vars, ed.ptr, ed.length)) {
							// Returning a type variant name - use literal tag value
							let tag_idx = find_variant_tag(unwrap(rt), ed.ptr, ed.length);
							let is_zero_variant = is_done_name(ed.ptr, ed.length);
							let is_error_alias = false;
							let type_def = find_typedef(ctx, ed.ptr, ed.length);
							match (type_def) {
							case let tdef: *node =>
								let resolved = resolve_type_alias(ctx, tdef);
								if (resolved.kind == node_kind::N_TERR) {
									let terr = resolved.data: *n_terr_data;
									let inner: *node = terr.inner;
									let is_void_err = false;
									if (inner.kind == node_kind::N_TPRIM) {
										let pd = inner.data: *n_id_data;
										is_void_err = streq(pd.ptr, pd.length, "void");
									};
									if (!is_void_err) {
										emit_error_at_node(ctx, expr, "cannot use non-void error type alias as literal (needs a value)");
									} else {
										is_error_alias = true;
									};
								};
							case null => void;
							};
							let td = unwrap(rt).data: *n_ttagged_data;
							for (let vi = 0z; vi < td.nvariants; vi += 1) {
								let vnode = td.variants[vi];
								if (vnode.kind == node_kind::N_TPRIM || vnode.kind == node_kind::N_TALIAS) {
									let vnd = vnode.data: *n_id_data;
									if (vnd.length == ed.length) {
										let matched = true;
										let vnd_bytes = vnd.ptr: *[*]u8;
										let ed_bytes = ed.ptr: *[*]u8;
										for (let j = 0z; j < vnd.length; j += 1) {
											if (vnd_bytes[j] != ed_bytes[j]) {
												matched = false;
												break;
											};
										};
										if (matched) {
											if (is_void_type(ctx, vnode) || is_nomem_type(vnode)) {
												is_zero_variant = true;
											};
											vi = td.nvariants;  // Break loop
										};
									};
								};
							};
							strbuf_append(sb, "{.tag = ");
							strbuf_append_int(sb, tag_idx);
							if (!is_zero_variant) {
								strbuf_append(sb, ", .value._");
								strbuf_append_bytes(sb, ed.ptr, ed.length);
								strbuf_append(sb, " = ");
								if (is_error_alias) {
									strbuf_append(sb, "((");
									strbuf_append_bytes(sb, ed.ptr, ed.length);
									strbuf_append(sb, ")0)}");
								} else {
									strbuf_append(sb, "(");
									strbuf_append_bytes(sb, ed.ptr, ed.length);
									strbuf_append(sb, "){0}}");
								};
							} else {
								strbuf_append(sb, "}");
							};
						} else {
							// Returning a value - default to the first variant
							let ttd = unwrap(rt).data: *n_ttagged_data;
							if (ttd.nvariants > 0) {
								let vnode = ttd.variants[0];
								let is_zero_variant = false;
								if (is_void_type(ctx, vnode) || is_nomem_type(vnode)) {
									is_zero_variant = true;
								} else if (vnode.kind == node_kind::N_TPRIM) {
									let vnd = vnode.data: *n_id_data;
									if (is_done_name(vnd.ptr, vnd.length)) {
										is_zero_variant = true;
									};
								};
								strbuf_append(sb, "{.tag = 0");
								if (!is_zero_variant) {
									strbuf_append(sb, ", .value._");
									emit_type_tag(sb, vnode);
									strbuf_append(sb, " = (");
									emit_node(ctx, expr);
									strbuf_append(sb, ")}");
								} else {
									strbuf_append(sb, "}");
								};
							} else {
								strbuf_append(sb, "{.tag = 0, .value._int = (");
								emit_node(ctx, expr);
								strbuf_append(sb, ")}");
							};
						};
					} else if (expr.kind == node_kind::N_CAST) {
						// Returning a cast like `n: invalid` - use cast target type name
						let cast_data = expr.data: *n_cast_data;
						let cast_target = cast_data.target;
						// Check for type name (N_TPRIM is used for both primitives and type aliases)
						if (cast_target.kind == node_kind::N_TPRIM || cast_target.kind == node_kind::N_TALIAS) {
							let type_id = cast_target.data: *n_id_data;
							// Check if this is a tagged union variant
							let variant_tag = find_variant_tag(unwrap(rt), type_id.ptr, type_id.length);
							if (variant_tag >= 0) {
								// It's a tagged union variant - use variant name
								let is_zero_variant = is_done_name(type_id.ptr, type_id.length);
								let td = unwrap(rt).data: *n_ttagged_data;
								for (let vi = 0z; vi < td.nvariants; vi += 1) {
									let vnode = td.variants[vi];
									if (vnode.kind == node_kind::N_TPRIM || vnode.kind == node_kind::N_TALIAS) {
										let vnd = vnode.data: *n_id_data;
										if (vnd.length == type_id.length) {
											let matched = true;
											let vnd_bytes = vnd.ptr: *[*]u8;
											let type_bytes = type_id.ptr: *[*]u8;
											for (let j = 0z; j < vnd.length; j += 1) {
												if (vnd_bytes[j] != type_bytes[j]) {
													matched = false;
													break;
												};
											};
											if (matched) {
												if (is_void_type(ctx, vnode) || is_nomem_type(vnode)) {
													is_zero_variant = true;
												};
												vi = td.nvariants;  // Break loop
											};
										};
									};
								};
								strbuf_append(sb, "{.tag = ");
								strbuf_append_int(sb, variant_tag);
								if (!is_zero_variant) {
									strbuf_append(sb, ", .value._");
									strbuf_append_bytes(sb, type_id.ptr, type_id.length);
									strbuf_append(sb, " = (");
									emit_node(ctx, cast_data.expr);
									strbuf_append(sb, ")}");
								} else {
									strbuf_append(sb, "}");
								};
							} else {
								// Fallback - use int (primitive cast)
								let int_tag = find_variant_tag_int(unwrap(rt));
								if (int_tag < 0) { int_tag = 0; };
								strbuf_append(sb, "{.tag = ");
								strbuf_append_int(sb, int_tag);
								strbuf_append(sb, ", .value._int = (");
								emit_node(ctx, expr);
								strbuf_append(sb, ")}");
							};
						} else {
							// Fallback for other cast targets
							let other_tag = find_variant_tag_int(unwrap(rt));
							if (other_tag < 0) { other_tag = 0; };
							strbuf_append(sb, "{.tag = ");
							strbuf_append_int(sb, other_tag);
							strbuf_append(sb, ", .value._int = (");
							emit_node(ctx, expr);
							strbuf_append(sb, ")}");
						};
					} else {
						// Returning an expression - default to the first variant
						let ttd = unwrap(rt).data: *n_ttagged_data;
						if (ttd.nvariants > 0) {
							let vnode = ttd.variants[0];
							let is_zero_variant = false;
							if (is_void_type(ctx, vnode) || is_nomem_type(vnode)) {
								is_zero_variant = true;
							} else if (vnode.kind == node_kind::N_TPRIM) {
								let vnd = vnode.data: *n_id_data;
								if (is_done_name(vnd.ptr, vnd.length)) {
									is_zero_variant = true;
								};
							};
							strbuf_append(sb, "{.tag = 0");
							if (!is_zero_variant) {
								strbuf_append(sb, ", .value._");
								emit_type_tag(sb, vnode);
								strbuf_append(sb, " = (");
								emit_node(ctx, expr);
								strbuf_append(sb, ")}");
							} else {
								strbuf_append(sb, "}");
							};
						} else {
							strbuf_append(sb, "{.tag = 0, .value._int = (");
							emit_node(ctx, expr);
							strbuf_append(sb, ")}");
						};
					};
				// Check if we need to wrap for named tagged union return
				} else if (ctx.ret_type != null && ctx.ret_name_len > 0) {
					// If expression is a cast to the return type, emit directly
					if (expr.kind == node_kind::N_CAST &&
					    is_cast_to_ret_type(ctx, expr.data: *n_cast_data)) {
						emit_node(ctx, expr);
					} else if (expr.kind == node_kind::N_VOID) {
						strbuf_append(sb, "(");
						strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
						strbuf_append(sb, "){.tag = ");
						strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
						strbuf_append(sb, "_TAG_void}");
					} else if (expr.kind == node_kind::N_ID) {
						let ed = expr.data: *n_id_data;
						// Check if returning a type variant (not a local var)
						if (ed.length > 1 && (!is_primitive_type(ed.ptr, ed.length) || is_done_name(ed.ptr, ed.length)) &&
						    !is_tracked_var(&ctx.local_vars, ed.ptr, ed.length)) {
							let is_zero_variant = is_done_name(ed.ptr, ed.length);
							let is_error_alias = false;
							let type_def = find_typedef(ctx, ed.ptr, ed.length);
							match (type_def) {
							case let tdef: *node =>
								let resolved = resolve_type_alias(ctx, tdef);
								if (is_void_type(ctx, tdef) || is_nomem_type(tdef)) {
									is_zero_variant = true;
								};
								if (resolved.kind == node_kind::N_TERR) {
									let terr = resolved.data: *n_terr_data;
									let inner: *node = terr.inner;
									let is_void_err = false;
									if (inner.kind == node_kind::N_TPRIM) {
										let pd = inner.data: *n_id_data;
										is_void_err = streq(pd.ptr, pd.length, "void");
									};
									if (!is_void_err) {
										emit_error_at_node(ctx, expr, "cannot use non-void error type alias as literal (needs a value)");
									} else {
										is_error_alias = true;
									};
								};
							case null => void;
							};
							strbuf_append(sb, "(");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							strbuf_append(sb, "){.tag = ");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							strbuf_append(sb, "_TAG_");
							strbuf_append_bytes(sb, ed.ptr, ed.length);
							if (!is_zero_variant) {
								strbuf_append(sb, ", .value._");
								strbuf_append_bytes(sb, ed.ptr, ed.length);
								strbuf_append(sb, " = ");
								if (is_error_alias) {
									strbuf_append(sb, "((");
									strbuf_append_bytes(sb, ed.ptr, ed.length);
									strbuf_append(sb, ")0)}");
								} else {
									strbuf_append(sb, "(");
									strbuf_append_bytes(sb, ed.ptr, ed.length);
									strbuf_append(sb, "){0}}");
								};
							} else {
								strbuf_append(sb, "}");
							};
						} else {
							// Returning a local variable value
							strbuf_append(sb, "(");
							strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
							// Check if this is a variant binding (match case variable)
							let variant_type_ptr = get_variant_type(&ctx.variant_bindings, ed.ptr, ed.length);
							let variant_type_len = get_variant_type_len(&ctx.variant_bindings, ed.ptr, ed.length);
							if (variant_type_ptr != null) {
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_");
								strbuf_append_bytes(sb, unwrap_u8(variant_type_ptr), variant_type_len);
								strbuf_append(sb, ", .value._");
								strbuf_append_bytes(sb, unwrap_u8(variant_type_ptr), variant_type_len);
								strbuf_append(sb, " = (");
							} else if (is_tracked_var(&ctx.ptr_vars, ed.ptr, ed.length)) {
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_ptr_int, .value._ptr_int = (");
							} else {
								strbuf_append(sb, "){.tag = ");
								strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
								strbuf_append(sb, "_TAG_int, .value._int = (");
							};
							emit_node(ctx, expr);
							strbuf_append(sb, ")}");
						};
					} else {
						strbuf_append(sb, "(");
						strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
						strbuf_append(sb, "){.tag = ");
						strbuf_append_bytes(sb, ctx.ret_name_ptr, ctx.ret_name_len);
						strbuf_append(sb, "_TAG_int, .value._int = (");
						emit_node(ctx, expr);
						strbuf_append(sb, ")}");
					};
				} else {
					// Set in_return_expr so match expressions use ret_type
					let prev_in_return = ctx.in_return_expr;
					ctx.in_return_expr = true;
					let did_cast = false;
					match (ctx.ret_type) {
					case let rt: *node =>
						if (rt.kind == node_kind::N_TPRIM) {
							let rtd = rt.data: *n_id_data;
							if (is_scalar_prim_name(rtd.ptr, rtd.length)) {
								strbuf_append(sb, "(");
								emit_type(ctx, rt);
								strbuf_append(sb, ")(");
								emit_node(ctx, expr);
								strbuf_append(sb, ")");
								did_cast = true;
							};
						};
					case null => void;
					};
					if (!did_cast) {
						emit_node(ctx, expr);
					};
					ctx.in_return_expr = prev_in_return;
				};
			};
			strbuf_append(sb, ";");
		};
		return;
	};

	// Let
	if (k == node_kind::N_LET) {
		let d = n.data: *n_let_data;

		// Pika: Check for variable shadowing (not allowed)
		if (is_tracked_var(&ctx.global_vars, d.name_ptr, d.name_len)) {
			emit_error_with_name_at_node(ctx, n, "variable shadowing is not allowed: ", d.name_ptr, d.name_len, " shadows global");
		};

		// Track all let bindings as local variables
		add_tracked_var(&ctx.local_vars, d.name_ptr, d.name_len);

		// Static prefix
		if (d.is_static) {
			strbuf_append(sb, "static ");
		};

		// Track str variables for len() handling
		let typ = d.typ;
		let is_str = false;
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPRIM) {
			let td = (*unwrap(typ)).data: *n_id_data;
			is_str = streq(td.ptr, td.length, "str");
		};
		// Also infer str type from string literal initializer
		if (!is_str && d.init != null && (*unwrap(d.init)).kind == node_kind::N_STR) {
			is_str = true;
		};
		// Also infer str type from cast expression with str target (e.g., expr as str)
		if (!is_str && d.init != null && (*unwrap(d.init)).kind == node_kind::N_CAST) {
			let cast_d = (*unwrap(d.init)).data: *n_cast_data;
			if (cast_d.target.kind == node_kind::N_TPRIM) {
				let cast_td = cast_d.target.data: *n_id_data;
				is_str = streq(cast_td.ptr, cast_td.length, "str");
			};
		};
		if (is_str) {
			add_str_var(&ctx.str_vars, d.name_ptr, d.name_len);
		};

		// Track slice variables for proper indexing
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TSLICE) {
			add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
		};
		// Also track variables initialized from slice expressions (e.g., let s = arr[..])
		if (d.init != null && (*unwrap(d.init)).kind == node_kind::N_SLICE) {
			add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
			// Track the element type from the base array/slice
			let slice_init = (*unwrap(d.init)).data: *n_slice_data;
			let slice_base = slice_init.base;
			if (slice_base.kind == node_kind::N_ID) {
				let base_id = slice_base.data: *n_id_data;
				// Check if base is an array - get element type from arr_elem_types
				let arr_elem_ptr = get_variant_type(&ctx.arr_elem_types, base_id.ptr, base_id.length);
				if (arr_elem_ptr != null) {
					let arr_elem_len = get_variant_type_len(&ctx.arr_elem_types, base_id.ptr, base_id.length);
					add_variant_binding(&ctx.slice_elem_types, d.name_ptr, d.name_len, unwrap_u8(arr_elem_ptr), arr_elem_len);
				} else {
					// Check if base is a slice - get element type from slice_elem_types
					let slice_elem_ptr = get_variant_type(&ctx.slice_elem_types, base_id.ptr, base_id.length);
					if (slice_elem_ptr != null) {
						let slice_elem_len = get_variant_type_len(&ctx.slice_elem_types, base_id.ptr, base_id.length);
						add_variant_binding(&ctx.slice_elem_types, d.name_ptr, d.name_len, unwrap_u8(slice_elem_ptr), slice_elem_len);
					};
				};
			};
		};

		// Track array variables for slice conversion (buf[..0] syntax)
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TARR) {
			add_tracked_var(&ctx.arr_vars, d.name_ptr, d.name_len);
			// Also track the element type for correct slice type generation
			let arrd = (*unwrap(typ)).data: *n_tarr_data;
			if (arrd.elem != null) {
				let elem = arrd.elem;
				// For primitive or custom type elements, store the type name
				if (elem.kind == node_kind::N_TPRIM || elem.kind == node_kind::N_TALIAS) {
					let elemd = elem.data: *n_id_data;
					add_variant_binding(&ctx.arr_elem_types, d.name_ptr, d.name_len, elemd.ptr, elemd.length);
				};
			};
		};

		// Track pointer variables for -> field access
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPTR) {
			add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
		};

		// Track variable types from explicit type annotations
		// This is needed for `is` operator and match case resolution
		if (typ != null) {
			add_var_type(ctx, d.name_ptr, d.name_len, unwrap(typ));
			track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, typ);
		};

		let has_explicit_type = typ != null;

		// Track variables initialized from pointer-returning function calls
		// Also track variable types from function call initializers
			if (d.init != null) {
				let init = unwrap(d.init);
			if (has_explicit_type && is_strings_dup_call(ctx, init) && !is_tagged_union_type(ctx, unwrap(typ))) {
				emit_error_at_node(ctx, init, "strings::dup() returns error type (str | !void), must unwrap or handle it");
			};
		if (!has_explicit_type) {
			// Array literal without explicit type: infer as array
			if (init.kind == node_kind::N_ARR_LIT) {
				let arr = init.data: *n_arr_lit_data;
				let elem_type = infer_arr_lit_elem_type(ctx, arr);
				match (elem_type) {
				case let et: *node =>
					let arr_type = node_new(ctx.arena, node_kind::N_TARR, size(n_tarr_data), 0, 0);
					let ad = arr_type.data: *n_tarr_data;
					ad.elem = et;
					ad.length = make_int(ctx.arena, arr.nelems: i64, 0, 0);
					ad.inferred = true;
					add_var_type(ctx, d.name_ptr, d.name_len, arr_type);
					add_tracked_var(&ctx.arr_vars, d.name_ptr, d.name_len);
					if (et.kind == node_kind::N_TPRIM || et.kind == node_kind::N_TALIAS) {
						let elemd = et.data: *n_id_data;
						add_variant_binding(&ctx.arr_elem_types, d.name_ptr, d.name_len, elemd.ptr, elemd.length);
					};
				case null => void;
				};
			};
			// Direct function call: let p = make_point(...)
			if (init.kind == node_kind::N_CALL) {
				let cd = init.data: *n_call_data;
				let func_expr = cd.func;
				if (func_expr.kind == node_kind::N_ID) {
					let func_id = func_expr.data: *n_id_data;
					if (is_tracked_var(&ctx.ptr_fns, func_id.ptr, func_id.length)) {
						add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
					};
					// Track variable type from function return type
					let fn_ret = find_fn_ret_type(ctx, func_id.ptr, func_id.length);
					if (fn_ret != null) {
						add_var_type(ctx, d.name_ptr, d.name_len, unwrap(fn_ret));
						track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, fn_ret);
						// If function returns a slice, track this variable as a slice
						if ((*unwrap(fn_ret)).kind == node_kind::N_TSLICE) {
							add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
						};
					} else {
					// Check for known library functions that return slices
					// strings::toutf8 returns []u8
					if (name_matches_module_member(ctx, func_id.ptr, func_id.length, "strings", "toutf8")) {
						add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
						// Track element type as u8
						add_variant_binding(&ctx.slice_elem_types, d.name_ptr, d.name_len,
							strings::toutf8("u8"): *[*]u8: *u8, 2);
					};
					// strings::fromutf8_unsafe returns str
					if (name_matches_module_member(ctx, func_id.ptr, func_id.length, "strings", "fromutf8_unsafe")) {
						add_str_var(&ctx.str_vars, d.name_ptr, d.name_len);
					};
				};
			};
			};
			// Unwrapped alloc: let p = alloc(...)!
			if (init.kind == node_kind::N_UNWRAP) {
				let ud = init.data: *n_prop_data;
				if ((*(ud.expr)).kind == node_kind::N_ALLOC) {
					add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
				};
			};
			// Unwrap/propagate results: infer success type for tracking
			if (init.kind == node_kind::N_UNWRAP || init.kind == node_kind::N_PROP) {
				let inferred = infer_expr_type(ctx, init);
				if (inferred != null) {
					add_var_type(ctx, d.name_ptr, d.name_len, unwrap(inferred));
					track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, inferred);
					if ((*unwrap(inferred)).kind == node_kind::N_TSLICE) {
						add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
					};
					if (is_str_type(inferred)) {
						add_str_var(&ctx.str_vars, d.name_ptr, d.name_len);
					};
				};
			};
			// Cast expression: let n = expr: *tnode
			if (init.kind == node_kind::N_CAST) {
				let castd = init.data: *n_cast_data;
				let target_type = castd.target;
				// Track variable type from cast target type
				add_var_type(ctx, d.name_ptr, d.name_len, target_type);
				track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, target_type);
				// If cast to pointer, track as pointer variable
				if (target_type.kind == node_kind::N_TPTR) {
					add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
				};
				// If cast to slice, track as slice variable
				if (target_type.kind == node_kind::N_TSLICE) {
					add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
				};
			};
			// Simple identifier: let t = other_var (copy type from source var)
			if (init.kind == node_kind::N_ID) {
				let src_id = init.data: *n_id_data;
				let src_type = find_var_type(ctx, src_id.ptr, src_id.length);
				if (src_type != null) {
					add_var_type(ctx, d.name_ptr, d.name_len, unwrap(src_type));
					track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, src_type);
					// If source is a pointer, track destination as pointer too
					if ((*unwrap(src_type)).kind == node_kind::N_TPTR) {
						add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
					};
					// If source is a slice, track destination as slice too
					if ((*unwrap(src_type)).kind == node_kind::N_TSLICE) {
						add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
					};
				} else {
					// Enum constant initializer: infer enum type from prefix
					for (let i = 0z; i < ctx.enum_types.count; i += 1) {
						let enum_ptr = ctx.enum_types.names[i];
						let enum_bytes = enum_ptr: *[*]u8;
						let enum_len = ctx.enum_types.lengths[i];
						let src_bytes = src_id.ptr: *[*]u8;
						if (src_id.length > enum_len + 1 && src_bytes[enum_len] == '_') {
							let matched = true;
							for (let j = 0z; j < enum_len; j += 1) {
								if (src_bytes[j] != enum_bytes[j]) {
									matched = false;
								};
							};
							if (matched) {
								let type_node = node_new(ctx.arena, node_kind::N_TPRIM, size(n_id_data), 0, 0);
								let tdata = type_node.data: *n_id_data;
								tdata.ptr = enum_ptr;
								tdata.length = enum_len;
								add_var_type(ctx, d.name_ptr, d.name_len, type_node);
								break;
							};
						};
					};
				};
			};
			// Field access: let last = c.last (infer type from field)
			if (init.kind == node_kind::N_FLD) {
				let fld_type = infer_expr_type(ctx, init);
				if (fld_type != null) {
					add_var_type(ctx, d.name_ptr, d.name_len, unwrap(fld_type));
					track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, fld_type);
					// If field is a pointer, track as pointer variable
					if ((*unwrap(fld_type)).kind == node_kind::N_TPTR) {
						add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
					};
					// If field is a slice, track as slice variable
					if ((*unwrap(fld_type)).kind == node_kind::N_TSLICE) {
						add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
					};
				};
			};
			// Match expression: let p = match (...) { case *T => ...; }
			// Infer type from the non-null case in nullable pointer match
			if (init.kind == node_kind::N_MATCH) {
				let md = init.data: *n_match_data;
				// Look for non-null pointer case
				for (let j = 0z; j < md.ncases; j += 1) {
					let c: *node = md.cases[j];
					let mcd = c.data: *n_mcase_data;
					if (mcd.typ != null) {
						let ctyp = unwrap(mcd.typ);
						// Skip null case and catch-all
						if (ctyp.kind == node_kind::N_TPTR ||
						    ctyp.kind == node_kind::N_TPRIM ||
						    ctyp.kind == node_kind::N_TALIAS) {
							add_var_type(ctx, d.name_ptr, d.name_len, ctyp);
							track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, ctyp);
							if (ctyp.kind == node_kind::N_TPTR) {
								add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
							};
							break;
						};
					};
				};
			};
			// Index expression: let field = st.fields[i] (infer type from array element)
			if (init.kind == node_kind::N_IDX) {
				let idx_type = infer_expr_type(ctx, init);
				if (idx_type != null) {
					add_var_type(ctx, d.name_ptr, d.name_len, unwrap(idx_type));
					track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, idx_type);
					// If element is a pointer, track as pointer variable
					if ((*unwrap(idx_type)).kind == node_kind::N_TPTR) {
						add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
					};
					// If element is a slice, track as slice variable
					if ((*unwrap(idx_type)).kind == node_kind::N_TSLICE) {
						add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
					};
				};
			};
			// Unary expression: let p = &arr[0] (infer pointer type)
			if (init.kind == node_kind::N_UN) {
				let un_type = infer_expr_type(ctx, init);
				if (un_type != null) {
					add_var_type(ctx, d.name_ptr, d.name_len, unwrap(un_type));
					track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, un_type);
					// If result is a pointer, track as pointer variable
					if ((*unwrap(un_type)).kind == node_kind::N_TPTR) {
						add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
					};
				};
			};
			// Struct literal: let a = arena { ... } (register type from typedef lookup)
			if (init.kind == node_kind::N_STRUCT_LIT) {
				let sld = init.data: *n_struct_lit_data;
				if (sld.type_name_len > 0) {
					match (sld.type_name_ptr) {
					case let ptr: *u8 =>
						// Look up the typedef to get the struct type definition
						let typ_def = find_typedef(ctx, ptr, sld.type_name_len);
						if (typ_def != null) {
							add_var_type(ctx, d.name_ptr, d.name_len, unwrap(typ_def));
						};
					case null =>
						void;
					};
				};
			};
			};
		};

		// Nullable pointer safety check for let initialization
		if (typ != null) {
			check_nonnull_assignment(ctx, unwrap(typ), d.init, d.name_ptr, d.name_len);
		};

		// Handle slice types with N_SLICE initializers (array-to-slice conversion)
		// Use the correct element type from the slice type annotation
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TSLICE &&
		    d.init != null && (*unwrap(d.init)).kind == node_kind::N_SLICE) {
			let st = (*unwrap(typ)).data: *n_tarr_data;
			let slice_expr = (*unwrap(d.init)).data: *n_slice_data;

			// Emit: hare_slice_<elem> name = ((hare_slice_<elem>){.data = (<elem>*)(arr) + start, ...});
			emit_type(ctx, unwrap(typ));
			strbuf_append(sb, " ");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			strbuf_append(sb, " = ((");
			emit_type(ctx, unwrap(typ));
			strbuf_append(sb, "){.data = (");
			emit_type(ctx, st.elem);
			strbuf_append(sb, "*)(");
			emit_node(ctx, slice_expr.base);
			strbuf_append(sb, ") + ");
			if (slice_expr.start != null) {
				emit_node(ctx, unwrap(slice_expr.start));
			} else {
				strbuf_append(sb, "0");
			};
			strbuf_append(sb, ", .len = ");
			if (slice_expr.end != null) {
				emit_node(ctx, unwrap(slice_expr.end));
			} else {
				strbuf_append(sb, "(sizeof(");
				emit_node(ctx, slice_expr.base);
				strbuf_append(sb, ")/sizeof((");
				emit_node(ctx, slice_expr.base);
				strbuf_append(sb, ")[0]))");
			};
			strbuf_append(sb, " - ");
			if (slice_expr.start != null) {
				emit_node(ctx, unwrap(slice_expr.start));
			} else {
				strbuf_append(sb, "0");
			};
			// For capacity: check if base is pointer to unbounded array
			// If so, use end-start (no sizeof available for pointers)
			let is_ptr_to_uarr = false;
			let base_type = infer_expr_type(ctx, slice_expr.base);
			match (base_type) {
			case let bt: *node =>
				if (bt.kind == node_kind::N_TPTR) {
					let pd = bt.data: *n_tptr_data;
					if ((*(pd.inner)).kind == node_kind::N_TARR) {
						let ad = (*(pd.inner)).data: *n_tarr_data;
						if (ad.length == null) {
							is_ptr_to_uarr = true;
						};
					};
				};
			case null => void;
			};

			strbuf_append(sb, ", .cap = ");
			if (is_ptr_to_uarr) {
				// Pointer to unbounded array: capacity = end - start
				if (slice_expr.end != null) {
					emit_node(ctx, unwrap(slice_expr.end));
				} else {
					strbuf_append(sb, "0");
				};
				strbuf_append(sb, " - ");
				if (slice_expr.start != null) {
					emit_node(ctx, unwrap(slice_expr.start));
				} else {
					strbuf_append(sb, "0");
				};
			} else {
				// Array: capacity = sizeof(arr)/sizeof(arr[0]) - start
				strbuf_append(sb, "(sizeof(");
				emit_node(ctx, slice_expr.base);
				strbuf_append(sb, ")/sizeof((");
				emit_node(ctx, slice_expr.base);
				strbuf_append(sb, ")[0])) - ");
				if (slice_expr.start != null) {
					emit_node(ctx, unwrap(slice_expr.start));
				} else {
					strbuf_append(sb, "0");
				};
			};
			strbuf_append(sb, "});");
			return;
		};

		// Handle slice types with array literal initializers specially
		// Generates: elem __name_data[] = { ... }; slice_type name = {.data = __name_data, .len = N, .cap = N};
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TSLICE &&
		    d.init != null && (*unwrap(d.init)).kind == node_kind::N_ARR_LIT) {
			let st = (*unwrap(typ)).data: *n_tarr_data;  // Reuse n_tarr_data for elem
			let arr = (*unwrap(d.init)).data: *n_arr_lit_data;

			// For empty slice literals [], use NULL data for growable dynamic slices
			if (arr.nelems == 0) {
				emit_type(ctx, unwrap(typ));
				strbuf_append(sb, " ");
				strbuf_append_bytes(sb, d.name_ptr, d.name_len);
				strbuf_append(sb, " = {.data = NULL, .len = 0, .cap = 0};");
				return;
			};

			// Emit backing array: elem __name_data[] = { ... };
			emit_type(ctx, st.elem);
			strbuf_append(sb, " __");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			strbuf_append(sb, "_data[] = { ");
			for (let i = 0z; i < arr.nelems; i += 1) {
				if (i > 0) {
					strbuf_append(sb, ", ");
				};
				emit_node(ctx, arr.elems[i]);
			};
			strbuf_append(sb, " };\n    ");

			// Emit slice struct: slice_type name = {.data = __name_data, .len = N, .cap = N};
			emit_type(ctx, unwrap(typ));
			strbuf_append(sb, " ");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			strbuf_append(sb, " = {.data = __");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			strbuf_append(sb, "_data, .len = ");
			strbuf_append_uint(sb, arr.nelems);
			strbuf_append(sb, ", .cap = ");
			strbuf_append_uint(sb, arr.nelems);
			strbuf_append(sb, "};");
			return;
		};

		// Handle slice copy allocation: let dst: []T = alloc(src...)!
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TSLICE &&
		    d.init != null && (*unwrap(d.init)).kind == node_kind::N_UNWRAP) {
			let ud = (*unwrap(d.init)).data: *n_prop_data;
			if ((*(ud.expr)).kind == node_kind::N_ALLOC) {
				let alld = (*(ud.expr)).data: *n_alloc_data;
				if (alld.is_copy) {
					// Copy allocation: alloc(src...)!
					let st = (*unwrap(typ)).data: *n_tarr_data;  // elem type
					let src_expr = alld.expr;

					// Generate:
					// __auto_type __src = (src);
					// T* __data = rt_malloc(__src.len * sizeof(T));
					// if (__data == NULL) rt_abort_msg("out of memory");
					// for (size_t __i = 0; __i < __src.len; ++__i) __data[__i] = __src.data[__i];
					// slice_type name = { .data = __data, .len = __src.len, .cap = __src.len };

					strbuf_append(sb, "__auto_type __src_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " = (");
					emit_node(ctx, src_expr);
					strbuf_append(sb, ");\n    ");
					emit_type(ctx, st.elem);
					strbuf_append(sb, "* __data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " = rt_malloc(__src_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ".len * sizeof(");
					emit_type(ctx, st.elem);
					strbuf_append(sb, "));\n    if (__data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " == NULL) rt_abort_fixed(&__hare_file,0,0,2);\n    for (size_t __i_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " = 0; __i_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " < __src_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ".len; ++__i_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ") __data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, "[__i_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, "] = __src_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ".data[__i_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, "];\n    ");
					emit_type(ctx, unwrap(typ));
					strbuf_append(sb, " ");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " = { .data = __data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ", .len = __src_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ".len, .cap = __src_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ".len };");
					return;
				};
			};
		};

		// Handle slice allocation with capacity: let slice: []T = alloc([...], cap)!
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TSLICE &&
		    d.init != null && (*unwrap(d.init)).kind == node_kind::N_UNWRAP) {
			let ud = (*unwrap(d.init)).data: *n_prop_data;
			if ((*(ud.expr)).kind == node_kind::N_ALLOC) {
				let alld = (*(ud.expr)).data: *n_alloc_data;
				if (alld.capacity != null && (*(alld.expr)).kind == node_kind::N_ARR_LIT) {
					// Slice with capacity: alloc([...], cap)!
					let st = (*unwrap(typ)).data: *n_tarr_data;  // elem type
					let arr_lit = (*(alld.expr)).data: *n_arr_lit_data;
					let cap_expr = unwrap(alld.capacity);

					// Generate:
					// T* __data = rt_malloc(cap * sizeof(T));
					// if (__data == NULL) rt_abort_msg("out of memory");
					// __data[0] = v0; __data[1] = v1; ...
					// slice_type name = { .data = __data, .len = N, .cap = cap };

					emit_type(ctx, st.elem);
					strbuf_append(sb, "* __data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " = rt_malloc((");
					emit_node(ctx, cap_expr);
					strbuf_append(sb, ") * sizeof(");
					emit_type(ctx, st.elem);
					strbuf_append(sb, "));\n    if (__data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " == NULL) rt_abort_fixed(&__hare_file,0,0,2);\n    ");

					// Copy initial values
					// Check if element type is f32 for float literal suffix
					let was_expecting_f32 = ctx.expecting_f32;
					if ((*(st.elem)).kind == node_kind::N_TPRIM) {
						let etd = (*(st.elem)).data: *n_id_data;
						let elem_str = strings::fromutf8_unsafe((etd.ptr: *[*]u8)[..etd.length]);
						if (elem_str == "f32") {
							ctx.expecting_f32 = true;
						};
					};
					for (let i = 0z; i < arr_lit.nelems; i += 1) {
						strbuf_append(sb, "__data_");
						strbuf_append_bytes(sb, d.name_ptr, d.name_len);
						strbuf_append(sb, "[");
						strbuf_append_uint(sb, i);
						strbuf_append(sb, "] = ");
						emit_node(ctx, arr_lit.elems[i]);
						strbuf_append(sb, ";\n    ");
					};
					ctx.expecting_f32 = was_expecting_f32;

					emit_type(ctx, unwrap(typ));
					strbuf_append(sb, " ");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, " = { .data = __data_");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ", .len = ");
					strbuf_append_uint(sb, arr_lit.nelems);
					strbuf_append(sb, ", .cap = ");
					emit_node(ctx, cap_expr);
					strbuf_append(sb, " };");
					return;
				};
			};
		};

		// Handle function pointer types: *fn(params) ret -> ret (*name)(params)
		// For const: ret (*const name)(params)
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPTR) {
			let pd = (*unwrap(typ)).data: *n_tptr_data;
			if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TFUNC) {
				let fd = (*(pd.inner)).data: *n_tfunc_data;
				// Emit: ret_type (*name)(param_types) or ret_type (*const name)(param_types)
				emit_type(ctx, fd.ret_type);
				if (d.is_mut) {
					strbuf_append(sb, " (*");
				} else {
					strbuf_append(sb, " (*const ");
				};
				strbuf_append_bytes(sb, d.name_ptr, d.name_len);
				strbuf_append(sb, ")(");
				if (fd.nparams == 0) {
					strbuf_append(sb, "void");
				} else {
					for (let i = 0z; i < fd.nparams; i += 1) {
						if (i > 0) {
							strbuf_append(sb, ", ");
						};
						let param = fd.params[i];
						let fpd = param.data: *n_param_data;
						emit_type(ctx, fpd.typ);
					};
				};
				strbuf_append(sb, ")");
				if (d.init != null) {
					strbuf_append(sb, " = ");
					emit_init_expr(ctx, unwrap(d.init), typ);
				};
				strbuf_append(sb, ";");
				return;
			};
		};

		// Handle pointer-to-array types specially: *[N]T -> T (*name)[N]
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPTR) {
			let pd = (*unwrap(typ)).data: *n_tptr_data;
			if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TARR) {
				let ad = (*(pd.inner)).data: *n_tarr_data;
				if (ad.length != null) {
					// Check for alloc([0...])! pattern - use rt_calloc for zero-fill arrays
					let use_calloc = false;
					if (d.init != null) {
						let init = unwrap(d.init);
						// Check for unwrap (!) containing alloc with array fill literal
						if (init.kind == node_kind::N_UNWRAP) {
							let ud = init.data: *n_prop_data;
							if ((*(ud.expr)).kind == node_kind::N_ALLOC) {
								let alld = (*(ud.expr)).data: *n_alloc_data;
								if ((*(alld.expr)).kind == node_kind::N_ARR_LIT) {
									let arrl = (*(alld.expr)).data: *n_arr_lit_data;
									// Check if it's a fill literal with 0
									if (arrl.fill != null && arrl.nelems == 0) {
										let fill = unwrap(arrl.fill);
										if (fill.kind == node_kind::N_INT) {
											let fv = fill.data: *n_int_data;
											if (fv.val == 0) {
												use_calloc = true;
											};
										};
									};
								};
							};
						};
					};

					// Pointer to fixed-size array: T (*name)[N]
					emit_type(ctx, ad.elem);
					strbuf_append(sb, " (*");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ")[");
					emit_node(ctx, unwrap(ad.length));
					strbuf_append(sb, "]");

					if (use_calloc) {
						// Special case: alloc([0...])! -> rt_calloc
						strbuf_append(sb, " = rt_calloc(");
						emit_node(ctx, unwrap(ad.length));
						strbuf_append(sb, ", sizeof(");
						emit_type(ctx, ad.elem);
						strbuf_append(sb, "));");
					} else if (d.init != null) {
						strbuf_append(sb, " = ");
						emit_init_expr(ctx, unwrap(d.init), typ);
						strbuf_append(sb, ";");
					} else {
						strbuf_append(sb, ";");
					};
					return;
				};
			};
		};

		// Handle multi-level pointers to arrays: **[N]T -> T (**name)[N]
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPTR) {
			let cur = unwrap(typ);
			let ptr_depth: size = 0;
			// Count pointer levels
			for (cur.kind == node_kind::N_TPTR) {
				ptr_depth += 1;
				let pd = cur.data: *n_tptr_data;
				cur = pd.inner;
			};
			// Check if innermost type is a fixed-size array (ptr_depth > 1 to avoid single-ptr case already handled)
			if (ptr_depth > 1 && cur.kind == node_kind::N_TARR) {
				let ad = cur.data: *n_tarr_data;
				if (ad.length != null) {
					// Emit: T (**...*name)[N]
					emit_type(ctx, ad.elem);
					strbuf_append(sb, " (");
					for (let i = 0z; i < ptr_depth; i += 1) {
						strbuf_append(sb, "*");
					};
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, ")[");
					emit_node(ctx, unwrap(ad.length));
					strbuf_append(sb, "]");
					if (d.init != null) {
						strbuf_append(sb, " = ");
						emit_init_expr(ctx, unwrap(d.init), typ);
					};
					strbuf_append(sb, ";");
					return;
				};
			};
		};

		// Handle pointer to unbounded array with &arr initializer: *[*]T = &arr
		// In C, &arr has type T(*)[N], not T*. Strip the & to let array decay to pointer.
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPTR &&
		    d.init != null && (*unwrap(d.init)).kind == node_kind::N_UN) {
			let pd = (*unwrap(typ)).data: *n_tptr_data;
			if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TARR) {
				let ad = (*(pd.inner)).data: *n_tarr_data;
				if (ad.length == null) {
					// Target is *[*]T - check if init is &arr
					let ud = (*unwrap(d.init)).data: *n_un_data;
					if (ud.op == token_kind::AMP && (*(ud.operand)).kind == node_kind::N_ID) {
						// Emit: T* name = arr; (strip the &, let array decay)
						emit_type(ctx, ad.elem);
						strbuf_append(sb, "* ");
						strbuf_append_bytes(sb, d.name_ptr, d.name_len);
						strbuf_append(sb, " = ");
						emit_node(ctx, ud.operand);
						strbuf_append(sb, ";");
						return;
					};
				};
			};
		};

		// Handle simple pointer value allocation: let ptr: *T = alloc(expr)!
		// (after pointer-to-array handling, for pointer to simple types)
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPTR &&
		    d.init != null && (*unwrap(d.init)).kind == node_kind::N_UNWRAP) {
			let pd = (*unwrap(typ)).data: *n_tptr_data;
			// Skip if inner is array (already handled above)
			if (pd.inner != null && (*(pd.inner)).kind != node_kind::N_TARR) {
				let ud = (*unwrap(d.init)).data: *n_prop_data;
				if ((*(ud.expr)).kind == node_kind::N_ALLOC) {
					let alld = (*(ud.expr)).data: *n_alloc_data;
					// Only handle simple value allocation (no copy, no capacity)
					if (!alld.is_copy && alld.capacity == null) {
						let inner: *node = pd.inner;
						let expr: *node = alld.expr;

						// Skip struct literals - handled by generic emit_node
						if (expr.kind != node_kind::N_STRUCT_LIT) {
							// Generate:
							// T* name = ({ T __v = expr; T* __p = rt_malloc(sizeof(T));
							//              if (__p == NULL) rt_abort_msg("out of memory");
							//              *__p = __v; __p; });
							emit_type(ctx, inner);
							strbuf_append(sb, "* ");
							strbuf_append_bytes(sb, d.name_ptr, d.name_len);
							strbuf_append(sb, " = ({ ");
							emit_type(ctx, inner);
							strbuf_append(sb, " __v = ");
							emit_node(ctx, expr);
							strbuf_append(sb, "; ");
							emit_type(ctx, inner);
							strbuf_append(sb, "* __p = rt_malloc(sizeof(");
							emit_type(ctx, inner);
							strbuf_append(sb, ")); if (__p == NULL) rt_abort_fixed(&__hare_file,0,0,2); *__p = __v; __p; });");
							return;
						};
					};
				};
			};
		};

		// Handle array of function pointers: [N]*fn(params) ret -> ret (*name[N])(params)
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TARR) {
			let arr = (*unwrap(typ)).data: *n_tarr_data;
			if (arr.elem != null && (*(arr.elem)).kind == node_kind::N_TPTR) {
				let pd = (*(arr.elem)).data: *n_tptr_data;
				if (pd.inner != null && (*(pd.inner)).kind == node_kind::N_TFUNC) {
					let fd = (*(pd.inner)).data: *n_tfunc_data;
					// Emit: ret_type (*name[N])(param_types)
					emit_type(ctx, fd.ret_type);
					strbuf_append(sb, " (*");
					strbuf_append_bytes(sb, d.name_ptr, d.name_len);
					strbuf_append(sb, "[");
					if (arr.length != null) {
						emit_node(ctx, unwrap(arr.length));
					};
					strbuf_append(sb, "])(");
					if (fd.nparams == 0) {
						strbuf_append(sb, "void");
					} else {
						for (let i = 0z; i < fd.nparams; i += 1) {
							if (i > 0) {
								strbuf_append(sb, ", ");
							};
							let param = fd.params[i];
							let fpd = param.data: *n_param_data;
							emit_type(ctx, fpd.typ);
						};
					};
					strbuf_append(sb, ")");
					if (d.init != null) {
						strbuf_append(sb, " = ");
						emit_init_expr(ctx, unwrap(d.init), typ);
					};
					strbuf_append(sb, ";");
					return;
				};
			};
		};

		// Infer array literal types for untyped let bindings.
		let inferred_arr = false;
		let inferred_elem: nullable *node = null;
		if (typ == null && d.init != null && (*unwrap(d.init)).kind == node_kind::N_ARR_LIT) {
			let arr = (*unwrap(d.init)).data: *n_arr_lit_data;
			inferred_elem = infer_arr_lit_elem_type(ctx, arr);
			if (inferred_elem != null) {
				inferred_arr = true;
			};
		};

		// Handle array types specially: T name[N1][N2]... instead of T[N1][N2]... name
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TARR) {
			// Check for inferred size array [_]T - emit T name[]
			let first_arr = (*unwrap(typ)).data: *n_tarr_data;
			if (first_arr.inferred) {
				// Inferred size: emit T name[] = {...}
				emit_type(ctx, first_arr.elem);
				strbuf_append(sb, " ");
				strbuf_append_bytes(sb, d.name_ptr, d.name_len);
				strbuf_append(sb, "[]");
			} else {
				// Collect all array dimensions
				let dims: [8]nullable *node = [null...];
				let ndims: size = 0;
				let cur = unwrap(typ);
				for (ndims < 8 && cur.kind == node_kind::N_TARR) {
					let ad = cur.data: *n_tarr_data;
					if (ad.length != null) {
						dims[ndims] = ad.length;
						ndims += 1;
					};
					cur = ad.elem;
				};

				// Emit element type (innermost type)
				emit_type(ctx, cur);
				strbuf_append(sb, " ");
				strbuf_append_bytes(sb, d.name_ptr, d.name_len);

				// Emit all dimensions
				for (let i = 0z; i < ndims; i += 1) {
					strbuf_append(sb, "[");
					emit_node(ctx, unwrap(dims[i]));
					strbuf_append(sb, "]");
				};
			};
		} else {
			if (typ != null) {
				emit_type(ctx, unwrap(typ));
			} else if (inferred_arr && inferred_elem != null) {
				emit_type(ctx, unwrap(inferred_elem));
			} else if (d.init != null && emit_inferred_type(ctx, unwrap(d.init))) {
				// Type was inferred and emitted
				void;
			} else {
				// Fall back to __auto_type for complex expressions
				strbuf_append(sb, "__auto_type");
			};
			strbuf_append(sb, " ");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			if (inferred_arr) {
				strbuf_append(sb, "[]");
			};
		};

		if (d.init != null) {
			strbuf_append(sb, " = ");
			let init = unwrap(d.init);

			// Handle array fill patterns specially: [val...] or [a, b, c, val...]
			if (init.kind == node_kind::N_ARR_LIT && typ != null && (*unwrap(typ)).kind == node_kind::N_TARR) {
				let arr_lit = init.data: *n_arr_lit_data;
				let arr_typ = (*unwrap(typ)).data: *n_tarr_data;
				if (arr_lit.fill != null && arr_typ.length != null) {
					// We have a fill pattern and know the array size
					// Check if fill value is zero-like (0, null, false, [0...]) - C11 auto-zeros remaining elements
					let fill_node = unwrap(arr_lit.fill);
					let is_zero_fill = false;
					if (fill_node.kind == node_kind::N_INT) {
						let fd = fill_node.data: *n_int_data;
						is_zero_fill = (fd.val == 0);
					} else if (fill_node.kind == node_kind::N_BOOL) {
						// N_BOOL uses n_int_data with val=0 for false, val=1 for true
						let fd = fill_node.data: *n_int_data;
						is_zero_fill = (fd.val == 0);
					} else if (fill_node.kind == node_kind::N_NULL) {
						is_zero_fill = true;
					} else if (fill_node.kind == node_kind::N_CAST) {
						// Cast of null (e.g., null: *T) is still a zero value
						let cd = fill_node.data: *n_cast_data;
						if ((*(cd.expr)).kind == node_kind::N_NULL) {
							is_zero_fill = true;
						};
					} else if (fill_node.kind == node_kind::N_ARR_LIT) {
						// Nested array literal - check if it's also a zero fill
						let inner_arr = fill_node.data: *n_arr_lit_data;
						if (inner_arr.nelems == 0 && inner_arr.fill != null) {
							// Check inner fill
							let inner_fill = unwrap(inner_arr.fill);
							if (inner_fill.kind == node_kind::N_INT) {
								let ifd = inner_fill.data: *n_int_data;
								is_zero_fill = (ifd.val == 0);
							};
						};
					};

					strbuf_append(sb, "{");
					// Emit explicit elements first
					for (let i = 0z; i < arr_lit.nelems; i += 1) {
						if (i > 0) {
							strbuf_append(sb, ", ");
						};
						emit_node(ctx, arr_lit.elems[i]);
					};

					if (!is_zero_fill) {
						// Emit a portable fill loop instead of GNU range designators.
						if (arr_lit.nelems == 0) {
							// Ensure a non-empty initializer for C11.
							strbuf_append(sb, "0");
						};
						strbuf_append(sb, "};\n");
						strbuf_append(sb, "for (size_t __i = ");
						strbuf_append_uint(sb, arr_lit.nelems);
						strbuf_append(sb, "; __i < ");
						emit_node(ctx, unwrap(arr_typ.length));
						strbuf_append(sb, "; __i += 1) { ");
						strbuf_append_bytes(sb, d.name_ptr, d.name_len);
						strbuf_append(sb, "[__i] = ");
						emit_node(ctx, fill_node);
						strbuf_append(sb, "; }\n");
						return;
					};

					// C11: remaining elements are zero-initialized automatically
					if (arr_lit.nelems == 0) {
						// Pure zero fill: just use {0}
						strbuf_append(sb, "0");
					};
					// else: {a, b, c} - rest auto-zeros
					strbuf_append(sb, "};");
					return;
				};
			};

			// Check if type is a tagged union (non-primitive named type)
			let is_tagged = false;
			let type_name_ptr: nullable *u8 = null;
			let type_name_len: size = 0;
			if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPRIM) {
				let td = (*unwrap(typ)).data: *n_id_data;
				if (!is_primitive_type(td.ptr, td.length)) {
					is_tagged = true;
					type_name_ptr = td.ptr;
					type_name_len = td.length;
				};
			};

			if (is_tagged) {
				let name_ptr = unwrap_u8(type_name_ptr);

				// Wrap init value for tagged union
				// Check if this type is actually a tagged union (not just a type alias)
				let is_tracked_tagged = is_tracked_var(&ctx.tagged_types, name_ptr, type_name_len);

				if (init.kind == node_kind::N_VOID) {
					// void variant - definitely a tagged union
					strbuf_append(sb, "(");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "){.tag = ");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "_TAG_void}");
				} else if (is_tracked_tagged && init.kind == node_kind::N_INT) {
					// Integer literal assigned to known tagged union - wrap as int variant
					let int_name: str = "int";
					let tag_ptr: *u8 = strings::toutf8(int_name): *[*]u8: *u8;
					let tag_len: size = 3;
					let tagged_def = find_typedef(ctx, name_ptr, type_name_len);
					match (tagged_def) {
					case let tdef: *node =>
						if (tdef.kind == node_kind::N_TTAGGED) {
							let td = tdef.data: *n_ttagged_data;
							for (let vi = 0z; vi < td.nvariants; vi += 1) {
								let vnode = td.variants[vi];
								if (vnode.kind == node_kind::N_TPRIM) {
									let vnd = vnode.data: *n_id_data;
									if (is_int_like_name(vnd.ptr, vnd.length)) {
										tag_ptr = vnd.ptr;
										tag_len = vnd.length;
										break;
									};
								};
							};
						};
					case null => void;
					};
					strbuf_append(sb, "(");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "){.tag = ");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "_TAG_");
					strbuf_append_bytes(sb, tag_ptr, tag_len);
					strbuf_append(sb, ", .value._");
					strbuf_append_bytes(sb, tag_ptr, tag_len);
					strbuf_append(sb, " = (");
					emit_node(ctx, init);
					strbuf_append(sb, ")}");
				} else if (is_tracked_tagged && init.kind == node_kind::N_BOOL) {
					// Boolean literal assigned to known tagged union - wrap as bool variant
					strbuf_append(sb, "(");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "){.tag = ");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "_TAG_bool, .value._bool = (");
					emit_node(ctx, init);
					strbuf_append(sb, ")}");
				} else if (is_tracked_tagged && init.kind == node_kind::N_STR) {
					// String literal assigned to known tagged union - wrap as str variant
					strbuf_append(sb, "(");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "){.tag = ");
					strbuf_append_bytes(sb, name_ptr, type_name_len);
					strbuf_append(sb, "_TAG_str, .value._str = ");
					emit_node(ctx, init);
					strbuf_append(sb, "}");
				} else if (is_tracked_tagged && init.kind == node_kind::N_ID) {
					// Identifier assigned to known tagged union
					// Check if it's a variant type name (not a local variable)
					let id = init.data: *n_id_data;
					if (!is_tracked_var(&ctx.local_vars, id.ptr, id.length) &&
					    (!is_primitive_type(id.ptr, id.length) || is_done_name(id.ptr, id.length))) {
						let is_zero_variant = is_done_name(id.ptr, id.length);
						let is_error_alias = false;
						// Check if this identifier is a non-void error type alias
						// e.g., type invalid = !int can't be used as literal
						let type_def = find_typedef(ctx, id.ptr, id.length);
						match (type_def) {
						case let tdef: *node =>
							let resolved = resolve_type_alias(ctx, tdef);
							if (is_void_type(ctx, tdef) || is_nomem_type(tdef)) {
								is_zero_variant = true;
							};
							if (resolved.kind == node_kind::N_TERR) {
								let terr = resolved.data: *n_terr_data;
								let inner: *node = terr.inner;
								let is_void_err = false;
								if (inner.kind == node_kind::N_TPRIM) {
									let pd = inner.data: *n_id_data;
									is_void_err = streq(pd.ptr, pd.length, "void");
								};
								if (!is_void_err) {
									emit_error_at_node(ctx, init, "cannot use non-void error type alias as literal (needs a value)");
								} else {
									is_error_alias = true;
								};
							};
							case null => void;
							};
						// Likely a variant type name - wrap it
						strbuf_append(sb, "(");
						strbuf_append_bytes(sb, name_ptr, type_name_len);
						strbuf_append(sb, "){.tag = ");
						strbuf_append_bytes(sb, name_ptr, type_name_len);
						strbuf_append(sb, "_TAG_");
						strbuf_append_bytes(sb, id.ptr, id.length);
						if (!is_zero_variant) {
							strbuf_append(sb, ", .value._");
							strbuf_append_bytes(sb, id.ptr, id.length);
							strbuf_append(sb, " = ");
							if (is_error_alias) {
								strbuf_append(sb, "((");
								strbuf_append_bytes(sb, id.ptr, id.length);
								strbuf_append(sb, ")0)}");
							} else {
								strbuf_append(sb, "(");
								strbuf_append_bytes(sb, id.ptr, id.length);
								strbuf_append(sb, "){}}");
							};
						} else {
							strbuf_append(sb, "}");
						};
					} else {
						// Local variable - emit directly
						emit_node(ctx, init);
					};
				} else if (is_tracked_tagged && init.kind == node_kind::N_STRUCT_LIT) {
					let sld = init.data: *n_struct_lit_data;
					if (sld.type_name_len > 0) {
						let type_ptr = unwrap_u8(sld.type_name_ptr);
						strbuf_append_bytes(sb, name_ptr, type_name_len);
						strbuf_append(sb, "_from_");
						strbuf_append_bytes(sb, type_ptr, sld.type_name_len);
						strbuf_append(sb, "(");
						emit_node(ctx, init);
						strbuf_append(sb, ")");
					} else {
						emit_node(ctx, init);
					};
				} else if (is_tracked_tagged && init.kind == node_kind::N_UN) {
					// Unary expression with cast inside (e.g., -1: invalid parses as -(1: invalid))
					let un_init = init.data: *n_un_data;
					let inner = un_init.operand;
					if (inner.kind == node_kind::N_CAST) {
						let cast_inner = inner.data: *n_cast_data;
						let cast_target = cast_inner.target;
						if (cast_target.kind == node_kind::N_TPRIM || cast_target.kind == node_kind::N_TALIAS) {
							let target_id = cast_target.data: *n_id_data;
							// Generate: typename_from_varianttype(unary_op(value))
							strbuf_append_bytes(sb, name_ptr, type_name_len);
							strbuf_append(sb, "_from_");
							strbuf_append_bytes(sb, target_id.ptr, target_id.length);
							strbuf_append(sb, "(");
							emit_unop(sb, un_init.op);
							strbuf_append(sb, "(");
							emit_node(ctx, cast_inner.expr);
							strbuf_append(sb, "))");
						} else {
							// Fallback - emit as-is
							emit_node(ctx, init);
						};
					} else {
						// Regular unary - emit as-is
						emit_node(ctx, init);
					};
				} else if (is_tracked_tagged && init.kind == node_kind::N_CAST) {
					// Direct cast expression (e.g., 1: invalid or 0: number)
					let cast_init = init.data: *n_cast_data;
					let cast_target = cast_init.target;
					if (cast_target.kind == node_kind::N_TPRIM || cast_target.kind == node_kind::N_TALIAS) {
						let target_id = cast_target.data: *n_id_data;
						// Check if cast target is the tagged union type itself
						// (e.g., `0: number` where `number = (i32 | f32)`)
						let variant_ptr = target_id.ptr;
						let variant_len = target_id.length;
						let variant_found = false;
						let variant_node: nullable *node = null;
						// Check if target type name equals the variable type name
						let names_match = (target_id.length == type_name_len);
						if (names_match) {
							let name_bytes = name_ptr: *[*]u8;
							let target_bytes = target_id.ptr: *[*]u8;
							for (let ci = 0z; ci < type_name_len; ci += 1) {
								if (target_bytes[ci] != name_bytes[ci]) {
									names_match = false;
								};
							};
						};
						if (names_match) {
							// Cast target is the tagged union itself - need to infer variant
							// Look up the tagged union type definition
							let tagged_def = find_typedef(ctx, name_ptr, type_name_len);
							if (tagged_def != null && (*unwrap(tagged_def)).kind == node_kind::N_TTAGGED) {
								let ttd = (*unwrap(tagged_def)).data: *n_ttagged_data;
								// Infer variant based on expression type
								if (cast_init.expr.kind == node_kind::N_INT) {
									// Integer literal - find first int-like variant
									for (let vi = 0z; vi < ttd.nvariants; vi += 1) {
										let vnode = ttd.variants[vi];
										if (vnode.kind == node_kind::N_TPRIM) {
											let vnd = vnode.data: *n_id_data;
											// Check for int-like types
											if (streq(vnd.ptr, vnd.length, "int") ||
											    streq(vnd.ptr, vnd.length, "i8") ||
											    streq(vnd.ptr, vnd.length, "i16") ||
											    streq(vnd.ptr, vnd.length, "i32") ||
											    streq(vnd.ptr, vnd.length, "i64") ||
											    streq(vnd.ptr, vnd.length, "uint") ||
											    streq(vnd.ptr, vnd.length, "u8") ||
											    streq(vnd.ptr, vnd.length, "u16") ||
											    streq(vnd.ptr, vnd.length, "u32") ||
											    streq(vnd.ptr, vnd.length, "u64") ||
											    streq(vnd.ptr, vnd.length, "size") ||
											    streq(vnd.ptr, vnd.length, "uintptr")) {
												variant_ptr = vnd.ptr;
												variant_len = vnd.length;
												variant_found = true;
												variant_node = vnode;
												vi = ttd.nvariants;  // Break loop
											};
										};
									};
								} else if (cast_init.expr.kind == node_kind::N_FLOAT) {
									// Float literal - find first float-like variant
									for (let vi = 0z; vi < ttd.nvariants; vi += 1) {
										let vnode = ttd.variants[vi];
										if (vnode.kind == node_kind::N_TPRIM) {
											let vnd = vnode.data: *n_id_data;
											// Check for float-like types
											if (streq(vnd.ptr, vnd.length, "f32") ||
											    streq(vnd.ptr, vnd.length, "f64")) {
												variant_ptr = vnd.ptr;
												variant_len = vnd.length;
												variant_found = true;
												variant_node = vnode;
												vi = ttd.nvariants;  // Break loop
											};
										};
									};
								} else if (cast_init.expr.kind == node_kind::N_VOID) {
									// Void literal - find void-like variant
									for (let vi = 0z; vi < ttd.nvariants; vi += 1) {
										let vnode = ttd.variants[vi];
										if (is_void_type(ctx, vnode)) {
											if (vnode.kind == node_kind::N_TPRIM || vnode.kind == node_kind::N_TALIAS) {
												let vnd = vnode.data: *n_id_data;
												variant_ptr = vnd.ptr;
												variant_len = vnd.length;
												variant_found = true;
												variant_node = vnode;
												vi = ttd.nvariants;  // Break loop
											};
										};
									};
								} else if (cast_init.expr.kind == node_kind::N_CAST) {
									// Cast expression - use cast target as variant type
									let inner_cast = cast_init.expr.data: *n_cast_data;
									let inner_target = inner_cast.target;
									if (inner_target.kind == node_kind::N_TPRIM || inner_target.kind == node_kind::N_TALIAS) {
										let inner_id = inner_target.data: *n_id_data;
										for (let vi = 0z; vi < ttd.nvariants; vi += 1) {
											let vnode = ttd.variants[vi];
											if (vnode.kind == node_kind::N_TPRIM || vnode.kind == node_kind::N_TALIAS) {
												let vnd = vnode.data: *n_id_data;
												if (vnd.length == inner_id.length) {
													let matched = true;
													let vnd_bytes = vnd.ptr: *[*]u8;
													let inner_bytes = inner_id.ptr: *[*]u8;
													for (let j = 0z; j < vnd.length; j += 1) {
														if (vnd_bytes[j] != inner_bytes[j]) {
															matched = false;
															break;
														};
													};
													if (matched) {
														variant_ptr = vnd.ptr;
														variant_len = vnd.length;
														variant_found = true;
														variant_node = vnode;
														vi = ttd.nvariants;  // Break loop
													};
												};
											};
										};
									};
								} else if (cast_init.expr.kind == node_kind::N_STRUCT_LIT) {
									let sld = cast_init.expr.data: *n_struct_lit_data;
									if (sld.type_name_len > 0) {
										variant_ptr = unwrap_u8(sld.type_name_ptr);
										variant_len = sld.type_name_len;
										variant_found = true;
										let type_def = find_typedef(ctx, variant_ptr, variant_len);
										match (type_def) {
										case let tdef: *node => variant_node = tdef;
										case null => void;
										};
									};
								};
							};
						} else {
							// Cast target is a variant type - use it directly
							variant_found = true;
							let type_def = find_typedef(ctx, variant_ptr, variant_len);
							match (type_def) {
							case let tdef: *node => variant_node = tdef;
							case null => void;
							};
						};
						if (variant_found) {
							// Generate: typename_from_varianttype(value)
							strbuf_append_bytes(sb, name_ptr, type_name_len);
							strbuf_append(sb, "_from_");
							strbuf_append_bytes(sb, variant_ptr, variant_len);
							strbuf_append(sb, "(");
							if (!(variant_node != null &&
							      (is_void_type(ctx, unwrap(variant_node)) ||
							       is_nomem_type(unwrap(variant_node))))) {
								emit_node(ctx, cast_init.expr);
							};
							strbuf_append(sb, ")");
						} else {
							// Fallback - emit as-is if variant couldn't be inferred
							emit_node(ctx, init);
						};
					} else {
						// Fallback - emit as-is
						emit_node(ctx, init);
					};
				} else {
					// Function call or complex expression - don't wrap
					emit_node(ctx, init);
				};
			} else {
				// For slice types, set expected element type for alloc
				if (typ != null && (*unwrap(typ)).kind == node_kind::N_TSLICE) {
					let st = (*unwrap(typ)).data: *n_tarr_data;
					ctx.expected_slice_elem = st.elem;
				};
				// For f32 types, set flag for float literal suffix
				let was_expecting_f32 = ctx.expecting_f32;
				if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPRIM) {
					let td = (*unwrap(typ)).data: *n_id_data;
					let prim_str = strings::fromutf8_unsafe((td.ptr: *[*]u8)[..td.length]);
					if (prim_str == "f32") {
						ctx.expecting_f32 = true;
					};
				};
				emit_init_expr(ctx, init, typ);
				// Clear expected types after emitting
				ctx.expected_slice_elem = null;
				ctx.expecting_f32 = was_expecting_f32;
			};
		};
		strbuf_append(sb, ";");
		return;
	};

	// If
	if (k == node_kind::N_IF) {
		let d = n.data: *n_if_data;
		strbuf_append(sb, "if (");
		emit_node(ctx, d.cond);
		strbuf_append(sb, ") ");
		emit_stmt(ctx, d.then_branch);
		if (d.else_branch != null) {
			strbuf_append(sb, " else ");
			emit_stmt(ctx, unwrap(d.else_branch));
		};
		return;
	};

	// For
	if (k == node_kind::N_FOR) {
		let d = n.data: *n_for_data;

		// Collect defers from the loop body for break/continue handling
		let prev_defer_count = ctx.loop_defer_count;
		ctx.loop_defer_count = 0;
		let body: *node = d.body;
		if (body.kind == node_kind::N_BLOCK) {
			let bd = body.data: *n_block_data;
			for (let i = 0z; i < bd.nstmts && ctx.loop_defer_count < 32; i += 1) {
				let stmt: *node = bd.stmts[i];
				if (stmt.kind == node_kind::N_DEFER) {
					let dd = stmt.data: *n_defer_data;
					ctx.loop_defers[ctx.loop_defer_count] = dd.expr;
					ctx.loop_defer_count += 1;
				};
			};
		};

		// Check if loop condition compares against a size_t expression
		let bound_is_size = false;
		if (d.cond != null) {
			let cond = unwrap(d.cond);
			if (cond.kind == node_kind::N_BIN) {
				let cd = cond.data: *n_bin_data;
				let right: *node = cd.right;
				// .len, .cap, len(), size() are size_t
				if (right.kind == node_kind::N_FLD) {
					let fd = right.data: *n_fld_data;
					if (streq(fd.field_ptr, fd.field_len, "len") ||
					    streq(fd.field_ptr, fd.field_len, "cap")) {
						bound_is_size = true;
					};
				} else if (right.kind == node_kind::N_LEN) {
					bound_is_size = true;
				};
			};
		};

		strbuf_append(sb, "for (");
		if (d.init != null) {
			// Emit init without semicolon
			let init = unwrap(d.init);
			if (init.kind == node_kind::N_LET) {
				let ld = init.data: *n_let_data;
				if (ld.typ != null) {
					emit_type(ctx, unwrap(ld.typ));
				} else {
					// For loop counters: check for explicit integer suffix
					let emitted = false;
					if (ld.init != null) {
						let linit = unwrap(ld.init);
						if (linit.kind == node_kind::N_INT) {
							let id = linit.data: *n_int_data;
							if (id.suffix == 'i') {
								strbuf_append(sb, "intptr_t");
								emitted = true;
							} else if (id.suffix == 'u') {
								strbuf_append(sb, "uintptr_t");
								emitted = true;
							} else if (id.suffix == 'z' || bound_is_size) {
								// Explicit size suffix or bound is size_t
								strbuf_append(sb, "size_t");
								emitted = true;
							};
							// No suffix and bound isn't size -> fall through to intptr_t
						} else if (emit_inferred_type(ctx, linit)) {
							// Use inferred type for non-integer expressions
							emitted = true;
						};
					};
					if (!emitted) {
						// Default to intptr_t for signed loop bounds
						strbuf_append(sb, "intptr_t");
					};
				};
				strbuf_append(sb, " ");
				strbuf_append_bytes(sb, ld.name_ptr, ld.name_len);
				if (ld.init != null) {
					strbuf_append(sb, " = ");
					emit_node(ctx, unwrap(ld.init));
				};
			} else {
				emit_node(ctx, init);
			};
		};
		strbuf_append(sb, "; ");
		if (d.cond != null) {
			emit_node(ctx, unwrap(d.cond));
		};
		strbuf_append(sb, "; ");
		if (d.step != null) {
			let step = unwrap(d.step);
			// Handle assignment expressions specially (no semicolon)
			if (step.kind == node_kind::N_ASGN) {
				emit_asgn_expr(ctx, step);
			} else {
				emit_node(ctx, step);
			};
		};
		strbuf_append(sb, ") ");
		emit_stmt(ctx, d.body);

		// Restore previous defer count
		ctx.loop_defer_count = prev_defer_count;
		return;
	};

	// For-each by value: for (let x .. items) { body }
	// Generates: for (size_t __x_i = 0; __x_i < (items).len; __x_i++) { elem_type x = (items).data[__x_i]; body }
	if (k == node_kind::N_FOREACH) {
		let d = n.data: *n_foreach_data;

		// Collect defers from the loop body for break/continue handling
		let prev_defer_count = ctx.loop_defer_count;
		ctx.loop_defer_count = 0;
		let body: *node = d.body;
		if (body.kind == node_kind::N_BLOCK) {
			let bd = body.data: *n_block_data;
			for (let i = 0z; i < bd.nstmts && ctx.loop_defer_count < 32; i += 1) {
				let stmt: *node = bd.stmts[i];
				if (stmt.kind == node_kind::N_DEFER) {
					let dd = stmt.data: *n_defer_data;
					ctx.loop_defers[ctx.loop_defer_count] = dd.expr;
					ctx.loop_defer_count += 1;
				};
			};
		};

		// Infer element type from iterable
		let elem_type: nullable *node = null;
		let iter_is_slice = false;
		let iter_is_array = false;
		let iter_type = infer_expr_type(ctx, d.iterable);
		match (iter_type) {
		case let it: *node =>
			// Slice type - get element type
			if (it.kind == node_kind::N_TSLICE) {
				let sd = it.data: *n_tarr_data;
				elem_type = sd.elem;
				iter_is_slice = true;
			};
			// Array type - get element type
			if (it.kind == node_kind::N_TARR) {
				let ad = it.data: *n_tarr_data;
				elem_type = ad.elem;
				iter_is_array = true;
			};
		case null => void;
		};
		if (!iter_is_slice && !iter_is_array && d.iterable.kind == node_kind::N_ID) {
			let id = d.iterable.data: *n_id_data;
			iter_is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
			iter_is_array = is_tracked_var(&ctx.arr_vars, id.ptr, id.length);
		};
		if (!iter_is_slice && !iter_is_array) {
			iter_is_slice = true;
		};

		// Track loop variable type for field access inference
		match (elem_type) {
		case let et: *node =>
			add_var_type(ctx, d.name_ptr, d.name_len, et);
			// Track as local variable
			add_tracked_var(&ctx.local_vars, d.name_ptr, d.name_len);
			// Track str variables for len() handling
			if (et.kind == node_kind::N_TPRIM) {
				let etd = et.data: *n_id_data;
				if (streq(etd.ptr, etd.length, "str")) {
					add_str_var(&ctx.str_vars, d.name_ptr, d.name_len);
				};
			};
			// Track pointer variables for auto-dereference
			if (et.kind == node_kind::N_TPTR) {
				add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
			};
		case null => void;
		};

		strbuf_append(sb, "for (size_t __");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i = 0; __");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i < ");
		if (iter_is_array) {
			strbuf_append(sb, "HARE_ARRAY_LEN(");
			emit_node(ctx, d.iterable);
			strbuf_append(sb, ")");
		} else {
			strbuf_append(sb, "(");
			emit_node(ctx, d.iterable);
			strbuf_append(sb, ").len");
		};
		strbuf_append(sb, "; __");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i++) { ");
		// Emit correct element type (or fallback to intptr_t)
		match (elem_type) {
		case let et: *node =>
			emit_type(ctx, et);
		case null =>
			strbuf_append(sb, "intptr_t");
		};
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, " = (");
		emit_node(ctx, d.iterable);
		if (iter_is_array) {
			strbuf_append(sb, ")[__");
		} else {
			strbuf_append(sb, ").data[__");
		};
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i]; ");
		emit_stmt(ctx, d.body);
		strbuf_append(sb, " }");

		// Restore previous defer count
		ctx.loop_defer_count = prev_defer_count;
		return;
	};

	// For-each by reference: for (let ptr &.. items) { body }
	// Generates: for (size_t __ptr_i = 0; __ptr_i < (items).len; __ptr_i++) { elem_type* ptr = &(items).data[__ptr_i]; body }
	if (k == node_kind::N_FOREACH_REF) {
		let d = n.data: *n_foreach_data;

		// Collect defers from the loop body for break/continue handling
		let prev_defer_count = ctx.loop_defer_count;
		ctx.loop_defer_count = 0;
		let body: *node = d.body;
		if (body.kind == node_kind::N_BLOCK) {
			let bd = body.data: *n_block_data;
			for (let i = 0z; i < bd.nstmts && ctx.loop_defer_count < 32; i += 1) {
				let stmt: *node = bd.stmts[i];
				if (stmt.kind == node_kind::N_DEFER) {
					let dd = stmt.data: *n_defer_data;
					ctx.loop_defers[ctx.loop_defer_count] = dd.expr;
					ctx.loop_defer_count += 1;
				};
			};
		};

		// Infer element type from iterable
		let elem_type: nullable *node = null;
		let iter_is_slice = false;
		let iter_is_array = false;
		let iter_type = infer_expr_type(ctx, d.iterable);
		match (iter_type) {
		case let it: *node =>
			// Slice type - get element type
			if (it.kind == node_kind::N_TSLICE) {
				let sd = it.data: *n_tarr_data;
				elem_type = sd.elem;
				iter_is_slice = true;
			};
			// Array type - get element type
			if (it.kind == node_kind::N_TARR) {
				let ad = it.data: *n_tarr_data;
				elem_type = ad.elem;
				iter_is_array = true;
			};
		case null => void;
		};
		if (!iter_is_slice && !iter_is_array && d.iterable.kind == node_kind::N_ID) {
			let id = d.iterable.data: *n_id_data;
			iter_is_slice = is_tracked_var(&ctx.slice_vars, id.ptr, id.length);
			iter_is_array = is_tracked_var(&ctx.arr_vars, id.ptr, id.length);
		};
		if (!iter_is_slice && !iter_is_array) {
			iter_is_slice = true;
		};

		// Track loop variable as local variable (ref loops give pointer to element)
		add_tracked_var(&ctx.local_vars, d.name_ptr, d.name_len);
		// For ref loops, the variable is always a pointer (to the element)
		add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);

		strbuf_append(sb, "for (size_t __");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i = 0; __");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i < ");
		if (iter_is_array) {
			strbuf_append(sb, "HARE_ARRAY_LEN(");
			emit_node(ctx, d.iterable);
			strbuf_append(sb, ")");
		} else {
			strbuf_append(sb, "(");
			emit_node(ctx, d.iterable);
			strbuf_append(sb, ").len");
		};
		strbuf_append(sb, "; __");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i++) { ");
		// Emit correct element type pointer (or fallback to intptr_t*)
		match (elem_type) {
		case let et: *node =>
			emit_type(ctx, et);
		case null =>
			strbuf_append(sb, "intptr_t");
		};
		strbuf_append(sb, "* ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, " = &(");
		emit_node(ctx, d.iterable);
		if (iter_is_array) {
			strbuf_append(sb, ")[__");
		} else {
			strbuf_append(sb, ").data[__");
		};
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "_i]; ");
		emit_stmt(ctx, d.body);
		strbuf_append(sb, " }");

		// Restore previous defer count
		ctx.loop_defer_count = prev_defer_count;
		return;
	};

	// For-each iterator: for (let x => next()) { body }
	// Generates: for (;;) { auto __r = iter(); if (__r.tag == TAG_done) break; T x = __r.value._T; body }
	// Note: done is typically the second variant (tag 1) in (T | done) unions
	if (k == node_kind::N_FOREACH_ITER) {
		let d = n.data: *n_foreach_data;

		// Collect defers from the loop body for break/continue handling
		let prev_defer_count = ctx.loop_defer_count;
		ctx.loop_defer_count = 0;
		let body: *node = d.body;
		if (body.kind == node_kind::N_BLOCK) {
			let bd = body.data: *n_block_data;
			for (let i = 0z; i < bd.nstmts && ctx.loop_defer_count < 32; i += 1) {
				let stmt: *node = bd.stmts[i];
				if (stmt.kind == node_kind::N_DEFER) {
					let dd = stmt.data: *n_defer_data;
					ctx.loop_defers[ctx.loop_defer_count] = dd.expr;
					ctx.loop_defer_count += 1;
				};
			};
		};

		let done_tag: i64 = 1;
		let elem_type: nullable *node = null;
		let elem_variant: nullable *node = null;
		let iter_type = infer_expr_type(ctx, d.iterable);
		let tagged_type: nullable *node = null;
		match (iter_type) {
		case let it: *node =>
			let resolved = resolve_type_alias(ctx, it);
			if (resolved.kind == node_kind::N_TTAGGED) {
				tagged_type = resolved;
			};
		case null => void;
		};
		match (tagged_type) {
		case let tt: *node =>
			let td = tt.data: *n_ttagged_data;
			done_tag = -1;
			for (let i = 0z; i < td.nvariants; i += 1) {
				let variant = td.variants[i];
				let resolved = resolve_type_alias(ctx, variant);
				let is_done = false;
				if (resolved.kind == node_kind::N_TPRIM) {
					let vd = resolved.data: *n_id_data;
					is_done = streq(vd.ptr, vd.length, "done");
				};
				if (is_done) {
					done_tag = i: i64;
				} else if (elem_variant == null) {
					elem_variant = variant;
					elem_type = variant;
				};
			};
			if (done_tag < 0) {
				done_tag = 1;
			};
		case null => void;
		};

		// Track loop variable type for field access inference
		match (elem_type) {
		case let et: *node =>
			add_var_type(ctx, d.name_ptr, d.name_len, et);
			add_tracked_var(&ctx.local_vars, d.name_ptr, d.name_len);
			// Track str variables for len() handling
			if (et.kind == node_kind::N_TPRIM) {
				let etd = et.data: *n_id_data;
				if (streq(etd.ptr, etd.length, "str")) {
					add_str_var(&ctx.str_vars, d.name_ptr, d.name_len);
				};
			};
			if (et.kind == node_kind::N_TPTR) {
				add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
			};
		case null => void;
		};

		strbuf_append(sb, "for (;;) { __auto_type __iter_result = ");
		emit_node(ctx, d.iterable);
		strbuf_append(sb, "; if (__iter_result.tag == ");
		strbuf_append_int(sb, done_tag);
		strbuf_append(sb, "U) break; ");
		match (elem_type) {
		case let et: *node =>
			emit_type(ctx, et);
		case null =>
			strbuf_append(sb, "intptr_t");
		};
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, " = __iter_result.value._");
		match (elem_variant) {
		case let ev: *node =>
			emit_type_tag(sb, ev);
		case null =>
			strbuf_append(sb, "intptr_t");
		};
		strbuf_append(sb, "; ");
		emit_stmt(ctx, d.body);
		strbuf_append(sb, " }");

		// Restore previous defer count
		ctx.loop_defer_count = prev_defer_count;
		return;
	};

	// Assignment (N_ASGN)
	if (k == node_kind::N_ASGN) {
		let d = n.data: *n_asgn_data;
		let target: *node = d.target;
		let value: *node = d.value;

		// Special case: slice assignment (x[start..end] = src)
		if (target.kind == node_kind::N_SLICE && d.op == token_kind::EQ) {
			let sd = target.data: *n_slice_data;
			let base: *node = sd.base;

			// Check if base is a slice (vs array)
			let base_is_slice = false;
			if (base.kind == node_kind::N_ID) {
				let bid = base.data: *n_id_data;
				base_is_slice = is_tracked_var(&ctx.slice_vars, bid.ptr, bid.length);
			};

			// Handle array literal value: x[1..4] = [10, 20, 30]
			if (value.kind == node_kind::N_ARR_LIT) {
				let ad = value.data: *n_arr_lit_data;
				for (let i = 0z; i < ad.nelems; i += 1) {
					if (i > 0) {
						strbuf_append(sb, " ");
					};
					// Generate: base.data[start + i] = elem; (or base[start + i] for arrays)
					if (base_is_slice) {
						strbuf_append(sb, "(");
						emit_node(ctx, base);
						strbuf_append(sb, ").data[");
					} else {
						strbuf_append(sb, "(");
						emit_node(ctx, base);
						strbuf_append(sb, ")[");
					};
					if (sd.start != null) {
						emit_node(ctx, unwrap(sd.start));
						strbuf_append(sb, "+");
					};
					strbuf_append_uint(sb, i);
					strbuf_append(sb, "] = ");
					emit_node(ctx, ad.elems[i]);
					strbuf_append(sb, ";");
				};
				return;
			};

			// Handle slice value: x[2..8] = other_slice
			// Generate: rt_slice_assign(base, start, end, src);
			strbuf_append(sb, "rt_slice_assign(");
			emit_node(ctx, base);
			strbuf_append(sb, ", ");
			if (sd.start != null) {
				emit_node(ctx, unwrap(sd.start));
			} else {
				strbuf_append(sb, "0");
			};
			strbuf_append(sb, ", ");
			if (sd.end != null) {
				emit_node(ctx, unwrap(sd.end));
			} else {
				// Full length
				if (base_is_slice) {
					strbuf_append(sb, "(");
					emit_node(ctx, base);
					strbuf_append(sb, ").len");
				} else {
					strbuf_append(sb, "HARE_ARRAY_LEN(");
					emit_node(ctx, base);
					strbuf_append(sb, ")");
				};
			};
			strbuf_append(sb, ", ");
			emit_node(ctx, value);
			strbuf_append(sb, ");");
			return;
		};

		// Nullable pointer safety check for regular assignment (= operator only)
		// Only check identifier assignments - field type inference is not reliable enough
			if (d.op == token_kind::EQ && target.kind == node_kind::N_ID) {
				let tid = target.data: *n_id_data;
				let target_ty = find_var_type(ctx, tid.ptr, tid.length);
				if (target_ty != null && is_strings_dup_call(ctx, value) && !is_tagged_union_type(ctx, unwrap(target_ty))) {
					emit_error_at_node(ctx, value, "strings::dup() returns error type (str | !void), must unwrap or handle it");
				};
				check_nonnull_assignment(ctx, target_ty, value, tid.ptr, tid.length);
			};

		// Regular assignment
		// If target contains indexed expressions, emit bounds checks first
		if (contains_idx_node(target)) {
			emit_lvalue_bounds_checks(ctx, target);
			ctx.in_lvalue = true;
			emit_node(ctx, target);
			ctx.in_lvalue = false;
		} else {
			emit_node(ctx, target);
		};
		strbuf_append(sb, " ");
		emit_asgn_op(sb, d.op);
		strbuf_append(sb, " ");
		// Hint f32 context for float literals on RHS.
		let want_f32 = false;
		let target_type = infer_expr_type(ctx, target);
		match (target_type) {
		case let tt: *node =>
			if (tt.kind == node_kind::N_TPRIM) {
				let td = tt.data: *n_id_data;
				if (type_is(td.ptr, td.length, "f32")) {
					want_f32 = true;
				};
			};
		case null => void;
		};
		let prev_expect_f32 = ctx.expecting_f32;
		if (want_f32) {
			ctx.expecting_f32 = true;
		};
		emit_node(ctx, value);
		ctx.expecting_f32 = prev_expect_f32;
		strbuf_append(sb, ";");
		return;
	};

	// Expression statement (N_EXPR)
		if (k == node_kind::N_EXPR) {
			// N_EXPR wraps an expression - result is not used
			let d = n.data: *n_ret_data;
			let expr = unwrap(d.expr);
			// Check for append/insert without ! - these return error types in Hare
			if (expr.kind == node_kind::N_APPEND) {
				emit_error_at_node(ctx, expr, "append() returns error type, must use append()! to unwrap");
			};
			if (expr.kind == node_kind::N_INSERT) {
				emit_error_at_node(ctx, expr, "insert() returns error type, must use insert()! to unwrap");
			};
			if (is_strings_dup_call(ctx, expr)) {
				emit_error_at_node(ctx, expr, "strings::dup() returns error type (str | !void), must unwrap or handle it");
			};
		let was_result_used = ctx.result_used;
		ctx.result_used = false;
		if (expr.kind == node_kind::N_ASSERT) {
			emit_node(ctx, expr);
		} else {
			strbuf_append(sb, "(void)(");
			emit_node(ctx, expr);
			strbuf_append(sb, ")");
		};
		ctx.result_used = was_result_used;
		strbuf_append(sb, ";");
		return;
	};

	// Break - emit loop defers first
	if (k == node_kind::N_BREAK) {
		if (ctx.loop_defer_count > 0) {
			strbuf_append(sb, "{ ");
			// Emit defers in reverse order
			let idx = ctx.loop_defer_count;
			for (idx > 0) {
				idx -= 1;
				let defer_expr = ctx.loop_defers[idx];
				emit_node(ctx, defer_expr);
				strbuf_append(sb, "; ");
			};
			strbuf_append(sb, "break; }");
		} else {
			strbuf_append(sb, "break;");
		};
		return;
	};

	// Continue - emit loop defers first
	if (k == node_kind::N_CONT) {
		if (ctx.loop_defer_count > 0) {
			strbuf_append(sb, "{ ");
			// Emit defers in reverse order
			let idx = ctx.loop_defer_count;
			for (idx > 0) {
				idx -= 1;
				let defer_expr = ctx.loop_defers[idx];
				emit_node(ctx, defer_expr);
				strbuf_append(sb, "; ");
			};
			strbuf_append(sb, "continue; }");
		} else {
			strbuf_append(sb, "continue;");
		};
		return;
	};

	// Switch
	if (k == node_kind::N_SWITCH) {
		let d = n.data: *n_switch_data;

		// Check if switch expression is a tagged union (should use match instead)
		let switch_type = infer_expr_type(ctx, d.expr);
		match (switch_type) {
		case let st: *node =>
			// Check if it's a type alias that is a tracked tagged union
				if (st.kind == node_kind::N_TPRIM || st.kind == node_kind::N_TALIAS) {
					let td = st.data: *n_id_data;
					if (is_tracked_var(&ctx.tagged_types, td.ptr, td.length)) {
						emit_error_at_node(ctx, d.expr, "cannot switch on tagged union; use match");
					};
				};
				// Also check for inline tagged union types
				if (st.kind == node_kind::N_TTAGGED) {
					emit_error_at_node(ctx, d.expr, "cannot switch on tagged union; use match");
				};
		case null => void;
		};

		// Check if this is a string switch (switch expr is str type)
		let is_str_switch = is_string_expr(ctx, d.expr);

		if (is_str_switch) {
			// String switch - emit as if-else chain with rt_strcmp
			strbuf_append(sb, "({\n");
			strbuf_append(sb, "    intptr_t __r = 0;\n");
			strbuf_append(sb, "    hare_str __sw = ");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ";\n");

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
				strbuf_append(sb, "        __r = ");
				if ((*unwrap(cd.body)).kind == node_kind::N_BLOCK) {
					let bd = (*unwrap(cd.body)).data: *n_block_data;
					if (bd.nstmts > 0) {
						emit_node(ctx, bd.stmts[0]);
					} else {
						strbuf_append(sb, "0");
					};
				} else {
					emit_node(ctx, cd.body);
				};
				strbuf_append(sb, ";\n");
				strbuf_append(sb, "    }\n");
			};

			if (ctx.result_used) {
				strbuf_append(sb, "    __r;\n");
			} else {
				strbuf_append(sb, "    (void)0;\n");
			};
			strbuf_append(sb, "});");
			return;
		};

		// Determine if switch is expression-style (case bodies yield values)
		// or statement-style (case bodies are statements with side effects)
		let is_expression_switch = true;
		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_case_data;
			let body: *node = cd.body;
			// If case body is a block with assignment or statement nodes, it's statement-style
			if (body.kind == node_kind::N_BLOCK) {
				let bd = body.data: *n_block_data;
				if (bd.nstmts == 0) {
					// Empty block is statement-style (no value)
					is_expression_switch = false;
				} else {
					let first_stmt = bd.stmts[0];
					// Assignment, let, return, call, if, for statements indicate statement-style
					if (first_stmt.kind == node_kind::N_ASGN ||
					    first_stmt.kind == node_kind::N_LET ||
					    first_stmt.kind == node_kind::N_RET ||
					    first_stmt.kind == node_kind::N_CALL ||
					    first_stmt.kind == node_kind::N_IF ||
					    first_stmt.kind == node_kind::N_FOR ||
					    first_stmt.kind == node_kind::N_FOREACH ||
					    first_stmt.kind == node_kind::N_FOREACH_REF ||
					    first_stmt.kind == node_kind::N_FOREACH_ITER ||
					    first_stmt.kind == node_kind::N_MATCH ||
					    first_stmt.kind == node_kind::N_SWITCH ||
					    first_stmt.kind == node_kind::N_EXPR) {
						is_expression_switch = false;
					};
				};
			} else if (body.kind == node_kind::N_RET) {
				// Direct return statement - statement-style
				is_expression_switch = false;
			} else if (body.kind == node_kind::N_EXPR) {
				// N_EXPR wrapping a statement - check inner expression
				let ed = body.data: *n_ret_data;
				let inner = unwrap(ed.expr);
				if (inner.kind == node_kind::N_RET ||
				    inner.kind == node_kind::N_ASGN ||
				    inner.kind == node_kind::N_LET) {
					is_expression_switch = false;
				};
			};
		};

		if (is_expression_switch) {
			// Expression-style switch - emit as statement expression to capture value
			strbuf_append(sb, "({\n");
			strbuf_append(sb, "    __auto_type __s = (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ");\n");
			strbuf_append(sb, "    intptr_t __r = 0;\n");
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

				// Emit body - capture value in __r
				strbuf_append(sb, "        __r = ");
				if ((*unwrap(cd.body)).kind == node_kind::N_BLOCK) {
					// Block - extract first statement value
					let bd = (*unwrap(cd.body)).data: *n_block_data;
					if (bd.nstmts > 0) {
						emit_node(ctx, bd.stmts[0]);
					} else {
						strbuf_append(sb, "0");
					};
				} else if ((*unwrap(cd.body)).kind == node_kind::N_EXPR) {
					// Expression statement - extract inner expression
					let ed = (*unwrap(cd.body)).data: *n_ret_data;  // N_EXPR reuses ret data
					emit_node(ctx, ed.expr);
				} else {
					// Single expression
					emit_node(ctx, cd.body);
				};
				strbuf_append(sb, ";\n    } break;\n");
			};

			strbuf_append(sb, "    }\n");
			if (ctx.result_used) {
				strbuf_append(sb, "    __r;\n");
			} else {
				strbuf_append(sb, "    (void)0;\n");
			};
			strbuf_append(sb, "});");
		} else {
			// Statement-style switch - emit as regular C switch
			strbuf_append(sb, "switch (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ") {\n");

			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_case_data;

				if (cd.nvalues == 0) {
					// Default case
					strbuf_append(sb, "    default:");
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
				};

				// Emit body as statement
				strbuf_append(sb, " ");
				emit_stmt(ctx, cd.body);
				strbuf_append(sb, " break;\n");
			};

			strbuf_append(sb, "}");
		};
		return;
	};

	// Yield
	if (k == node_kind::N_YIELD) {
		let d = n.data: *n_yield_data;
		// Yield assigns to __r when in match context, otherwise it's a no-op
		// Since we can't track context easily, emit conditional code
		if (d.expr != null) {
			// Non-void yield - emit as expression statement
			// In match context, the match handler will handle this
			emit_node(ctx, unwrap(d.expr));
			strbuf_append(sb, ";");
		} else {
			// void yield - emit as comment (no-op)
			strbuf_append(sb, "/* yield */;");
		};
		return;
	};

	// Match
	if (k == node_kind::N_MATCH) {
		let d = n.data: *n_match_data;

		// Check if this is nullable pointer matching (has null case)
		let is_nullable_match = false;
		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_mcase_data;
			if (cd.typ != null && ((*unwrap(cd.typ)).kind == node_kind::N_NULL)) {
				is_nullable_match = true;
			};
		};

		// Determine if match is expression-style (case bodies yield values)
		// or statement-style (case bodies are statements with side effects)
		let is_expression_match = true;
		for (let i = 0z; i < d.ncases; i += 1) {
			let c: *node = d.cases[i];
			let cd = c.data: *n_mcase_data;
			let body: *node = cd.body;
			// If case body is a block with assignment or statement nodes, it's statement-style
			if (body.kind == node_kind::N_BLOCK) {
				let bd = body.data: *n_block_data;
				if (bd.nstmts == 0) {
					// Empty block is statement-style (no value)
					is_expression_match = false;
				} else {
					let first_stmt = bd.stmts[0];
					// Assignment, let, return, call, if, for statements indicate statement-style
					if (first_stmt.kind == node_kind::N_ASGN ||
					    first_stmt.kind == node_kind::N_LET ||
					    first_stmt.kind == node_kind::N_RET ||
					    first_stmt.kind == node_kind::N_CALL ||
					    first_stmt.kind == node_kind::N_IF ||
					    first_stmt.kind == node_kind::N_FOR ||
					    first_stmt.kind == node_kind::N_FOREACH ||
					    first_stmt.kind == node_kind::N_FOREACH_REF ||
					    first_stmt.kind == node_kind::N_FOREACH_ITER ||
					    first_stmt.kind == node_kind::N_MATCH ||
					    first_stmt.kind == node_kind::N_SWITCH ||
					    first_stmt.kind == node_kind::N_EXPR) {
						is_expression_match = false;
					};
				};
			};
		};

		if (is_expression_match) {
			strbuf_append(sb, "({\n");
			strbuf_append(sb, "    __auto_type __m = (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ");\n");
			strbuf_append(sb, "    intptr_t __r = 0;\n");
		} else {
			// Statement-style match - no __r needed
			strbuf_append(sb, "{ __auto_type __m = (");
			emit_node(ctx, d.expr);
			strbuf_append(sb, ");\n");
		};

		if (is_nullable_match) {
			// Nullable pointer matching - generate if/else
			// Find null case and non-null case first (order in source doesn't matter)
			let null_case: nullable *node = null;
			let ptr_case: nullable *node = null;
			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_mcase_data;
				if (cd.typ != null && ((*unwrap(cd.typ)).kind == node_kind::N_NULL)) {
					null_case = c;
				} else if (cd.typ == null) {
					// Catch-all case acts as non-null case
					if (ptr_case == null) {
						ptr_case = c;
					};
				} else {
					ptr_case = c;
				};
			};

			// Emit null case first: if (__m == NULL) { ... }
			if (null_case != null) {
				let ncd = (*unwrap(null_case)).data: *n_mcase_data;
				strbuf_append(sb, "    if (__m == NULL) {\n");
				strbuf_append(sb, "        ");
				emit_match_case_body(ctx, ncd.body, is_expression_match);
				strbuf_append(sb, "\n");
				strbuf_append(sb, "    }");
			};

			// Emit non-null case: else { ... }
			if (ptr_case != null) {
				let pcd = (*unwrap(ptr_case)).data: *n_mcase_data;
				if (null_case != null) {
					strbuf_append(sb, " else {\n");
				} else {
					strbuf_append(sb, "    {\n");
				};
				if (pcd.bind_ptr != null && pcd.bind_len > 0 && pcd.typ != null) {
					match (pcd.bind_ptr) {
					case let bind_ptr: *u8 =>
						strbuf_append(sb, "        ");
						emit_type(ctx, unwrap(pcd.typ));
						strbuf_append(sb, " __attribute__((unused)) ");
						strbuf_append_bytes(sb, bind_ptr, pcd.bind_len);
						strbuf_append(sb, " = __m;\n");
						add_var_type(ctx, bind_ptr, pcd.bind_len, unwrap(pcd.typ));
					case null =>
						void;
					};
				};
				strbuf_append(sb, "        ");
				// Track narrowed nullable pointer for compile-time safety checks
				let prev_narrowed_ptr = ctx.narrowed_nullable_ptr;
				let prev_narrowed_len = ctx.narrowed_nullable_len;
				if ((*(d.expr)).kind == node_kind::N_ID) {
					let matched_id = (*(d.expr)).data: *n_id_data;
					ctx.narrowed_nullable_ptr = matched_id.ptr;
					ctx.narrowed_nullable_len = matched_id.length;
				};
				emit_match_case_body(ctx, pcd.body, is_expression_match);
				// Restore narrowed nullable tracking
				ctx.narrowed_nullable_ptr = prev_narrowed_ptr;
				ctx.narrowed_nullable_len = prev_narrowed_len;
				strbuf_append(sb, "\n");
				strbuf_append(sb, "    }\n");
			} else if (null_case != null) {
				strbuf_append(sb, "\n");
			};
		} else {
			// Tagged union matching - switch on tag
			strbuf_append(sb, "    switch (__m.tag) {\n");

			// Get the tagged union type for proper tag index lookup
			// This avoids issues with TAG_xxx macro conflicts across different unions
			let matched_type: nullable *node = null;
			let match_expr: *node = d.expr;
			if (match_expr.kind == node_kind::N_ID) {
				// Look up variable's type
				let id = match_expr.data: *n_id_data;
				let var_type = find_var_type(ctx, id.ptr, id.length);
				if (var_type != null) {
					let vt = unwrap(var_type);
					if (vt.kind == node_kind::N_TALIAS) {
						// Resolve type alias to actual tagged union
						let td = vt.data: *n_id_data;
						let resolved = find_typedef(ctx, td.ptr, td.length);
						if (resolved != null) {
							matched_type = resolved;
						};
					} else if (vt.kind == node_kind::N_TTAGGED) {
						matched_type = vt;
					} else if (vt.kind == node_kind::N_TPRIM) {
						// Check if this is a user-defined type (not a built-in primitive)
						let td = vt.data: *n_id_data;
						if (!is_prim_type_name(td.ptr, td.length)) {
							let resolved = find_typedef(ctx, td.ptr, td.length);
							if (resolved != null) {
								matched_type = resolved;
							};
						};
					};
				};
			};

			for (let i = 0z; i < d.ncases; i += 1) {
				let c: *node = d.cases[i];
				let cd = c.data: *n_mcase_data;

				if (cd.typ == null) {
					// Catch-all case (case =>)
					strbuf_append(sb, "    default: {\n");
				} else if (((*unwrap(cd.typ)).kind == node_kind::N_TNOMEM)) {
					// nomem error case - use HARE_ERROR_TAG_BASE
					strbuf_append(sb, "    case HARE_ERROR_TAG_BASE: {\n");
				} else {
					// Regular case - use numeric literal with comment
					let case_type = unwrap(cd.typ);
					let tag_idx: i64 = -1;
					let tag_variant: *node = case_type;

					// Get variant name for tag lookup
					if (case_type.kind == node_kind::N_TPRIM || case_type.kind == node_kind::N_TALIAS) {
						let td = case_type.data: *n_id_data;
						if (matched_type != null) {
							tag_idx = find_variant_tag_in_type(unwrap(matched_type), td.ptr, td.length);
						};
					} else if (case_type.kind == node_kind::N_VOID) {
						// void variant - look up "void" in tagged union
						if (matched_type != null) {
							let void_name: str = "void";
							tag_idx = find_variant_tag_in_type(unwrap(matched_type), strings::toutf8(void_name): *[*]u8: *u8, 4);
						};
					} else if (case_type.kind == node_kind::N_TERR) {
						if (matched_type != null) {
							let td = unwrap(matched_type).data: *n_ttagged_data;
							let cd = case_type.data: *n_terr_data;
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
						};
					};

					if (matched_type != null && tag_idx >= 0) {
						let td = unwrap(matched_type).data: *n_ttagged_data;
						tag_variant = td.variants[tag_idx];
					};

					if (tag_idx >= 0) {
						// Emit numeric literal with comment
						strbuf_append(sb, "    case ");
						strbuf_append_int(sb, tag_idx);
						strbuf_append(sb, "U: /* ");
						emit_type_tag(sb, tag_variant);
						strbuf_append(sb, " */ {\n");
					} else {
						// Fallback to old style if we couldn't resolve the type
						strbuf_append(sb, "    case ");
						strbuf_append_int(sb, i: i64);
						strbuf_append(sb, "U: /* ");
						emit_type_tag(sb, tag_variant);
						strbuf_append(sb, " */ {\n");
					};

					// Emit binding if present - use union value field
					if (cd.bind_ptr != null && cd.bind_len > 0) {
						match (cd.bind_ptr) {
						case let bind_ptr: *u8 =>
							strbuf_append(sb, "        ");
							emit_type(ctx, unwrap(cd.typ));
							strbuf_append(sb, " __attribute__((unused)) ");
							strbuf_append_bytes(sb, bind_ptr, cd.bind_len);
							strbuf_append(sb, " = __m.value._");
							emit_type_tag(sb, tag_variant);
							strbuf_append(sb, ";\n");
							// Track binding type for auto-dereference in field access
							add_var_type(ctx, bind_ptr, cd.bind_len, unwrap(cd.typ));
						case null =>
							void;
						};
					};
				};

				// Emit body
				strbuf_append(sb, "        ");
				emit_match_case_body(ctx, cd.body, is_expression_match);
				strbuf_append(sb, "\n    } break;\n");
			};

			strbuf_append(sb, "    }\n");
		};

		if (is_expression_match) {
			if (ctx.result_used) {
				strbuf_append(sb, "    __r;\n");
			} else {
				strbuf_append(sb, "    (void)0;\n");
			};
			strbuf_append(sb, "});");
		} else {
			strbuf_append(sb, "}");
		};
		return;
	};

	// Default - try as expression
	emit_node(ctx, n);
	strbuf_append(sb, ";");
};

// Helper to emit match case body
// is_expr: true if this is an expression-style match (body should be assigned to __r)
fn emit_match_case_body(ctx: *transform_ctx, body: *node, is_expr: bool) void = {
	let sb = ctx.output;
	if (body.kind == node_kind::N_BLOCK) {
		// Inline block contents
		let bd = body.data: *n_block_data;
		for (let j = 0z; j < bd.nstmts; j += 1) {
			emit_stmt(ctx, bd.stmts[j]);
			strbuf_append(sb, "\n        ");
		};
	} else if (body.kind == node_kind::N_RET) {
		// Return statement - emit directly
		emit_stmt(ctx, body);
	} else if (body.kind == node_kind::N_EXPR) {
		// Expression statement
		let ed = body.data: *n_ret_data;
		let expr = unwrap(ed.expr);
		if (expr.kind == node_kind::N_ASSERT) {
			emit_node(ctx, expr);
			strbuf_append(sb, ";");
		} else if (is_expr && !is_void_result(expr)) {
			strbuf_append(sb, "__r = ");
			emit_node(ctx, expr);
			strbuf_append(sb, ";");
		} else {
			strbuf_append(sb, "(void)(");
			emit_node(ctx, expr);
			strbuf_append(sb, ");");
		};
	} else if (body.kind == node_kind::N_VOID) {
		// void case body - emit nothing (void; is invalid C)
		void;
	} else {
		// Other statement or expression - if expression match, assign to __r
		if (is_expr) {
			strbuf_append(sb, "__r = ");
		};
		emit_node(ctx, body);
		strbuf_append(sb, ";");
	};
};

// Emit type tag for match union field access (C-safe identifier)
fn emit_type_tag(sb: *strbuf, n: *node) void = {
	let k = n.kind;

	// Error type !T - use inner type for tag name
	if (k == node_kind::N_TERR) {
		let d = n.data: *n_terr_data;
		emit_type_tag(sb, d.inner);
		return;
	};

	// nomem error type
	if (k == node_kind::N_TNOMEM) {
		strbuf_append(sb, "nomem");
		return;
	};

	// Primitive type
	if (k == node_kind::N_TPRIM) {
		let d = n.data: *n_id_data;
		// Convert type name to C-safe identifier
		strbuf_append_bytes(sb, d.ptr, d.length);
		return;
	};

	// Type alias
	if (k == node_kind::N_TALIAS) {
		let d = n.data: *n_id_data;
		let d_bytes = d.ptr: *[*]u8;
		// Replace :: with _
		for (let i = 0z; i < d.length; i += 1) {
			let c = d_bytes[i];
			if (c == ':') {
				strbuf_append(sb, "_");
			} else {
				strbuf_append_byte(sb, c);
			};
		};
		return;
	};

	// Pointer type
	if (k == node_kind::N_TPTR) {
		strbuf_append(sb, "ptr_");
		let d = n.data: *n_tptr_data;
		emit_type_tag(sb, d.inner);
		return;
	};

	// Default
	strbuf_append(sb, "unknown");
};

// Emit assignment as expression (no semicolon)
fn emit_asgn_expr(ctx: *transform_ctx, n: *node) void = {
	let d = n.data: *n_asgn_data;
	let sb = ctx.output;
	emit_node(ctx, d.target);
	strbuf_append(sb, " ");
	emit_asgn_op(sb, d.op);
	strbuf_append(sb, " ");
	emit_node(ctx, d.value);
};

// Emit assignment operator
fn emit_asgn_op(sb: *strbuf, op: token_kind) void = {
	if (op == token_kind::EQ) { strbuf_append(sb, "="); return; };
	if (op == token_kind::PLUS_EQ) { strbuf_append(sb, "+="); return; };
	if (op == token_kind::MINUS_EQ) { strbuf_append(sb, "-="); return; };
	if (op == token_kind::STAR_EQ) { strbuf_append(sb, "*="); return; };
	if (op == token_kind::SLASH_EQ) { strbuf_append(sb, "/="); return; };
	if (op == token_kind::PERCENT_EQ) { strbuf_append(sb, "%="); return; };
	if (op == token_kind::AMP_EQ) { strbuf_append(sb, "&="); return; };
	if (op == token_kind::PIPE_EQ) { strbuf_append(sb, "|="); return; };
	if (op == token_kind::CARET_EQ) { strbuf_append(sb, "^="); return; };
	if (op == token_kind::LSHIFT_EQ) { strbuf_append(sb, "<<="); return; };
	if (op == token_kind::RSHIFT_EQ) { strbuf_append(sb, ">>="); return; };
	strbuf_append(sb, "=");
};

// Check if a node contains an indexed expression (N_IDX)
fn contains_idx_node(n: *node) bool = {
	let k = n.kind;
	if (k == node_kind::N_IDX) {
		return true;
	};
	// Check child nodes that could contain indexed access
	if (k == node_kind::N_FLD) {
		let d = n.data: *n_fld_data;
		return contains_idx_node(d.base);
	};
	if (k == node_kind::N_UN) {
		let d = n.data: *n_un_data;
		return contains_idx_node(d.operand);
	};
	return false;
};

// Emit bounds check statements for an indexed expression (used before lvalue assignment)
fn emit_lvalue_bounds_checks(ctx: *transform_ctx, n: *node) void = {
	let k = n.kind;
	let sb = ctx.output;

	if (k == node_kind::N_IDX) {
		let d = n.data: *n_idx_data;
		let idx_base = d.base;

		// Recursively emit checks for nested indexed expressions
		emit_lvalue_bounds_checks(ctx, idx_base);

		// Check if base is a tracked slice or array
		if (idx_base.kind == node_kind::N_ID) {
			let bid = idx_base.data: *n_id_data;
			if (is_tracked_var(&ctx.slice_vars, bid.ptr, bid.length)) {
				// Slice bounds check
				strbuf_append(sb, "(void)((size_t)(");
				emit_node(ctx, d.index);
				strbuf_append(sb, ")>=(size_t)((");
				emit_node(ctx, idx_base);
				strbuf_append(sb, ").len)?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0); ");
				return;
			};
			let arr_len = get_arr_len(ctx, bid.ptr, bid.length);
			match (arr_len) {
			case let al: *node =>
				// Array bounds check
				strbuf_append(sb, "(void)((size_t)(");
				emit_node(ctx, d.index);
				strbuf_append(sb, ")>=(size_t)(");
				emit_node(ctx, al);
				strbuf_append(sb, ")?(rt_abort_fixed(&__hare_file,0,0,0),(void)0):(void)0); ");
				return;
			case null => void;
			};
		};
		return;
	};

	// Recursively check field access and dereference
	if (k == node_kind::N_FLD) {
		let d = n.data: *n_fld_data;
		emit_lvalue_bounds_checks(ctx, d.base);
		return;
	};
	if (k == node_kind::N_UN) {
		let d = n.data: *n_un_data;
		emit_lvalue_bounds_checks(ctx, d.operand);
		return;
	};
};

// Emit typedef
export fn emit_typedef(ctx: *transform_ctx, n: *node) void = {
	let d = n.data: *n_typedef_data;
	let sb = ctx.output;

	// Handle enum types specially
	if ((*unwrap(d.typ)).kind == node_kind::N_TENUM) {
		// Track this as an enum type (to detect match on enum error)
		add_tracked_var(&ctx.enum_types, d.name_ptr, d.name_len);
		emit_enum_typedef(ctx, d.name_ptr, d.name_len, d.typ);
		return;
	};

	// Handle tagged union types specially
	if ((*unwrap(d.typ)).kind == node_kind::N_TTAGGED) {
		// Register this type name as a tagged union for assignment wrapping
		add_tracked_var(&ctx.tagged_types, d.name_ptr, d.name_len);
		// Check if success type (first variant, tag 0) is void
		let td = (*unwrap(d.typ)).data: *n_ttagged_data;
		if (td.nvariants > 0 && is_void_type(ctx, td.variants[0])) {
			add_tracked_var(&ctx.void_success_types, d.name_ptr, d.name_len);
		};
		emit_tagged_typedef(ctx, d.name_ptr, d.name_len, d.typ);
		return;
	};

	// Handle error types specially (!T) - emit inner type as typedef
	if ((*unwrap(d.typ)).kind == node_kind::N_TERR) {
		let ed = (*unwrap(d.typ)).data: *n_terr_data;
		let inner_typ: *node = ed.inner;
		// For !void, emit a word-sized typedef
		if (is_void_type(ctx, inner_typ)) {
			strbuf_append(sb, "typedef intptr_t ");
			strbuf_append_bytes(sb, d.name_ptr, d.name_len);
			strbuf_append(sb, ";");
			return;
		};
		// For other error types (!int, !str, etc.), emit the inner type
		strbuf_append(sb, "typedef ");
		emit_type(ctx, inner_typ);
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, ";");
		return;
	};

	// Handle struct types specially - use named struct since we forward-declared
	if ((*unwrap(d.typ)).kind == node_kind::N_TSTRUCT) {
		let st = (*unwrap(d.typ)).data: *n_tstruct_data;
		strbuf_append(sb, "struct ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, " { ");
		for (let i = 0z; i < st.nfields; i += 1) {
			let field: *node = st.fields[i];
			let fd = field.data: *n_param_data;
			// Use emit_param_decl to handle array types correctly
			emit_param_decl(ctx, fd.typ, fd.name_ptr, fd.name_len);
			strbuf_append(sb, "; ");
		};
		strbuf_append(sb, "};");
		return;
	};

	// Handle union types specially - use named union for consistency
	if ((*unwrap(d.typ)).kind == node_kind::N_TUNION) {
		let st = (*unwrap(d.typ)).data: *n_tstruct_data;  // Reuses struct data layout
		strbuf_append(sb, "union ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, " { ");
		for (let i = 0z; i < st.nfields; i += 1) {
			let field: *node = st.fields[i];
			let fd = field.data: *n_param_data;
			emit_param_decl(ctx, fd.typ, fd.name_ptr, fd.name_len);
			strbuf_append(sb, "; ");
		};
		strbuf_append(sb, "};");
		return;
	};

	// Handle array types specially: typedef T name[N] instead of typedef T[N] name
	if ((*unwrap(d.typ)).kind == node_kind::N_TARR) {
		strbuf_append(sb, "typedef ");
		// Collect all array dimensions
		let dims: [8]nullable *node = [null...];
		let ndims: size = 0;
		let cur = d.typ;
		for (ndims < 8 && cur.kind == node_kind::N_TARR) {
			let ad = cur.data: *n_tarr_data;
			if (ad.length != null) {
				dims[ndims] = ad.length;
				ndims += 1;
			};
			cur = ad.elem;
		};
		// Emit element type (innermost type)
		emit_type(ctx, cur);
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		// Emit all dimensions
		for (let i = 0z; i < ndims; i += 1) {
			strbuf_append(sb, "[");
			emit_node(ctx, unwrap(dims[i]));
			strbuf_append(sb, "]");
		};
		strbuf_append(sb, ";");
		return;
	};

	strbuf_append(sb, "typedef ");
	emit_type(ctx, d.typ);
	strbuf_append(sb, " ");
	strbuf_append_bytes(sb, d.name_ptr, d.name_len);
	strbuf_append(sb, ";");
};

// Emit enum typedef
// Enum members are prefixed with enum name (e.g., color_RED) to match
// Hare's color::RED -> color_RED identifier conversion in parser
fn emit_enum_typedef(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: *node) void = {
	let d = typ.data: *n_tenum_data;
	let sb = ctx.output;

	// typedef enum { ... } name;
	strbuf_append(sb, "typedef enum { ");

	for (let i = 0z; i < d.nmembers; i += 1) {
		if (i > 0) {
			strbuf_append(sb, ", ");
		};
		let member = d.members[i];
		let md = member.data: *n_enum_member_data;
		// Prefix member with enum name: RED -> color_RED
		strbuf_append_bytes(sb, name_ptr, name_len);
		strbuf_append(sb, "_");
		strbuf_append_bytes(sb, md.name_ptr, md.name_len);
		if (md.value != null) {
			strbuf_append(sb, " = ");
			emit_node(ctx, unwrap(md.value));
		};
	};

	strbuf_append(sb, " } ");
	strbuf_append_bytes(sb, name_ptr, name_len);
	strbuf_append(sb, ";");
};

// Emit tagged union typedef
// Generates tag constants and typedef struct
// Note: void variants are skipped in union but still have tags
// Handles spread types (...T) by expanding them inline
fn emit_tagged_typedef(ctx: *transform_ctx, name_ptr: *u8, name_len: size, typ: *node) void = {
	let d = typ.data: *n_ttagged_data;
	let sb = ctx.output;

	// Expand spread types into a flat variant array
	let all_variants: [64]nullable *node = [null...];
	let all_count = 0z;

	for (let i = 0z; i < d.nvariants; i += 1) {
		let is_spread = (d.spread_mask & (1: u32 << i: u32)) != 0;
		let variant = d.variants[i];

		if (is_spread && variant.kind == node_kind::N_TPRIM) {
			// Look up the spread type and inline its variants
			// (Type names are stored as N_TPRIM in the parser)
			let ad = variant.data: *n_id_data;
			let spread_type = find_typedef(ctx, ad.ptr, ad.length);
			if (spread_type != null) {
				let st = unwrap(spread_type);
				if (st.kind == node_kind::N_TTAGGED) {
					let std = st.data: *n_ttagged_data;
					for (let j = 0z; j < std.nvariants && all_count < 64; j += 1) {
						all_variants[all_count] = std.variants[j];
						all_count += 1;
					};
				};
			};
		} else {
			// Regular variant - add directly
			if (all_count < 64) {
				all_variants[all_count] = variant;
				all_count += 1;
			};
		};
	};

	// Emit tag constants: #define typename_TAG_variant index
	// Using type-prefixed TAG names avoids conflicts when multiple tagged unions
	// share variant type names (e.g., both unsigned_int and integer_type have 'uint')
	for (let i = 0z; i < all_count; i += 1) {
		let variant = unwrap(all_variants[i]);
		strbuf_append(sb, "#define ");
		strbuf_append_bytes(sb, name_ptr, name_len);
		strbuf_append(sb, "_TAG_");
		emit_type_tag(sb, variant);
		strbuf_append(sb, " ");
		strbuf_append_int(sb, i: i64);
		strbuf_append(sb, "U\n");
	};

	// Emit typedef
	strbuf_append(sb, "typedef struct ");
	strbuf_append_bytes(sb, name_ptr, name_len);
	strbuf_append(sb, " { uint32_t tag; union { ");

	let has_non_void = false;
	for (let i = 0z; i < all_count; i += 1) {
		let variant = unwrap(all_variants[i]);
		// Skip void variants - they don't need storage
		if (is_void_type(ctx, variant)) {
			continue;
		};
		has_non_void = true;
		emit_type(ctx, variant);
		strbuf_append(sb, " _");
		emit_type_tag(sb, variant);
		strbuf_append(sb, "; ");
	};

	// If all variants are void, add a dummy field
	if (!has_non_void) {
		strbuf_append(sb, "char _dummy; ");
	};

	strbuf_append(sb, "} value; } ");
	strbuf_append_bytes(sb, name_ptr, name_len);
	strbuf_append(sb, ";\n");

	// Emit from_X helper functions for each variant
	for (let i = 0z; i < all_count; i += 1) {
		let variant = unwrap(all_variants[i]);
		// Generate: static inline typename typename_from_varianttype(varianttype __v) { typename __r; __r.tag = indexU; __r.value._varianttype = __v; return __r; }
		strbuf_append(sb, "static inline ");
		strbuf_append_bytes(sb, name_ptr, name_len);
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, name_ptr, name_len);
		strbuf_append(sb, "_from_");
		emit_type_tag(sb, variant);
		strbuf_append(sb, "(");
		// Void and nomem types don't take a parameter
		let is_zerosize = is_void_type(ctx, variant) || is_nomem_type(variant);
		if (is_zerosize) {
			strbuf_append(sb, "void");
		} else {
			emit_type(ctx, variant);
			strbuf_append(sb, " __v");
		};
		strbuf_append(sb, ") { ");
		strbuf_append_bytes(sb, name_ptr, name_len);
		strbuf_append(sb, " __r; __r.tag = ");
		strbuf_append_int(sb, i: i64);
		strbuf_append(sb, "U;");
		if (!is_zerosize) {
			strbuf_append(sb, " __r.value._");
			emit_type_tag(sb, variant);
			strbuf_append(sb, " = __v;");
		};
		strbuf_append(sb, " return __r; }\n");
	};
};

// Check if type is void
fn is_void_type(ctx: *transform_ctx, n: *node) bool = {
	if (n.kind == node_kind::N_TPRIM || n.kind == node_kind::N_TALIAS) {
		let d = n.data: *n_id_data;
		if (streq(d.ptr, d.length, "void")) {
			return true;
		};
		let resolved = find_typedef(ctx, d.ptr, d.length);
		match (resolved) {
		case let r: *node =>
			if (r.kind == node_kind::N_TERR) {
				return false;
			};
			return is_void_type(ctx, r);
		case null => void;
		};
	};
	if (n.kind == node_kind::N_TERR) {
		return false;
	};
	return false;
};

// Check if type is nomem (zero-size error type)
fn is_nomem_type(n: *node) bool = {
	return n.kind == node_kind::N_TNOMEM;
};

// Check if cast target matches the current return type name
fn is_cast_to_ret_type(ctx: *transform_ctx, cd: *n_cast_data) bool = {
	let target: *node = cd.target;
	if (target.kind != node_kind::N_TPRIM && target.kind != node_kind::N_TALIAS) {
		return false;
	};
	let ttd = target.data: *n_id_data;
	if (ttd.length != ctx.ret_name_len) {
		return false;
	};
	let ttd_bytes = ttd.ptr: *[*]u8;
	let ret_bytes = ctx.ret_name_ptr: *[*]u8;
	for (let i = 0z; i < ttd.length; i += 1) {
		if (ttd_bytes[i] != ret_bytes[i]) {
			return false;
		};
	};
	return true;
};

// Find tag index for a variant name in a tagged union type
// Returns -1 if not found
fn find_variant_tag(tagged_type: *node, variant_ptr: *u8, variant_len: size) i64 = {
	if (tagged_type.kind != node_kind::N_TTAGGED) {
		return -1;
	};
	let td = tagged_type.data: *n_ttagged_data;
	for (let i = 0z; i < td.nvariants; i += 1) {
		let variant = td.variants[i];
		if (variant.kind == node_kind::N_TPRIM) {
			let vd = variant.data: *n_id_data;
			if (vd.length == variant_len) {
				let matched = true;
				let vd_bytes = vd.ptr: *[*]u8;
				let variant_bytes = variant_ptr: *[*]u8;
				for (let j = 0z; j < variant_len; j += 1) {
					if (vd_bytes[j] != variant_bytes[j]) {
						matched = false;
					};
				};
				if (matched) {
					return i: i64;
				};
			};
		};
	};
	return -1;
};

// Find tag index for 'void' in a tagged union type
fn find_variant_tag_void(ctx: *transform_ctx, tagged_type: *node) i64 = {
	if (tagged_type.kind != node_kind::N_TTAGGED) {
		return -1;
	};
	let td = tagged_type.data: *n_ttagged_data;
	for (let i = 0z; i < td.nvariants; i += 1) {
		let variant = td.variants[i];
		if (is_void_type(ctx, variant)) {
			return i: i64;
		};
	};
	return -1;
};

// Find tag index for 'int' in a tagged union type
fn find_variant_tag_int(tagged_type: *node) i64 = {
	if (tagged_type.kind != node_kind::N_TTAGGED) return -1;
	let td = tagged_type.data: *n_ttagged_data;
	for (let i = 0z; i < td.nvariants; i += 1) {
		let variant = td.variants[i];
		if (variant.kind == node_kind::N_TPRIM) {
			let vd = variant.data: *n_id_data;
			if (streq(vd.ptr, vd.length, "int")) return i: i64;
		};
	};
	return -1;
};

// Emit constant definition
export fn emit_def(ctx: *transform_ctx, n: *node) void = {
	let d = n.data: *n_let_data;
	let sb = ctx.output;

	// Emit as #define for simple constants
	strbuf_append(sb, "#define ");
	strbuf_append_bytes(sb, d.name_ptr, d.name_len);
	strbuf_append(sb, " ");
	if (d.init != null) {
		// If type is specified, wrap in a cast to ensure correct C type
		let typ = d.typ;
		if (typ != null && (*unwrap(typ)).kind == node_kind::N_TPRIM) {
			strbuf_append(sb, "((");
			emit_type(ctx, unwrap(typ));
			strbuf_append(sb, ")(");
			emit_init_expr(ctx, unwrap(d.init), typ);
			strbuf_append(sb, "))");
		} else {
			emit_init_expr(ctx, unwrap(d.init), typ);
		};
	};
};

// Emit global variable
export fn emit_global(ctx: *transform_ctx, n: *node) void = {
	let d = n.data: *n_let_data;
	let sb = ctx.output;

	// Track global variable name for shadowing check
	add_tracked_var(&ctx.global_vars, d.name_ptr, d.name_len);

	// Infer array literal types for untyped globals.
	let typ = d.typ;
	if (typ == null && d.init != null && (*unwrap(d.init)).kind == node_kind::N_ARR_LIT) {
		let arr = (*unwrap(d.init)).data: *n_arr_lit_data;
		let elem_type = infer_arr_lit_elem_type(ctx, arr);
		match (elem_type) {
		case let et: *node =>
			let arr_type = node_new(ctx.arena, node_kind::N_TARR, size(n_tarr_data), 0, 0);
			let ad = arr_type.data: *n_tarr_data;
			ad.elem = et;
			ad.length = make_int(ctx.arena, arr.nelems: i64, 0, 0);
			ad.inferred = true;
			typ = arr_type;
		case null => void;
		};
	};

	if (typ != null) {
		add_global_var_type(ctx, d.name_ptr, d.name_len, unwrap(typ));
		track_ptr_uarr_var(ctx, d.name_ptr, d.name_len, typ);
		if ((*unwrap(typ)).kind == node_kind::N_TARR) {
			add_tracked_var(&ctx.arr_vars, d.name_ptr, d.name_len);
			let arrd = (*unwrap(typ)).data: *n_tarr_data;
			if (arrd.elem != null &&
			    ((*(arrd.elem)).kind == node_kind::N_TPRIM || (*(arrd.elem)).kind == node_kind::N_TALIAS)) {
				let elemd = (*(arrd.elem)).data: *n_id_data;
				add_variant_binding(&ctx.arr_elem_types, d.name_ptr, d.name_len, elemd.ptr, elemd.length);
			};
		};
		if ((*unwrap(typ)).kind == node_kind::N_TSLICE) {
			add_tracked_var(&ctx.slice_vars, d.name_ptr, d.name_len);
		};
		if ((*unwrap(typ)).kind == node_kind::N_TPTR) {
			add_tracked_var(&ctx.ptr_vars, d.name_ptr, d.name_len);
		};
	};

	// const -> static const, let -> static
	if (!d.is_mut) {
		strbuf_append(sb, "static const ");
	} else {
		strbuf_append(sb, "static ");
	};

	// Handle array types specially: T name[N] instead of T* name
	if (typ != null && (*unwrap(typ)).kind == node_kind::N_TARR) {
		let td = (*unwrap(typ)).data: *n_tarr_data;
		emit_type(ctx, td.elem);
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
		strbuf_append(sb, "[");
		if (td.length != null) {
			emit_node(ctx, unwrap(td.length));
		};
		strbuf_append(sb, "]");
	} else {
		if (typ != null) {
			emit_type(ctx, unwrap(typ));
		} else {
			strbuf_append(sb, "intptr_t");
		};
		strbuf_append(sb, " ");
		strbuf_append_bytes(sb, d.name_ptr, d.name_len);
	};

	if (d.init != null) {
		strbuf_append(sb, " = ");
		emit_init_expr(ctx, unwrap(d.init), typ);
	};
	strbuf_append(sb, ";");
};

// C prelude - minimal runtime declarations
export fn emit_prelude(sb: *strbuf) void = {
	strbuf_append(sb, "/* Generated by hare2c */\n");
	strbuf_append(sb, "#include <stdint.h>\n");
	strbuf_append(sb, "#include <stddef.h>\n");
	strbuf_append(sb, "\n");

	// String type
	strbuf_append(sb, "typedef struct { uint8_t* data; size_t len; } hare_str;\n");
	strbuf_append(sb, "static hare_str __hare_file = {.data=(uint8_t*)\"<stdin>\",.len=7};\n");
	strbuf_append(sb, "\n");

	// Slice macros
	strbuf_append(sb, "#define HARE_DEFINE_SLICE(T, name) typedef struct { T* data; size_t len; size_t cap; } name\n");
	strbuf_append(sb, "\n");

	// Abort functions
	strbuf_append(sb, "extern void rt_abort(hare_str*,uint64_t,uint64_t,hare_str) __attribute__((noreturn));\n");
	strbuf_append(sb, "extern void rt_abort_fixed(hare_str*,uint64_t,uint64_t,uint64_t) __attribute__((noreturn));\n");
	strbuf_append(sb, "#define HARE_BOUNDS_CHECK(i, len) ((void)((size_t)(i) >= (size_t)(len) ? (rt_abort_fixed(&__hare_file,0,0,0), 0) : 0))\n");
	strbuf_append(sb, "#define HARE_ASSERT(cond) ((void)(!(cond) ? (rt_abort_fixed(&__hare_file,0,0,6), 0) : 0))\n");
	strbuf_append(sb, "#define HARE_ERROR_TAG_BASE 0x80000000U\n");
	strbuf_append(sb, "#define HARE_IS_ERROR(x) (((x).tag & HARE_ERROR_TAG_BASE) != 0)\n");
	strbuf_append(sb, "\n");

	// Array/slice utility macros
	strbuf_append(sb, "#define HARE_ARRAY_LEN(x) (sizeof(x)/sizeof((x)[0]))\n");
	strbuf_append(sb, "#define HARE_SLICE(c,s,e) (hare_slice_intptr_t){.data=(intptr_t*)(c)+(s),.len=(e)-(s),.cap=HARE_ARRAY_LEN(c)-(s)}\n");
	strbuf_append(sb, "\n");

	// Common slice types
	strbuf_append(sb, "HARE_DEFINE_SLICE(uint8_t, hare_slice_uint8_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(intptr_t, hare_slice_intptr_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(float, hare_slice_float);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(double, hare_slice_double);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(int8_t, hare_slice_int8_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(int16_t, hare_slice_int16_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(int32_t, hare_slice_int32_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(int64_t, hare_slice_int64_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(uint16_t, hare_slice_uint16_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(uint32_t, hare_slice_uint32_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(uint64_t, hare_slice_uint64_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(uintptr_t, hare_slice_uintptr_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(size_t, hare_slice_size_t);\n");
	strbuf_append(sb, "HARE_DEFINE_SLICE(hare_str, hare_slice_hare_str);\n");
	strbuf_append(sb, "\n");

	// rt declarations
	strbuf_append(sb, "/* rt:: declarations */\n");
	strbuf_append(sb, "extern void* rt_malloc(size_t n);\n");
	strbuf_append(sb, "extern void* rt_calloc(size_t nmemb, size_t size);\n");
	strbuf_append(sb, "extern void rt_free(void* p);\n");
	strbuf_append(sb, "extern void* rt_realloc(void* p, size_t n);\n");
	strbuf_append(sb, "extern void rt_memcpy(void* dest, const void* src, size_t n);\n");
	strbuf_append(sb, "extern void rt_memmove(void* dest, const void* src, size_t n);\n");
	strbuf_append(sb, "extern void rt_memset(void* s, int c, size_t n);\n");
	strbuf_append(sb, "extern int64_t rt_write(int fd, const void* buf, size_t count);\n");
	strbuf_append(sb, "extern int64_t rt_read(int fd, void* buf, size_t count);\n");
	strbuf_append(sb, "extern void rt_exit(int status);\n");
	strbuf_append(sb, "extern _Bool rt_strcmp(hare_str a, hare_str b);\n");
	strbuf_append(sb, "\n");

	// strings:: function prototypes (implementations in lib/hare/rt.c)
	strbuf_append(sb, "/* strings:: module - function prototypes (implementations in lib/hare/rt.c) */\n");
	strbuf_append(sb, "typedef struct __hare_strings_dup_result __hare_strings_dup_result;\n");
	strbuf_append(sb, "extern hare_slice_uint8_t strings_toutf8(hare_str s);\n");
	strbuf_append(sb, "extern hare_str strings_fromutf8_unsafe(hare_slice_uint8_t in);\n");
	strbuf_append(sb, "extern __hare_strings_dup_result strings_dup(hare_str s);\n");
	strbuf_append(sb, "\n");

	// Slice operation macros (compact, efficient versions)
	strbuf_append(sb, "/* Slice operation macros */\n");
	strbuf_append(sb, "#define rt_append(sp,v) ({__auto_type __sp=(sp);if(__sp->len>=__sp->cap){__sp->cap=__sp->cap?__sp->cap*2:8;__sp->data=rt_realloc(__sp->data,__sp->cap*sizeof(*__sp->data));}__sp->data[__sp->len++]=(v);})\n");
	strbuf_append(sb, "#define rt_insert(sp,i,v) ({__auto_type __sp=(sp);size_t __i=(i);if(__sp->len>=__sp->cap){__sp->cap=__sp->cap?__sp->cap*2:8;__sp->data=rt_realloc(__sp->data,__sp->cap*sizeof(*__sp->data));}for(size_t __j=__sp->len;__j>__i;--__j)__sp->data[__j]=__sp->data[__j-1];__sp->data[__i]=(v);__sp->len++;})\n");
	strbuf_append(sb, "#define rt_delete(sp,s,e) ({__auto_type __sp=(sp);size_t __s=(s),__e=(e),__n=__e-__s;for(size_t __i=__s;__i+__n<__sp->len;++__i)__sp->data[__i]=__sp->data[__i+__n];__sp->len-=__n;})\n");
	strbuf_append(sb, "#define rt_static_append(sp,v) ({__auto_type __sp=(sp);if(__sp->len>=__sp->cap)rt_abort_fixed(&__hare_file,0,0,3);__sp->data[__sp->len++]=(v);})\n");
	strbuf_append(sb, "#define rt_static_insert(sp,i,v) ({__auto_type __sp=(sp);size_t __i=(i);if(__sp->len>=__sp->cap)rt_abort_fixed(&__hare_file,0,0,3);for(size_t __j=__sp->len;__j>__i;--__j)__sp->data[__j]=__sp->data[__j-1];__sp->data[__i]=(v);__sp->len++;})\n");
	strbuf_append(sb, "#define rt_static_delete(sp,s,e) ({__auto_type __sp=(sp);size_t __s=(s),__e=(e),__n=__e-__s;for(size_t __i=__s;__i+__n<__sp->len;++__i)__sp->data[__i]=__sp->data[__i+__n];__sp->len-=__n;})\n");
	strbuf_append(sb, "#define rt_slice_assign(d,s,e,src) ({__auto_type __d=(d);__auto_type __src=(src);for(size_t __i=0;__i<(e)-(s);++__i)__d.data[(s)+__i]=__src.data[__i];})\n");
	strbuf_append(sb, "\n");
};

// Helper to scan a type node for slice-of-array patterns
// Uses parallel arrays: arr_sizes[i], elem_strs[i] (null-terminated), elem_lens[i]
fn scan_type_for_slice_arr(n: *node, arr_sizes: *[16]size, elem_strs: *[16][32]u8, elem_lens: *[16]size, count: *size, ctx: *transform_ctx) void = {
	if (n == null) return;
	let k = n.kind;

	if (k == node_kind::N_TSLICE) {
		let d = n.data: *n_tarr_data;
		let elem: *node = d.elem;
		if (elem.kind == node_kind::N_TARR) {
			let ad = elem.data: *n_tarr_data;
			if (ad.length != null) {
				// Get the array size
				let arr_sz: size = 0;
				let len_node = unwrap(ad.length);
				if (len_node.kind == node_kind::N_INT) {
					let id = len_node.data: *n_int_data;
					arr_sz = id.val: size;
				};
				// Get element type name into a temp buffer
				let temp_sb = strbuf_new(ctx.arena);
				let saved_sb = ctx.output;
				ctx.output = &temp_sb;
				emit_type(ctx, ad.elem);
				ctx.output = saved_sb;
				let elem_str = strbuf_ptr(&temp_sb);
				let elem_bytes = elem_str: *[*]u8;
				let elem_len = 0z;
				for (elem_len < 31 && elem_bytes[elem_len] != 0) {
					elem_len += 1;
				};
				// Check if already in list
				let found = false;
				for (let i = 0z; i < *count; i += 1) {
					if ((*arr_sizes)[i] == arr_sz && (*elem_lens)[i] == elem_len) {
						let mch = true;
						for (let j = 0z; j < elem_len; j += 1) {
							if ((*elem_strs)[i][j] != elem_bytes[j]) {
								mch = false;
							};
						};
						if (mch) {
							found = true;
						};
					};
				};
				if (!found && *count < 16) {
					(*arr_sizes)[*count] = arr_sz;
					for (let j = 0z; j < elem_len && j < 31; j += 1) {
						(*elem_strs)[*count][j] = elem_bytes[j];
					};
					(*elem_strs)[*count][elem_len] = 0;
					(*elem_lens)[*count] = elem_len;
					*count += 1;
				};
			};
		};
	};

	// Recurse into sub-types
	if (k == node_kind::N_TPTR) {
		let d = n.data: *n_tptr_data;
		scan_type_for_slice_arr(d.inner, arr_sizes, elem_strs, elem_lens, count, ctx);
	};
	if (k == node_kind::N_TARR || k == node_kind::N_TSLICE) {
		let d = n.data: *n_tarr_data;
		scan_type_for_slice_arr(d.elem, arr_sizes, elem_strs, elem_lens, count, ctx);
	};
};

// Scan function parameters and return type for slice-of-array types
fn scan_fn_for_slice_arr(fn_node: *node, arr_sizes: *[16]size, elem_strs: *[16][32]u8, elem_lens: *[16]size, count: *size, ctx: *transform_ctx) void = {
	let fd = fn_node.data: *n_fn_data;
	// Scan parameters
	for (let i = 0z; i < fd.nparams; i += 1) {
		let param = fd.params[i];
		let pd = param.data: *n_param_data;
		if (pd.typ != null) {
			scan_type_for_slice_arr(pd.typ, arr_sizes, elem_strs, elem_lens, count, ctx);
		};
	};
	// Scan return type
	if (fd.ret_type != null) {
		scan_type_for_slice_arr(unwrap(fd.ret_type), arr_sizes, elem_strs, elem_lens, count, ctx);
	};
};

// Compare two type nodes for structural equality (for tuple matching)
fn tuple_tuple_types_equal(a: *node, b: *node) bool = {
	if (a == b) return true;
	if (a == null || b == null) return false;
	if (a.kind != b.kind) return false;

	let k = a.kind;
	if (k == node_kind::N_TPRIM) {
		let da = a.data: *n_id_data;
		let db = b.data: *n_id_data;
		if (da.length != db.length) return false;
		let da_bytes = da.ptr: *[*]u8;
		let db_bytes = db.ptr: *[*]u8;
		for (let i = 0z; i < da.length; i += 1) {
			if (da_bytes[i] != db_bytes[i]) return false;
		};
		return true;
	};
	if (k == node_kind::N_TPTR) {
		let da = a.data: *n_tptr_data;
		let db = b.data: *n_tptr_data;
		return tuple_tuple_types_equal(da.inner, db.inner);
	};
	if (k == node_kind::N_TTUPLE || k == node_kind::N_TTAGGED) {
		let da = a.data: *n_ttagged_data;
		let db = b.data: *n_ttagged_data;
		if (da.nvariants != db.nvariants) return false;
		for (let i = 0z; i < da.nvariants; i += 1) {
			if (!tuple_tuple_types_equal(da.variants[i], db.variants[i])) return false;
		};
		return true;
	};
	// For other types, just compare by identity
	return false;
};

// Scan a type node for tuple types and register them
fn scan_type_for_tuples(n: *node, ctx: *transform_ctx) void = {
	if (n == null) return;
	let k = n.kind;

	if (k == node_kind::N_TTUPLE) {
		let d = n.data: *n_ttagged_data;
		// FIRST scan element types (for nested tuples) - inner types must be registered first!
		for (let i = 0z; i < d.nvariants; i += 1) {
			scan_type_for_tuples(d.variants[i], ctx);
		};
		// THEN register this tuple type (check for structural equality)
		let found = false;
		for (let i = 0z; i < ctx.tuple_count; i += 1) {
			if (tuple_tuple_types_equal(ctx.tuple_types[i], n)) {
				found = true;
				break;
			};
		};
		if (!found && ctx.tuple_count < 32) {
			ctx.tuple_types[ctx.tuple_count] = n;
			ctx.tuple_count += 1;
		};
		return;
	};

	// Recursively scan other type nodes
	if (k == node_kind::N_TPTR) {
		let d = n.data: *n_tptr_data;
		scan_type_for_tuples(d.inner, ctx);
	};
	if (k == node_kind::N_TSLICE || k == node_kind::N_TARR) {
		let d = n.data: *n_tarr_data;
		scan_type_for_tuples(d.elem, ctx);
	};
	if (k == node_kind::N_TTAGGED) {
		let d = n.data: *n_ttagged_data;
		for (let i = 0z; i < d.nvariants; i += 1) {
			scan_type_for_tuples(d.variants[i], ctx);
		};
	};
	if (k == node_kind::N_TERR) {
		let d = n.data: *n_terr_data;
		scan_type_for_tuples(d.inner, ctx);
	};
};

// Recursively scan any AST node for tuple types in type annotations
fn scan_node_for_tuples(n: *node, ctx: *transform_ctx) void = {
	if (n == null) return;
	let k = n.kind;

	// Check let statements for tuple type annotations
	if (k == node_kind::N_LET) {
		let d = n.data: *n_let_data;
		if (d.typ != null) {
			scan_type_for_tuples(unwrap(d.typ), ctx);
		};
		// Also scan initializer for nested tuples
		if (d.init != null) {
			scan_node_for_tuples(unwrap(d.init), ctx);
		};
		return;
	};

	// Scan block statements
	if (k == node_kind::N_BLOCK) {
		let d = n.data: *n_block_data;
		for (let i = 0z; i < d.nstmts; i += 1) {
			scan_node_for_tuples(d.stmts[i], ctx);
		};
		return;
	};

	// Scan if statements
	if (k == node_kind::N_IF) {
		let d = n.data: *n_if_data;
		scan_node_for_tuples(d.then_branch, ctx);
		if (d.else_branch != null) {
			scan_node_for_tuples(unwrap(d.else_branch), ctx);
		};
		return;
	};

	// Scan for loops
	if (k == node_kind::N_FOR) {
		let d = n.data: *n_for_data;
		if (d.init != null) {
			scan_node_for_tuples(unwrap(d.init), ctx);
		};
		scan_node_for_tuples(d.body, ctx);
		return;
	};
};

// Scan function for tuple types
fn scan_fn_for_tuples(fn_node: *node, ctx: *transform_ctx) void = {
	let fd = fn_node.data: *n_fn_data;
	// Scan parameters
	for (let i = 0z; i < fd.nparams; i += 1) {
		let param = fd.params[i];
		let pd = param.data: *n_param_data;
		if (pd.typ != null) {
			scan_type_for_tuples(pd.typ, ctx);
		};
	};
	// Scan return type
	if (fd.ret_type != null) {
		scan_type_for_tuples(unwrap(fd.ret_type), ctx);
	};
	// Scan function body for let statements with tuple types
	if (fd.body != null) {
		scan_node_for_tuples(unwrap(fd.body), ctx);
	};
};

// Check if a type name is a builtin slice type (already defined in prelude)
fn is_builtin_slice_elem(ptr: *u8, plen: size) bool = {
	// Check for primitive types that have predefined slice types
	return type_is(ptr, plen, "int") ||
	       type_is(ptr, plen, "uint") ||
	       type_is(ptr, plen, "i8") ||
	       type_is(ptr, plen, "i16") ||
	       type_is(ptr, plen, "i32") ||
	       type_is(ptr, plen, "i64") ||
	       type_is(ptr, plen, "u8") ||
	       type_is(ptr, plen, "u16") ||
	       type_is(ptr, plen, "u32") ||
	       type_is(ptr, plen, "u64") ||
	       type_is(ptr, plen, "str") ||
	       type_is(ptr, plen, "hare_str") ||
	       type_is(ptr, plen, "f32") ||
	       type_is(ptr, plen, "f64") ||
	       type_is(ptr, plen, "size") ||
	       type_is(ptr, plen, "uintptr") ||
	       type_is(ptr, plen, "intptr_t") ||
	       type_is(ptr, plen, "uint8_t") ||
	       type_is(ptr, plen, "int8_t") ||
	       type_is(ptr, plen, "uint16_t") ||
	       type_is(ptr, plen, "int16_t") ||
	       type_is(ptr, plen, "uint32_t") ||
	       type_is(ptr, plen, "int32_t") ||
	       type_is(ptr, plen, "uint64_t") ||
	       type_is(ptr, plen, "int64_t") ||
	       type_is(ptr, plen, "uintptr_t") ||
	       type_is(ptr, plen, "size_t") ||
	       type_is(ptr, plen, "float") ||
	       type_is(ptr, plen, "double");
};

// Scan a type for custom slice types (slices of non-primitive types)
fn scan_type_for_custom_slices(n: *node, names: *[32][64]u8, lens: *[32]size, count: *size, ctx: *transform_ctx) void = {
	if (n == null) return;
	let k = n.kind;

	if (k == node_kind::N_TSLICE) {
		let d = n.data: *n_tarr_data;
		let elem: *node = d.elem;
		// Check if element type is a simple custom type (not array, not pointer)
		if (elem.kind == node_kind::N_TPRIM || elem.kind == node_kind::N_TALIAS) {
			let ed = elem.data: *n_id_data;
			let ed_bytes = ed.ptr: *[*]u8;
			// Skip builtin types
			if (!is_builtin_slice_elem(ed.ptr, ed.length)) {
				// Check if already in list
				let found = false;
				for (let i = 0z; i < *count; i += 1) {
					if ((*lens)[i] == ed.length) {
						let eq = true;
						for (let j = 0z; j < ed.length; j += 1) {
							if ((*names)[i][j] != ed_bytes[j]) {
								eq = false;
							};
						};
						if (eq) {
							found = true;
						};
					};
				};
				if (!found && *count < 32 && ed.length < 64) {
					for (let i = 0z; i < ed.length; i += 1) {
						(*names)[*count][i] = ed_bytes[i];
					};
					(*lens)[*count] = ed.length;
					*count += 1;
				};
			};
		};
		// Recurse into element type
		scan_type_for_custom_slices(elem, names, lens, count, ctx);
		return;
	};

	if (k == node_kind::N_TARR) {
		let d = n.data: *n_tarr_data;
		scan_type_for_custom_slices(d.elem, names, lens, count, ctx);
	};
	if (k == node_kind::N_TPTR) {
		let d = n.data: *n_tptr_data;
		scan_type_for_custom_slices(d.inner, names, lens, count, ctx);
	};
	if (k == node_kind::N_TTAGGED) {
		let d = n.data: *n_ttagged_data;
		for (let i = 0z; i < d.nvariants; i += 1) {
			scan_type_for_custom_slices(d.variants[i], names, lens, count, ctx);
		};
	};
	if (k == node_kind::N_TERR) {
		let d = n.data: *n_terr_data;
		scan_type_for_custom_slices(d.inner, names, lens, count, ctx);
	};
};

// Recursively scan statements/expressions for custom slice type annotations
fn scan_node_for_custom_slices(n: *node, names: *[32][64]u8, lens: *[32]size, count: *size, ctx: *transform_ctx) void = {
	if (n == null) return;
	let k = n.kind;

	if (k == node_kind::N_LET) {
		let d = n.data: *n_let_data;
		if (d.typ != null) {
			scan_type_for_custom_slices(unwrap(d.typ), names, lens, count, ctx);
		};
		if (d.init != null) {
			scan_node_for_custom_slices(unwrap(d.init), names, lens, count, ctx);
		};
		return;
	};

	if (k == node_kind::N_BLOCK) {
		let d = n.data: *n_block_data;
		for (let i = 0z; i < d.nstmts; i += 1) {
			scan_node_for_custom_slices(d.stmts[i], names, lens, count, ctx);
		};
		return;
	};

	if (k == node_kind::N_IF) {
		let d = n.data: *n_if_data;
		scan_node_for_custom_slices(d.then_branch, names, lens, count, ctx);
		if (d.else_branch != null) {
			scan_node_for_custom_slices(unwrap(d.else_branch), names, lens, count, ctx);
		};
		return;
	};

	if (k == node_kind::N_FOR) {
		let d = n.data: *n_for_data;
		if (d.init != null) {
			scan_node_for_custom_slices(unwrap(d.init), names, lens, count, ctx);
		};
		if (d.cond != null) {
			scan_node_for_custom_slices(unwrap(d.cond), names, lens, count, ctx);
		};
		if (d.step != null) {
			scan_node_for_custom_slices(unwrap(d.step), names, lens, count, ctx);
		};
		scan_node_for_custom_slices(d.body, names, lens, count, ctx);
		return;
	};

	if (k == node_kind::N_MATCH) {
		let d = n.data: *n_match_data;
		scan_node_for_custom_slices(d.expr, names, lens, count, ctx);
		for (let i = 0z; i < d.ncases; i += 1) {
			let c = d.cases[i];
			let cd = c.data: *n_mcase_data;
			if (cd.typ != null) {
				scan_type_for_custom_slices(unwrap(cd.typ), names, lens, count, ctx);
			};
			scan_node_for_custom_slices(cd.body, names, lens, count, ctx);
		};
		return;
	};

	if (k == node_kind::N_SWITCH) {
		let d = n.data: *n_switch_data;
		scan_node_for_custom_slices(d.expr, names, lens, count, ctx);
		for (let i = 0z; i < d.ncases; i += 1) {
			let c = d.cases[i];
			let cd = c.data: *n_case_data;
			for (let j = 0z; j < cd.nvalues; j += 1) {
				scan_node_for_custom_slices(cd.values[j], names, lens, count, ctx);
			};
			scan_node_for_custom_slices(cd.body, names, lens, count, ctx);
		};
		return;
	};

	if (k == node_kind::N_FOREACH || k == node_kind::N_FOREACH_REF || k == node_kind::N_FOREACH_ITER) {
		let d = n.data: *n_foreach_data;
		scan_node_for_custom_slices(d.iterable, names, lens, count, ctx);
		scan_node_for_custom_slices(d.body, names, lens, count, ctx);
		return;
	};
};

// Scan function parameters and return type for custom slice types
fn scan_fn_for_custom_slices(fn_node: *node, names: *[32][64]u8, lens: *[32]size, count: *size, ctx: *transform_ctx) void = {
	let fd = fn_node.data: *n_fn_data;
	// Scan parameters
	for (let i = 0z; i < fd.nparams; i += 1) {
		let param = fd.params[i];
		let pd = param.data: *n_param_data;
		if (pd.typ != null) {
			scan_type_for_custom_slices(pd.typ, names, lens, count, ctx);
		};
	};
	// Scan return type
	if (fd.ret_type != null) {
		scan_type_for_custom_slices(unwrap(fd.ret_type), names, lens, count, ctx);
	};
	// Scan function body
	if (fd.body != null) {
		scan_node_for_custom_slices(unwrap(fd.body), names, lens, count, ctx);
	};
};

// Emit a complete compilation unit
export fn emit_unit(ctx: *transform_ctx, unit: *node) void = {
	let sb = ctx.output;

	// Emit prelude
	emit_prelude(sb);

	// Emit declarations
	let d = unit.data: *n_unit_data;

	// Scan for use statements and set flags
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_USE) {
			let ud = decl.data: *n_use_data;
			// Register alias: alias -> full module path
			add_alias(ctx, ud.alias_ptr, ud.alias_len, ud.module_ptr, ud.module_len);
			// Check for "strings" module
			let module_str = strings::fromutf8_unsafe((ud.module_ptr: *[*]u8)[..ud.module_len]);
			if (module_str == "strings") {
				ctx.use_strings = true;
			};
		};
	};
	if (ctx.use_strings) {
		register_strings_dup_fn(ctx);
	};

	// First: collect all typedefs for spread type expansion
	// This must happen before emitting any typedefs
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_TYPEDEF) {
			let td = decl.data: *n_typedef_data;
			add_typedef(ctx, td.name_ptr, td.name_len, td.typ);
		};
	};
	// Pre-register function return types so field access can infer pointer depth
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_FN) {
			let fd = decl.data: *n_fn_data;
			if (fd.ret_type != null) {
				let rt = unwrap(fd.ret_type);
				add_fn_ret_type(ctx, fd.name_ptr, fd.name_len, rt);
			};
		};
	};

	// Scan for slice-of-array types and emit typedefs
	let slice_arr_sizes: [16]size = [0z...];
	let slice_arr_elems: [16][32]u8 = [[0u8...]...];
	let slice_arr_elens: [16]size = [0z...];
	let slice_arr_count: size = 0;
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_FN) {
			scan_fn_for_slice_arr(decl, &slice_arr_sizes, &slice_arr_elems, &slice_arr_elens, &slice_arr_count, ctx);
		};
	};
	// Emit typedefs for slice-of-array types
	for (let i = 0z; i < slice_arr_count; i += 1) {
		strbuf_append(sb, "typedef struct { ");
		strbuf_append_bytes(sb, &slice_arr_elems[i][0], slice_arr_elens[i]);
		strbuf_append(sb, " (*data)[");
		strbuf_append_int(sb, slice_arr_sizes[i]: i64);
		strbuf_append(sb, "]; size_t len; size_t cap; } hare_slice_arr");
		strbuf_append_int(sb, slice_arr_sizes[i]: i64);
		strbuf_append(sb, "_");
		strbuf_append_bytes(sb, &slice_arr_elems[i][0], slice_arr_elens[i]);
		strbuf_append(sb, ";\n");
	};
	if (slice_arr_count > 0) {
		strbuf_append(sb, "\n");
	};

	// Scan for custom slice types (slices of non-primitive types like []point)
	// We scan here but emit later, after struct forward declarations
	let custom_slice_names: [32][64]u8 = [[0u8...]...];
	let custom_slice_lens: [32]size = [0z...];
	let custom_slice_count: size = 0;
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_FN) {
			scan_fn_for_custom_slices(decl, &custom_slice_names, &custom_slice_lens, &custom_slice_count, ctx);
		};
	};

	// Scan for tuple types in functions and typedefs
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_FN) {
			scan_fn_for_tuples(decl, ctx);
		};
		if (decl.kind == node_kind::N_TYPEDEF) {
			let td = decl.data: *n_typedef_data;
			scan_type_for_tuples(td.typ, ctx);
		};
	};
	// Emit tuple typedefs
	for (let i = 0z; i < ctx.tuple_count; i += 1) {
		let tt = ctx.tuple_types[i];
		let td = tt.data: *n_ttagged_data;
		strbuf_append(sb, "typedef struct { ");
		for (let j = 0z; j < td.nvariants; j += 1) {
			emit_type(ctx, td.variants[j]);
			strbuf_append(sb, " _");
			strbuf_append_int(sb, j: i64);
			strbuf_append(sb, "; ");
		};
		strbuf_append(sb, "} __hare_tuple_");
		strbuf_append_int(sb, i: i64);
		strbuf_append(sb, ";\n");
	};
	if (ctx.tuple_count > 0) {
		strbuf_append(sb, "\n");
	};

	// First pass: emit forward declarations for all struct and union types
	// This allows struct/union pointers to reference types defined later
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_TYPEDEF) {
			let td = decl.data: *n_typedef_data;
			let typ = td.typ;
			// Forward-declare struct types
			if (typ.kind == node_kind::N_TSTRUCT) {
				strbuf_append(sb, "typedef struct ");
				strbuf_append_bytes(sb, td.name_ptr, td.name_len);
				strbuf_append(sb, " ");
				strbuf_append_bytes(sb, td.name_ptr, td.name_len);
				strbuf_append(sb, ";\n");
			};
			// Forward-declare union types
			if (typ.kind == node_kind::N_TUNION) {
				strbuf_append(sb, "typedef union ");
				strbuf_append_bytes(sb, td.name_ptr, td.name_len);
				strbuf_append(sb, " ");
				strbuf_append_bytes(sb, td.name_ptr, td.name_len);
				strbuf_append(sb, ";\n");
			};
		};
	};
	strbuf_append(sb, "\n");

	// Now emit HARE_DEFINE_SLICE for custom slice types (after struct forward decls)
	for (let i = 0z; i < custom_slice_count; i += 1) {
		strbuf_append(sb, "HARE_DEFINE_SLICE(");
		strbuf_append_bytes(sb, &custom_slice_names[i][0], custom_slice_lens[i]);
		strbuf_append(sb, ", hare_slice_");
		strbuf_append_bytes(sb, &custom_slice_names[i][0], custom_slice_lens[i]);
		strbuf_append(sb, ");\n");
	};
	if (custom_slice_count > 0) {
		strbuf_append(sb, "\n");
	};

	// Emit typedefs in dependency order to make output file-order-agnostic:
	// 1. Defs first (constants used in array sizes within structs)
	// 2. Enums (can't be forward-declared, used by structs)
	// 3. Struct/union definitions (already forward-declared above)
	// 4. Tagged unions and other typedefs

	// Pass 1: Emit defs (constants) first - needed for array sizes in structs
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_DEF) {
			emit_def(ctx, decl);
			strbuf_append(sb, "\n");
		};
	};

	// Pass 2: Emit all enum typedefs
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_TYPEDEF) {
			let td = decl.data: *n_typedef_data;
			if ((*unwrap(td.typ)).kind == node_kind::N_TENUM) {
				emit_typedef(ctx, decl);
				strbuf_append(sb, "\n");
			};
		};
	};

	// Pass 3: Emit struct and union definitions
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_TYPEDEF) {
			let td = decl.data: *n_typedef_data;
			let tk = (*unwrap(td.typ)).kind;
			if (tk == node_kind::N_TSTRUCT || tk == node_kind::N_TUNION) {
				emit_typedef(ctx, decl);
				strbuf_append(sb, "\n");
			};
		};
	};

	// Pass 4: Emit tagged unions, error types, and other typedefs
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_TYPEDEF) {
			let td = decl.data: *n_typedef_data;
			let tk = (*unwrap(td.typ)).kind;
			// Skip enums, structs, unions (already emitted)
			if (tk != node_kind::N_TENUM && tk != node_kind::N_TSTRUCT && tk != node_kind::N_TUNION) {
				emit_typedef(ctx, decl);
				strbuf_append(sb, "\n");
			};
		};
	};
	if (ctx.use_strings) {
		let name_ptr = strings::toutf8(STRINGS_DUP_TYPE_NAME): *[*]u8: *u8;
		let name_len = STRINGS_DUP_TYPE_NAME_LEN;
		let t = find_typedef(ctx, name_ptr, name_len);
		match (t) {
		case let td: *node =>
			emit_tagged_typedef(ctx, name_ptr, name_len, unwrap(td));
			strbuf_append(sb, "\n");
		case null => void;
		};
	};

	// Track functions that return pointers for -> field access
	// Also track functions that return void-success tagged unions
	// Also track function info for variadic calls and defaults
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_FN) {
			let fd = decl.data: *n_fn_data;
			// Always track function info for variadic/default handling
			add_fn_info(ctx, fd.name_ptr, fd.name_len, decl);
			// Track @symbol name if present (to detect invalid calls by symbol name)
			if (fd.symbol_len > 0) {
				match (fd.symbol_ptr) {
				case let sp: *u8 =>
					add_symbol_name(ctx, sp, fd.symbol_len);
				case null => void;
				};
			};
			if (fd.ret_type != null) {
				let rt = unwrap(fd.ret_type);
				// Register return type for variable type inference in let bindings
				add_fn_ret_type(ctx, fd.name_ptr, fd.name_len, rt);
				if (rt.kind == node_kind::N_TPTR) {
					add_tracked_var(&ctx.ptr_fns, fd.name_ptr, fd.name_len);
				};
				// Check if return type is a void-success tagged union
				// Note: parser uses N_TPRIM for both primitives and type aliases
				if (rt.kind == node_kind::N_TPRIM) {
					let rtd = rt.data: *n_id_data;
					if (is_tracked_var(&ctx.void_success_types, rtd.ptr, rtd.length)) {
						add_tracked_var(&ctx.void_result_fns, fd.name_ptr, fd.name_len);
					};
				};
			};
		};
	};

	// Emit forward declarations for all functions
	// Skip functions with inline tagged union return types (anonymous structs conflict)
	strbuf_append(sb, "/* Forward declarations */\n");
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		if (decl.kind == node_kind::N_FN) {
			let fd = decl.data: *n_fn_data;
			// Skip forward decl if return type is inline tagged union
			if (fd.ret_type != null) {
				let rt = unwrap(fd.ret_type);
				if (rt.kind == node_kind::N_TTAGGED) {
					continue;
				};
			};
			emit_fn_decl(ctx, decl);
		};
	};
	strbuf_append(sb, "\n");

	// Emit globals first
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		let k = decl.kind;
		if (k == node_kind::N_GLOBAL) {
			emit_global(ctx, decl);
			strbuf_append(sb, "\n");
		};
	};

	// Emit function definitions only (typedefs/defs already emitted above)
	for (let i = 0z; i < d.ndecls; i += 1) {
		let decl = d.decls[i];
		let k = decl.kind;

		if (k == node_kind::N_FN) {
			emit_fn(ctx, decl);
			strbuf_append(sb, "\n\n");
		};
	};
};
