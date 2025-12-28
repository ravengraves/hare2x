// Example: Error handling and tagged unions in Hare

// Define a simple error type
type myerror = !void;

// Define a more complex error type with data
type parse_error = !struct {
    line: int,
    col: int,
};

// Tagged union for results (success | error)
type int_result = (int | myerror);

// Function that can fail
fn divide(a: int, b: int) int_result = {
    if (b == 0) {
        return myerror;
    };
    return a / b;
};

// Function using error assertion (crashes on error)
fn safe_divide(a: int, b: int) int = {
    let result: int_result = divide(a, b);
    // In real Hare, this would be: divide(a, b)!
    // For now we use match
    return match (result) {
    case let v: int =>
        yield v;
    case myerror =>
        yield 0;
    };
};

// More complex tagged union
type value = (int | str | bool | void);

fn get_value_type(v: value) int = {
    return match (v) {
    case let i: int =>
        yield 1;
    case let s: str =>
        yield 2;
    case let b: bool =>
        yield 3;
    case void =>
        yield 0;
    };
};

// Using the 'is' operator for type testing
fn is_integer(v: value) bool = {
    return v is int;
};

// Switch expression (for non-tagged values)
fn day_name(day: int) int = {
    return switch (day) {
    case 0 =>
        yield 0;
    case 1 =>
        yield 1;
    case 2, 3, 4 =>
        yield 2;
    case =>
        yield 99;
    };
};

// Multiple error types
type io_error = !int;
type fs_error = !int;

type file_result = (int | io_error | fs_error);

fn open_file(path: str) file_result = {
    // Simulated - would actually open a file
    return 42;
};

fn read_file(fd: int) file_result = {
    if (fd < 0) {
        return io_error;
    };
    return 100;
};

// Error propagation example (conceptual)
// In real Hare: fn process_file(path: str) file_result = {
//     let fd = open_file(path)?;
//     let data = read_file(fd)?;
//     return data;
// };

fn process_file(path: str) file_result = {
    let fd_result: file_result = open_file(path);
    let fd: int = match (fd_result) {
    case let f: int =>
        yield f;
    case let e: io_error =>
        return e;
    case let e: fs_error =>
        return e;
    };
    
    let data_result: file_result = read_file(fd);
    return match (data_result) {
    case let d: int =>
        yield d;
    case let e: io_error =>
        yield e;
    case let e: fs_error =>
        yield e;
    };
};

// Nullable pointer handling with match
fn maybe_deref(ptr: nullable *int) int = {
    return match (ptr) {
    case null =>
        yield 0;
    case let p: *int =>
        yield *p;
    };
};

export fn main() void = {
    // Test divide
    let r1: int_result = divide(10, 2);
    let r2: int_result = divide(10, 0);
    
    // Test safe_divide with error assertion semantics
    let v1: int = safe_divide(20, 4);
    
    // Test tagged union matching
    let val: value = 42;
    let vtype: int = get_value_type(val);
    
    // Test type checking
    let is_int: bool = is_integer(val);
    
    // Test switch
    let name: int = day_name(3);
    
    // Test nullable pointers
    let x: int = 100;
    let p: nullable *int = &x;
    let deref: int = maybe_deref(p);
    let null_deref: int = maybe_deref(null);
};
