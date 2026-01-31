// Example: Variadic Functions, Default Parameters, and Slice Assignment
use rt;
use strings;

// --- Variadic Functions ---

// Variadic function - accepts multiple int arguments
fn printints(prefix: str, x: int...) void = {
    // x is now a []int slice containing all variadic args
    for (let i: size = 0; i < len(x); i += 1) {
        let val: int = x[i];
    };
};

// Sum any number of integers
fn sum(values: int...) int = {
    let total: int = 0;
    for (let i: size = 0; i < len(values); i += 1) {
        total += values[i];
    };
    return total;
};

// --- Default Parameters ---

// Function with default parameter value
fn printage(age: int, name: str = "Paula") str = {
    return name;
};

// Multiple default parameters
fn greet(greeting: str = "Hello", name: str = "World", times: int = 1) int = {
    return times;
};

// Mix of required and optional parameters
fn open_file(path: str, flags: int = 0, mode: int = 0o644) int = {
    return flags + mode;
};

// --- Slice Assignment ---

fn test_slice_assignment() void = {
    // Create a slice
    let x: []int = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    // Assign to a range within the slice
    let zeros: []int = [0, 0, 0, 0, 0, 0];
    x[2..8] = zeros;

    assert(x[0] == 1);
    assert(x[1] == 2);
    assert(x[2] == 0);
    assert(x[7] == 0);
    assert(x[8] == 9);
    assert(x[9] == 10);

    // Can also use array literal directly
    let y: []int = [1, 2, 3, 4, 5];
    y[1..4] = [10, 20, 30];

    assert(y[0] == 1);
    assert(y[1] == 10);
    assert(y[2] == 20);
    assert(y[3] == 30);
    assert(y[4] == 5);
};

// Copy from one slice to another using slice assignment
fn copy_data(dest: []int, src: []int) void = {
    let src_len: size = len(src);
    dest[0..src_len] = src;
};

// Variadic with different types (would need type parameter in real Hare)
fn max(first: int, rest: int...) int = {
    let result: int = first;
    for (let i: size = 0; i < len(rest); i += 1) {
        if (rest[i] > result) {
            result = rest[i];
        };
    };
    return result;
};

// Function that builds a slice from variadic args and returns it
fn make_slice(values: int...) []int = {
    return values;
};

// --- Main Function ---

export fn main() void = {
    // Call variadic function with individual args
    printints("args: ", 1, 2, 3, 4, 5);

    // Test sum with different arg counts
    assert(sum() == 0);
    assert(sum(1) == 1);
    assert(sum(1, 2) == 3);
    assert(sum(1, 2, 3) == 6);
    assert(sum(1, 2, 3, 4, 5) == 15);

    // Call variadic function with slice spread
    let nums: []int = [5, 4, 3, 2, 1];
    printints("slice: ", nums...);

    // Sum with spread slice
    let result: int = sum(nums...);
    assert(result == 15);

    // Test max
    assert(max(1) == 1);
    assert(max(1, 5, 3) == 5);
    assert(max(10, 5, 3, 8) == 10);
    assert(max(-1, -5, -3) == -1);

    // Default parameter - uses default name
    let name1: str = printage(28);
    assert(name1 == "Paula");

    // Default parameter - override default
    let name2: str = printage(11, "Tim");
    assert(name2 == "Tim");

    // Multiple defaults - use all defaults
    assert(greet() == 1);

    // Multiple defaults - override some
    assert(greet("Hi") == 1);
    assert(greet("Hi", "Claude") == 1);
    assert(greet("Hi", "Claude", 3) == 3);

    // Test open_file with defaults
    assert(open_file("test.txt") == 0 + 0o644);
    assert(open_file("test.txt", 1) == 1 + 0o644);
    assert(open_file("test.txt", 1, 0o755) == 1 + 0o755);

    // Test slice assignment
    test_slice_assignment();

    // Test copy_data
    let src: [3]int = [100, 200, 300];
    let dst: [5]int = [0...];
    copy_data(dst[..], src[..]);
    assert(dst[0] == 100);
    assert(dst[1] == 200);
    assert(dst[2] == 300);
    assert(dst[3] == 0);

    // Test make_slice
    let made: []int = make_slice(10, 20, 30);
    assert(len(made) == 3);
    assert(made[0] == 10);
    assert(made[1] == 20);
    assert(made[2] == 30);

    let msg: str = "Variadic tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
