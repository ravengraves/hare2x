// Test unbounded arrays - like C pointers to arrays
// ERROR: This test contains invalid Hare syntax
use strings;

// C-style string is *[*]u8
fn cstrlen(s: *[*]u8) size = {
    let i: size = 0;
    for (s[i] != 0) {
        i += 1;
    };
    return i;
};

// Pointer to single object vs pointer to array
fn test_ptr_semantics() void = {
    let x: i32 = 42;
    let p: *i32 = &x;  // Pointer to single i32
    assert(*p == 42, "single ptr");

    // Array and pointer to unbounded array
    let arr: [5]i32 = [10, 20, 30, 40, 50];
    // Cast array directly to pointer (array decays to pointer)
    // ERROR on next line: Invalid cast from [5]i32 to *[*]i32
    // Expected message: "Invalid cast from [N]T to *[*]T"
    let parr: *[*]i32 = arr: *[*]i32;
    parr[0] = 11;

    // Unbounded array access - NO bounds checking
    assert(parr[0] == 11, "uarr[0]");
    assert(parr[2] == 30, "uarr[2]");
    assert(parr[4] == 50, "uarr[4]");
};

// Test C-style strings
fn test_cstrings() void = {
    // A C string literal (null-terminated)
    let cstr: *[*]u8 = strings::toutf8("hello\0"): *[*]u8;
    assert(cstrlen(cstr) == 5, "cstrlen");
    assert(cstr[0] == 104, "h");  // 'h'
    assert(cstr[4] == 111, "o");  // 'o'
    assert(cstr[5] == 0, "null");
};

export fn main() void = {
    test_ptr_semantics();
    test_cstrings();
};
