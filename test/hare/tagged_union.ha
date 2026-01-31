// Clean test for error handling and tagged unions
use rt;
use strings;

// Simple tagged union (no error types for simplicity)
type maybe_int = (int | void);

// Function returning tagged union
fn make_maybe(have_value: bool, v: int) maybe_int = {
    if (have_value) {
        return v;
    };
    return void;
};

// Use match to extract value
fn get_or_default(m: maybe_int, default_val: int) int = {
    return match (m) {
    case let v: int =>
        yield v;
    case void =>
        yield default_val;
    };
};

// Switch expression
fn classify(x: int) int = {
    return switch (x) {
    case 0 =>
        yield 0;
    case 1, 2, 3 =>
        yield 1;
    case =>
        yield 2;
    };
};

// Type test with 'is'
fn has_value(m: maybe_int) bool = {
    return m is int;
};

export fn main() void = {
    // Test make_maybe with value
    let m1: maybe_int = make_maybe(true, 42);
    assert(m1 is int);
    assert(get_or_default(m1, 0) == 42);

    // Test make_maybe without value
    let m2: maybe_int = make_maybe(false, 0);
    assert(m2 is void);
    assert(get_or_default(m2, 99) == 99);

    // Test has_value
    let h1: bool = has_value(m1);
    let h2: bool = has_value(m2);
    assert(h1 == true);
    assert(h2 == false);

    // Test classify switch
    assert(classify(0) == 0);
    assert(classify(1) == 1);
    assert(classify(2) == 1);
    assert(classify(3) == 1);
    assert(classify(4) == 2);
    assert(classify(100) == 2);
    assert(classify(-1) == 2);

    // Test direct tagged union assignment
    let m3: maybe_int = 100;
    assert(m3 is int);
    assert(get_or_default(m3, 0) == 100);

    let m4: maybe_int = void;
    assert(m4 is void);
    assert(get_or_default(m4, -1) == -1);

    // Test match expression inline
    let val: int = match (m1) {
    case let v: int =>
        yield v * 2;
    case void =>
        yield 0;
    };
    assert(val == 84);

    let msg: str = "Tagged union tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
