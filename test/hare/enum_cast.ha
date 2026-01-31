// Test enums and type casting in Hare
use rt;
use strings;

// Basic enum
type color = enum {
    RED,
    ORANGE,
    YELLOW,
    GREEN,
    BLUE,
    VIOLET,
};

// Enum with explicit values
type http_status = enum {
    OK = 200,
    CREATED = 201,
    BAD_REQUEST = 400,
    NOT_FOUND = 404,
    SERVER_ERROR = 500,
};

// Enum with underlying type
type small_enum = enum u8 {
    A,
    B,
    C,
};

// Tagged union for type testing
type value = (int | uint | str | bool);

// Get color name using switch on enum
fn get_color_name(c: color) str = {
    return switch (c) {
        case color::RED => yield "red";
        case color::ORANGE => yield "orange";
        case color::YELLOW => yield "yellow";
        case color::GREEN => yield "green";
        case color::BLUE => yield "blue";
        case color::VIOLET => yield "violet";
        case => yield "unknown";
    };
};

// Test numeric casting
fn test_numeric_cast() void = {
    // Float to int (truncates)
    let f: f32 = 13.37;
    let i: int = f: int;
    assert(i == 13);

    // Int to float
    let n: int = 42;
    let fl: f64 = n: f64;
    assert(fl == 42.0);

    // Between integer sizes
    let big: i64 = 1000;
    let small: i32 = big: i32;
    assert(small == 1000);

    // Signed/unsigned conversion
    let u: uint = 100;
    let s: int = u: int;
    assert(s == 100);

    // Test truncation
    let f2: f32 = 99.9;
    assert(f2: int == 99);

    let f3: f32 = -5.7;
    assert(f3: int == -5);
};

// Test type assertions with 'is'
fn test_type_is() void = {
    let x: value = 42;
    let is_int: bool = x is int;
    let is_uint: bool = x is uint;
    let is_str: bool = x is str;
    assert(is_int == true);
    assert(is_uint == false);
    assert(is_str == false);

    let y: value = "hello";
    let y_is_str: bool = y is str;
    let y_is_int: bool = y is int;
    assert(y_is_str == true);
    assert(y_is_int == false);

    let z: value = true;
    assert(z is bool);
    assert(!(z is int));
};

// Test pointer casting
fn test_pointer_cast() void = {
    let x: int = 42;
    let ptr: *int = &x;

    // Pointer to uintptr
    let addr: uintptr = ptr: uintptr;
    assert(addr != 0);

    // uintptr back to pointer
    let back: *int = addr: *int;
    assert(*back == 42);

    // Modify through reconstituted pointer
    *back = 100;
    assert(x == 100);
};

// Test nullable pointer with is
fn test_nullable_is() void = {
    let ptr: nullable *int = null;
    let is_null: bool = ptr is null;
    assert(is_null == true);

    let x: int = 100;
    let ptr2: nullable *int = &x;
    let is_null2: bool = ptr2 is null;
    assert(is_null2 == false);

    // Test with match
    match (ptr) {
    case null =>
        assert(true);
    case let p: *int =>
        abort();
    };

    match (ptr2) {
    case null =>
        abort();
    case let p: *int =>
        assert(*p == 100);
    };
};

export fn main() void = {
    // Test enum values
    const c = color::BLUE;
    let name: str = get_color_name(c);
    assert(name == "blue");

    assert(get_color_name(color::RED) == "red");
    assert(get_color_name(color::GREEN) == "green");
    assert(get_color_name(color::VIOLET) == "violet");

    // Test enum comparison
    assert(c == color::BLUE);
    assert(c != color::RED);

    // Test HTTP status enum with explicit values
    let status = http_status::NOT_FOUND;
    assert(status == http_status::NOT_FOUND);
    assert(status != http_status::OK);

    // Test small_enum
    let se = small_enum::B;
    assert(se == small_enum::B);
    assert(se != small_enum::A);

    // Run other tests
    test_numeric_cast();
    test_type_is();
    test_pointer_cast();
    test_nullable_is();

    let msg: str = "Enum and cast tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
