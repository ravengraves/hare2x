// Test string comparisons and string switch statements
use rt;
use strings;

// Test == comparison
fn str_equal(a: str, b: str) bool = a == b;

// Test != comparison
fn str_not_equal(a: str, b: str) bool = a != b;

// Test string switch with single cases
fn get_color_code(color: str) int = {
    return switch(color) {
        case "red" => yield 1;
        case "green" => yield 2;
        case "blue" => yield 3;
        case => yield 0;
    };
};

// Test string switch with multiple values per case
fn get_category(fruit: str) str = {
    return switch(fruit) {
        case "apple", "pear", "peach" => yield "pome";
        case "orange", "lemon", "lime" => yield "citrus";
        case "grape", "blueberry" => yield "berry";
        case => yield "unknown";
    };
};

// Test string comparison in if statement
fn greet(name: str) str = {
    if (name == "world") {
        return "Hello, world!";
    };
    if (name != "") {
        return "Hello, stranger!";
    };
    return "Hello!";
};

// Test with local string variables
fn compare_locals() bool = {
    let a: str = "test";
    let b: str = "test";
    let c: str = "other";
    return a == b && a != c;
};

export fn main() void = {
    // Test equality
    let eq1: bool = str_equal("hello", "hello");
    assert(eq1 == true);

    let eq2: bool = str_equal("hello", "world");
    assert(eq2 == false);

    let eq3: bool = str_equal("", "");
    assert(eq3 == true);

    let eq4: bool = str_equal("a", "ab");
    assert(eq4 == false);

    // Test inequality
    let ne1: bool = str_not_equal("foo", "bar");
    assert(ne1 == true);

    let ne2: bool = str_not_equal("same", "same");
    assert(ne2 == false);

    // Test color switch
    let red: int = get_color_code("red");
    assert(red == 1);

    let green: int = get_color_code("green");
    assert(green == 2);

    let blue: int = get_color_code("blue");
    assert(blue == 3);

    let other: int = get_color_code("pink");
    assert(other == 0);

    let unknown: int = get_color_code("yellow");
    assert(unknown == 0);

    // Test multi-value switch
    let cat1: str = get_category("apple");
    assert(cat1 == "pome");

    let cat2: str = get_category("pear");
    assert(cat2 == "pome");

    let cat3: str = get_category("orange");
    assert(cat3 == "citrus");

    let cat4: str = get_category("lemon");
    assert(cat4 == "citrus");

    let cat5: str = get_category("grape");
    assert(cat5 == "berry");

    let cat6: str = get_category("banana");
    assert(cat6 == "unknown");

    // Test if with string comparison
    let g1: str = greet("world");
    assert(g1 == "Hello, world!");

    let g2: str = greet("alice");
    assert(g2 == "Hello, stranger!");

    let g3: str = greet("");
    assert(g3 == "Hello!");

    // Test local comparison
    let locals_ok: bool = compare_locals();
    assert(locals_ok == true);

    // Test direct comparisons
    assert("abc" == "abc");
    assert("abc" != "def");
    assert("" == "");
    assert("x" != "");

    let msg: str = "String tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
