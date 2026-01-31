// Simplified stress test for hare2c transpiler
use rt;
use strings;

// ============================================
// PART 1: Complex error types and propagation
// ============================================

type io_error = !void;
type parse_error = !void;

type multi_result = (int | io_error | parse_error);

fn may_fail_io(x: int) multi_result = {
    if (x < 0) {
        return io_error;
    };
    return x;
};

fn may_fail_parse(x: int) multi_result = {
    if (x == 0) {
        return parse_error;
    };
    return x * 2;
};

// Chained error propagation
fn chain_errors(x: int) multi_result = {
    let a = may_fail_io(x)?;
    let b = may_fail_parse(a)?;
    return b + 1;
};

// ============================================
// PART 2: Nullable pointer scenarios
// ============================================

type point = struct {
    x: int,
    y: int,
};

fn find_point_by_x(pts: []point, target_x: int) nullable *point = {
    for (let i = 0z; i < len(pts); i += 1) {
        if (pts[i].x == target_x) {
            return &pts[i];
        };
    };
    return null;
};

fn get_point_sum(ptr: nullable *point) int = {
    match (ptr) {
    case null =>
        return 0;
    case let p: *point =>
        return p.x + p.y;
    };
};

// ============================================
// PART 3: Loop with errors
// ============================================

type loop_error = !void;
type loop_result = (int | loop_error);

fn sum_until_negative(arr: []int) loop_result = {
    let total = 0;
    for (let i = 0z; i < len(arr); i += 1) {
        if (arr[i] < 0) {
            return loop_error;
        };
        total += arr[i];
    };
    return total;
};

// ============================================
// PART 4: Enum and switch
// ============================================

type color = enum {
    RED = 0,
    GREEN = 1,
    BLUE = 2,
};

fn color_value(c: color) int = {
    return switch (c) {
    case color::RED =>
        yield 0xFF0000;
    case color::GREEN =>
        yield 0x00FF00;
    case color::BLUE =>
        yield 0x0000FF;
    };
};

// ============================================
// PART 5: Slice operations
// ============================================

fn slice_middle(arr: []int) []int = {
    if (len(arr) < 3) {
        return arr[0..len(arr)];
    };
    return arr[1..len(arr)-1];
};

// ============================================
// PART 6: @symbol functions
// ============================================

@symbol("ext_process") fn process(x: int) int = x + 1;

// ============================================
// PART 7: RT module
// ============================================

fn test_rt() void = {
    let src: [8]u8 = [1, 2, 3, 4, 5, 6, 7, 8];
    let dst: [8]u8 = [0, 0, 0, 0, 0, 0, 0, 0];
    
    rt::memcpy(&dst, &src, 8);
    assert(dst[0] == 1);
    assert(dst[7] == 8);
    
    rt::memset(&dst, 0, 4);
    assert(dst[0] == 0);
    assert(dst[4] == 5);
};

// ============================================
// MAIN
// ============================================

export fn main() void = {
    // Test error handling
    let r1 = chain_errors(5);
    match (r1) {
    case let v: int =>
        assert(v == 11);
    case io_error =>
        abort();
    case parse_error =>
        abort();
    };
    
    let r2 = chain_errors(-1);
    match (r2) {
    case let v: int =>
        abort();
    case io_error =>
        void;
    case parse_error =>
        abort();
    };
    
    // Test nullable pointers
    let pts: [2]point = [
        point { x = 1, y = 2 },
        point { x = 3, y = 4 },
    ];
    
    let found = find_point_by_x(pts[..], 3);
    match (found) {
    case null =>
        abort();
    case let p: *point =>
        assert(p.y == 4);
    };
    
    let not_found = find_point_by_x(pts[..], 99);
    assert(not_found is null);
    
    let sum1 = get_point_sum(&pts[0]);
    assert(sum1 == 3);
    
    let sum2 = get_point_sum(null);
    assert(sum2 == 0);
    
    // Test loop with errors
    let arr1: [4]int = [1, 2, 3, 4];
    let loop_r1 = sum_until_negative(arr1[..]);
    match (loop_r1) {
    case let v: int =>
        assert(v == 10);
    case loop_error =>
        abort();
    };
    
    let arr2: [4]int = [1, 2, -1, 4];
    let loop_r2 = sum_until_negative(arr2[..]);
    match (loop_r2) {
    case let v: int =>
        abort();
    case loop_error =>
        void;
    };
    
    // Test enum
    let red_val = color_value(color::RED);
    assert(red_val == 0xFF0000);
    
    // Test slice
    let arr3: [5]int = [1, 2, 3, 4, 5];
    let middle = slice_middle(arr3[..]);
    assert(len(middle) == 3);
    
    // Test @symbol
    let processed = process(10);
    assert(processed == 11);
    
    // Test RT
    test_rt();
    
    let msg: str = "All simplified stress tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
