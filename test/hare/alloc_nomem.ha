// Example: Alloc returning tagged union (*T | nomem)
use rt;
use strings;

// Test alloc with ! (crash on OOM)
fn test_alloc_unwrap() void = {
    let p: *int = alloc(42)!;
    assert(*p == 42);
    *p = 100;
    assert(*p == 100);
    free(p);
};

// Test alloc with explicit match
fn test_alloc_match() void = {
    match (alloc(123)) {
    case let p: *int =>
        assert(*p == 123);
        free(p);
    case nomem =>
        abort("unexpected OOM");
    };
};

// Return type for propagation test
type alloc_result = (*int | nomem);

// Test alloc with ? (error propagation)
fn allocate_and_double(val: int) alloc_result = {
    let p: *int = alloc(val)?;
    *p = *p * 2;
    return p;
};

fn test_alloc_propagate() void = {
    match (allocate_and_double(21)) {
    case let p: *int =>
        assert(*p == 42);
        free(p);
    case nomem =>
        abort("unexpected OOM");
    };
};

export fn main() void = {
    test_alloc_unwrap();
    test_alloc_match();
    test_alloc_propagate();

    let msg: str = "Alloc nomem tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
