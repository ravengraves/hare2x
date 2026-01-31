// Example: Bitwise operations and control flow
use rt;
use strings;

type flags = u32;

def FLAG_READ: flags = 1;
def FLAG_WRITE: flags = 2;
def FLAG_EXEC: flags = 4;

fn has_flag(value: flags, flag: flags) bool = {
    return (value & flag) != 0;
};

fn set_flag(value: *flags, flag: flags) void = {
    *value = *value | flag;
};

fn clear_flag(value: *flags, flag: flags) void = {
    *value = *value & ~flag;
};

// Conditional expressions
fn max(a: int, b: int) int = if (a > b) a else b;

fn min(a: int, b: int) int = if (a < b) a else b;

fn clamp(value: int, low: int, high: int) int = {
    if (value < low) {
        return low;
    };
    if (value > high) {
        return high;
    };
    return value;
};

// Logical operations
fn is_valid(x: int, y: int) bool = {
    return x >= 0 && y >= 0 && x < 100 && y < 100;
};

fn is_either(a: bool, b: bool) bool = {
    return a || b;
};

// XOR operation (Hare's ^^)
fn xor_bool(a: bool, b: bool) bool = {
    return a ^^ b;
};

// Shift operations
fn shift_left(x: u32, n: u32) u32 = {
    return x << n;
};

fn shift_right(x: u32, n: u32) u32 = {
    return x >> n;
};

// Type casts
fn int_to_u8(x: int) u8 = {
    return x: u8;
};

fn u8_to_int(x: u8) int = {
    return x: int;
};

// Nested control flow
fn gcd(a: int, b: int) int = {
    for (b != 0) {
        let t: int = b;
        b = a % b;
        a = t;
    };
    return a;
};

// More complex expression
fn abs(x: int) int = {
    return if (x < 0) -x else x;
};

export fn main() void = {
    // Test flag operations
    let f: flags = 0;
    set_flag(&f, FLAG_READ);
    assert(has_flag(f, FLAG_READ));
    assert(!has_flag(f, FLAG_WRITE));
    assert(!has_flag(f, FLAG_EXEC));

    set_flag(&f, FLAG_WRITE);
    assert(has_flag(f, FLAG_READ));
    assert(has_flag(f, FLAG_WRITE));
    assert(f == (FLAG_READ | FLAG_WRITE));

    clear_flag(&f, FLAG_READ);
    assert(!has_flag(f, FLAG_READ));
    assert(has_flag(f, FLAG_WRITE));

    // Test max/min
    let m: int = max(10, 20);
    assert(m == 20);
    assert(max(-5, -10) == -5);
    assert(min(10, 20) == 10);
    assert(min(-5, -10) == -10);

    // Test clamp
    assert(clamp(5, 0, 10) == 5);
    assert(clamp(-5, 0, 10) == 0);
    assert(clamp(15, 0, 10) == 10);

    // Test logical ops
    assert(is_valid(50, 50) == true);
    assert(is_valid(-1, 50) == false);
    assert(is_valid(50, 100) == false);

    assert(is_either(true, false) == true);
    assert(is_either(false, true) == true);
    assert(is_either(false, false) == false);

    // Test XOR
    assert(xor_bool(true, false) == true);
    assert(xor_bool(false, true) == true);
    assert(xor_bool(true, true) == false);
    assert(xor_bool(false, false) == false);

    // Test shifts
    assert(shift_left(1, 3) == 8);
    assert(shift_left(5, 2) == 20);
    assert(shift_right(16, 2) == 4);
    assert(shift_right(100, 3) == 12);

    // Test casts
    assert(int_to_u8(255) == 255);
    assert(u8_to_int(200) == 200);

    // Test GCD
    let g: int = gcd(48, 18);
    assert(g == 6);
    assert(gcd(17, 13) == 1);
    assert(gcd(100, 25) == 25);

    // Test abs
    assert(abs(5) == 5);
    assert(abs(-5) == 5);
    assert(abs(0) == 0);

    let msg: str = "Advanced tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
