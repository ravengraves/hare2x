// Test @init, @fini, and @test attributes
let counter: int = 0;

@init fn setup() void = {
    counter = 42;
};

@fini fn teardown() void = {
    counter = 0;
};

@test fn test_counter() void = {
    assert(counter == 42, "counter should be 42");
};

export fn main() void = {
    assert(counter == 42, "init should have run");
};
