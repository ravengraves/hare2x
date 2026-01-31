// ERROR: Type mismatch: (str | nomem) not assignable to str
// Test strings module: str <-> []u8 conversions
use strings;
use rt;

// Convert string to byte slice
fn test_toutf8() void = {
    let s: str = "hello";
    let bytes: []u8 = strings::toutf8(s);

    assert(len(bytes) == 5);

    // Access individual bytes
    let h: u8 = bytes[0];  // 104 = 'h'
    let e: u8 = bytes[1];  // 101 = 'e'
    let l: u8 = bytes[2];  // 108 = 'l'

    assert(h == 104);
    assert(e == 101);
    assert(l == 108);
    assert(bytes[3] == 108);  // 'l'
    assert(bytes[4] == 111);  // 'o'
};

// Convert byte slice to string (unsafe - no UTF-8 validation)
fn test_fromutf8_unsafe() void = {
    // "hello" in ASCII bytes
    let data: [5]u8 = [104, 101, 108, 108, 111];
    let slice: []u8 = data[..];
    let s: str = strings::fromutf8_unsafe(slice);
    assert(s == "hello");
    assert(len(s) == 5);
};

fn test_dup() void = {
    let s: str = "hello";
    let dup: str = strings::dup(s);
    assert(dup == "hello");
    assert(len(dup) == 5);
};

// Roundtrip: str -> []u8 -> str
fn roundtrip(s: str) str = {
    let bytes: []u8 = strings::toutf8(s);
    return strings::fromutf8_unsafe(bytes);
};

// Get byte at index
fn byte_at(s: str, i: size) u8 = {
    let bytes: []u8 = strings::toutf8(s);
    return bytes[i];
};

export fn main() void = {
    // Test toutf8
    test_toutf8();

    // Test fromutf8_unsafe
    test_fromutf8_unsafe();

    // Test dup
    test_dup();

    // Test roundtrip
    let original: str = "test string";
    let back: str = roundtrip(original);
    assert(original == back);

    // More roundtrip tests
    assert(roundtrip("") == "");
    assert(roundtrip("a") == "a");
    assert(roundtrip("Hello, World!") == "Hello, World!");

    // Test byte access
    let first: u8 = byte_at("hello", 0);
    assert(first == 104);  // 'h'

    let last: u8 = byte_at("hello", 4);
    assert(last == 111);  // 'o'

    // Test with different characters
    assert(byte_at("ABC", 0) == 65);  // 'A'
    assert(byte_at("ABC", 1) == 66);  // 'B'
    assert(byte_at("ABC", 2) == 67);  // 'C'

    // Test byte slice operations
    let s: str = "test";
    let bytes: []u8 = strings::toutf8(s);
    assert(bytes[0] == 116);  // 't'
    assert(bytes[1] == 101);  // 'e'
    assert(bytes[2] == 115);  // 's'
    assert(bytes[3] == 116);  // 't'

    let msg: str = "Strings module tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
