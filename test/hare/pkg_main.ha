// Main file for package test
use rt;

fn helper(x: int) int = x * 2;

export fn main() void = {
    let result: int = helper(21);
    assert(result == 42, "helper failed");
};
