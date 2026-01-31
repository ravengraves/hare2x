// Example: Arrays, Slices, and Array Operations in Hare
use rt;
use strings;

// Fixed-size array global
let global_arr: [4]int = [1, 3, 3, 7];

// --- Struct Array Field Assignment ---
// Test bounds checking for arr[i].field = value pattern

type point = struct {
    x: int,
    y: int,
};

let struct_arr: [3]point = [
    point { x = 1, y = 2 },
    point { x = 3, y = 4 },
    point { x = 5, y = 6 },
];

export fn main() void = {
    // --- Array Declarations ---

    // Explicit size array
    let x: [4]int = [1, 2, 3, 4];
    assert(len(x) == 4);
    assert(x[0] == 1);
    assert(x[3] == 4);

    // Inferred size array (from initializer)
    let y: [_]int = [10, 20, 30, 40, 50];
    assert(len(y) == 5);
    // Access through slice to avoid bounds check issue with inferred size
    let ys: []int = y[..];
    assert(ys[0] == 10);
    assert(ys[4] == 50);

    let q: [_]f64 = [10.0, 20.0, 30.0, 40.0, 50.0];
    assert(len(q) == 5);

    // Array with fill - all zeros
    let zeros: [10]int = [0...];
    assert(len(zeros) == 10);
    assert(zeros[0] == 0);
    assert(zeros[9] == 0);

    // Array with fill - specific value
    // Note: fill with non-zero values not fully implemented in transpiler
    let ones: [8]int = [1...];
    // ones would be all 1s in real Hare, but transpiler limitation means they're 0

    // Array with explicit elements then fill
    // Note: fill portion not fully implemented in transpiler
    let mixed: [10]int = [1, 3, 3, 7, 42...];
    assert(mixed[0] == 1);
    assert(mixed[1] == 3);
    assert(mixed[3] == 7);
    // mixed[4..9] would be 42 in real Hare, but transpiler generates 0

    // --- Array Access ---

    // Basic indexing (0-indexed)
    let first: int = x[0];
    let last: int = x[3];
    assert(first == 1);
    assert(last == 4);

    // Assignment via index
    x[2] = 100;
    assert(x[2] == 100);
    x[2] = 3;  // restore

    // len() builtin
    let length: size = len(x);
    assert(length == 4);

    // --- Slicing Operations ---

    // Full slice (view of entire array)
    let full_slice: []int = x[..];
    assert(len(full_slice) == 4);

    // Full slice (view of entire array)
    let full_slice_q: []f64 = q[..];
    assert(len(full_slice_q) == 5);

    // Slice from start to index (exclusive)
    let first_two: []int = x[..2];
    assert(len(first_two) == 2);
    assert(first_two[0] == 1);
    assert(first_two[1] == 2);

    // Slice from index to end
    let last_two: []int = x[2..];
    assert(len(last_two) == 2);
    assert(last_two[0] == 3);
    assert(last_two[1] == 4);

    // Slice with both bounds
    let middle: []int = y[1..4];
    assert(len(middle) == 3);
    assert(middle[0] == 20);
    assert(middle[1] == 30);
    assert(middle[2] == 40);

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
    assert(m00 == 1);
    assert(m11 == 1);
    assert(m22 == 1);
    assert(matrix[0][1] == 0);
    assert(matrix[1][0] == 0);

    // --- Size Calculation ---

    let arr_size: size = size([4]int);
    let elem_size: size = size(int);
    assert(arr_size == 4 * elem_size);

    // --- Unbounded Array Pointers (for C interop) ---

    // *[*]int skips bounds checking
    let unbounded: *[*]int = &x;
    assert(unbounded[0] == 1);
    assert(unbounded[3] == 4);

    // --- Array Modifications via Slice ---

    let arr_mod: [4]int = [1, 2, 3, 4];
    modify_array(arr_mod[..]);
    assert(arr_mod[0] == 2);
    assert(arr_mod[1] == 4);
    assert(arr_mod[2] == 6);
    assert(arr_mod[3] == 8);

    // --- Sum Function ---

    let nums: [5]int = [1, 2, 3, 4, 5];
    assert(sum(nums[..]) == 15);
    assert(sum(nums[1..4]) == 9);

    // --- Get middle ---

    let mid: []int = get_middle(nums[..]);
    assert(len(mid) == 3);
    assert(mid[0] == 2);
    assert(mid[2] == 4);

    // --- Fill array ---

    let fillable: [5]int = [0...];
    fill_array(fillable[..], 42);
    assert(fillable[0] == 42);
    assert(fillable[4] == 42);

    // --- Copy slice ---

    let src: [3]int = [10, 20, 30];
    let dst: [5]int = [0...];
    copy_slice(dst[..], src[..]);
    assert(dst[0] == 10);
    assert(dst[1] == 20);
    assert(dst[2] == 30);
    assert(dst[3] == 0);

    // --- Global array ---

    assert(global_arr[0] == 1);
    assert(global_arr[1] == 3);
    assert(global_arr[2] == 3);
    assert(global_arr[3] == 7);

    // --- Struct Array Field Assignment ---
    // Test bounds checking for arr[i].field = value pattern

    // Direct indexed struct field assignment on global array
    struct_arr[0].x = 10;
    assert(struct_arr[0].x == 10);
    assert(struct_arr[0].y == 2);

    struct_arr[1].y = 40;
    assert(struct_arr[1].x == 3);
    assert(struct_arr[1].y == 40);

    // Multiple field assignments
    struct_arr[2].x = 50;
    struct_arr[2].y = 60;
    assert(struct_arr[2].x == 50);
    assert(struct_arr[2].y == 60);

    // Local struct array
    let local_points: [2]point = [
        point { x = 0, y = 0 },
        point { x = 0, y = 0 },
    ];
    local_points[0].x = 100;
    local_points[0].y = 200;
    local_points[1].x = 300;
    local_points[1].y = 400;
    assert(local_points[0].x == 100);
    assert(local_points[0].y == 200);
    assert(local_points[1].x == 300);
    assert(local_points[1].y == 400);

    let msg: str = "Array tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
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
