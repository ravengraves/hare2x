// Test raw strings (backtick) and multi-line strings
use rt;

export fn main() void = {
    // === Backtick strings (raw - no escape processing) ===

    // Escape sequences are literal in raw strings
    let raw1: str = `hello\nworld`;  // Contains literal backslash-n, not newline
    assert(len(raw1) == 12, "raw1: backslash-n should be 2 chars");

    let raw2: str = `tab\there`;  // Contains literal backslash-t
    assert(len(raw2) == 9, "raw2: backslash-t should be 2 chars");

    // Multi-line raw string
    let raw_multi: str = `line one
line two
line three`;
    assert(len(raw_multi) == 28, "raw_multi length");

    // Raw string with special characters
    let raw_special: str = `path\to\file.txt`;
    assert(len(raw_special) == 16, "raw_special: backslashes are literal");

    // === Double-quoted strings (with escape processing) ===

    // Escape sequences are processed
    let esc1: str = "hello\nworld";  // Contains actual newline
    assert(len(esc1) == 11, "esc1: newline is 1 char");

    let esc2: str = "tab\there";  // Contains actual tab
    assert(len(esc2) == 8, "esc2: tab is 1 char");

    // Multi-line quoted string (actual newlines in source)
    let quoted_multi: str = "line one
line two
line three";
    assert(len(quoted_multi) == 28, "quoted_multi length");

    // === Comparison ===

    // Raw and escaped should differ when escapes are involved
    let with_escape: str = "a\nb";  // 3 chars: a, newline, b
    let without_escape: str = `a\nb`;  // 4 chars: a, backslash, n, b
    assert(len(with_escape) == 3, "escaped newline");
    assert(len(without_escape) == 4, "literal backslash-n");

    // But identical when no escapes
    let plain1: str = "hello";
    let plain2: str = `hello`;
    assert(len(plain1) == len(plain2), "plain strings equal length");
};
