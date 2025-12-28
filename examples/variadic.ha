// Example: Variadic Functions, Default Parameters, and Slice Assignment

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
fn printage(age: int, name: str = "Paula") void = {
    // If name not provided, defaults to "Paula"
    let a: int = age;
    let n: str = name;
};

// Multiple default parameters
fn greet(greeting: str = "Hello", name: str = "World", times: int = 1) void = {
    for (let i: int = 0; i < times; i += 1) {
        let g: str = greeting;
        let n: str = name;
    };
};

// Mix of required and optional parameters
fn open_file(path: str, flags: int = 0, mode: int = 0644) int = {
    let p: str = path;
    let f: int = flags;
    let m: int = mode;
    return 0;
};

// --- Slice Assignment ---

fn test_slice_assignment() void = {
    // Create a slice
    let x: []int = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    
    // Assign to a range within the slice
    // x[2..8] = [0, 0, 0, 0, 0, 0]
    // This replaces elements 2 through 7 with zeros
    let zeros: []int = [0, 0, 0, 0, 0, 0];
    x[2..8] = zeros;
    
    // Can also use array literal directly
    let y: []int = [1, 2, 3, 4, 5];
    y[1..4] = [10, 20, 30];
};

// Copy from one slice to another using slice assignment
fn copy_data(dest: []int, src: []int) void = {
    // Copy src into the beginning of dest
    let src_len: size = len(src);
    dest[0..src_len] = src;
};

// --- Main Function ---

export fn main() void = {
    // Call variadic function with individual args
    printints("args: ", 1, 2, 3, 4, 5);
    
    // Call variadic function with slice spread
    let nums: []int = [5, 4, 3, 2, 1];
    printints("slice: ", nums...);
    
    // Sum with variadic args
    let total: int = sum(1, 2, 3, 4, 5);
    
    // Sum with spread slice
    let result: int = sum(nums...);
    
    // Default parameter - uses default name
    printage(28);
    
    // Default parameter - override default
    printage(11, "Tim");
    
    // Multiple defaults - use all defaults
    greet();
    
    // Multiple defaults - override some
    greet("Hi");
    greet("Hi", "Claude");
    greet("Hi", "Claude", 3);
    
    // Test slice assignment
    test_slice_assignment();
};

// --- Additional Examples ---

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
    return values;  // Just return the slice directly
};
