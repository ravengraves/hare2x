// ERROR: Cannot use non void or done type alias 'invalid' as literal
// Example: Custom Error Types and Tagged Unions
use rt;
use strings;

// --- Error Type Definitions ---

// Custom error type based on void (zero-size error)
type unexpectedeof = !void;

// Error type wrapping another error
type invalid = !int;

// Error type with struct payload
type parse_error = !struct {
    line: int,
    col: int,
    message: str,
};

// --- Tagged Union of Error Types ---

// Combined error type (all possible errors)
type error = (invalid | unexpectedeof | parse_error);

// --- Non-Error Tagged Unions ---

// Signed integer types
type signed_int = (int | i8 | i16 | i32 | i64);

// Unsigned integer types
type unsigned_int = (uint | u8 | u16 | u32 | u64);

// Using spread to flatten nested unions
type integer_type = (...signed_int | ...unsigned_int);

// Floating point types
type floating_type = (f32 | f64);

// All numeric types (combining with spread)
type numeric_type = (...integer_type | ...floating_type);

// --- Nullable Pointer Types ---

type coords = struct {
    x: int,
    y: int,
};

// Function that accepts nullable pointer
fn printcoords(pos: nullable *coords) int = {
    match (pos) {
    case null =>
        return -1;
    case let p: *coords =>
        return p.x + p.y;
    };
};

// --- Functions Returning Custom Error Types ---

fn check_value(n: int) (void | invalid) = {
    if (n < 0) {
        return invalid;
    };
};

fn read_data(eof: bool) (int | unexpectedeof) = {
    if (eof) {
        return unexpectedeof;
    };
    return 42;
};

// Function with combined error type
fn process() (int | error) = {
    let result: int = 0;
    return result;
};

// --- Error to String Conversion ---

fn strerror(err: error) str = {
    match (err) {
    case invalid =>
        return "Invalid value provided";
    case unexpectedeof =>
        return "Unexpected end of file";
    case let e: parse_error =>
        return "Parse error";
    };
};

// --- Main Function ---

export fn main() void = {
    // Test nullable pointer - null case
    let null_result: int = printcoords(null);
    assert(null_result == -1);

    // Test nullable pointer - non-null case
    let pos: coords = coords { x = 10, y = 20 };
    let pos_result: int = printcoords(&pos);
    assert(pos_result == 30);

    // Test check_value - valid case
    let check_valid = check_value(5);
    assert(check_valid is void);

    // Test check_value - invalid case
    let check_invalid = check_value(-1);
    assert(check_invalid is invalid);

    // Test read_data - success case
    let read_ok = read_data(false);
    assert(read_ok is int);
    match (read_ok) {
    case let n: int =>
        assert(n == 42);
    case unexpectedeof =>
        abort();
    };

    // Test read_data - eof case
    let read_eof = read_data(true);
    assert(read_eof is unexpectedeof);

    // Test process function
    let proc_result = process();
    assert(proc_result is int);
    match (proc_result) {
    case let n: int =>
        assert(n == 0);
    case let e: error =>
        abort();
    };

    // Test error conversion
    let err1: error = invalid;
    let msg1: str = strerror(err1);
    assert(msg1 == "Invalid value provided");

    let err2: error = unexpectedeof;
    let msg2: str = strerror(err2);
    assert(msg2 == "Unexpected end of file");

    // Test coords struct
    let c1: coords = coords { x = 5, y = 10 };
    assert(c1.x == 5);
    assert(c1.y == 10);

    let c2: coords = coords { x = -3, y = 7 };
    assert(printcoords(&c2) == 4);

    let msg: str = "Custom types tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
