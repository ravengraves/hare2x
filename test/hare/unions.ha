// Test: Union types
use rt;

// Simple union type
type number_union = union {
    as_int: int,
    as_u32: u32,
    as_f64: f64,
};

// Struct with anonymous union (like C11 anonymous unions)
type numeric_repr = struct {
    id: u32,
    union {
        _int: int,
        _i8: i8,
        _i16: i16,
        _i32: i32,
        _i64: i64,
        _f32: f32,
        _f64: f64,
    },
};

export fn main() void = {
    // Test 1: Basic union type
    let u: number_union = number_union { as_int = 42 };
    assert(u.as_int == 42);

    // Reinterpret the same memory as different type
    u.as_u32 = 0x12345678;
    assert(u.as_u32 == 0x12345678);

    // Test 2: Struct with anonymous union
    let repr: numeric_repr = numeric_repr {
        id = 100,
        _int = 1337,
    };
    assert(repr.id == 100);
    assert(repr._int == 1337);

    // Test 3: Pointer to struct with union - access via ->
    let ptr: *numeric_repr = &repr;
    assert(ptr.id == 100);
    assert(ptr._int == 1337);

    // Modify through pointer
    ptr._i32 = 42;
    assert(repr._i32 == 42);

    // Test 4: Union size should be max of all members
    // (can't easily test this without sizeof, but we can verify access works)
    repr._f64 = 3.14;
    // Reading _f64 should work
    let f: f64 = repr._f64;
    assert(f > 3.0);
    assert(f < 4.0);
};
