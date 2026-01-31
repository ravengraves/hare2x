// Fibonacci sequence test
use rt;
use strings;

// Iterative fibonacci
fn fib_iter(n: int) int = {
    if (n <= 1) {
        return n;
    };
    let a = 0;
    let b = 1;
    for (let i = 2; i <= n; i += 1) {
        let tmp = a + b;
        a = b;
        b = tmp;
    };
    return b;
};

// Recursive fibonacci (for small n)
fn fib_rec(n: int) int = {
    if (n <= 1) {
        return n;
    };
    return fib_rec(n - 1) + fib_rec(n - 2);
};

export fn main() void = {
    // Test known Fibonacci values
    assert(fib_iter(0) == 0);
    assert(fib_iter(1) == 1);
    assert(fib_iter(2) == 1);
    assert(fib_iter(3) == 2);
    assert(fib_iter(4) == 3);
    assert(fib_iter(5) == 5);
    assert(fib_iter(6) == 8);
    assert(fib_iter(7) == 13);
    assert(fib_iter(8) == 21);
    assert(fib_iter(9) == 34);
    assert(fib_iter(10) == 55);
    assert(fib_iter(20) == 6765);
    assert(fib_iter(30) == 832040);

    // Verify recursive matches iterative
    for (let i = 0; i <= 20; i += 1) {
        assert(fib_iter(i) == fib_rec(i));
    };

    let msg: str = "Fibonacci tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
