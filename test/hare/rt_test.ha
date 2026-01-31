// Test rt:: module usage
use rt;

let buffer: [64]u8 = [0...];

export fn main() void = {
    // Test rt::memset
    rt::memset(&buffer, 42, 64);

    // Test rt::memcpy
    let src: [6]u8 = ['h', 'e', 'l', 'l', 'o', '\n'];
    rt::memcpy(&buffer, &src, len(src));
    assert(buffer[0] == 'h', "memcpy failed");
    let n = rt::write(1, &src: *const opaque, len(src));
};
