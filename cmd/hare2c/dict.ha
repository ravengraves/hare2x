// dict.ha - Hash table with FNV-1a hashing
// Open addressing with linear probing
use strings;

// FNV-1a constants for 32-bit hash
def FNV_OFFSET: u32 = 2166136261;
def FNV_PRIME: u32 = 16777619;

// Dictionary entry
export type dict_entry = struct {
	key: str,
	val: *opaque,
	hash: u32,
	used: bool,
};

// Dictionary (hash table)
export type dict = struct {
	entries: *[*]dict_entry,
	cap: size,
	count: size,
};

// FNV-1a hash for strings
export fn hash_str(s: str) u32 = {
	let h: u32 = FNV_OFFSET;
	let bytes = strings::toutf8(s): *[*]u8;
	for (let i = 0z; i < len(s); i += 1) {
		h ^= bytes[i]: u32;
		h *= FNV_PRIME;
	};
	return h;
};

// String equality helper
fn str_eq(a: str, b: str) bool = {
	if (len(a) != len(b)) return false;
	let ap = strings::toutf8(a): *[*]u8;
	let bp = strings::toutf8(b): *[*]u8;
	for (let i = 0z; i < len(a); i += 1) {
		if (ap[i] != bp[i]) return false;
	};
	return true;
};

// Create a new dictionary with given capacity
export fn dict_new(a: *arena, cap: size) *dict = {
	// Round up capacity to power of 2 for fast modulo
	let c = 8z;
	for (c < cap) {
		c *= 2;
	};

	let d = arena_alloc(a, size(dict)): *dict;
	d.entries = arena_calloc(a, c * size(dict_entry)): *[*]dict_entry;
	d.cap = c;
	d.count = 0;
	return d;
};

// Find slot for key (linear probing)
// Returns the index of the slot (either matching key or first empty)
fn dict_find_slot(d: *dict, key: str, h: u32) size = {
	let mask = d.cap - 1;
	let idx = (h: size) & mask;

	for (let i = 0z; i < d.cap; i += 1) {
		if (!d.entries[idx].used) {
			return idx;
		};
		if (d.entries[idx].hash == h && str_eq(d.entries[idx].key, key)) {
			return idx;
		};
		idx = (idx + 1) & mask;
	};

	// Should never reach here if load factor < 1
	return 0;
};

// Check if slot contains the key
fn dict_slot_has_key(d: *dict, idx: size, key: str, h: u32) bool = {
	return d.entries[idx].used && d.entries[idx].hash == h && str_eq(d.entries[idx].key, key);
};

// Grow dictionary capacity
fn dict_grow(d: *dict, a: *arena) void = {
	let old_entries = d.entries;
	let old_cap = d.cap;

	// Double capacity
	let new_cap = d.cap * 2;
	d.entries = arena_calloc(a, new_cap * size(dict_entry)): *[*]dict_entry;
	d.cap = new_cap;
	d.count = 0;

	// Rehash all entries
	for (let i = 0z; i < old_cap; i += 1) {
		if (old_entries[i].used) {
			dict_set(d, a, old_entries[i].key, old_entries[i].val);
		};
	};
};

// Get value for key, returns null if not found
export fn dict_get(d: *dict, key: str) nullable *opaque = {
	if (d.count == 0) return null;

	let h = hash_str(key);
	let idx = dict_find_slot(d, key, h);

	if (dict_slot_has_key(d, idx, key, h)) {
		return d.entries[idx].val;
	};
	return null;
};

// Set value for key
export fn dict_set(d: *dict, a: *arena, key: str, val: *opaque) void = {
	// Check load factor (resize at 70%)
	if (d.count * 10 >= d.cap * 7) {
		dict_grow(d, a);
	};

	let h = hash_str(key);
	let idx = dict_find_slot(d, key, h);

	if (dict_slot_has_key(d, idx, key, h)) {
		// Update existing
		d.entries[idx].val = val;
	} else {
		// Insert new
		d.entries[idx] = dict_entry {
			key = key,
			val = val,
			hash = h,
			used = true,
		};
		d.count += 1;
	};
};

// Check if key exists
export fn dict_has(d: *dict, key: str) bool = {
	if (d.count == 0) return false;

	let h = hash_str(key);
	let idx = dict_find_slot(d, key, h);
	return dict_slot_has_key(d, idx, key, h);
};

