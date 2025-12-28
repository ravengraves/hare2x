// Example: Bitwise operations and control flow

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
    let f: flags = 0;
    set_flag(&f, FLAG_READ);
    set_flag(&f, FLAG_WRITE);
    
    let has_read: bool = has_flag(f, FLAG_READ);
    let has_exec: bool = has_flag(f, FLAG_EXEC);
    
    let m: int = max(10, 20);
    let g: int = gcd(48, 18);
};
