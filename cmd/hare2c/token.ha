// token.ha - Token types for Hare lexer
use strings;

// Token kinds
export type token_kind = enum u8 {
	// Special
	EOF = 0,
	INVALID,

	// Literals
	INT,
	FLOAT,
	STR,
	RAWSTR,   // Raw string literal (backticks)
	RUNE,

	// Identifier (includes keywords after lookup)
	ID,

	// Keywords
	FN, LET, CONST, TYPE, STRUCT, UNION, ENUM,
	RETURN, IF, ELSE, FOR, BREAK, CONTINUE,
	MATCH, SWITCH, CASE, YIELD, DEFER,
	EXPORT, USE, DEF,
	TRUE, FALSE, NULL, VOID,
	NULLABLE, STATIC,
	ALLOC, FREE, APPEND, INSERT, DELETE,
	LEN, SIZE, OFFSET, ASSERT, ABORT,
	AS, IS,
	NOMEM,  // Error type for allocation failure
	OPAQUE, // Opaque type (void in C)

	// Type keywords
	BOOL, STR_T, RUNE_T,
	I8, I16, I32, I64,
	U8, U16, U32, U64,
	INT_T, UINT, F32, F64,
	UINTPTR,

	// Single-char punctuation
	LPAREN,    // (
	RPAREN,    // )
	LBRACE,    // {
	RBRACE,    // }
	LBRACKET,  // [
	RBRACKET,  // ]
	COMMA,     // ,
	SEMI,      // ;
	COLON,     // :
	DOT,       // .
	AT,        // @
	QUESTION,  // ?
	HASH,      // #
	UNDERSCORE, // _

	// Operators
	PLUS,      // +
	MINUS,     // -
	STAR,      // *
	SLASH,     // /
	PERCENT,   // %
	AMP,       // &
	PIPE,      // |
	CARET,     // ^
	TILDE,     // ~
	BANG,      // !
	LT,        // <
	GT,        // >
	EQ,        // =

	// Two-char operators
	COLONCOLON, // ::
	EQEQ,      // ==
	NEQ,       // !=
	LE,        // <=
	GE,        // >=
	LSHIFT,    // <<
	RSHIFT,    // >>
	LAND,      // &&
	LOR,       // ||
	XOR,       // ^^
	ARROW,     // =>
	DOTDOT,    // ..

	// Compound assignment
	PLUS_EQ,   // +=
	MINUS_EQ,  // -=
	STAR_EQ,   // *=
	SLASH_EQ,  // /=
	PERCENT_EQ, // %=
	AMP_EQ,    // &=
	PIPE_EQ,   // |=
	CARET_EQ,  // ^=
	LSHIFT_EQ, // <<=
	RSHIFT_EQ, // >>=

	// Three-char
	ELLIPSIS,  // ...
};

// Token with position info
export type token = struct {
	kind: token_kind,
	val_ptr: *u8,    // Pointer to value in source
	val_len: size,   // Length of value
	line: u32,
	col: u16,
};

// Keyword lookup table entry
type kw_entry = struct {
	name: str,
	kind: token_kind,
};

// Keywords sorted for binary search
let KEYWORDS: [_]kw_entry = [
	kw_entry { name = "_", kind = token_kind::UNDERSCORE },
	kw_entry { name = "abort", kind = token_kind::ABORT },
	kw_entry { name = "alloc", kind = token_kind::ALLOC },
	kw_entry { name = "append", kind = token_kind::APPEND },
	kw_entry { name = "as", kind = token_kind::AS },
	kw_entry { name = "assert", kind = token_kind::ASSERT },
	kw_entry { name = "bool", kind = token_kind::BOOL },
	kw_entry { name = "break", kind = token_kind::BREAK },
	kw_entry { name = "case", kind = token_kind::CASE },
	kw_entry { name = "const", kind = token_kind::CONST },
	kw_entry { name = "continue", kind = token_kind::CONTINUE },
	kw_entry { name = "def", kind = token_kind::DEF },
	kw_entry { name = "defer", kind = token_kind::DEFER },
	kw_entry { name = "delete", kind = token_kind::DELETE },
	kw_entry { name = "else", kind = token_kind::ELSE },
	kw_entry { name = "enum", kind = token_kind::ENUM },
	kw_entry { name = "export", kind = token_kind::EXPORT },
	kw_entry { name = "f32", kind = token_kind::F32 },
	kw_entry { name = "f64", kind = token_kind::F64 },
	kw_entry { name = "false", kind = token_kind::FALSE },
	kw_entry { name = "fn", kind = token_kind::FN },
	kw_entry { name = "for", kind = token_kind::FOR },
	kw_entry { name = "free", kind = token_kind::FREE },
	kw_entry { name = "i16", kind = token_kind::I16 },
	kw_entry { name = "i32", kind = token_kind::I32 },
	kw_entry { name = "i64", kind = token_kind::I64 },
	kw_entry { name = "i8", kind = token_kind::I8 },
	kw_entry { name = "if", kind = token_kind::IF },
	kw_entry { name = "insert", kind = token_kind::INSERT },
	kw_entry { name = "int", kind = token_kind::INT_T },
	kw_entry { name = "is", kind = token_kind::IS },
	kw_entry { name = "len", kind = token_kind::LEN },
	kw_entry { name = "let", kind = token_kind::LET },
	kw_entry { name = "match", kind = token_kind::MATCH },
	kw_entry { name = "nomem", kind = token_kind::NOMEM },
	kw_entry { name = "null", kind = token_kind::NULL },
	kw_entry { name = "nullable", kind = token_kind::NULLABLE },
	kw_entry { name = "offset", kind = token_kind::OFFSET },
	kw_entry { name = "opaque", kind = token_kind::OPAQUE },
	kw_entry { name = "return", kind = token_kind::RETURN },
	kw_entry { name = "rune", kind = token_kind::RUNE_T },
	kw_entry { name = "size", kind = token_kind::SIZE },
	kw_entry { name = "static", kind = token_kind::STATIC },
	kw_entry { name = "str", kind = token_kind::STR_T },
	kw_entry { name = "struct", kind = token_kind::STRUCT },
	kw_entry { name = "switch", kind = token_kind::SWITCH },
	kw_entry { name = "true", kind = token_kind::TRUE },
	kw_entry { name = "type", kind = token_kind::TYPE },
	kw_entry { name = "u16", kind = token_kind::U16 },
	kw_entry { name = "u32", kind = token_kind::U32 },
	kw_entry { name = "u64", kind = token_kind::U64 },
	kw_entry { name = "u8", kind = token_kind::U8 },
	kw_entry { name = "uint", kind = token_kind::UINT },
	kw_entry { name = "uintptr", kind = token_kind::UINTPTR },
	kw_entry { name = "union", kind = token_kind::UNION },
	kw_entry { name = "use", kind = token_kind::USE },
	kw_entry { name = "void", kind = token_kind::VOID },
	kw_entry { name = "yield", kind = token_kind::YIELD },
];

// Compare ptr/len to str
fn cmp_to_str(aptr: *u8, alen: size, b: str) int = {
	let ap = aptr: *[*]u8;
	let bp = strings::toutf8(b): *[*]u8;
	let blen = len(b);
	let min_len = alen;
	if (blen < min_len) {
		min_len = blen;
	};

	for (let i = 0z; i < min_len; i += 1) {
		if (ap[i] < bp[i]) return -1;
		if (ap[i] > bp[i]) return 1;
	};

	if (alen < blen) return -1;
	if (alen > blen) return 1;
	return 0;
};

// Lookup keyword by ptr/len, returns ID if not found
export fn lookup_keyword(ptr: *u8, plen: size) token_kind = {
	let lo = 0z;
	let hi = len(KEYWORDS);

	for (lo < hi) {
		let mid = lo + (hi - lo) / 2;
		let cmp = cmp_to_str(ptr, plen, KEYWORDS[mid].name);
		if (cmp == 0) {
			return KEYWORDS[mid].kind;
		} else if (cmp < 0) {
			hi = mid;
		} else {
			lo = mid + 1;
		};
	};

	return token_kind::ID;
};
