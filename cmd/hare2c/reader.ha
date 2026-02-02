// reader.ha - Tokenizer for Hare source

// Reader state
export type reader = struct {
	src: *[*]u8,
	srclen: size,
	pos: size,
	line: u32,
	col: u16,
	arena: *arena,
};

// Create a new reader
export fn reader_new(a: *arena, src: *[*]u8, srclen: size) reader = {
	return reader {
		src = src,
		srclen = srclen,
		pos = 0,
		line = 1,
		col = 1,
		arena = a,
	};
};

// Check if at end
fn at_end(r: *reader) bool = {
	return r.pos >= r.srclen;
};

// Peek current character
fn r_peek(r: *reader) u8 = {
	if (r.pos >= r.srclen) return 0;
	return r.src[r.pos];
};

// Peek ahead n characters
fn r_peek_n(r: *reader, n: size) u8 = {
	if (r.pos + n >= r.srclen) return 0;
	return r.src[r.pos + n];
};

// Advance and return current character
fn r_advance(r: *reader) u8 = {
	if (r.pos >= r.srclen) return 0;
	let c = r.src[r.pos];
	r.pos += 1;
	if (c == '\n') {
		r.line += 1;
		r.col = 1;
	} else {
		r.col += 1;
	};
	return c;
};

// Skip whitespace and comments
fn skip_ws(r: *reader) void = {
	for (!at_end(r)) {
		let c = r_peek(r);
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
			r_advance(r);
		} else if (c == '/' && r_peek_n(r, 1) == '/') {
			// Line comment
			for (!at_end(r) && r_peek(r) != '\n') {
				r_advance(r);
			};
		} else {
			return;
		};
	};
};

// Check if character is digit
fn is_digit(c: u8) bool = {
	return c >= '0' && c <= '9';
};

// Check if character is hex digit
fn is_hex(c: u8) bool = {
	return is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
};

// Check if character is identifier start
fn is_id_start(c: u8) bool = {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
};

// Check if character is identifier continue
fn is_id_cont(c: u8) bool = {
	return is_id_start(c) || is_digit(c);
};

// Make a token with pointer to source slice
fn make_token(r: *reader, kind: token_kind, start: size, line: u32, col: u16) token = {
	let vlen = r.pos - start;
	let vptr = (r.src: uintptr + start): *u8;
	return token {
		kind = kind,
		val_ptr = vptr,
		val_len = vlen,
		line = line,
		col = col,
	};
};

// Read identifier or keyword
fn read_id(r: *reader) token = {
	let start = r.pos;
	let line = r.line;
	let col = r.col;

	for (!at_end(r) && is_id_cont(r_peek(r))) {
		r_advance(r);
	};

	let t = make_token(r, token_kind::ID, start, line, col);
	t.kind = lookup_keyword(t.val_ptr, t.val_len);
	return t;
};

// Read number (int or float)
fn read_number(r: *reader) token = {
	let start = r.pos;
	let line = r.line;
	let col = r.col;
	let is_float = false;
	let has_prefix = false;

	// Check for hex/octal/binary prefix
	if (r_peek(r) == '0' && r.pos + 1 < r.srclen) {
		let next = r_peek_n(r, 1);
		if (next == 'x' || next == 'X') {
			has_prefix = true;
			r_advance(r);
			r_advance(r);
			for (!at_end(r) && (is_hex(r_peek(r)) || r_peek(r) == '_')) {
				r_advance(r);
			};
		} else if (next == 'o' || next == 'O') {
			has_prefix = true;
			r_advance(r);
			r_advance(r);
			for (!at_end(r) && ((r_peek(r) >= '0' && r_peek(r) <= '7') || r_peek(r) == '_')) {
				r_advance(r);
			};
		} else if (next == 'b' || next == 'B') {
			has_prefix = true;
			r_advance(r);
			r_advance(r);
			for (!at_end(r) && (r_peek(r) == '0' || r_peek(r) == '1' || r_peek(r) == '_')) {
				r_advance(r);
			};
		};
	};

	if (!has_prefix) {
		// Decimal number
		for (!at_end(r) && (is_digit(r_peek(r)) || r_peek(r) == '_')) {
			r_advance(r);
		};

		// Check for float - but NOT if preceded by '.' (chained tuple access like .0.1)
		// In that case, .0.1 should be field .0 then field .1, not float 0.1
		let preceded_by_dot = start > 0 && r.src[start - 1] == '.';
		if (!preceded_by_dot && r_peek(r) == '.' && is_digit(r_peek_n(r, 1))) {
			is_float = true;
			r_advance(r);
			for (!at_end(r) && (is_digit(r_peek(r)) || r_peek(r) == '_')) {
				r_advance(r);
			};
		};

		// Float: exponent
		if (r_peek(r) == 'e' || r_peek(r) == 'E') {
			is_float = true;
			r_advance(r);
			if (r_peek(r) == '+' || r_peek(r) == '-') {
				r_advance(r);
			};
			for (!at_end(r) && (is_digit(r_peek(r)) || r_peek(r) == '_')) {
				r_advance(r);
			};
		};
	};

	// Type suffix
	let c = r_peek(r);
	if (c == 'i' || c == 'u' || c == 'f' || c == 'z') {
		if (c == 'f') { is_float = true; };
		r_advance(r);
		for (!at_end(r) && is_digit(r_peek(r))) {
			r_advance(r);
		};
	};

	let kind: token_kind = token_kind::INT;
	if (is_float) {
		kind = token_kind::FLOAT;
	};
	return make_token(r, kind, start, line, col);
};

// Read string literal
fn read_string(r: *reader) token = {
	let start = r.pos;
	let line = r.line;
	let col = r.col;

	r_advance(r); // opening "
	for (!at_end(r) && r_peek(r) != '"') {
		if (r_peek(r) == '\\') {
			r_advance(r);
			if (!at_end(r)) { r_advance(r); };
		} else {
			r_advance(r);
		};
	};
	if (!at_end(r)) { r_advance(r); }; // closing "

	return make_token(r, token_kind::STR, start, line, col);
};

// Read raw string literal (backticks) - no escape processing
fn read_rawstring(r: *reader) token = {
	let start = r.pos;
	let line = r.line;
	let col = r.col;

	r_advance(r); // opening `
	for (!at_end(r) && r_peek(r) != '`') {
		r_advance(r);
	};
	if (!at_end(r)) { r_advance(r); }; // closing `

	return make_token(r, token_kind::RAWSTR, start, line, col);
};

// Read rune literal
fn read_rune(r: *reader) token = {
	let start = r.pos;
	let line = r.line;
	let col = r.col;

	r_advance(r); // opening '
	if (!at_end(r) && r_peek(r) == '\\') {
		r_advance(r);
		if (!at_end(r)) {
			let esc = r_peek(r);
			r_advance(r);
			let count = 0z;
			if (esc == 'x') { count = 2; }
			else if (esc == 'u') { count = 4; }
			else if (esc == 'U') { count = 8; };
			for (count > 0 && !at_end(r)) {
				r_advance(r);
				count -= 1;
			};
		};
	} else if (!at_end(r)) {
		r_advance(r);
	};
	if (!at_end(r) && r_peek(r) == '\'') { r_advance(r); }; // closing '

	return make_token(r, token_kind::RUNE, start, line, col);
};

// Read next token
export fn read_token(r: *reader) token = {
	skip_ws(r);

	if (at_end(r)) {
		return token {
			kind = token_kind::EOF,
			val_ptr = r.src: *u8,
			val_len = 0,
			line = r.line,
			col = r.col,
		};
	};

	let start = r.pos;
	let line = r.line;
	let col = r.col;
	let c = r_peek(r);

	// Identifier or keyword
	if (is_id_start(c)) {
		return read_id(r);
	};

	// Number
	if (is_digit(c)) {
		return read_number(r);
	};

	// String
	if (c == '"') {
		return read_string(r);
	};

	// Raw string (backticks)
	if (c == '`') {
		return read_rawstring(r);
	};

	// Rune
	if (c == '\'') {
		return read_rune(r);
	};

	// Operators and punctuation
	r_advance(r);

	// Three-character operators
	if (c == '.' && r_peek(r) == '.' && r_peek_n(r, 1) == '.') {
		r_advance(r);
		r_advance(r);
		return make_token(r, token_kind::ELLIPSIS, start, line, col);
	};
	if (c == '>' && r_peek(r) == '>' && r_peek_n(r, 1) == '=') {
		r_advance(r);
		r_advance(r);
		return make_token(r, token_kind::RSHIFT_EQ, start, line, col);
	};
	if (c == '<' && r_peek(r) == '<' && r_peek_n(r, 1) == '=') {
		r_advance(r);
		r_advance(r);
		return make_token(r, token_kind::LSHIFT_EQ, start, line, col);
	};

	// Two-character operators
	let c2 = r_peek(r);
	if (c == ':' && c2 == ':') { r_advance(r); return make_token(r, token_kind::COLONCOLON, start, line, col); };
	if (c == '=' && c2 == '=') { r_advance(r); return make_token(r, token_kind::EQEQ, start, line, col); };
	if (c == '!' && c2 == '=') { r_advance(r); return make_token(r, token_kind::NEQ, start, line, col); };
	if (c == '<' && c2 == '=') { r_advance(r); return make_token(r, token_kind::LE, start, line, col); };
	if (c == '>' && c2 == '=') { r_advance(r); return make_token(r, token_kind::GE, start, line, col); };
	if (c == '<' && c2 == '<') { r_advance(r); return make_token(r, token_kind::LSHIFT, start, line, col); };
	if (c == '>' && c2 == '>') { r_advance(r); return make_token(r, token_kind::RSHIFT, start, line, col); };
	if (c == '&' && c2 == '&') { r_advance(r); return make_token(r, token_kind::LAND, start, line, col); };
	if (c == '|' && c2 == '|') { r_advance(r); return make_token(r, token_kind::LOR, start, line, col); };
	if (c == '^' && c2 == '^') { r_advance(r); return make_token(r, token_kind::XOR, start, line, col); };
	if (c == '=' && c2 == '>') { r_advance(r); return make_token(r, token_kind::ARROW, start, line, col); };
	if (c == '.' && c2 == '.') { r_advance(r); return make_token(r, token_kind::DOTDOT, start, line, col); };
	if (c == '+' && c2 == '=') { r_advance(r); return make_token(r, token_kind::PLUS_EQ, start, line, col); };
	if (c == '-' && c2 == '=') { r_advance(r); return make_token(r, token_kind::MINUS_EQ, start, line, col); };
	if (c == '*' && c2 == '=') { r_advance(r); return make_token(r, token_kind::STAR_EQ, start, line, col); };
	if (c == '/' && c2 == '=') { r_advance(r); return make_token(r, token_kind::SLASH_EQ, start, line, col); };
	if (c == '%' && c2 == '=') { r_advance(r); return make_token(r, token_kind::PERCENT_EQ, start, line, col); };
	if (c == '&' && c2 == '=') { r_advance(r); return make_token(r, token_kind::AMP_EQ, start, line, col); };
	if (c == '|' && c2 == '=') { r_advance(r); return make_token(r, token_kind::PIPE_EQ, start, line, col); };
	if (c == '^' && c2 == '=') { r_advance(r); return make_token(r, token_kind::CARET_EQ, start, line, col); };

	// Single-character tokens
	let kind = single_char_token(c);
	return make_token(r, kind, start, line, col);
};

// Map single character to token kind
fn single_char_token(c: u8) token_kind = {
	if (c == '(') return token_kind::LPAREN;
	if (c == ')') return token_kind::RPAREN;
	if (c == '{') return token_kind::LBRACE;
	if (c == '}') return token_kind::RBRACE;
	if (c == '[') return token_kind::LBRACKET;
	if (c == ']') return token_kind::RBRACKET;
	if (c == ',') return token_kind::COMMA;
	if (c == ';') return token_kind::SEMI;
	if (c == ':') return token_kind::COLON;
	if (c == '.') return token_kind::DOT;
	if (c == '@') return token_kind::AT;
	if (c == '?') return token_kind::QUESTION;
	if (c == '#') return token_kind::HASH;
	if (c == '+') return token_kind::PLUS;
	if (c == '-') return token_kind::MINUS;
	if (c == '*') return token_kind::STAR;
	if (c == '/') return token_kind::SLASH;
	if (c == '%') return token_kind::PERCENT;
	if (c == '&') return token_kind::AMP;
	if (c == '|') return token_kind::PIPE;
	if (c == '^') return token_kind::CARET;
	if (c == '~') return token_kind::TILDE;
	if (c == '!') return token_kind::BANG;
	if (c == '<') return token_kind::LT;
	if (c == '>') return token_kind::GT;
	if (c == '=') return token_kind::EQ;
	return token_kind::INVALID;
};

// Token array result
export type token_list = struct {
	tokens: *[*]token,
	count: size,
};

// Tokenize entire source into array
export fn tokenize_all(a: *arena, src: *[*]u8, srclen: size) token_list = {
	let r = reader_new(a, src, srclen);

	// First pass: count tokens
	let count = 0z;
	for (true) {
		let t = read_token(&r);
		count += 1;
		if (t.kind == token_kind::EOF) break;
	};

	// Allocate token array
	let tokens = arena_alloc(a, count * size(token)): *[*]token;

	// Second pass: fill tokens
	r = reader_new(a, src, srclen);
	for (let i = 0z; i < count; i += 1) {
		tokens[i] = read_token(&r);
	};

	return token_list {
		tokens = tokens,
		count = count,
	};
};
