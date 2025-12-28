// Example: Arrays, Slices, and Array Operations in Hare

// Fixed-size array global
let global_arr: [4]int = [1, 3, 3, 7];

export fn main() void = {
    // --- Array Declarations ---
    
    // Explicit size array
    let x: [4]int = [1, 2, 3, 4];
    
    // Inferred size array (from initializer)
    let y: [_]int = [10, 20, 30, 40, 50];
    
    // Array with fill - all zeros
    let zeros: [10]int = [0...];
    
    // Array with fill - specific value
    let ones: [8]int = [1...];
    
    // Array with explicit elements then fill
    let mixed: [1024]int = [1, 3, 3, 7, 42...];
    
    // --- Array Access ---
    
    // Basic indexing (0-indexed)
    let first: int = x[0];
    let last: int = x[3];
    
    // Assignment via index
    x[2] = 100;
    
    // len() builtin
    let length: size = len(x);
    
    // --- Slicing Operations ---
    
    // Full slice (view of entire array)
    let full_slice: []int = x[..];
    
    // Slice from start to index (exclusive)
    let first_two: []int = x[..2];
    
    // Slice from index to end
    let last_two: []int = x[2..];
    
    // Slice with both bounds
    let middle: []int = y[1..4];
    
    // --- Passing Arrays to Functions ---
    
    // Pass array slice to function
    printvals(y[..]);
    printvals(y[..3]);
    printvals(y[2..5]);
    
    // --- Nested Arrays ---
    
    let matrix: [3][3]int = [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1]
    ];
    
    let m00: int = matrix[0][0];
    let m11: int = matrix[1][1];
    let m22: int = matrix[2][2];
    
    // --- Size Calculation ---
    
    let arr_size: size = size([4]int);
    let elem_size: size = size(int);
    
    // --- Unbounded Array Pointers (for C interop) ---
    
    // *[*]int skips bounds checking
    let unbounded: *[*]int = &x;
    // This would be undefined behavior: unbounded[100]
    
    // --- Array Modifications via Slice ---
    
    modify_array(x[..]);
    
    // --- Assertions ---
    
    assert(len(x) == 4);
    assert(x[0] == 1);
};

// Function taking a slice parameter
fn printvals(input: []int) void = {
    for (let i: size = 0; i < len(input); i += 1) {
        // Access slice element
        let val: int = input[i];
    };
};

// Function that modifies array via slice
fn modify_array(arr: []int) void = {
    for (let i: size = 0; i < len(arr); i += 1) {
        arr[i] = arr[i] * 2;
    };
};

// Sum elements in a slice
fn sum(items: []int) int = {
    let total: int = 0;
    for (let i: size = 0; i < len(items); i += 1) {
        total += items[i];
    };
    return total;
};

// Return a view into an array
fn get_middle(arr: []int) []int = {
    let start: size = 1;
    let end: size = len(arr) - 1;
    return arr[start..end];
};

// Working with multi-dimensional arrays
fn matrix_diagonal_sum(mat: [][3]int) int = {
    let total: int = 0;
    for (let i: size = 0; i < len(mat); i += 1) {
        total += mat[i][i];
    };
    return total;
};

// Fill array with value
fn fill_array(arr: []int, value: int) void = {
    for (let i: size = 0; i < len(arr); i += 1) {
        arr[i] = value;
    };
};

// Copy from one slice to another
fn copy_slice(dest: []int, src: []int) void = {
    let copy_len: size = len(src);
    if (len(dest) < copy_len) {
        copy_len = len(dest);
    };
    for (let i: size = 0; i < copy_len; i += 1) {
        dest[i] = src[i];
    };
};
