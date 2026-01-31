// Simpler test for error handling and tagged unions
use rt;
use strings;

// Define error type
type myerror = !void;

// Tagged union result
type int_result = (int | myerror);

// Function that can fail
fn divide(a: int, b: int) int_result = {
    if (b == 0) {
        return myerror;
    };
    return a / b;
};

// Using match
fn test_match(r: int_result) int = {
    return match (r) {
    case let v: int =>
        yield v;
    case myerror =>
        yield 0;
    };
};

export fn main() void = {
    // Test successful division
    let r1: int_result = divide(10, 2);
    assert(r1 is int);
    let v1: int = test_match(r1);
    assert(v1 == 5);

    // Test division by zero
    let r2: int_result = divide(10, 0);
    assert(r2 is myerror);
    let v2: int = test_match(r2);
    assert(v2 == 0);

    // Test more divisions
    let r3: int_result = divide(100, 5);
    assert(test_match(r3) == 20);

    let r4: int_result = divide(-20, 4);
    assert(test_match(r4) == -5);

    // Test edge cases
    let r5: int_result = divide(0, 5);
    assert(test_match(r5) == 0);
    assert(r5 is int);  // 0 is a valid int result

    let msg: str = "Simple error tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
