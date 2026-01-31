// ERROR: Cannot ignore error here - append() returns error type
// Example: Memory management and slice operations in Hare
use rt;
use strings;

// Static global variable
let counter: int = 0;

// Dynamic slice operations
fn test_dynamic_slice() void = {
    // Create an empty dynamic slice
    let items: []int = [];

    // Append single values
    append(items, 10);
    append(items, 20);
    append(items, 30);

    // Get length
    let length: size = len(items);
    assert(length == 3);
    assert(items[0] == 10);
    assert(items[1] == 20);
    assert(items[2] == 30);

    // Insert at index 0
    insert(items[0], 5);
    assert(len(items) == 4);
    assert(items[0] == 5);
    assert(items[1] == 10);

    // Delete at index 2
    delete(items[2]);
    assert(len(items) == 3);
    assert(items[0] == 5);
    assert(items[1] == 10);
    assert(items[2] == 30);

    // Free when done
    free(items);
};

// Static slice operations (no allocation)
fn test_static_slice() void = {
    // Fixed buffer backing the slice
    let buf: [10]int = [0...];
    let items: []int = buf[..0];

    // Static append (won't reallocate)
    static append(items, 1);
    static append(items, 2);
    static append(items, 3);

    assert(len(items) == 3);
    assert(items[0] == 1);
    assert(items[1] == 2);
    assert(items[2] == 3);

    // Static insert
    static insert(items[0], 0);
    assert(len(items) == 4);
    assert(items[0] == 0);
    assert(items[1] == 1);

    // Static delete
    static delete(items[2]);
    assert(len(items) == 3);
    assert(items[2] == 3);
};

// Dynamic memory allocation
fn test_heap_alloc() void = {
    // Allocate single value
    let ptr: *int = alloc(42)!;
    let value: int = *ptr;
    assert(value == 42);
    *ptr = 100;
    assert(*ptr == 100);
    free(ptr);

    // Allocate array
    let arr: *[10]int = alloc([0...])!;
    (*arr)[0] = 1;
    (*arr)[9] = 9;
    assert((*arr)[0] == 1);
    assert((*arr)[9] == 9);
    free(arr);

    // Allocate slice with capacity
    let slice: []f32 = alloc([1.0, 2.7, 3.8], 10)!;
    assert(len(slice) == 3);
    assert(slice[0] == 1.0);
    free(slice);
};

// Static local variables
fn increment() int = {
    static let x: int = 0;
    x += 1;
    return x;
};

fn get_static_buffer() *[1024]u8 = {
    static let buffer: [1024]u8 = [0...];
    return &buffer;
};

// Using size builtin
fn test_size() size = {
    let s1: size = size(int);
    let s2: size = size(u8);
    let s3: size = size(*int);
    assert(s2 == 1);
    assert(s1 >= 4);
    assert(s3 >= 4);
    return s1 + s2 + s3;
};

// Slice with for-each iteration pattern
fn sum_slice(items: []int) int = {
    let total: int = 0;
    for (let i: size = 0; i < len(items); i += 1) {
        total += items[i];
    };
    return total;
};

// Copy slice data
fn test_slice_copy() void = {
    let src: []int = [1, 2, 3, 4, 5];
    let dst: []int = alloc(src...)!;
    assert(len(dst) == 5);
    assert(dst[0] == 1);
    assert(dst[4] == 5);
    free(dst);
};

// Working with strings (which are slices of bytes)
fn string_length(s: str) size = {
    return len(s);
};

export fn main() void = {
    // Test dynamic slices
    test_dynamic_slice();

    // Test static slices
    test_static_slice();

    // Test heap allocation
    test_heap_alloc();

    // Test static locals - should persist across calls
    let v1: int = increment();
    assert(v1 == 1);
    let v2: int = increment();
    assert(v2 == 2);
    let v3: int = increment();
    assert(v3 == 3);

    // Test static buffer
    let buf1 = get_static_buffer();
    (*buf1)[0] = 42;
    let buf2 = get_static_buffer();
    assert((*buf2)[0] == 42);  // Same buffer

    // Test size
    let total_size: size = test_size();
    assert(total_size > 0);

    // Test slice sum
    let numbers: []int = [10, 20, 30, 40, 50];
    let total: int = sum_slice(numbers);
    assert(total == 150);

    // Test copy
    test_slice_copy();

    // Test string length
    assert(string_length("hello") == 5);
    assert(string_length("") == 0);
    assert(string_length("test string") == 11);

    let msg: str = "Memory tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
