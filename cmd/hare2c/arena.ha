// arena.ha - Simple growable bump allocator
// Starts with 2MB block, grows by 2MB chunks as needed
use rt;
use strings;

// Block size: 2MB (should handle most transpilation workloads)
def BLOCK_SIZE: size = 2 * 1024 * 1024;

// Maximum blocks (2MB * 32 = 64MB total capacity)
def MAX_BLOCKS: size = 32;

// Arena allocator with large fixed-size blocks
export type arena = struct {
	blocks: [32]nullable *[*]u8,
	num_blocks: size,
	cur_offset: size,
};

// Create a new arena with first 2MB block
export fn arena_new() arena = {
	let a = arena {
		blocks = [null...],
		num_blocks = 1,
		cur_offset = 0,
	};
	a.blocks[0] = rt::malloc(BLOCK_SIZE): nullable *[*]u8;
	return a;
};

// Allocate n bytes from arena, 8-byte aligned
export fn arena_alloc(a: *arena, n: size) *opaque = {
	// Align to 8 bytes
	n = (n + 7) & ~7z;

	// Check if current block has space
	if (a.cur_offset + n > BLOCK_SIZE) {
		// Need new block
		if (a.num_blocks >= MAX_BLOCKS) {
			die("arena.ha: out of memory blocks");
		};
		// Allocate at least BLOCK_SIZE, but more if needed for large allocations
		let alloc_size = BLOCK_SIZE;
		if (n > BLOCK_SIZE) {
			alloc_size = n;
		};
		a.blocks[a.num_blocks] = rt::malloc(alloc_size): nullable *[*]u8;
		if (a.blocks[a.num_blocks] == null) {
			rt::write(2, strings::toutf8("arena.ha: malloc failed size="): *[*]u8,
				len("arena.ha: malloc failed size="));
			write_size(alloc_size);
			rt::write(2, strings::toutf8(" block="): *[*]u8, len(" block="));
			write_size(a.num_blocks);
			rt::write(2, strings::toutf8(" n="): *[*]u8, len(" n="));
			write_size(n);
			rt::write(2, strings::toutf8(" cur="): *[*]u8, len(" cur="));
			write_size(a.cur_offset);
			rt::write(2, strings::toutf8("\n"): *[*]u8, len("\n"));
			abort();
		};
		a.num_blocks += 1;
		a.cur_offset = 0;
	};

	// Get pointer from current block (last one)
	let blk = match (a.blocks[a.num_blocks - 1]) {
	case let b: *[*]u8 =>
		yield b;
	case null =>
		die("arena.ha: block is null");
		abort();
	};
	let result = (blk: uintptr + a.cur_offset): *opaque;
	a.cur_offset += n;
	return result;
};

// Reset arena for reuse (keeps allocated blocks)
export fn arena_reset(a: *arena) void = {
	a.num_blocks = 1;
	a.cur_offset = 0;
};

// Allocate and zero-initialize
export fn arena_calloc(a: *arena, n: size) *opaque = {
	let p = arena_alloc(a, n);
	let bytes = p: *[*]u8;
	for (let i = 0z; i < n; i += 1) {
		bytes[i] = 0;
	};
	return p;
};

// Abort with error message (for debugging)
export fn die(msg: str) void = {
	rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
	rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
	abort();
};

// Write an integer to stderr
export fn write_int(n: u32) void = {
	let buf: [16]u8 = [0...];
	let i = 15z;
	if (n == 0) {
		rt::write(2, strings::toutf8("0"): *[*]u8, 1);
		return;
	};
	for (n > 0) {
		buf[i] = ('0': u8) + (n % 10): u8;
		n = n / 10;
		i -= 1;
	};
	i += 1;
	// Use pointer arithmetic to avoid bounds check issue
	let ptr = &buf: *[*]u8;
	rt::write(2, (ptr: uintptr + i): *[*]u8, 16 - i);
};

// Write a size_t to stderr
export fn write_size(n: size) void = {
	let buf: [32]u8 = [0...];
	let i = 31z;
	if (n == 0) {
		rt::write(2, strings::toutf8("0"): *[*]u8, 1);
		return;
	};
	for (n > 0) {
		buf[i] = ('0': u8) + (n % 10): u8;
		n = n / 10;
		i -= 1;
	};
	i += 1;
	let ptr = &buf: *[*]u8;
	rt::write(2, (ptr: uintptr + i): *[*]u8, 32 - i);
};

// Global source buffer for error context (set by main)
let ERROR_SRC_PTR: nullable *[*]u8 = null;
let ERROR_SRC_LEN: size = 0;

// Register source buffer for error context
export fn set_error_source(src: *[*]u8, srclen: size) void = {
	ERROR_SRC_PTR = src;
	ERROR_SRC_LEN = srclen;
};

// Find start/end offsets for a 1-based line number
fn find_error_line_bounds(src: *[*]u8, srclen: size, line: u32, start_out: *size, end_out: *size) bool = {
	if (line == 0) {
		return false;
	};
	let cur_line: u32 = 1;
	let i = 0z;
	let line_start = 0z;
	for (i < srclen) {
		if (cur_line == line) {
			break;
		};
		if (src[i] == '\n') {
			cur_line += 1;
			line_start = i + 1;
		};
		i += 1;
	};
	if (cur_line != line) {
		return false;
	};
	let line_end = line_start;
	for (line_end < srclen) {
		let c = src[line_end];
		if (c == '\n' || c == '\r') {
			break;
		};
		line_end += 1;
	};
	*start_out = line_start;
	*end_out = line_end;
	return true;
};

// Emit the full line and caret indicator for a line/column
export fn write_error_context(line: u32, col: u16) void = {
	if (line == 0 || col == 0) {
		return;
	};
	match (ERROR_SRC_PTR) {
	case let src: *[*]u8 =>
		let start = 0z;
		let end = 0z;
		if (!find_error_line_bounds(src, ERROR_SRC_LEN, line, &start, &end)) {
			return;
		};
		if (end > start) {
			rt::write(2, (src: uintptr + start): *[*]u8, end - start);
		};
		rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
		let col_pos = (col - 1): size;
		for (let i = 0z; i < col_pos; i += 1) {
			let outc: u8 = ' ';
			if (start + i < end) {
				let sc = src[start + i];
				if (sc == '\t') {
					outc = '\t';
				};
			};
			rt::write(2, (&outc): *[*]u8, 1);
		};
		rt::write(2, strings::toutf8("^\n"): *[*]u8, 2);
	case null => void;
	};
};

// Abort with error message including line and column
export fn die_at(msg: str, line: u32, col: u16) void = {
	write_int(line);
	rt::write(2, strings::toutf8(":"): *[*]u8, 1);
	write_int(col: u32);
	rt::write(2, strings::toutf8(": error: "): *[*]u8, 9);
	rt::write(2, strings::toutf8(msg): *[*]u8, len(msg));
	rt::write(2, strings::toutf8("\n"): *[*]u8, 1);
	write_error_context(line, col);
	abort();
};
