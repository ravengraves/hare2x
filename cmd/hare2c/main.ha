// main.ha - Hare2C metacompiler entry point
use rt;
use strings;

// Read buffer size
def READ_BUF_SIZE: size = 1024 * 1024;  // 1MB

// Main transpilation pipeline
export fn main() void = {
	let a = arena_new();

	// Read source from stdin
	let buf = arena_alloc(&a, READ_BUF_SIZE): *[*]u8;
	let total = 0z;

	// Read in chunks until EOF
	for (true) {
		let n = rt::read(0, &buf[total], READ_BUF_SIZE - total);
		if (n <= 0) {
			break;
		};
		total += n: size;
		if (total >= READ_BUF_SIZE) {
			break;
		};
	};

	if (total == 0) {
		let msg: str = "hare2c: no input\n";
		rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
		rt::exit(1);
	};

	// Check for optional -N prefix argument at start of input
	let prefix_ptr: *u8 = &buf[0];
	let prefix_len: size = 0;
	let src_start: size = 0;

	if (total >= 3 && buf[0] == '-' && buf[1] == 'N' && buf[2] == ' ') {
		// Found "-N ", extract prefix until newline
		let i = 3z;
		prefix_ptr = &buf[3];
		for (i < total && buf[i] != '\n') {
			i += 1;
		};
		prefix_len = i - 3;
		// Skip past the newline
		if (i < total && buf[i] == '\n') {
			i += 1;
		};
		src_start = i;
	};

	// Tokenize (starting after -p line if present)
	let src_ptr = (&buf[src_start]): *[*]u8;
	set_error_source(src_ptr, total - src_start);
	let toks = tokenize_all(&a, src_ptr, total - src_start);
	if (toks.count == 0) {
		let msg: str = "hare2c: tokenization failed\n";
		rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
		rt::exit(1);
	};

	// Parse
	let p = parser_new(&a, toks.tokens, toks.count);
	let unit = parse_unit(&p);
	if (unit == null) {
		let msg: str = "hare2c: parse failed\n";
		rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
		rt::exit(1);
	};

	// Transform to C
	let sb = strbuf_new(&a);

	let ctx = arena_alloc(&a, size(transform_ctx)): *transform_ctx;
	ctx.arena = &a;
	ctx.output = &sb;
	ctx.prefix_ptr = prefix_ptr;
	ctx.prefix_len = prefix_len;
	ctx.result_used = true;

	// Emit the unit
	emit_unit(ctx, unit);

	// Check for compile-time errors
	if (ctx.has_errors) {
		rt::exit(1);
	};

	// Write output to stdout
	rt::write(1, strbuf_ptr(&sb): *[*]u8, strbuf_len(&sb));
};
