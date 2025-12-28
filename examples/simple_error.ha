// Simpler test for error handling and tagged unions

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
    let r: int_result = divide(10, 2);
    let v: int = test_match(r);
};
