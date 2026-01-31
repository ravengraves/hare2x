// Test: Type definition ordering - structs with cross-references
use rt;

// Node refers to Tree (defined below)
type Node = struct {
    value: int,
    parent: nullable *Tree,
};

// Tree refers to Node (defined above) - this should work
type Tree = struct {
    root: *Node,
    count: size,
};

// More complex case: mutual references
type Parent = struct {
    name: int,
    child: nullable *Child,
};

type Child = struct {
    age: int,
    parent: nullable *Parent,
};

export fn main() void = {
    let n: Node = Node { value = 42, parent = null };
    assert(n.value == 42);

    let c: Child = Child { age = 10, parent = null };
    let p: Parent = Parent { name = 1, child = &c };
    c.parent = &p;

    assert(c.age == 10);
    assert(p.name == 1);
    assert(p.child == &c);
};
