// failtests.ha - Tests that should FAIL to compile
// These test that the transpiler properly rejects invalid Hare syntax
//
// Each test is commented out and marked with the expected error.
// To test, uncomment one at a time and verify the transpiler rejects it.

use rt;

// =============================================================================
// FAIL TEST 1: Invalid array to unbounded pointer cast
// =============================================================================
// Expected error: "Invalid cast from [N]T to *[*]T"
//
// export fn test_invalid_array_cast() void = {
//     let arr: [5]i32 = [1, 2, 3, 4, 5];
//     let parr: *[*]i32 = arr: *[*]i32;  // INVALID
// };

// =============================================================================
// FAIL TEST 2: Using type alias as literal value
// =============================================================================
// Expected error: "Cannot use type alias as literal"
//
// type invalid = !void;
//
// fn test_return_type_alias() (void | invalid) = {
//     return invalid;  // INVALID - cannot use type name as value
// };

// =============================================================================
// FAIL TEST 3: Pointer to void (zero-sized type)
// =============================================================================
// Expected error: "Cannot have pointer to zero-sized type"
//
// export fn test_void_pointer() void = {
//     let i: int = 42;
//     let raw: *void = &i;  // INVALID - void is zero-sized
// };

// =============================================================================
// FAIL TEST 4: Leading zero in decimal literal (octal syntax)
// =============================================================================
// Expected error: "Leading zero in base 10 literal"
//
// export fn test_octal_literal() void = {
//     let mode: int = 0644;  // INVALID - use 0o644 for octal
// };

// =============================================================================
// FAIL TEST 5: Match on non-tagged/non-nullable type
// =============================================================================
// Expected error: "Match value is not tagged union, pointer to tagged union, or nullable pointer"
//
// export fn test_invalid_match() void = {
//     let c: u8 = 'a';
//     let result = match (c) {  // INVALID - u8 is not a tagged union
//         case 'a' => 1;
//         case 'b' => 2;
//         case => 0;
//     };
// };

// =============================================================================
// FAIL TEST 6: Using undefined type (char)
// =============================================================================
// Expected error: "Unresolvable identifier 'char'"
//
// fn test_char_type() char = {  // INVALID - no 'char' type in Hare
//     return 'a';
// };

// =============================================================================
// FAIL TEST 7: Cannot ignore error return value
// =============================================================================
// Expected error: "Cannot ignore error here"
//
// export fn test_ignore_error() void = {
//     let items: []int = [];
//     append(items, 10);  // INVALID - append returns error, can't ignore
// };

// =============================================================================
// FAIL TEST 8: Invalid function pointer syntax
// =============================================================================
// Expected error: Syntax error in function pointer declaration
//
// fn test_fn_pointer(func: *fn(int, int) int, a: int, b: int) int = {
//     return func(a, b);
// };

// =============================================================================
// FAIL TEST 9: Type mismatch - tagged union member not assignable
// =============================================================================
// Expected error: "Initializer of type (T | U) is not assignable to binding type T"
//
// type nomem = !void;
//
// fn dup(s: str) (str | nomem) = {
//     return s;  // For test purposes
// };
//
// export fn test_type_mismatch() void = {
//     let s = "hello";
//     let dup_str: str = dup(s);  // INVALID - returns (str | nomem), not str
// };

// =============================================================================
// FAIL TEST 10: Reserved keyword as parameter name
// =============================================================================
// Expected error: Syntax error or reserved word conflict
//
// fn test_reserved_param(data: []u8, offset: size) *u8 = {
//     return &data[offset];
// };

// =============================================================================
// FAIL TEST 11: Invalid cast - incompatible types
// =============================================================================
// Expected error: "Invalid cast from str to *[*]u8"
//
// export fn test_invalid_str_cast() void = {
//     let s = "hello";
//     let ptr: *[*]u8 = s: *[*]u8;  // INVALID
// };

// =============================================================================
// FAIL TEST 12: Null to non-nullable pointer
// =============================================================================
// Expected error: "Argument type null is not assignable to parameter type *T"
//
// fn takes_str_ptr(path: *str, line: u64, col: u64, reason: u64) void = {
//     return;
// };
//
// export fn test_null_to_nonnullable() void = {
//     takes_str_ptr(null, 0, 0, 6);  // INVALID - *str is not nullable
// };

// =============================================================================
// VALID TEST - This should compile successfully
// =============================================================================

export fn main() void = {
    // This test file is designed to have all actual code commented out
    // Uncomment individual tests to verify they fail as expected
    let msg: [25]u8 = ['F', 'a', 'i', 'l', ' ', 't', 'e', 's', 't', 's', ' ', 'r', 'e', 'a', 'd', 'y', '\n', 0, 0, 0, 0, 0, 0, 0, 0];
    let n = rt::write(1, &msg: *const opaque, 17);
};
