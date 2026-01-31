// Test file for defer statement functionality
use rt;
use strings;

// Global counter and order array to verify execution order
let counter: int = 0;
let order: [20]int = [0...];

fn record(val: int) void = {
    order[counter] = val;
    counter += 1;
};

fn reset() void = {
    counter = 0;
    for (let i: size = 0; i < 20; i += 1) {
        order[i] = 0;
    };
};

// Test 1: Basic defer - LIFO order
fn test_basic_defer() void = {
    reset();
    {
        defer record(1);
        defer record(2);
        defer record(3);
    };
    // Should execute in reverse: 3, 2, 1
    assert(order[0] == 3);
    assert(order[1] == 2);
    assert(order[2] == 1);
    assert(counter == 3);
};

// Test 2: Defer with return
fn test_defer_return_helper() int = {
    defer record(99);
    defer record(88);
    return 42;
};

fn test_defer_with_return() void = {
    reset();
    let result: int = test_defer_return_helper();
    assert(result == 42);
    // Defers should have run: 88, then 99
    assert(order[0] == 88);
    assert(order[1] == 99);
    assert(counter == 2);
};

// Test 3: Defer with early return (defers only run for those that were reached)
fn test_early_return_helper(do_early: bool) void = {
    if (do_early) {
        record(1);  // This runs
        return;     // No defers yet
    };
    defer record(2);  // Only reached if !do_early
    record(3);
};

fn test_defer_early_return() void = {
    reset();
    test_early_return_helper(true);
    // Only record(1) should have run, no defers
    assert(order[0] == 1);
    assert(counter == 1);

    reset();
    test_early_return_helper(false);
    // record(3) runs first, then defer record(2)
    assert(order[0] == 3);
    assert(order[1] == 2);
    assert(counter == 2);
};

// Test 4: Nested blocks with defers
fn test_nested_blocks() void = {
    reset();
    {
        defer record(1);
        {
            defer record(2);
            defer record(3);
        };  // Inner block ends: 3, 2
        defer record(4);
    };  // Outer block ends: 4, 1
    // Order should be: 3, 2, 4, 1
    assert(order[0] == 3);
    assert(order[1] == 2);
    assert(order[2] == 4);
    assert(order[3] == 1);
    assert(counter == 4);
};

// Test 5: Defer in loop (each iteration has its own scope)
fn test_defer_in_loop() void = {
    reset();
    for (let i: int = 0; i < 3; i += 1) {
        defer record(i);
        // Loop body ends, defer runs for this iteration
    };
    // Each iteration runs its defer at end of loop body
    // i=0: defer record(0) -> order[0]=0
    // i=1: defer record(1) -> order[1]=1
    // i=2: defer record(2) -> order[2]=2
    assert(order[0] == 0);
    assert(order[1] == 1);
    assert(order[2] == 2);
    assert(counter == 3);
};

// Test 6: Defer with break
fn test_defer_with_break() void = {
    reset();
    for (let i: int = 0; i < 10; i += 1) {
        defer record(i);
        if (i == 2) {
            break;  // Should run defer for i=2 before breaking
        };
    };
    // i=0: defer record(0) -> order[0]=0
    // i=1: defer record(1) -> order[1]=1
    // i=2: break with defer record(2) -> order[2]=2
    assert(order[0] == 0);
    assert(order[1] == 1);
    assert(order[2] == 2);
    assert(counter == 3);
};

// Test 7: Defer with continue
fn test_defer_with_continue() void = {
    reset();
    for (let i: int = 0; i < 4; i += 1) {
        defer record(i);
        if (i == 1) {
            continue;  // Should run defer before continuing
        };
        // This only runs for i != 1
    };
    // All defers run regardless of continue
    assert(order[0] == 0);
    assert(order[1] == 1);
    assert(order[2] == 2);
    assert(order[3] == 3);
    assert(counter == 4);
};

// Test 8: Multiple defers before return
fn multi_defer_return() int = {
    defer record(1);
    defer record(2);
    defer record(3);
    defer record(4);
    return 100;
};

fn test_multi_defer_return() void = {
    reset();
    let r: int = multi_defer_return();
    assert(r == 100);
    // LIFO: 4, 3, 2, 1
    assert(order[0] == 4);
    assert(order[1] == 3);
    assert(order[2] == 2);
    assert(order[3] == 1);
    assert(counter == 4);
};

// Test 9: Defer with conditional return in nested block
fn conditional_nested() void = {
    defer record(1);  // Outer defer
    {
        defer record(2);  // Inner defer
        if (true) {
            return;  // Should run both defers: 2, then 1
        };
    };
};

fn test_conditional_nested() void = {
    reset();
    conditional_nested();
    // Return runs inner defer (2), then outer defer (1)
    assert(order[0] == 2);
    assert(order[1] == 1);
    assert(counter == 2);
};

export fn main() void = {
    test_basic_defer();
    test_defer_with_return();
    test_defer_early_return();
    test_nested_blocks();
    test_defer_in_loop();
    test_defer_with_break();
    test_defer_with_continue();
    test_multi_defer_return();
    test_conditional_nested();

    let msg: str = "All defer tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
