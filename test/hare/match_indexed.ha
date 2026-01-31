// Test: Match on complex expressions (function return values)
use rt;

type maybe_int = (int | void);

fn get_maybe(idx: int) maybe_int = {
    if (idx == 0) {
        return 42;
    } else if (idx == 1) {
        return void;
    };
    return 100;
};

export fn main() void = {
    // Match on function call - a complex expression
    let x: int = match (get_maybe(0)) {
    case let v: int =>
        yield v;
    case void =>
        yield 0;
    };
    assert(x == 42);

    let y: int = match (get_maybe(1)) {
    case let v: int =>
        yield v;
    case void =>
        yield -1;
    };
    assert(y == -1);

    let z: int = match (get_maybe(2)) {
    case let v: int =>
        yield v;
    case void =>
        yield 0;
    };
    assert(z == 100);
};
