// parser.ha - Iterative parser with Shunting Yard for expressions
use strings;

// Parser state
export type parser = struct {
	tokens: *[*]token,
	ntokens: size,
	pos: size,
	arena: *arena,
};

// Create a new parser
export fn parser_new(a: *arena, tokens: *[*]token, ntokens: size) parser = {
	return parser {
		tokens = tokens,
		ntokens = ntokens,
		pos = 0,
		arena = a,
	};
};

// Peek at current token
fn peek(p: *parser) *token = {
	if (p.pos >= p.ntokens) {
		return &p.tokens[p.ntokens - 1];  // EOF
	};
	return &p.tokens[p.pos];
};

// Check if current token matches kind
fn at(p: *parser, k: token_kind) bool = {
	return (*peek(p)).kind == k;
};

// Check if token at offset matches kind (lookahead)
fn at_offset(p: *parser, off: size, k: token_kind) bool = {
	let pos = p.pos + off;
	if (pos >= p.ntokens) {
		return false;
	};
	return (*(&p.tokens[pos])).kind == k;
};

// Advance and return previous token
fn advance(p: *parser) *token = {
	let t = peek(p);
	if (p.pos < p.ntokens) {
		p.pos += 1;
	};
	return t;
};

// Consume token if it matches, return true if consumed
fn eat(p: *parser, k: token_kind) bool = {
	if (at(p, k)) {
		advance(p);
		return true;
	};
	return false;
};

// Abort with message at current token position
fn die_parse(p: *parser, msg: str) void = {
	let t = peek(p);
	die_at(msg, t.line, t.col);
};

// Expect and consume token, abort on mismatch
fn expect(p: *parser, k: token_kind) *token = {
	if (!at(p, k)) {
		die_parse(p, "unexpected token");
	};
	return advance(p);
};

// Operator precedence table
fn precedence(op: token_kind) int = {
	return switch (op) {
	case token_kind::LOR => yield 1;
	case token_kind::XOR => yield 2;
	case token_kind::LAND => yield 3;
	case token_kind::EQEQ, token_kind::NEQ => yield 4;
	case token_kind::LT, token_kind::GT, token_kind::LE, token_kind::GE => yield 5;
	case token_kind::PIPE => yield 6;
	case token_kind::CARET => yield 7;
	case token_kind::AMP => yield 8;
	case token_kind::LSHIFT, token_kind::RSHIFT => yield 9;
	case token_kind::PLUS, token_kind::MINUS => yield 10;
	case token_kind::STAR, token_kind::SLASH, token_kind::PERCENT => yield 11;
	case => yield -1;  // Not a binary operator
	};
};

// Parse primary expression
fn parse_primary(p: *parser) *node = {
	let t = peek(p);
	let line = t.line;
	let col = t.col;

	// Integer literal
	if (t.kind == token_kind::INT) {
		let tbytes = t.val_ptr: *[*]u8;
		if (!int_literal_underscores_ok(tbytes, t.val_len)) {
			die_at("invalid numeric literal", line, col);
		};
		// Check for leading zero error (0644 should be 0o644)
		if (t.val_len >= 2 && tbytes[0] == '0') {
			let c1 = tbytes[1];
			// If second char is a digit (not x, o, b, or underscore), it's an error
			if (c1 >= '0' && c1 <= '9') {
				die_at("leading zero in base 10 literal (use 0o prefix for octal)", line, col);
			};
		};
		advance(p);
		let n = node_new(p.arena, node_kind::N_INT, size(n_int_data), line, col);
		let d = n.data: *n_int_data;
		d.val = parse_int_value(t.val_ptr, t.val_len);
		// Extract suffix from token (i, u, z, or 0 for none)
		d.suffix = 0;
		for (let i = 0z; i < t.val_len; i += 1) {
			let c = tbytes[i];
			if (c == 'i' || c == 'u' || c == 'z') {
				d.suffix = c;
				break;
			};
		};
		return n;
	};

	// Float literal - store as string for precise representation
	if (t.kind == token_kind::FLOAT) {
		let tbytes = t.val_ptr: *[*]u8;
		if (!float_literal_underscores_ok(tbytes, t.val_len)) {
			die_at("invalid numeric literal", line, col);
		};
		advance(p);
		let n = node_new(p.arena, node_kind::N_FLOAT, size(n_str_data), line, col);
		let d = n.data: *n_str_data;
		d.ptr = t.val_ptr;
		d.length = t.val_len;
		return n;
	};

	// String literal - support concatenation of adjacent strings
	// "abc" "def" => "abcdef", "a" `b` => "ab"
	if (t.kind == token_kind::STR || t.kind == token_kind::RAWSTR) {
		// Collect all adjacent strings (max 8 for simplicity)
		let placeholder: u8 = 0;
		let placeholder_ptr = (&placeholder): *[*]u8;
		let str_ptrs: [8]*[*]u8 = [
			placeholder_ptr, placeholder_ptr, placeholder_ptr, placeholder_ptr,
			placeholder_ptr, placeholder_ptr, placeholder_ptr, placeholder_ptr,
		];
		let str_lens: [8]size = [0, 0, 0, 0, 0, 0, 0, 0];
		let str_is_raw: [8]bool = [false, false, false, false, false, false, false, false];
		let nparts = 0z;
		let all_raw = true;

		for (nparts < 8) {
			let tok = peek(p);
			if (tok.kind != token_kind::STR && tok.kind != token_kind::RAWSTR) {
				break;
			};
			advance(p);

			let is_raw = tok.kind == token_kind::RAWSTR;
			if (!is_raw) {
				all_raw = false;
			};

			// Skip quotes/backticks
			str_ptrs[nparts] = (tok.val_ptr: uintptr + 1): *[*]u8;
			str_lens[nparts] = tok.val_len - 2;
			str_is_raw[nparts] = is_raw;
			nparts += 1;
		};

		// Calculate total length
		let total_len = 0z;
		for (let i = 0z; i < nparts; i += 1) {
			total_len += str_lens[i];
		};

		// If single string, use it directly (avoid allocation)
		if (nparts == 1) {
			let n = node_new(p.arena, node_kind::N_STR, size(n_str_data), line, col);
			let d = n.data: *n_str_data;
			d.ptr = str_ptrs[0]: *u8;
			d.length = str_lens[0];
			d.is_raw = str_is_raw[0];
			return n;
		};

		// Multiple strings - concatenate into arena
		// If mixing raw and regular, need to escape backslashes in raw parts
		let buf_size = total_len;
		if (!all_raw) {
			// Count extra space needed for escaping backslashes in raw strings
			for (let i = 0z; i < nparts; i += 1) {
				if (str_is_raw[i]) {
					for (let j = 0z; j < str_lens[i]; j += 1) {
						if (str_ptrs[i][j] == '\\') {
							buf_size += 1;  // Need extra char for escape
						};
					};
				};
			};
		};

		let buf = arena_alloc(p.arena, buf_size): *[*]u8;
		let pos = 0z;
		for (let i = 0z; i < nparts; i += 1) {
			let src = str_ptrs[i];
			// If this is a raw string and we're in mixed mode, escape backslashes
			if (str_is_raw[i] && !all_raw) {
				for (let j = 0z; j < str_lens[i]; j += 1) {
					if (src[j] == '\\') {
						buf[pos] = '\\';
						pos += 1;
						buf[pos] = '\\';
						pos += 1;
					} else {
						buf[pos] = src[j];
						pos += 1;
					};
				};
			} else {
				for (let j = 0z; j < str_lens[i]; j += 1) {
					buf[pos] = src[j];
					pos += 1;
				};
			};
		};

		let n = node_new(p.arena, node_kind::N_STR, size(n_str_data), line, col);
		let d = n.data: *n_str_data;
		d.ptr = buf: *u8;
		d.length = pos;  // Use actual position, not total_len
		d.is_raw = all_raw;
		return n;
	};

	// Rune literal - character inside single quotes
	if (t.kind == token_kind::RUNE) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_RUNE, size(n_int_data), line, col);
		let d = n.data: *n_int_data;
		// Parse the rune value from token (skip quotes, handle escape)
		let val_ptr = t.val_ptr: *[*]u8;
		let val_len = t.val_len;
		if (val_len >= 3 && val_ptr[1] == '\\') {
			// Escape sequence
			let c = val_ptr[2];
			if (c == 'n') { d.val = 10; }
			else if (c == 't') { d.val = 9; }
			else if (c == 'r') { d.val = 13; }
			else if (c == '\\') { d.val = 92; }
			else if (c == '\'') { d.val = 39; }
			else if (c == '0') { d.val = 0; }
			else if (c == 'x' || c == 'o' || c == 'O' ||
				c == 'u' || c == 'U') {
				let base: i64 = 16;
				let count = 2z;
				if (c == 'u' || c == 'o') { count = 4; }
				else if (c == 'U' || c == 'O') { count = 8; };
				if (c == 'o' || c == 'O') { base = 8; };
				let val: i64 = 0;
				let ok = true;
				for (let i = 0z; i < count; i += 1) {
					let idx = 3z + i;
					if (idx >= val_len - 1) { ok = false; break; };
					let digit = digit_val(val_ptr[idx]);
					if (digit < 0 || digit >= base) { ok = false; break; };
					val = val * base + digit;
				};
				if (!ok) {
					die_at("invalid escape sequence", line, col);
				} else {
					d.val = val;
				};
			}
			else { d.val = c: i64; };
		} else if (val_len >= 3) {
			// Normal character
			d.val = val_ptr[1]: i64;
		} else {
			d.val = 0;
		};
		return n;
	};

	// Boolean literals
	if (t.kind == token_kind::TRUE || t.kind == token_kind::FALSE) {
		let is_true = t.kind == token_kind::TRUE;
		advance(p);
		return make_bool(p.arena, is_true, line, col);
	};

	// Null
	if (t.kind == token_kind::NULL) {
		advance(p);
		return make_null(p.arena, line, col);
	};

	// size builtin - check BEFORE identifier check since SIZE is a type keyword
	// size(type) takes a type argument and returns sizeof(type)
	if (t.kind == token_kind::SIZE && at_offset(p, 1, token_kind::LPAREN)) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let typ = parse_type(p);
		expect(p, token_kind::RPAREN);
		// Reuse N_LEN node kind with type as operand
		let n = node_new(p.arena, node_kind::N_LEN, size(n_un_data), line, col);
		let d = n.data: *n_un_data;
		d.op = token_kind::SIZE;
		d.operand = typ;
		return n;
	};

	// void expression (before identifier check since void is in is_type_keyword)
	if (t.kind == token_kind::VOID) {
		advance(p);
		return make_void(p.arena, line, col);
	};

	// Identifier or keyword used as identifier
	if (t.kind == token_kind::ID || is_type_keyword(t.kind)) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_ID, size(n_id_data), line, col);
		let d = n.data: *n_id_data;
		d.ptr = t.val_ptr;
		d.length = t.val_len;
		return n;
	};

	// Parenthesized expression or tuple literal
	if (t.kind == token_kind::LPAREN) {
		advance(p);
		let expr = parse_expr(p);
		// Check for tuple literal (expr, expr, ...)
		if (at(p, token_kind::COMMA)) {
			let elems: [32]nullable *node = [null...];
			let nelems = 1z;
			elems[0] = expr;
			for (eat(p, token_kind::COMMA)) {
				if (nelems >= 32) {
					die_parse(p, "too many tuple elements");
				};
				elems[nelems] = parse_expr(p);
				nelems += 1;
			};
			expect(p, token_kind::RPAREN);
			let n = node_new(p.arena, node_kind::N_TUPLE_LIT, size(n_tuple_lit_data), line, col);
			let d = n.data: *n_tuple_lit_data;
			d.nelems = nelems;
			let arr = node_array(p.arena, nelems);
			for (let i = 0z; i < nelems; i += 1) {
				arr[i] = match (elems[i]) {
				case let e: *node =>
					yield e;
				case null =>
					die_parse(p, "internal error: null element");
					abort();
				};
			};
			d.elems = arr;
			d.type_name_ptr = null;
			d.type_name_len = 0;
			return n;
		};
		expect(p, token_kind::RPAREN);
		return expr;
	};

	// Block expression
	if (t.kind == token_kind::LBRACE) {
		return parse_block(p);
	};

	// Anonymous struct literal: struct { x: int = 10, y: int = 20 }
	if (t.kind == token_kind::STRUCT && at_offset(p, 1, token_kind::LBRACE)) {
		advance(p); // consume 'struct'
		advance(p); // consume '{'

		let fields: [32]nullable *node = [null...];
		let nfields = 0z;

		for (!at(p, token_kind::RBRACE)) {
			if (nfields >= 32) {
				die_parse(p, "too many anonymous struct fields");
			};

			// Parse: field_name: type = value
			let fname = peek(p);
			if (!is_name_token(fname.kind)) {
				die_parse(p, "expected field name in anonymous struct");
			};
			advance(p);
			expect(p, token_kind::COLON);
			let ftype = parse_type(p);
			expect(p, token_kind::EQ);
			let fvalue = parse_expr(p);

			let f = node_new(p.arena, node_kind::N_ANON_FIELD, size(n_anon_field_data), fname.line, fname.col);
			let fd = f.data: *n_anon_field_data;
			fd.name_ptr = fname.val_ptr;
			fd.name_len = fname.val_len;
			fd.typ = ftype;
			fd.value = fvalue;
			fields[nfields] = f;
			nfields += 1;

			if (!eat(p, token_kind::COMMA)) {
				break;
			};
		};

		expect(p, token_kind::RBRACE);

		let n = node_new(p.arena, node_kind::N_ANON_STRUCT_LIT, size(n_anon_struct_lit_data), line, col);
		let d = n.data: *n_anon_struct_lit_data;
		d.nfields = nfields;
		let arr = node_array(p.arena, nfields);
		for (let i = 0z; i < nfields; i += 1) {
			arr[i] = match (fields[i]) {
			case let f: *node =>
				yield f;
			case null =>
				die_parse(p, "internal error: null field");
				abort();
			};
		};
		d.fields = arr;
		return n;
	};

	// Array literal [1, 2, 3] or [val...]
	if (t.kind == token_kind::LBRACKET) {
		advance(p);
		return parse_array_literal(p, line, col);
	};

	// assert builtin - assert(cond) or assert(cond, msg)
	if (t.kind == token_kind::ASSERT) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let cond = parse_expr(p);
		// Skip optional message argument
		if (at(p, token_kind::COMMA)) {
			advance(p);
			parse_expr(p);  // Parse and discard message
		};
		expect(p, token_kind::RPAREN);
		let n = node_new(p.arena, node_kind::N_ASSERT, size(n_un_data), line, col);
		let d = n.data: *n_un_data;
		d.op = token_kind::ASSERT;
		d.operand = cond;
		return n;
	};

	// abort builtin - abort() or abort("message")
	if (t.kind == token_kind::ABORT) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let n = node_new(p.arena, node_kind::N_ABORT, size(n_abort_data), line, col);
		let d = n.data: *n_abort_data;
		// Parse message if present
		if (!at(p, token_kind::RPAREN)) {
			d.msg = parse_expr(p);
		} else {
			d.msg = null;
		};
		expect(p, token_kind::RPAREN);
		return n;
	};

	// len builtin
	if (t.kind == token_kind::LEN) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let expr = parse_expr(p);
		expect(p, token_kind::RPAREN);
		let n = node_new(p.arena, node_kind::N_LEN, size(n_un_data), line, col);
		let d = n.data: *n_un_data;
		d.op = token_kind::LEN;
		d.operand = expr;
		return n;
	};

	// offset builtin
	if (t.kind == token_kind::OFFSET) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let expr = parse_expr(p);
		expect(p, token_kind::RPAREN);
		let n = node_new(p.arena, node_kind::N_CALL, size(n_call_data), line, col);
		let d = n.data: *n_call_data;
		// Create an identifier node for "offset"
		let fn_id = node_new(p.arena, node_kind::N_ID, size(n_id_data), line, col);
		let id_d = fn_id.data: *n_id_data;
		id_d.ptr = strings::toutf8("offset"): *[*]u8: *u8;
		id_d.length = 6;
		d.func = fn_id;
		d.args[0] = expr;
		d.nargs = 1;
		return n;
	};

	// alloc builtin: alloc(expr), alloc(expr...), or alloc(expr, capacity)
	if (t.kind == token_kind::ALLOC) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let expr = parse_expr(p);
		let n = node_new(p.arena, node_kind::N_ALLOC, size(n_alloc_data), line, col);
		let d = n.data: *n_alloc_data;
		d.expr = expr;
		d.is_copy = false;
		d.capacity = null;

		// Check for spread syntax: alloc(expr...)
		if (eat(p, token_kind::ELLIPSIS)) {
			d.is_copy = true;
		} else if (eat(p, token_kind::COMMA)) {
			// alloc(expr, capacity)
			d.capacity = parse_expr(p);
		};
		expect(p, token_kind::RPAREN);
		return n;
	};

	// free builtin: free(ptr)
	if (t.kind == token_kind::FREE) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let expr = parse_expr(p);
		expect(p, token_kind::RPAREN);
		let n = node_new(p.arena, node_kind::N_FREE, size(n_free_data), line, col);
		let d = n.data: *n_free_data;
		d.expr = expr;
		return n;
	};

	// append builtin: append(slice, val)
	if (t.kind == token_kind::APPEND) {
		advance(p);
		expect(p, token_kind::LPAREN);
		let slice = parse_expr(p);
		expect(p, token_kind::COMMA);
		let value = parse_expr(p);
		expect(p, token_kind::RPAREN);
		let n = node_new(p.arena, node_kind::N_APPEND, size(n_append_data), line, col);
		let d = n.data: *n_append_data;
		d.slice = slice;
		d.value = value;
		d.is_static = false;
		return n;
	};

	// insert builtin: insert(slice[idx], val)
	if (t.kind == token_kind::INSERT) {
		advance(p);
		expect(p, token_kind::LPAREN);
		// Parse slice[idx] as an index expression
		let base = parse_expr(p);
		expect(p, token_kind::COMMA);
		let value = parse_expr(p);
		expect(p, token_kind::RPAREN);
		// base should be an index expression (slice[idx])
		let n = node_new(p.arena, node_kind::N_INSERT, size(n_insert_data), line, col);
		let d = n.data: *n_insert_data;
		if (base.kind == node_kind::N_IDX) {
			let idx_data = base.data: *n_idx_data;
			d.slice = idx_data.base;
			d.index = idx_data.index;
		} else {
			// Fallback - just use the expression as slice with index 0
			d.slice = base;
			d.index = node_new(p.arena, node_kind::N_INT, size(n_int_data), line, col);
		};
		d.value = value;
		d.is_static = false;
		return n;
	};

	// delete builtin: delete(slice[idx])
	if (t.kind == token_kind::DELETE) {
		advance(p);
		expect(p, token_kind::LPAREN);
		// Parse slice[idx] as an index expression
		let base = parse_expr(p);
		expect(p, token_kind::RPAREN);
		// base should be an index expression (slice[idx])
		let n = node_new(p.arena, node_kind::N_DELETE, size(n_delete_data), line, col);
		let d = n.data: *n_delete_data;
		if (base.kind == node_kind::N_IDX) {
			let idx_data = base.data: *n_idx_data;
			d.slice = idx_data.base;
			d.index = idx_data.index;
		} else {
			// Fallback - just use the expression as slice with index 0
			d.slice = base;
			d.index = node_new(p.arena, node_kind::N_INT, size(n_int_data), line, col);
		};
		d.is_static = false;
		return n;
	};

	// Switch expression
	if (t.kind == token_kind::SWITCH) {
		return parse_switch(p);
	};

	// Match expression
	if (t.kind == token_kind::MATCH) {
		return parse_match(p);
	};

	// If expression
	if (t.kind == token_kind::IF) {
		return parse_if(p);
	};

	// Yield expression
	if (t.kind == token_kind::YIELD) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_YIELD, size(n_yield_data), line, col);
		let d = n.data: *n_yield_data;
		if (!at(p, token_kind::SEMI) && !at(p, token_kind::RBRACE)) {
			d.expr = parse_expr(p);
		} else {
			d.expr = null;
		};
		return n;
	};

	// Unary operators handled in parse_unary
	die_parse(p, "unexpected token in expression");
	// Unreachable, but return a node to satisfy the type checker.
	return node_new(p.arena, node_kind::N_INT, size(n_int_data), line, col);
};

// Check if token is a type keyword that can be used as identifier
fn is_type_keyword(k: token_kind) bool = {
	return k == token_kind::VOID || k == token_kind::BOOL ||
	       k == token_kind::STR_T || k == token_kind::RUNE_T ||
	       k == token_kind::I8 || k == token_kind::I16 ||
	       k == token_kind::I32 || k == token_kind::I64 ||
	       k == token_kind::U8 || k == token_kind::U16 ||
	       k == token_kind::U32 || k == token_kind::U64 ||
	       k == token_kind::INT_T || k == token_kind::UINT ||
	       k == token_kind::F32 || k == token_kind::F64 ||
	       k == token_kind::SIZE || k == token_kind::UINTPTR ||
	       k == token_kind::OPAQUE;
};

// Check if token can be used as a name (ID or keyword like len/size/cap)
fn is_name_token(k: token_kind) bool = {
	return k == token_kind::ID || k == token_kind::LEN ||
	       k == token_kind::SIZE || is_type_keyword(k);
};

// Parse unary expression
fn parse_unary(p: *parser) *node = {
	let t = peek(p);
	let line = t.line;
	let col = t.col;

	// Unary operators: - ! ~ * &
	if (t.kind == token_kind::MINUS || t.kind == token_kind::BANG ||
	    t.kind == token_kind::TILDE || t.kind == token_kind::STAR ||
	    t.kind == token_kind::AMP) {
		let op = t.kind;
		advance(p);
		let operand = parse_unary(p);
		return make_un(p.arena, op, operand, line, col);
	};

	return parse_postfix(p);
};

// Parse postfix expressions (calls, indexing, field access, casts)
fn parse_postfix(p: *parser) *node = {
	let left = parse_primary(p);

	for (true) {
		let t = peek(p);

		// Function call
		if (t.kind == token_kind::LPAREN) {
			advance(p);
			left = parse_call(p, left);
			continue;
		};

		// Struct literal: TypeName { field = val, ... }
		// Only if left is an identifier (type name)
		if (t.kind == token_kind::LBRACE && left.kind == node_kind::N_ID) {
			advance(p);
			let ld = left.data: *n_id_data;
			left = parse_struct_literal(p, ld.ptr, ld.length, left.line, left.col);
			continue;
		};

		// Namespaced identifier: module::name
		// Combine into a single identifier with underscore
		if (t.kind == token_kind::COLONCOLON && left.kind == node_kind::N_ID) {
			advance(p);
			let name2 = peek(p);
			if (!is_name_token(name2.kind)) {
				die_parse(p, "expected identifier after ::");
			};
			advance(p);
			// Combine: module_name into new identifier
			let ld = left.data: *n_id_data;
			let ld_bytes = ld.ptr: *[*]u8;
			let name2_bytes = name2.val_ptr: *[*]u8;
			// Build combined name in arena: module_name
			let combined_len = ld.length + 1 + name2.val_len;
			let combined = arena_alloc(p.arena, combined_len): *[*]u8;
			// Copy first part
			for (let i = 0z; i < ld.length; i += 1) {
				combined[i] = ld_bytes[i];
			};
			combined[ld.length] = '_';
			// Copy second part
			for (let i = 0z; i < name2.val_len; i += 1) {
				combined[ld.length + 1 + i] = name2_bytes[i];
			};
			ld.ptr = combined: *u8;
			ld.length = combined_len;
			continue;
		};

		// Array index or slice
		if (t.kind == token_kind::LBRACKET) {
			advance(p);

			// Check for slice with no start: [..end]
			if (at(p, token_kind::DOTDOT)) {
				advance(p);
				let end_expr: nullable *node = null;
				if (!at(p, token_kind::RBRACKET)) {
					end_expr = parse_expr(p);
				};
				expect(p, token_kind::RBRACKET);
				let n = node_new(p.arena, node_kind::N_SLICE, size(n_slice_data), left.line, left.col);
				let d = n.data: *n_slice_data;
				d.base = left;
				d.start = null;
				d.end = end_expr;
				left = n;
				continue;
			};

			// Parse first expression (could be index or slice start)
			let first = parse_expr(p);

			// Check for slice: [start..end]
			if (at(p, token_kind::DOTDOT)) {
				advance(p);
				let end_expr: nullable *node = null;
				if (!at(p, token_kind::RBRACKET)) {
					end_expr = parse_expr(p);
				};
				expect(p, token_kind::RBRACKET);
				let n = node_new(p.arena, node_kind::N_SLICE, size(n_slice_data), left.line, left.col);
				let d = n.data: *n_slice_data;
				d.base = left;
				d.start = first;
				d.end = end_expr;
				left = n;
				continue;
			};

			// Regular index
			expect(p, token_kind::RBRACKET);
			let n = node_new(p.arena, node_kind::N_IDX, size(n_idx_data), left.line, left.col);
			let d = n.data: *n_idx_data;
			d.base = left;
			d.index = first;
			left = n;
			continue;
		};

		// Field access
		if (t.kind == token_kind::DOT) {
			advance(p);
			// Field name can be ID, keyword like len/size, or INTEGER for tuple access
			let field = peek(p);
			if (!is_name_token(field.kind) && field.kind != token_kind::INT) {
				die_parse(p, "expected field name");
			};
			advance(p);
			let n = node_new(p.arena, node_kind::N_FLD, size(n_fld_data), left.line, left.col);
			let d = n.data: *n_fld_data;
			d.base = left;
			d.field_ptr = field.val_ptr;
			d.field_len = field.val_len;
			left = n;
			continue;
		};

		// Type cast (: or as)
		if (t.kind == token_kind::COLON || t.kind == token_kind::AS) {
			advance(p);
			let typ = parse_type(p);
			let n = node_new(p.arena, node_kind::N_CAST, size(n_cast_data), left.line, left.col);
			let d = n.data: *n_cast_data;
			d.expr = left;
			d.target = typ;
			left = n;
			continue;
		};

		// Type test: expr is type
		// Special case: expr is null (for nullable pointers)
		if (t.kind == token_kind::IS) {
			advance(p);
			// Check for "is null" - special case for nullable pointers
			if (at(p, token_kind::NULL)) {
				advance(p);
				// Create comparison: expr == null
				let null_node = make_null(p.arena, t.line, t.col);
				left = make_bin(p.arena, token_kind::EQEQ, left, null_node, left.line, left.col);
				continue;
			};
			let typ = parse_type(p);
			let n = node_new(p.arena, node_kind::N_IS, size(n_is_data), left.line, left.col);
			let d = n.data: *n_is_data;
			d.expr = left;
			d.typ = typ;
			left = n;
			continue;
		};

		// Error propagation: expr?
		if (t.kind == token_kind::QUESTION) {
			advance(p);
			let n = node_new(p.arena, node_kind::N_PROP, size(n_prop_data), left.line, left.col);
			let d = n.data: *n_prop_data;
			d.expr = left;
			left = n;
			continue;
		};

		// Error unwrap: expr!
		// Note: BANG in postfix position means unwrap, not unary NOT
		if (t.kind == token_kind::BANG) {
			advance(p);
			let n = node_new(p.arena, node_kind::N_UNWRAP, size(n_prop_data), left.line, left.col);
			let d = n.data: *n_prop_data;
			d.expr = left;
			left = n;
			continue;
		};

		break;
	};

	return left;
};

// Parse array literal [1, 2, 3] or [val...]
fn parse_array_literal(p: *parser, line: u32, col: u16) *node = {
	// Already consumed [
	let elems: [4096]nullable *node = [null...];
	let nelems = 0z;
	let fill: nullable *node = null;

	// Empty array []
	if (at(p, token_kind::RBRACKET)) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_ARR_LIT, size(n_arr_lit_data), line, col);
		let d = n.data: *n_arr_lit_data;
		d.elems = node_array(p.arena, 0);
		d.nelems = 0;
		d.fill = null;
		return n;
	};

	// Parse first element
	let first = parse_expr(p);

	// Check for fill syntax [val...]
	if (at(p, token_kind::ELLIPSIS)) {
		advance(p);
		expect(p, token_kind::RBRACKET);
		let n = node_new(p.arena, node_kind::N_ARR_LIT, size(n_arr_lit_data), line, col);
		let d = n.data: *n_arr_lit_data;
		d.elems = node_array(p.arena, 0);
		d.nelems = 0;
		d.fill = first;
		return n;
	};

	elems[nelems] = first;
	nelems += 1;

	// Parse remaining elements
	for (eat(p, token_kind::COMMA)) {
		if (at(p, token_kind::RBRACKET)) {
			break;  // Trailing comma
		};
		if (nelems >= 4096) {
			die_parse(p, "too many array elements");
		};
		let elem = parse_expr(p);

		// Check if this element is followed by ... (fill)
		if (at(p, token_kind::ELLIPSIS)) {
			advance(p);
			fill = elem;
			break;  // Fill must be last
		};

		elems[nelems] = elem;
		nelems += 1;
	};

	expect(p, token_kind::RBRACKET);

	let n = node_new(p.arena, node_kind::N_ARR_LIT, size(n_arr_lit_data), line, col);
	let d = n.data: *n_arr_lit_data;
	d.nelems = nelems;
	d.fill = fill;
	let arr = node_array(p.arena, nelems);
	for (let i = 0z; i < nelems; i += 1) {
		arr[i] = match (elems[i]) {
		case let e: *node =>
			yield e;
		case null =>
			die_parse(p, "internal error: null element");
			abort();
		};
	};
	d.elems = arr;
	return n;
};

// Parse struct literal: TypeName { field = val, ... }
fn parse_struct_literal(p: *parser, type_name_ptr: *u8, type_name_len: size, line: u32, col: u16) *node = {
	// Already consumed TypeName {
	let fields: [128]nullable *node = [null...];
	let nfields = 0z;

	for (!at(p, token_kind::RBRACE)) {
		if (nfields >= 128) {
			die_parse(p, "too many struct fields");
		};

		let fname = peek(p);
		if (!is_name_token(fname.kind)) {
			die_parse(p, "expected field name");
		};
		advance(p);
		expect(p, token_kind::EQ);
		let val = parse_expr(p);

		let f = node_new(p.arena, node_kind::N_FIELD_INIT, size(n_field_init_data), fname.line, fname.col);
		let fd = f.data: *n_field_init_data;
		fd.name_ptr = fname.val_ptr;
		fd.name_len = fname.val_len;
		fd.value = val;
		fields[nfields] = f;
		nfields += 1;

		if (!eat(p, token_kind::COMMA)) {
			break;
		};
	};

	expect(p, token_kind::RBRACE);

	let n = node_new(p.arena, node_kind::N_STRUCT_LIT, size(n_struct_lit_data), line, col);
	let d = n.data: *n_struct_lit_data;
	d.type_name_ptr = type_name_ptr;
	d.type_name_len = type_name_len;
	d.nfields = nfields;
	let arr = node_array(p.arena, nfields);
	for (let i = 0z; i < nfields; i += 1) {
		arr[i] = match (fields[i]) {
		case let f: *node =>
			yield f;
		case null =>
			die_parse(p, "internal error: null field");
			abort();
		};
	};
	d.fields = arr;
	return n;
};

// Parse function call arguments
fn parse_call(p: *parser, func: *node) *node = {
	// Count arguments first
	let args: [64]nullable *node = [null...];
	let nargs = 0z;
	let has_spread = false;

	if (!at(p, token_kind::RPAREN)) {
		args[nargs] = parse_expr(p);
		nargs += 1;

		// Check for spread ... after first arg
		if (eat(p, token_kind::ELLIPSIS)) {
			has_spread = true;
		} else {
			for (eat(p, token_kind::COMMA)) {
				if (nargs >= 64) {
					die_parse(p, "too many call arguments");
				};
				args[nargs] = parse_expr(p);
				nargs += 1;

				// Check for spread ... after arg (must be last)
				if (eat(p, token_kind::ELLIPSIS)) {
					has_spread = true;
					break;
				};
			};
		};
	};

	expect(p, token_kind::RPAREN);

	let n = node_new(p.arena, node_kind::N_CALL, size(n_call_data), func.line, func.col);
	let d = n.data: *n_call_data;
	d.func = func;
	d.nargs = nargs;
	d.has_spread = has_spread;

	let arr = node_array(p.arena, nargs);
	for (let i = 0z; i < nargs; i += 1) {
		arr[i] = match (args[i]) {
		case let a: *node =>
			yield a;
		case null =>
			die_parse(p, "internal error: null arg");
			abort();
		};
	};
	d.args = arr;

	return n;
};

// Parse expression with Shunting Yard algorithm
export fn parse_expr(p: *parser) *node = {
	return parse_expr_prec(p, 0);
};

// Parse expression with minimum precedence (precedence climbing)
fn parse_expr_prec(p: *parser, min_prec: int) *node = {
	let left = parse_unary(p);

	for (true) {
		let op = (*peek(p)).kind;
		let prec = precedence(op);

		if (prec < min_prec) {
			break;
		};

		advance(p);
		let right = parse_expr_prec(p, prec + 1);
		left = make_bin(p.arena, op, left, right, left.line, left.col);
	};

	return left;
};

// Parse type
export fn parse_type(p: *parser) *node = {
	let t = peek(p);
	let line = t.line;
	let col = t.col;

	// Error type !T
	if (t.kind == token_kind::BANG) {
		advance(p);
		let inner = parse_type(p);
		let n = node_new(p.arena, node_kind::N_TERR, size(n_terr_data), line, col);
		let d = n.data: *n_terr_data;
		d.inner = inner;
		return n;
	};

	// Pointer type (handles *T and *const T)
	if (t.kind == token_kind::STAR) {
		advance(p);
		let is_const = false;
		if (peek(p).kind == token_kind::CONST) {
			advance(p);
			is_const = true;
		};
		let inner = parse_type(p);
		let n = node_new(p.arena, node_kind::N_TPTR, size(n_tptr_data), line, col);
		let d = n.data: *n_tptr_data;
		d.inner = inner;
		d.is_nullable = false;
		d.is_const = is_const;
		return n;
	};

	// Nullable pointer
	if (t.kind == token_kind::NULLABLE) {
		advance(p);
		expect(p, token_kind::STAR);
		let inner = parse_type(p);
		let n = node_new(p.arena, node_kind::N_TPTR, size(n_tptr_data), line, col);
		let d = n.data: *n_tptr_data;
		d.inner = inner;
		d.is_nullable = true;
		d.is_const = false;
		return n;
	};

	// Function type: fn(params) ret
	if (t.kind == token_kind::FN) {
		advance(p);
		expect(p, token_kind::LPAREN);

		let params: [64]nullable *node = [null...];
		let nparams = 0z;

		// Parse parameters
		for (!at(p, token_kind::RPAREN)) {
			if (nparams >= 64) {
				die_parse(p, "too many function type parameters");
			};

			// Parameters can be just types, or name: type
			let pname_ptr: nullable *u8 = null;
			let pname_len: size = 0;

			// Check if this is "name: type" or just "type"
			// If next token after ID/keyword is COLON, then it's named
			let first_tok = peek(p);
			if ((is_name_token(first_tok.kind) || is_type_keyword(first_tok.kind)) && at_offset(p, 1, token_kind::COLON)) {
				// Named parameter: name: type
				pname_ptr = first_tok.val_ptr;
				pname_len = first_tok.val_len;
				advance(p);
				expect(p, token_kind::COLON);
			};

			let ptype = parse_type(p);

			let param = node_new(p.arena, node_kind::N_PARAM, size(n_param_data), first_tok.line, first_tok.col);
			let pd = param.data: *n_param_data;
			// Handle nullable name_ptr - use dummy value if null
			match (pname_ptr) {
			case let ptr: *u8 =>
				pd.name_ptr = ptr;
			case null =>
				pd.name_ptr = strings::toutf8(""): *[*]u8: *u8;
			};
			pd.name_len = pname_len;
			pd.typ = ptype;
			params[nparams] = param;
			nparams += 1;

			if (!eat(p, token_kind::COMMA)) {
				break;
			};
		};

		expect(p, token_kind::RPAREN);

		// Parse return type
		let ret_type = parse_type(p);

		let n = node_new(p.arena, node_kind::N_TFUNC, size(n_tfunc_data), line, col);
		let d = n.data: *n_tfunc_data;
		d.nparams = nparams;
		d.ret_type = ret_type;
		let arr = node_array(p.arena, nparams);
		for (let i = 0z; i < nparams; i += 1) {
			arr[i] = match (params[i]) {
			case let param: *node =>
				yield param;
			case null =>
				die_parse(p, "internal error: null param");
				abort();
			};
		};
		d.params = arr;
		return n;
	};

	// Tagged union type (T1 | T2 | ...) with optional spread (...T)
	if (t.kind == token_kind::LPAREN) {
		advance(p);
		let variants: [32]nullable *node = [null...];
		let nvariants = 0z;
		let spread_mask: u32 = 0;

		// Parse first type (check for spread operator)
		if (eat(p, token_kind::ELLIPSIS)) {
			spread_mask |= 1: u32;
		};
		variants[nvariants] = parse_type(p);
		nvariants += 1;

		// Check for | (tagged union) or , (tuple)
		if (at(p, token_kind::COMMA)) {
			// Tuple type (T1, T2, ...)
			for (eat(p, token_kind::COMMA)) {
				if (nvariants >= 32) {
					die_parse(p, "too many tuple elements");
				};
				variants[nvariants] = parse_type(p);
				nvariants += 1;
			};
			expect(p, token_kind::RPAREN);

			let n = node_new(p.arena, node_kind::N_TTUPLE, size(n_ttagged_data), line, col);
			let d = n.data: *n_ttagged_data;
			d.nvariants = nvariants;
			let arr = node_array(p.arena, nvariants);
			for (let i = 0z; i < nvariants; i += 1) {
				arr[i] = match (variants[i]) {
				case let v: *node =>
					yield v;
				case null =>
					die_parse(p, "internal error: null variant");
					abort();
				};
			};
			d.variants = arr;
			return n;
		};

		if (!at(p, token_kind::PIPE)) {
			// Not a tagged union or tuple, just parenthesized type
			expect(p, token_kind::RPAREN);
			return match (variants[0]) {
			case let v: *node =>
				yield v;
			case null =>
				die_parse(p, "internal error: null variant");
				abort();
			};
		};

		// Parse remaining variants
		for (eat(p, token_kind::PIPE)) {
			if (nvariants >= 32) {
				die_parse(p, "too many tagged union variants");
			};
			// Check for spread operator before type
			if (eat(p, token_kind::ELLIPSIS)) {
				spread_mask |= (1: u32 << nvariants: u32);
			};
			variants[nvariants] = parse_type(p);
			nvariants += 1;
		};
		expect(p, token_kind::RPAREN);

		let n = node_new(p.arena, node_kind::N_TTAGGED, size(n_ttagged_data), line, col);
		let d = n.data: *n_ttagged_data;
		d.nvariants = nvariants;
		d.spread_mask = spread_mask;
		let arr = node_array(p.arena, nvariants);
		for (let i = 0z; i < nvariants; i += 1) {
			arr[i] = match (variants[i]) {
			case let v: *node =>
				yield v;
			case null =>
				die_parse(p, "internal error: null variant");
				abort();
			};
		};
		d.variants = arr;
		return n;
	};

	// Slice type []T, unbounded array [*]T, or array [N]T
	if (t.kind == token_kind::LBRACKET) {
		advance(p);

		// Check for slice []T
		if (at(p, token_kind::RBRACKET)) {
			advance(p);
			let elem = parse_type(p);
			let n = node_new(p.arena, node_kind::N_TSLICE, size(n_tarr_data), line, col);
			let d = n.data: *n_tarr_data;
			d.elem = elem;
			d.length = null;
			return n;
		};

		// Check for unbounded array [*]T
		if (at(p, token_kind::STAR)) {
			advance(p);
			expect(p, token_kind::RBRACKET);
			let elem = parse_type(p);
			// Unbounded array is like a pointer to element type
			let n = node_new(p.arena, node_kind::N_TARR, size(n_tarr_data), line, col);
			let d = n.data: *n_tarr_data;
			d.elem = elem;
			d.length = null;  // null length = unbounded
			return n;
		};

		// Check for inferred size array [_]T
		if (at(p, token_kind::UNDERSCORE)) {
			advance(p);
			expect(p, token_kind::RBRACKET);
			let elem = parse_type(p);
			// Inferred size - we'll determine from initializer
			let n = node_new(p.arena, node_kind::N_TARR, size(n_tarr_data), line, col);
			let d = n.data: *n_tarr_data;
			d.elem = elem;
			d.length = null;  // null = infer from initializer
			d.inferred = true;
			return n;
		};

		// Array with size [N]T
		let sz = parse_expr(p);
		expect(p, token_kind::RBRACKET);
		let elem = parse_type(p);
		let n = node_new(p.arena, node_kind::N_TARR, size(n_tarr_data), line, col);
		let d = n.data: *n_tarr_data;
		d.elem = elem;
		d.length = sz;
		return n;
	};

	// Struct type
	if (t.kind == token_kind::STRUCT) {
		advance(p);
		expect(p, token_kind::LBRACE);

		let fields: [128]nullable *node = [null...];
		let nfields = 0z;

		for (!at(p, token_kind::RBRACE)) {
			if (nfields >= 128) {
				die_parse(p, "too many struct fields");
			};

			// Check for anonymous union
			let fname = peek(p);
			if (fname.kind == token_kind::UNION) {
				// Parse anonymous union - it becomes a field with empty name
				let union_type = parse_type(p);
				let field = node_new(p.arena, node_kind::N_FIELD, size(n_param_data), fname.line, fname.col);
				let fd = field.data: *n_param_data;
				fd.name_ptr = strings::toutf8(""): *[*]u8: *u8;  // Anonymous - empty name
				fd.name_len = 0;
				fd.typ = union_type;
				fields[nfields] = field;
				nfields += 1;

				if (!eat(p, token_kind::COMMA)) {
					break;
				};
				continue;
			};

			// Parse field name (ID or keyword like len/size/cap)
			if (!is_name_token(fname.kind)) {
				die_parse(p, "expected field name in struct");
			};
			advance(p);
			expect(p, token_kind::COLON);
			let ftype = parse_type(p);

			let field = node_new(p.arena, node_kind::N_FIELD, size(n_param_data), fname.line, fname.col);
			let fd = field.data: *n_param_data;
			fd.name_ptr = fname.val_ptr;
			fd.name_len = fname.val_len;
			fd.typ = ftype;
			fields[nfields] = field;
			nfields += 1;

			if (!eat(p, token_kind::COMMA)) {
				break;
			};
		};
		expect(p, token_kind::RBRACE);

		let n = node_new(p.arena, node_kind::N_TSTRUCT, size(n_tstruct_data), line, col);
		let d = n.data: *n_tstruct_data;
		d.nfields = nfields;
		let arr = node_array(p.arena, nfields);
		for (let i = 0z; i < nfields; i += 1) {
			arr[i] = match (fields[i]) {
			case let f: *node =>
				yield f;
			case null =>
				die_parse(p, "internal error: null field");
				abort();
			};
		};
		d.fields = arr;
		return n;
	};

	// Union type (similar to struct but generates C union)
	if (t.kind == token_kind::UNION) {
		advance(p);
		expect(p, token_kind::LBRACE);

		let fields: [64]nullable *node = [null...];
		let nfields = 0z;

		for (!at(p, token_kind::RBRACE)) {
			if (nfields >= 64) {
				die_parse(p, "too many union fields");
			};

			// Parse field name
			let fname = peek(p);
			if (!is_name_token(fname.kind)) {
				die_parse(p, "expected field name in union");
			};
			advance(p);
			expect(p, token_kind::COLON);
			let ftype = parse_type(p);

			let field = node_new(p.arena, node_kind::N_FIELD, size(n_param_data), fname.line, fname.col);
			let fd = field.data: *n_param_data;
			fd.name_ptr = fname.val_ptr;
			fd.name_len = fname.val_len;
			fd.typ = ftype;
			fields[nfields] = field;
			nfields += 1;

			if (!eat(p, token_kind::COMMA)) {
				break;
			};
		};
		expect(p, token_kind::RBRACE);

		// Use n_tstruct_data since unions have the same structure as structs
		let n = node_new(p.arena, node_kind::N_TUNION, size(n_tstruct_data), line, col);
		let d = n.data: *n_tstruct_data;
		d.nfields = nfields;
		let arr = node_array(p.arena, nfields);
		for (let i = 0z; i < nfields; i += 1) {
			arr[i] = match (fields[i]) {
			case let f: *node =>
				yield f;
			case null =>
				die_parse(p, "internal error: null field");
				abort();
			};
		};
		d.fields = arr;
		return n;
	};

	// Enum type
	if (t.kind == token_kind::ENUM) {
		advance(p);

		// Optional base type (e.g., enum u8 { ... })
		let base_type: nullable *node = null;
		if (!at(p, token_kind::LBRACE)) {
			base_type = parse_type(p);
		};

		expect(p, token_kind::LBRACE);

		let members: [128]nullable *node = [null...];
		let nmembers = 0z;

		for (!at(p, token_kind::RBRACE)) {
			if (nmembers >= 128) {
				die_parse(p, "too many enum members");
			};

			let mname = peek(p);
			if (!is_name_token(mname.kind)) {
				die_parse(p, "expected enum member name");
			};
			advance(p);

			let member = node_new(p.arena, node_kind::N_ENUM_MEMBER, size(n_enum_member_data), mname.line, mname.col);
			let md = member.data: *n_enum_member_data;
			md.name_ptr = mname.val_ptr;
			md.name_len = mname.val_len;
			md.value = null;

			// Optional explicit value
			if (eat(p, token_kind::EQ)) {
				md.value = parse_expr(p);
			};

			members[nmembers] = member;
			nmembers += 1;

			if (!eat(p, token_kind::COMMA)) {
				break;
			};
		};
		expect(p, token_kind::RBRACE);

		let n = node_new(p.arena, node_kind::N_TENUM, size(n_tenum_data), line, col);
		let d = n.data: *n_tenum_data;
		d.nmembers = nmembers;
		d.base_type = base_type;
		let arr = node_array(p.arena, nmembers);
		for (let i = 0z; i < nmembers; i += 1) {
			arr[i] = match (members[i]) {
			case let m: *node =>
				yield m;
			case null =>
				die_parse(p, "internal error: null member");
				abort();
			};
		};
		d.members = arr;
		return n;
	};

	// nomem error type
	if (t.kind == token_kind::NOMEM) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_TNOMEM, 0, line, col);
		return n;
	};

	// Primitive type or type name (possibly namespaced like module::Type or enum::MEMBER)
	if (is_type_keyword(t.kind) || t.kind == token_kind::ID) {
		advance(p);
		let name_ptr = t.val_ptr;
		let name_len = t.val_len;

		// Handle namespaced types: module::name -> module_name
		for (at(p, token_kind::COLONCOLON)) {
			advance(p);
			let name2 = peek(p);
			if (!is_name_token(name2.kind)) {
				die_parse(p, "expected identifier after ::");
			};
			advance(p);
			let name_bytes = name_ptr: *[*]u8;
			let name2_bytes = name2.val_ptr: *[*]u8;
			// Build combined name in arena: module_name
			let combined_len = name_len + 1 + name2.val_len;
			let combined = arena_alloc(p.arena, combined_len): *[*]u8;
			// Copy first part
			for (let i = 0z; i < name_len; i += 1) {
				combined[i] = name_bytes[i];
			};
			combined[name_len] = '_';
			// Copy second part
			for (let i = 0z; i < name2.val_len; i += 1) {
				combined[name_len + 1 + i] = name2_bytes[i];
			};
			name_ptr = combined: *u8;
			name_len = combined_len;
		};

		let n = node_new(p.arena, node_kind::N_TPRIM, size(n_id_data), line, col);
		let d = n.data: *n_id_data;
		d.ptr = name_ptr;
		d.length = name_len;
		return n;
	};

	die_parse(p, "unexpected token in type");
	// Unreachable, but return a node to satisfy the type checker.
	return node_new(p.arena, node_kind::N_TPRIM, size(n_id_data), line, col);
};

// Parse block { ... }
export fn parse_block(p: *parser) *node = {
	let t = expect(p, token_kind::LBRACE);
	let line = t.line;
	let col = t.col;

	let stmts: [256]nullable *node = [null...];
	let nstmts = 0z;

	for (!at(p, token_kind::RBRACE) && !at(p, token_kind::EOF)) {
		if (nstmts >= 256) {
			die_parse(p, "too many statements in block");
		};
		stmts[nstmts] = parse_stmt(p);
		nstmts += 1;
	};

	expect(p, token_kind::RBRACE);
	eat(p, token_kind::SEMI);  // Optional trailing semicolon

	let n = node_new(p.arena, node_kind::N_BLOCK, size(n_block_data), line, col);
	let d = n.data: *n_block_data;
	d.nstmts = nstmts;

	let arr = node_array(p.arena, nstmts);
	for (let i = 0z; i < nstmts; i += 1) {
		arr[i] = match (stmts[i]) {
		case let s: *node =>
			yield s;
		case null =>
			die_parse(p, "internal error: null stmt");
			abort();
		};
	};
	d.stmts = arr;

	return n;
};

// Parse statement
export fn parse_stmt(p: *parser) *node = {
	let t = peek(p);
	let line = t.line;
	let col = t.col;

	// Static let/append/insert/delete statement
	if (t.kind == token_kind::STATIC) {
		advance(p);
		let next = peek(p);

		// static append(slice, val)
		if (next.kind == token_kind::APPEND) {
			advance(p);
			expect(p, token_kind::LPAREN);
			let slice = parse_expr(p);
			expect(p, token_kind::COMMA);
			let value = parse_expr(p);
			expect(p, token_kind::RPAREN);
			let n = node_new(p.arena, node_kind::N_APPEND, size(n_append_data), line, col);
			let d = n.data: *n_append_data;
			d.slice = slice;
			d.value = value;
			d.is_static = true;
			// Handle optional ! for error unwrap
			if (peek(p).kind == token_kind::BANG) {
				advance(p);
				let unwrap_n = node_new(p.arena, node_kind::N_UNWRAP, size(n_prop_data), line, col);
				let ud = unwrap_n.data: *n_prop_data;
				ud.expr = n;
				n = unwrap_n;
			};
			eat(p, token_kind::SEMI);  // optional semicolon - handled by expression statement
			return n;
		};

		// static insert(slice[idx], val)
		if (next.kind == token_kind::INSERT) {
			advance(p);
			expect(p, token_kind::LPAREN);
			let base = parse_expr(p);
			expect(p, token_kind::COMMA);
			let value = parse_expr(p);
			expect(p, token_kind::RPAREN);
			let n = node_new(p.arena, node_kind::N_INSERT, size(n_insert_data), line, col);
			let d = n.data: *n_insert_data;
			if (base.kind == node_kind::N_IDX) {
				let idx_data = base.data: *n_idx_data;
				d.slice = idx_data.base;
				d.index = idx_data.index;
			} else {
				d.slice = base;
				d.index = node_new(p.arena, node_kind::N_INT, size(n_int_data), line, col);
			};
			d.value = value;
			d.is_static = true;
			// Handle optional ! for error unwrap
			if (peek(p).kind == token_kind::BANG) {
				advance(p);
				let unwrap_n = node_new(p.arena, node_kind::N_UNWRAP, size(n_prop_data), line, col);
				let ud = unwrap_n.data: *n_prop_data;
				ud.expr = n;
				n = unwrap_n;
			};
			eat(p, token_kind::SEMI);  // optional semicolon
			return n;
		};

		// static delete(slice[idx])
		if (next.kind == token_kind::DELETE) {
			advance(p);
			expect(p, token_kind::LPAREN);
			let base = parse_expr(p);
			expect(p, token_kind::RPAREN);
			let n = node_new(p.arena, node_kind::N_DELETE, size(n_delete_data), line, col);
			let d = n.data: *n_delete_data;
			if (base.kind == node_kind::N_IDX) {
				let idx_data = base.data: *n_idx_data;
				d.slice = idx_data.base;
				d.index = idx_data.index;
			} else {
				d.slice = base;
				d.index = node_new(p.arena, node_kind::N_INT, size(n_int_data), line, col);
			};
			d.is_static = true;
			// Handle optional ! for error unwrap
			if (peek(p).kind == token_kind::BANG) {
				advance(p);
				let unwrap_n = node_new(p.arena, node_kind::N_UNWRAP, size(n_prop_data), line, col);
				let ud = unwrap_n.data: *n_prop_data;
				ud.expr = n;
				n = unwrap_n;
			};
			eat(p, token_kind::SEMI);  // optional semicolon
			return n;
		};

		// static let
		return parse_let(p, true);
	};

	// Let statement
	if (t.kind == token_kind::LET || t.kind == token_kind::CONST) {
		return parse_let(p, false);
	};

	// Return statement
	if (t.kind == token_kind::RETURN) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_RET, size(n_ret_data), line, col);
		let d = n.data: *n_ret_data;
		if (!at(p, token_kind::SEMI)) {
			d.expr = parse_expr(p);
		} else {
			d.expr = null;
		};
		expect(p, token_kind::SEMI);
		return n;
	};

	// If statement
	if (t.kind == token_kind::IF) {
		return parse_if(p);
	};

	// For loop
	if (t.kind == token_kind::FOR) {
		return parse_for(p);
	};

	// Block
	if (t.kind == token_kind::LBRACE) {
		return parse_block(p);
	};

	// Break
	if (t.kind == token_kind::BREAK) {
		advance(p);
		expect(p, token_kind::SEMI);
		return node_new(p.arena, node_kind::N_BREAK, 0, line, col);
	};

	// Continue
	if (t.kind == token_kind::CONTINUE) {
		advance(p);
		expect(p, token_kind::SEMI);
		return node_new(p.arena, node_kind::N_CONT, 0, line, col);
	};

	// Defer statement
	if (t.kind == token_kind::DEFER) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_DEFER, size(n_defer_data), line, col);
		let d = n.data: *n_defer_data;
		d.expr = parse_expr(p);
		expect(p, token_kind::SEMI);
		return n;
	};

	// Switch statement
	if (t.kind == token_kind::SWITCH) {
		let n = parse_switch(p);
		expect(p, token_kind::SEMI);
		return n;
	};

	// Match expression
	if (t.kind == token_kind::MATCH) {
		let n = parse_match(p);
		expect(p, token_kind::SEMI);
		return n;
	};

	// Yield expression
	if (t.kind == token_kind::YIELD) {
		advance(p);
		let n = node_new(p.arena, node_kind::N_YIELD, size(n_yield_data), line, col);
		let d = n.data: *n_yield_data;
		if (!at(p, token_kind::SEMI)) {
			d.expr = parse_expr(p);
		} else {
			d.expr = null;
		};
		expect(p, token_kind::SEMI);
		return n;
	};

	// Expression or assignment statement
	let expr = parse_expr(p);

	// Check for assignment
	let op = (*peek(p)).kind;
	if (is_assign_op(op)) {
		advance(p);
		let val = parse_expr(p);
		expect(p, token_kind::SEMI);

		let n = node_new(p.arena, node_kind::N_ASGN, size(n_asgn_data), line, col);
		let d = n.data: *n_asgn_data;
		d.target = expr;
		d.op = op;
		d.value = val;
		return n;
	};

	expect(p, token_kind::SEMI);
	let n = node_new(p.arena, node_kind::N_EXPR, size(n_ret_data), line, col);
	let d = n.data: *n_ret_data;
	d.expr = expr;  // Reuse ret data for single expr
	return n;
};

// Check if token is assignment operator
fn is_assign_op(k: token_kind) bool = {
	return switch (k) {
	case token_kind::EQ, token_kind::PLUS_EQ, token_kind::MINUS_EQ,
	     token_kind::STAR_EQ, token_kind::SLASH_EQ, token_kind::PERCENT_EQ,
	     token_kind::AMP_EQ, token_kind::PIPE_EQ, token_kind::CARET_EQ,
	     token_kind::LSHIFT_EQ, token_kind::RSHIFT_EQ => yield true;
	case => yield false;
	};
};

// Parse let statement
fn parse_let(p: *parser, is_static: bool) *node = {
	let t = advance(p);  // let or const
	let is_mut = t.kind == token_kind::LET;
	let line = t.line;
	let col = t.col;

	let name = expect(p, token_kind::ID);

	let n = node_new(p.arena, node_kind::N_LET, size(n_let_data), line, col);
	let d = n.data: *n_let_data;
	d.name_ptr = name.val_ptr;
	d.name_len = name.val_len;
	d.is_mut = is_mut;
	d.is_static = is_static;
	d.typ = null;
	d.init = null;

	// Optional type annotation
	if (eat(p, token_kind::COLON)) {
		d.typ = parse_type(p);
	};

	// Optional initializer
	if (eat(p, token_kind::EQ)) {
		d.init = parse_expr(p);
	};

	expect(p, token_kind::SEMI);
	return n;
};

// Parse if branch - can be block, statement-starting keyword, or expression
fn parse_if_branch(p: *parser) *node = {
	// If it's a block, parse the block
	if (at(p, token_kind::LBRACE)) {
		return parse_block(p);
	};
	// If it's a statement-starting keyword, parse as statement
	if (at(p, token_kind::RETURN) || at(p, token_kind::YIELD) ||
	    at(p, token_kind::BREAK) || at(p, token_kind::CONTINUE)) {
		return parse_stmt(p);
	};
	// Otherwise, it's an expression (e.g., in `if (cond) a else b`)
	return parse_expr(p);
};

// Parse if statement/expression
fn parse_if(p: *parser) *node = {
	let t = advance(p);  // if
	let line = t.line;
	let col = t.col;

	expect(p, token_kind::LPAREN);
	let cond = parse_expr(p);
	expect(p, token_kind::RPAREN);

	let then_branch = parse_if_branch(p);

	let n = node_new(p.arena, node_kind::N_IF, size(n_if_data), line, col);
	let d = n.data: *n_if_data;
	d.cond = cond;
	d.then_branch = then_branch;
	d.else_branch = null;

	if (eat(p, token_kind::ELSE)) {
		if (at(p, token_kind::IF)) {
			d.else_branch = parse_if(p);
		} else {
			d.else_branch = parse_if_branch(p);
		};
	};

	return n;
};

// Parse for loop
fn parse_for(p: *parser) *node = {
	let t = advance(p);  // for
	let line = t.line;
	let col = t.col;

	expect(p, token_kind::LPAREN);

	// Check for for-each patterns using lookahead:
	// for (let ID .. expr) - for-each by value
	// for (let ID &.. expr) - for-each by reference
	if (at(p, token_kind::LET) && at_offset(p, 1, token_kind::ID)) {
		// Check for &.. pattern: let ID &..
		if (at_offset(p, 2, token_kind::AMP) && at_offset(p, 3, token_kind::DOTDOT)) {
			advance(p);  // let
			let name = advance(p);  // ID
			advance(p);  // &
			advance(p);  // ..
			let iterable = parse_expr(p);
			expect(p, token_kind::RPAREN);
			let body = parse_block(p);

			let n = node_new(p.arena, node_kind::N_FOREACH_REF, size(n_foreach_data), line, col);
			let d = n.data: *n_foreach_data;
			d.name_ptr = name.val_ptr;
			d.name_len = name.val_len;
			d.iterable = iterable;
			d.body = body;
			return n;
		};
		// Check for .. pattern: let ID ..
		if (at_offset(p, 2, token_kind::DOTDOT)) {
			advance(p);  // let
			let name = advance(p);  // ID
			advance(p);  // ..
			let iterable = parse_expr(p);
			expect(p, token_kind::RPAREN);
			let body = parse_block(p);

			let n = node_new(p.arena, node_kind::N_FOREACH, size(n_foreach_data), line, col);
			let d = n.data: *n_foreach_data;
			d.name_ptr = name.val_ptr;
			d.name_len = name.val_len;
			d.iterable = iterable;
			d.body = body;
			return n;
		};
		// Check for => pattern: let ID => (iterator for-each)
		if (at_offset(p, 2, token_kind::ARROW)) {
			advance(p);  // let
			let name = advance(p);  // ID
			advance(p);  // =>
			let iterable = parse_expr(p);
			expect(p, token_kind::RPAREN);
			let body = parse_block(p);

			let n = node_new(p.arena, node_kind::N_FOREACH_ITER, size(n_foreach_data), line, col);
			let d = n.data: *n_foreach_data;
			d.name_ptr = name.val_ptr;
			d.name_len = name.val_len;
			d.iterable = iterable;
			d.body = body;
			return n;
		};
	};

	let n = node_new(p.arena, node_kind::N_FOR, size(n_for_data), line, col);
	let d = n.data: *n_for_data;
	d.init = null;
	d.cond = null;
	d.step = null;

	// Parse for (init; cond; step) or for (cond)
	if (!at(p, token_kind::RPAREN)) {
		// Check for empty init: for (; cond; step)
		if (at(p, token_kind::SEMI)) {
			// C-style with empty init: for (; cond; step)
			expect(p, token_kind::SEMI);

			if (!at(p, token_kind::SEMI)) {
				d.cond = parse_expr(p);
			};
			expect(p, token_kind::SEMI);

			if (!at(p, token_kind::RPAREN)) {
				d.step = parse_for_step(p);
			};
		} else {
			// Check for while-style: for (cond) body
			// vs C-style: for (init; cond; step) body

			// First try to parse as expression
			let first = parse_for_clause(p);

			if (at(p, token_kind::RPAREN)) {
				// while-style: for (cond)
				d.cond = first;
			} else {
				// C-style: init; cond; step
				d.init = first;
				expect(p, token_kind::SEMI);

				if (!at(p, token_kind::SEMI)) {
					d.cond = parse_expr(p);
				};
				expect(p, token_kind::SEMI);

				if (!at(p, token_kind::RPAREN)) {
					d.step = parse_for_step(p);
				};
			};
		};
	};

	expect(p, token_kind::RPAREN);
	d.body = parse_block(p);

	return n;
};

// Parse for loop init clause (let stmt or expression)
fn parse_for_clause(p: *parser) *node = {
	if (at(p, token_kind::LET)) {
		let t = advance(p);
		let name = expect(p, token_kind::ID);

		let n = node_new(p.arena, node_kind::N_LET, size(n_let_data), t.line, t.col);
		let d = n.data: *n_let_data;
		d.name_ptr = name.val_ptr;
		d.name_len = name.val_len;
		d.is_mut = true;
		d.typ = null;
		d.init = null;

		if (eat(p, token_kind::COLON)) {
			d.typ = parse_type(p);
		};
		if (eat(p, token_kind::EQ)) {
			d.init = parse_expr(p);
		};

		return n;
	};

	return parse_expr(p);
};

// Parse for loop step (expression or assignment)
fn parse_for_step(p: *parser) *node = {
	let expr = parse_expr(p);
	let t = peek(p);
	let line = expr.line;
	let col = expr.col;

	if (is_assign_op(t.kind)) {
		advance(p);
		let val = parse_expr(p);
		let n = node_new(p.arena, node_kind::N_ASGN, size(n_asgn_data), line, col);
		let d = n.data: *n_asgn_data;
		d.target = expr;
		d.op = t.kind;
		d.value = val;
		return n;
	};

	return expr;
};

// Parse switch statement
// Syntax: switch (expr) { case val1, val2 => body; case => default; };
fn parse_switch(p: *parser) *node = {
	let t = advance(p);  // switch
	let line = t.line;
	let col = t.col;

	expect(p, token_kind::LPAREN);
	let expr = parse_expr(p);
	expect(p, token_kind::RPAREN);
	expect(p, token_kind::LBRACE);

	// Parse cases
	let cases: [64]nullable *node = [null...];
	let ncases = 0z;

	for (!at(p, token_kind::RBRACE)) {
		if (ncases >= 64) {
			die_parse(p, "too many switch cases");
		};

		let case_line = (*peek(p)).line;
		let case_col = (*peek(p)).col;

		// All cases start with 'case' keyword
		expect(p, token_kind::CASE);

		let c = node_new(p.arena, node_kind::N_CASE, size(n_case_data), case_line, case_col);
		let cd = c.data: *n_case_data;

		// Check for default case (case =>)
		// Check for default case (case =>)
		if (at(p, token_kind::ARROW)) {
			cd.values = node_array(p.arena, 0);
			cd.nvalues = 0;
		} else {
			// Parse case values
			let vals: [16]nullable *node = [null...];
			let nvals = 0z;

			vals[nvals] = parse_expr(p);
			nvals += 1;

			for (eat(p, token_kind::COMMA)) {
				if (nvals >= 16) {
					die_parse(p, "too many case values");
				};
				vals[nvals] = parse_expr(p);
				nvals += 1;
			};

			cd.nvalues = nvals;
			let arr = node_array(p.arena, nvals);
			for (let i = 0z; i < nvals; i += 1) {
				arr[i] = match (vals[i]) {
				case let v: *node =>
					yield v;
				case null =>
					die_parse(p, "internal error: null val");
					abort();
				};
			};
			cd.values = arr;
		};

		expect(p, token_kind::ARROW);

		// Parse case body - can be block, statement, or expression
		if (at(p, token_kind::LBRACE)) {
			cd.body = parse_block(p);
			// parse_block already consumes optional trailing semicolon
		} else {
			// Non-block case body - could be statement (return, let, etc.) or expression
			cd.body = parse_stmt(p);
		};

		cases[ncases] = c;
		ncases += 1;
	};

	expect(p, token_kind::RBRACE);

	let n = node_new(p.arena, node_kind::N_SWITCH, size(n_switch_data), line, col);
	let d = n.data: *n_switch_data;
	d.expr = expr;
	d.ncases = ncases;
	let arr = node_array(p.arena, ncases);
	for (let i = 0z; i < ncases; i += 1) {
		arr[i] = match (cases[i]) {
		case let c: *node =>
			yield c;
		case null =>
			die_parse(p, "internal error: null case");
			abort();
		};
	};
	d.cases = arr;

	return n;
};

// Parse match expression
// match (expr) { case let name: type => body; case type => body; case => body; }
fn parse_match(p: *parser) *node = {
	let t = advance(p);  // match
	let line = t.line;
	let col = t.col;

	expect(p, token_kind::LPAREN);
	let expr = parse_expr(p);
	expect(p, token_kind::RPAREN);
	expect(p, token_kind::LBRACE);

	// Parse cases
	let cases: [64]nullable *node = [null...];
	let ncases = 0z;

	for (!at(p, token_kind::RBRACE)) {
		if (ncases >= 64) {
			die_parse(p, "too many match cases");
		};

		let case_line = (*peek(p)).line;
		let case_col = (*peek(p)).col;

		// All cases start with 'case' keyword
		expect(p, token_kind::CASE);

		let c = node_new(p.arena, node_kind::N_MCASE, size(n_mcase_data), case_line, case_col);
		let cd = c.data: *n_mcase_data;
		cd.bind_ptr = strings::toutf8(""): *[*]u8: *u8;
		cd.bind_len = 0;

		// Check for catch-all case (case =>)
		if (at(p, token_kind::ARROW)) {
			cd.typ = null;
		} else if (eat(p, token_kind::NULL)) {
			// null case for nullable pointers: case null =>
			cd.typ = node_new(p.arena, node_kind::N_NULL, 0, case_line, case_col);
		} else {
			// Check for binding: case let name: type =>
			if (eat(p, token_kind::LET)) {
				let bind_name = expect(p, token_kind::ID);
				cd.bind_ptr = bind_name.val_ptr;
				cd.bind_len = bind_name.val_len;
				expect(p, token_kind::COLON);
			};
			// Parse the type
			cd.typ = parse_type(p);
		};

		expect(p, token_kind::ARROW);

		// Parse case body - can be a block or multiple statements until next case/}
		if (at(p, token_kind::LBRACE)) {
			cd.body = parse_block(p);
			// parse_block already consumes optional trailing semicolon
		} else {
			// Parse statements until we see 'case' or '}'
			// Collect into an implicit block
			let stmts: [64]nullable *node = [null...];
			let nstmts: size = 0;
			for (!at(p, token_kind::CASE) && !at(p, token_kind::RBRACE)) {
				if (nstmts >= 64) {
					die_parse(p, "too many statements in match case");
				};
				stmts[nstmts] = parse_stmt(p);
				nstmts += 1;
			};
			// Create a block node for the statements
			let block = node_new(p.arena, node_kind::N_BLOCK, size(n_block_data), case_line, case_col);
			let bd = block.data: *n_block_data;
			bd.nstmts = nstmts;
			let arr = node_array(p.arena, nstmts);
			for (let i = 0z; i < nstmts; i += 1) {
				arr[i] = match (stmts[i]) {
				case let s: *node =>
					yield s;
				case null =>
					die_parse(p, "internal error: null stmt");
					abort();
				};
			};
			bd.stmts = arr;
			cd.body = block;
		};

		cases[ncases] = c;
		ncases += 1;
	};

	expect(p, token_kind::RBRACE);

	let n = node_new(p.arena, node_kind::N_MATCH, size(n_match_data), line, col);
	let d = n.data: *n_match_data;
	d.expr = expr;
	d.ncases = ncases;
	let arr = node_array(p.arena, ncases);
	for (let i = 0z; i < ncases; i += 1) {
		arr[i] = match (cases[i]) {
		case let c: *node =>
			yield c;
		case null =>
			die_parse(p, "internal error: null case");
			abort();
		};
	};
	d.cases = arr;

	return n;
};

// Parse function declaration (delegates to parse_fn_impl with default attributes)
export fn parse_fn(p: *parser, exported: bool) *node = {
	return parse_fn_impl(p, exported, false, false, false, strings::toutf8(""): *[*]u8: *u8, 0);
};

// Parse function with attributes (delegates to parse_fn_impl)
fn parse_fn_with_attrs(p: *parser, exported: bool, is_init: bool, is_fini: bool, is_test: bool, symbol_ptr: nullable *u8, symbol_len: size) *node = {
	return parse_fn_impl(p, exported, is_init, is_fini, is_test, symbol_ptr, symbol_len);
};

// Internal function parsing implementation
fn parse_fn_impl(p: *parser, exported: bool, is_init: bool, is_fini: bool, is_test: bool, symbol_ptr: nullable *u8, symbol_len: size) *node = {
	let t = expect(p, token_kind::FN);
	let line = t.line;
	let col = t.col;

	let name = expect(p, token_kind::ID);

	expect(p, token_kind::LPAREN);

	// Parse parameters
	let params: [32]nullable *node = [null...];
	let nparams = 0z;

	if (!at(p, token_kind::RPAREN)) {
		params[nparams] = parse_param(p);
		nparams += 1;

		for (eat(p, token_kind::COMMA)) {
			if (nparams >= 32) {
				die_parse(p, "too many function parameters");
			};
			params[nparams] = parse_param(p);
			nparams += 1;
		};
	};

	expect(p, token_kind::RPAREN);

	// Return type
	let ret_type: nullable *node = null;
	if (!at(p, token_kind::EQ) && !at(p, token_kind::SEMI)) {
		ret_type = parse_type(p);
	};

	let n = node_new(p.arena, node_kind::N_FN, size(n_fn_data), line, col);
	let d = n.data: *n_fn_data;
	d.name_ptr = name.val_ptr;
	d.name_len = name.val_len;
	d.exported = exported;
	d.ret_type = ret_type;
	d.nparams = nparams;
	d.is_init = is_init;
	d.is_fini = is_fini;
	d.is_test = is_test;
	d.symbol_ptr = symbol_ptr;
	d.symbol_len = symbol_len;

	let arr = node_array(p.arena, nparams);
	for (let i = 0z; i < nparams; i += 1) {
		arr[i] = match (params[i]) {
		case let param: *node =>
			yield param;
		case null =>
			die_parse(p, "internal error: null param");
			abort();
		};
	};
	d.params = arr;

	// Function body
	if (eat(p, token_kind::EQ)) {
		d.body = parse_expr(p);
		eat(p, token_kind::SEMI);
	} else if (at(p, token_kind::LBRACE)) {
		d.body = parse_block(p);
	} else {
		// Declaration only
		d.body = null;
		expect(p, token_kind::SEMI);
	};

	return n;
};

// Parse function parameter
fn parse_param(p: *parser) *node = {
	// Parameter name can be ID or type keyword (e.g., size: size)
	let t = peek(p);
	if (!is_name_token(t.kind)) {
		die_parse(p, "expected parameter name");
	};
	let name = t;
	advance(p);
	expect(p, token_kind::COLON);
	let typ = parse_type(p);

	// Check for variadic ... after type
	let is_variadic = false;
	if (eat(p, token_kind::ELLIPSIS)) {
		is_variadic = true;
	};

	// Check for default value: = expr
	let default_value: nullable *node = null;
	if (eat(p, token_kind::EQ)) {
		default_value = parse_expr(p);
	};

	let n = node_new(p.arena, node_kind::N_PARAM, size(n_param_data), name.line, name.col);
	let d = n.data: *n_param_data;
	d.name_ptr = name.val_ptr;
	d.name_len = name.val_len;
	d.typ = typ;
	d.is_variadic = is_variadic;
	d.default_value = default_value;
	return n;
};

// Parse top-level declaration
export fn parse_decl(p: *parser) *node = {
	let exported = eat(p, token_kind::EXPORT);

	// Parse function attributes (@init, @fini, @test, @symbol("name"))
	let is_init = false;
	let is_fini = false;
	let is_test = false;
	let symbol_ptr: nullable *u8 = null;
	let symbol_len: size = 0;

	for (at(p, token_kind::AT)) {
		advance(p);  // consume @
		let attr = expect(p, token_kind::ID);
		let attr_ptr = attr.val_ptr;
		let attr_len = attr.val_len;

		// Check attribute name using first-class string comparison
		let attr_str = strings::fromutf8_unsafe((attr_ptr: *[*]u8)[..attr_len]);
		if (attr_str == "init") {
			is_init = true;
		} else if (attr_str == "fini") {
			is_fini = true;
		} else if (attr_str == "test") {
			is_test = true;
		} else if (attr_str == "symbol") {
			// @symbol("name") - strip quotes from string
			expect(p, token_kind::LPAREN);
			let str_tok = expect(p, token_kind::STR);
			// Skip opening quote and don't include closing quote
			symbol_ptr = (str_tok.val_ptr: uintptr + 1): *u8;
			symbol_len = str_tok.val_len - 2;
			expect(p, token_kind::RPAREN);
		};
	};

	// Check for export after attributes (e.g., @symbol(...) export fn ...)
	if (!exported && eat(p, token_kind::EXPORT)) {
		exported = true;
	};

	let t = peek(p);

	if (t.kind == token_kind::FN) {
		return parse_fn_with_attrs(p, exported, is_init, is_fini, is_test, symbol_ptr, symbol_len);
	};

	// Type definition
	if (t.kind == token_kind::TYPE) {
		advance(p);
		let name = expect(p, token_kind::ID);
		expect(p, token_kind::EQ);
		let typ = parse_type(p);
		expect(p, token_kind::SEMI);

		let n = node_new(p.arena, node_kind::N_TYPEDEF, size(n_typedef_data), name.line, name.col);
		let d = n.data: *n_typedef_data;
		d.name_ptr = name.val_ptr;
		d.name_len = name.val_len;
		d.typ = typ;
		d.exported = exported;
		return n;
	};

	// Constant definition
	if (t.kind == token_kind::DEF) {
		advance(p);
		let name = expect(p, token_kind::ID);
		let typ: nullable *node = null;
		if (eat(p, token_kind::COLON)) {
			typ = parse_type(p);
		};
		expect(p, token_kind::EQ);
		let value = parse_expr(p);
		expect(p, token_kind::SEMI);

		// Store def as a node - we'll emit it as #define or static const
		let n = node_new(p.arena, node_kind::N_DEF, size(n_let_data), name.line, name.col);
		let d = n.data: *n_let_data;
		d.name_ptr = name.val_ptr;
		d.name_len = name.val_len;
		d.typ = typ;
		d.init = value;
		d.is_mut = false;
		return n;
	};

	// Use statement
	if (t.kind == token_kind::USE) {
		advance(p);
		// Get first identifier
		let first = expect(p, token_kind::ID);

		if (eat(p, token_kind::EQ)) {
			// Explicit alias: use t = path;
			let path_start = expect(p, token_kind::ID);
			let last = path_start;
			for (eat(p, token_kind::COLONCOLON)) {
				last = expect(p, token_kind::ID);
			};
			expect(p, token_kind::SEMI);
			// Build combined path string in arena
			let path_bytes = path_start.val_ptr: *[*]u8;
			let path_len = (last.val_ptr: uintptr - path_start.val_ptr: uintptr): size + last.val_len;
			let combined = arena_alloc(p.arena, path_len): *[*]u8;
			for (let i = 0z; i < path_len; i += 1) {
				combined[i] = path_bytes[i];
			};
			// Create N_USE node
			let n = node_new(p.arena, node_kind::N_USE, size(n_use_data), first.line, first.col);
			let d = n.data: *n_use_data;
			d.module_ptr = combined: *u8;
			d.module_len = path_len;
			d.alias_ptr = first.val_ptr;
			d.alias_len = first.val_len;
			return n;
		};

		// Regular use: parse path, implicit alias = last component
		let last = first;
		for (eat(p, token_kind::COLONCOLON)) {
			last = expect(p, token_kind::ID);
		};
		expect(p, token_kind::SEMI);
		// Build combined path string in arena
		let path_bytes = first.val_ptr: *[*]u8;
		let path_len = (last.val_ptr: uintptr - first.val_ptr: uintptr): size + last.val_len;
		let combined = arena_alloc(p.arena, path_len): *[*]u8;
		for (let i = 0z; i < path_len; i += 1) {
			combined[i] = path_bytes[i];
		};
		// Create N_USE node
		let n = node_new(p.arena, node_kind::N_USE, size(n_use_data), first.line, first.col);
		let d = n.data: *n_use_data;
		d.module_ptr = combined: *u8;
		d.module_len = path_len;
		d.alias_ptr = last.val_ptr;
		d.alias_len = last.val_len;
		return n;
	};

	// Global variable declaration (let or const at top level)
	if (t.kind == token_kind::LET || t.kind == token_kind::CONST) {
		let is_mut = t.kind == token_kind::LET;
		advance(p);
		let name = expect(p, token_kind::ID);
		let n = node_new(p.arena, node_kind::N_GLOBAL, size(n_let_data), name.line, name.col);
		let d = n.data: *n_let_data;
		d.name_ptr = name.val_ptr;
		d.name_len = name.val_len;
		d.is_mut = is_mut;
		d.is_static = false;
		d.typ = null;
		d.init = null;

		if (eat(p, token_kind::COLON)) {
			d.typ = parse_type(p);
		};
		if (eat(p, token_kind::EQ)) {
			d.init = parse_expr(p);
		};
		expect(p, token_kind::SEMI);
		return n;
	};

	die_parse(p, "unexpected declaration");
	// Unreachable, but return a node to satisfy the type checker.
	return node_new(p.arena, node_kind::N_UNIT, size(n_unit_data), t.line, t.col);
};

// Parse compilation unit
export fn parse_unit(p: *parser) *node = {
	let decls: [2048]nullable *node = [null...];
	let ndecls = 0z;

	for (!at(p, token_kind::EOF)) {
		if (ndecls >= 2048) {
			die_parse(p, "too many declarations");
		};
		decls[ndecls] = parse_decl(p);
		ndecls += 1;
	};

	let n = node_new(p.arena, node_kind::N_UNIT, size(n_unit_data), 1, 1);
	let d = n.data: *n_unit_data;
	d.ndecls = ndecls;

	let arr = node_array(p.arena, ndecls);
	for (let i = 0z; i < ndecls; i += 1) {
		arr[i] = match (decls[i]) {
		case let d: *node =>
			yield d;
		case null =>
			die_parse(p, "internal error: null decl");
			abort();
		};
	};
	d.decls = arr;

	return n;
};

// Parse integer value from token
fn parse_int_value(ptr: *u8, length: size) i64 = {
	let bytes = ptr: *[*]u8;
	let val: i64 = 0;
	let base: i64 = 10;
	let i = 0z;

	// Check for base prefix
	if (length >= 2 && bytes[0] == '0') {
		let c = bytes[1];
		if (c == 'x' || c == 'X') {
			base = 16;
			i = 2;
		} else if (c == 'o' || c == 'O') {
			base = 8;
			i = 2;
		} else if (c == 'b' || c == 'B') {
			base = 2;
			i = 2;
		};
	};

	for (i < length) {
		let c = bytes[i];
		i += 1;

		// Skip underscores
		if (c == '_') {
			continue;
		};

		// Stop at suffix
		if (c == 'i' || c == 'u' || c == 'z') {
			break;
		};

		let digit: i64 = 0;
		if (c >= '0' && c <= '9') {
			digit = (c - '0'): i64;
		} else if (c >= 'a' && c <= 'f') {
			digit = (c - 'a' + 10): i64;
		} else if (c >= 'A' && c <= 'F') {
			digit = (c - 'A' + 10): i64;
		} else {
			break;
		};

		val = val * base + digit;
	};

	return val;
};

fn digit_val(c: u8) i64 = {
	if (c >= '0' && c <= '9') {
		return (c - '0'): i64;
	} else if (c >= 'a' && c <= 'f') {
		return (c - 'a' + 10): i64;
	} else if (c >= 'A' && c <= 'F') {
		return (c - 'A' + 10): i64;
	};
	return -1;
};

fn digits_with_underscores_ok(bytes: *[*]u8, start: size, end: size, base: i64) bool = {
	if (end <= start) {
		return false;
	};
	let first = bytes[start];
	let last = bytes[end - 1];
	if (first == '_' || last == '_') { return false; };
	let digit_first = digit_val(first);
	let digit_last = digit_val(last);
	if (digit_first < 0 || digit_first >= base) { return false; };
	if (digit_last < 0 || digit_last >= base) { return false; };
	for (let i = start + 1; i + 1 < end; i += 1) {
		let c = bytes[i];
		if (c == '_') { continue; };
		let digit = digit_val(c);
		if (digit < 0 || digit >= base) { return false; };
	};
	return true;
};

fn int_literal_underscores_ok(bytes: *[*]u8, length: size) bool = {
	let base: i64 = 10;
	let start = 0z;
	if (length >= 2 && bytes[0] == '0') {
		let c = bytes[1];
		if (c == 'x' || c == 'X') {
			base = 16;
			start = 2;
		} else if (c == 'o' || c == 'O') {
			base = 8;
			start = 2;
		} else if (c == 'b' || c == 'B') {
			base = 2;
			start = 2;
		};
	};
	let end = length;
	let i: size = start;
	for (i < length) {
		let c = bytes[i];
		if (c == 'i' || c == 'u' || c == 'z') {
			end = i;
			break;
		};
		i += 1;
	};
	return digits_with_underscores_ok(bytes, start, end, base);
};

fn float_literal_underscores_ok(bytes: *[*]u8, length: size) bool = {
	let end = length;
	if (length >= 3 && bytes[length - 3] == 'f') {
		let c1 = bytes[length - 2];
		let c2 = bytes[length - 1];
		if ((c1 == '3' && c2 == '2') || (c1 == '6' && c2 == '4')) {
			end = length - 3;
		};
	};
	let exp_pos = end;
	for (let i = 0z; i < end; i += 1) {
		let c = bytes[i];
		if (c == 'e' || c == 'E') {
			exp_pos = i;
			break;
		};
	};
	let main_end = exp_pos;
	if (exp_pos < end) {
		let exp_start = exp_pos + 1;
		if (exp_start < end) {
			let c = bytes[exp_start];
			if (c == '+' || c == '-') { exp_start += 1; };
		};
		if (!digits_with_underscores_ok(bytes, exp_start, end, 10)) {
			return false;
		};
	};
	let dot_pos = main_end;
	for (let i = 0z; i < main_end; i += 1) {
		if (bytes[i] == '.') {
			dot_pos = i;
			break;
		};
	};
	if (dot_pos < main_end) {
		if (!digits_with_underscores_ok(bytes, 0, dot_pos, 10)) {
			return false;
		};
		if (!digits_with_underscores_ok(bytes, dot_pos + 1, main_end, 10)) {
			return false;
		};
		return true;
	};
	return digits_with_underscores_ok(bytes, 0, main_end, 10);
};
