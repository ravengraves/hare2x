// Clean test for error handling and tagged unions

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
    let m1: maybe_int = make_maybe(true, 42);
    let m2: maybe_int = make_maybe(false, 0);
    
    let v1: int = get_or_default(m1, 0);
    let v2: int = get_or_default(m2, 99);
    
    let c: int = classify(2);
    
    let h1: bool = has_value(m1);
    let h2: bool = has_value(m2);
};
