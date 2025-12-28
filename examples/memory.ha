// Example: Memory management and slice operations in Hare

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
    
    // Insert at index 0
    insert(items[0], 5);
    
    // Delete at index 2
    delete(items[2]);
    
    // Free when done
    free(items);
};

// Static slice operations (no allocation)
fn test_static_slice() void = {
    // Fixed buffer backing the slice
    let buf: [10]int = [0...];
    let items: []int = buf[..0];  // Zero-length slice backed by buf
    
    // Static append (won't reallocate)
    static append(items, 1);
    static append(items, 2);
    static append(items, 3);
    
    // Static insert
    static insert(items[0], 0);
    
    // Static delete
    static delete(items[2]);
};

// Dynamic memory allocation
fn test_heap_alloc() void = {
    // Allocate single value
    let ptr: *int = alloc(42);
    let value: int = *ptr;
    free(ptr);
    
    // Allocate array
    let arr: *[10]int = alloc([0...]);
    free(arr);
    
    // Allocate slice with capacity
    let slice: []int = alloc([1, 2, 3], 10);
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
    let dst: []int = alloc(src...);  // Copy allocation
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
    
    // Test static locals
    let v1: int = increment();  // Returns 1
    let v2: int = increment();  // Returns 2
    let v3: int = increment();  // Returns 3
    
    // Test size
    let total_size: size = test_size();
    
    // Test slice sum
    let numbers: []int = [10, 20, 30, 40, 50];
    let total: int = sum_slice(numbers);
    
    // Test copy
    test_slice_copy();
};
