// pattern.ha - Pattern matching engine for AST transformation

// Pattern kind enum - must come before pattern struct
export type pattern_kind = enum u8 {
	P_ANY = 0,    // Match any single node
	P_KIND,       // Match specific node kind
	P_BIND,       // Match and bind to variable
	P_SEQ,        // Match sequence of children
	P_ALT,        // Match one of several alternatives
	P_WILD,       // Match zero or more nodes (for sequences)
};

// Pattern node
export type pattern = struct {
	kind: pattern_kind,
	data: *opaque,
};

// P_KIND data - match specific node kind
export type p_kind_data = struct {
	nkind: node_kind,
};

// P_BIND data - match and bind to name
export type p_bind_data = struct {
	name_ptr: *u8,
	name_len: size,
	inner: nullable *pattern,  // Optional inner pattern to match
};

// P_SEQ data - match sequence of patterns against children
export type p_seq_data = struct {
	patterns: *[*]*pattern,
	npatterns: size,
};

// P_ALT data - match one of several alternatives
export type p_alt_data = struct {
	options: *[*]*pattern,
	noptions: size,
};

// Single binding entry (must be before bindings)
export type bind_entry = struct {
	name_ptr: *u8,
	name_len: size,
	node: *node,
};

// Bindings - maps names to AST nodes
export type bindings = struct {
	entries: *[*]bind_entry,
	nentries: size,
	capacity: size,
	arena: *arena,
};

// Create new bindings
export fn bindings_new(a: *arena) *bindings = {
	let b = arena_alloc(a, size(bindings)): *bindings;
	b.capacity = 32;
	b.nentries = 0;
	b.arena = a;
	b.entries = arena_alloc(a, 32 * size(bind_entry)): *[*]bind_entry;
	return b;
};

// Set a binding
export fn bindings_set(b: *bindings, name_ptr: *u8, name_len: size, n: *node) void = {
	// Check if exists and update
	for (let i = 0z; i < b.nentries; i += 1) {
		let e: *bind_entry = &b.entries[i];
		if (e.name_len == name_len && bytes_eq(e.name_ptr, name_ptr, name_len)) {
			e.node = n;
			return;
		};
	};

	// Add new entry
	if (b.nentries >= b.capacity) {
		die("pattern.ha: bindings_set() - too many bindings");
	};

	let e: *bind_entry = &b.entries[b.nentries];
	e.name_ptr = name_ptr;
	e.name_len = name_len;
	e.node = n;
	b.nentries += 1;
};

// Get a binding (returns null if not found)
export fn bindings_get(b: *bindings, name_ptr: *u8, name_len: size) nullable *node = {
	for (let i = 0z; i < b.nentries; i += 1) {
		let e: *bind_entry = &b.entries[i];
		if (e.name_len == name_len && bytes_eq(e.name_ptr, name_ptr, name_len)) {
			return e.node;
		};
	};
	return null;
};

// Helper: compare two strings
fn bytes_eq(a: *u8, b: *u8, slen: size) bool = {
	let ap = a: *[*]u8;
	let bp = b: *[*]u8;
	for (let i = 0z; i < slen; i += 1) {
		if (ap[i] != bp[i]) {
			return false;
		};
	};
	return true;
};

// Create pattern helpers
export fn pat_any(a: *arena) *pattern = {
	let p = arena_alloc(a, size(pattern)): *pattern;
	p.kind = pattern_kind::P_ANY;
	p.data = arena_alloc(a, 1);  // P_ANY has no data, but need non-null
	return p;
};

export fn pat_kind(a: *arena, k: node_kind) *pattern = {
	let p = arena_alloc(a, size(pattern)): *pattern;
	p.kind = pattern_kind::P_KIND;
	let d = arena_alloc(a, size(p_kind_data)): *p_kind_data;
	d.nkind = k;
	p.data = d;
	return p;
};

export fn pat_bind(a: *arena, name_ptr: *u8, name_len: size, inner: nullable *pattern) *pattern = {
	let p = arena_alloc(a, size(pattern)): *pattern;
	p.kind = pattern_kind::P_BIND;
	let d = arena_alloc(a, size(p_bind_data)): *p_bind_data;
	d.name_ptr = name_ptr;
	d.name_len = name_len;
	d.inner = inner;
	p.data = d;
	return p;
};

export fn pat_seq(a: *arena, patterns: *[*]*pattern, npatterns: size) *pattern = {
	let p = arena_alloc(a, size(pattern)): *pattern;
	p.kind = pattern_kind::P_SEQ;
	let d = arena_alloc(a, size(p_seq_data)): *p_seq_data;
	d.patterns = patterns;
	d.npatterns = npatterns;
	p.data = d;
	return p;
};

export fn pat_alt(a: *arena, options: *[*]*pattern, noptions: size) *pattern = {
	let p = arena_alloc(a, size(pattern)): *pattern;
	p.kind = pattern_kind::P_ALT;
	let d = arena_alloc(a, size(p_alt_data)): *p_alt_data;
	d.options = options;
	d.noptions = noptions;
	p.data = d;
	return p;
};

// Match a pattern against a node, populating bindings
// Returns true if match succeeded
export fn match_pattern(pat: *pattern, n: *node, b: *bindings) bool = {
	let pk = pat.kind;

	// P_ANY matches anything
	if (pk == pattern_kind::P_ANY) {
		return true;
	};

	// P_KIND matches specific node kind
	if (pk == pattern_kind::P_KIND) {
		let d = pat.data: *p_kind_data;
		return n.kind == d.nkind;
	};

	// P_BIND binds node to name and optionally matches inner pattern
	if (pk == pattern_kind::P_BIND) {
		let d = pat.data: *p_bind_data;
		// If there's an inner pattern, check it first
		match (d.inner) {
		case let inner: *pattern =>
			if (!match_pattern(inner, n, b)) {
				return false;
			};
		case null => void;
		};
		// Bind the node
		bindings_set(b, d.name_ptr, d.name_len, n);
		return true;
	};

	// P_ALT tries each alternative until one matches
	if (pk == pattern_kind::P_ALT) {
		let d = pat.data: *p_alt_data;
		for (let i = 0z; i < d.noptions; i += 1) {
			if (match_pattern(d.options[i], n, b)) {
				return true;
			};
		};
		return false;
	};

	// P_SEQ matches children - for now just match based on node kind
	// This is simplified - full implementation would extract children
	if (pk == pattern_kind::P_SEQ) {
		// Sequence matching requires node-specific child extraction
		// For now, just return true (simplified)
		return true;
	};

	return false;
};

