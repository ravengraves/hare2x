// Example: Custom Error Types and Tagged Unions

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
fn printcoords(pos: nullable *coords) void = {
    match (pos) {
    case null =>
        // Handle null case
        return;
    case let p: *coords =>
        // Handle non-null case
        let x: int = p.x;
        let y: int = p.y;
    };
};

// --- Functions Returning Custom Error Types ---

fn check_value(n: int) (void | invalid) = {
    if (n < 0) {
        return invalid;  // Return error variant
    };
    // Success - return void
};

fn read_data() (int | unexpectedeof) = {
    // Simulate EOF condition
    let eof: bool = true;
    if (eof) {
        return unexpectedeof;
    };
    return 42;
};

// Function with combined error type
fn process() (int | error) = {
    // Could return any of the error types
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
    // Test nullable pointer
    let pos: coords = coords { x = 10, y = 20 };
    printcoords(null);
    printcoords(&pos);
    
    // Test custom error types
    match (check_value(-1)) {
    case void =>
        // Success
        return;
    case invalid =>
        // Handle invalid error
        return;
    };
    
    // Test with combined error type
    match (read_data()) {
    case let n: int =>
        let value: int = n;
    case unexpectedeof =>
        // Handle EOF
        return;
    };
    
    // Test error conversion
    let err: error = invalid;
    let msg: str = strerror(err);
};

// --- Struct with Embedded Type for Sub-typing ---

type stream = struct {
    write: *fn(data: []u8) (size | error),
    read: *fn(buf: []u8) (size | error),
};

type limit_stream = struct {
    base: stream,  // Embedded stream for sub-typing
    limit: size,
    written: size,
};

// Create a limit stream
fn new_limit_stream(limit: size) limit_stream = {
    return limit_stream {
        base = stream {
            write = null,
            read = null,
        },
        limit = limit,
        written = 0,
    };
};

// --- Type Alias for Distinct Types ---

// Even though these have same underlying type, they're distinct
type array_index = size;
type byte_offset = size;

// Can be used in a tagged union despite same representation
type position = (array_index | byte_offset);
