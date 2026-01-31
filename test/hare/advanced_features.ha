// Test file for verifying fixes from fixme.txt
use rt;
use strings;

// 1: Array fill with non-zero values
fn test_array_fill() void = {
    let ones: [8]int = [1...];
    assert(ones[0] == 1);
    assert(ones[7] == 1);

    let mixed: [6]int = [1, 3, 3, 42...];
    assert(mixed[0] == 1);
    assert(mixed[1] == 3);
    assert(mixed[2] == 3);
    assert(mixed[3] == 42);  // Fill starts here
    assert(mixed[4] == 42);
    assert(mixed[5] == 42);
};

// 2: Bool literals in tagged union assignment
type value = (int | str | bool | void);

fn test_bool_tagged_union() void = {
    let val_bool: value = true;
    // Should be bool variant, not int variant
    match (val_bool) {
    case let i: int => abort("should not be int");
    case let s: str => abort("should not be str");
    case let b: bool => assert(b == true);
    case void => abort("should not be void");
    };
};

// 3: Match case ordering
fn get_type_name(v: value) int = {
    // Cases in different order than type definition
    return match (v) {
    case let s: str => yield 1;   // str is tag 1
    case let i: int => yield 0;   // int is tag 0
    case void => yield 3;         // void is tag 3
    case let b: bool => yield 2;  // bool is tag 2
    };
};

fn test_match_ordering() void = {
    let v_int: value = 42;
    let v_str: value = "hello";

    assert(get_type_name(v_int) == 0);
    assert(get_type_name(v_str) == 1);
};

// 4: 'is' operator for error types
type myerror = !void;
type int_result = (int | myerror);

fn divide(a: int, b: int) int_result = {
    if (b == 0) {
        return myerror;
    };
    return (a / b);
};

fn test_is_error() void = {
    let r: int_result = divide(10, 0);
    // 'is' should correctly check for error type with HARE_ERROR_TAG_BASE
    assert(r is myerror);

    let r2: int_result = divide(10, 2);
    assert(r2 is int);
};

// 5: Inferred array size bounds checking
fn test_inferred_array() void = {
    let y: [_]int = [10, 20, 30, 40, 50];
    // Should use HARE_ARRAY_LEN instead of None
    assert(y[0] == 10);
    assert(y[4] == 50);
};

// 6: Slice type inference
fn test_slice_inference() void = {
    let x: [4]int = [1, 2, 3, 4];
    let full_slice = x[..];  // No type annotation
    // len should use .len, not HARE_ARRAY_LEN
    assert(len(full_slice) == 4);
    assert(full_slice[0] == 1);
};

export fn main() void = {
    test_array_fill();
    test_bool_tagged_union();
    test_match_ordering();
    test_is_error();
    test_inferred_array();
    test_slice_inference();

    let msg: str = "All advanced feature tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
