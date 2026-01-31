// Test: Pointer field access (. vs ->)
use rt;

type point = struct {
    x: int,
    y: int,
};

// Function returning a pointer
fn make_point(x: int, y: int) *point = {
    let p: *point = alloc(point { x = x, y = y })!;
    return p;
};

// Test pointer indexing and field access
fn test_array_ptr() void = {
    let points: [3]point = [
        point { x = 1, y = 2 },
        point { x = 3, y = 4 },
        point { x = 5, y = 6 },
    ];

    // Test: let ptr = &arr[i]; ptr.field should use ->
    let ptr: *point = &points[1];
    assert(ptr.x == 3);  // Should generate ptr->x
    assert(ptr.y == 4);  // Should generate ptr->y
};

// Test function returning pointer with field access
fn test_fn_ptr_field() void = {
    // Test: fn().field where fn returns pointer should use ->
    let p = make_point(10, 20);
    assert(p.x == 10);  // p is *point, should use ->
    assert(p.y == 20);

    // Direct field access on function return
    assert(make_point(7, 8).x == 7);  // Should generate make_point(...)->x
    assert(make_point(7, 8).y == 8);
};

// Test multi-level pointer indirection (**, ***)
fn test_multi_level_ptr() void = {
    let p = point { x = 100, y = 200 };

    // Single pointer
    let ptr: *point = &p;
    assert(ptr.x == 100);  // Should generate (*ptr).x

    // Double pointer
    let pptr: **point = &ptr;
    assert(pptr.x == 100);  // Should generate (**pptr).x

    // Triple pointer
    let ppptr: ***point = &pptr;
    assert(ppptr.x == 100);  // Should generate (***ppptr).x
};

// Test cast expressions with field access
type node = struct {
    data: int,
    next: nullable *node,
    prev: nullable *node,
};

type container = struct {
    first: nullable *node,
    last: nullable *node,
};

fn test_cast_field_access(c: *container, n: *node) void = {
    match (c.last) {
    case let last: *node =>
        last.next = n;
        n.prev = last;
    case null =>
        c.first = n;
    };
    c.last = n;
};

fn test_cast_deref() void = {
    let n1 = node { data = 1, next = null, prev = null };
    let n2 = node { data = 2, next = null, prev = null };
    let c = container { first = null, last = null };

    test_cast_field_access(&c, &n1);
    assert(c.first == &n1);
    assert(c.last == &n1);

    test_cast_field_access(&c, &n2);
    assert(n1.next == &n2);
    assert(n2.prev == &n1);
    assert(c.last == &n2);
};

export fn main() void = {
    test_array_ptr();
    test_fn_ptr_field();
    test_multi_level_ptr();
    test_cast_deref();
};
