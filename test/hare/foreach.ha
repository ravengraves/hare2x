// Test for-each loop variants over arrays, slices, and iterators.

use rt;
use strings;

const greetings = [
    "Hello, world!",
    "Hola Mundo!",
    "Bonjour le monde!",
];

const items = [
    "apple",
    "banana",
    "carrot",
];
let items_counter = 0z;

fn next() (str | done) = {
    if (items_counter < len(items)) {
        let idx = items_counter;
        items_counter += 1z;
        return items[idx];
    };
    return done;
};

export fn main() void = {
    // For-each by value over string array
    let greet_count = 0z;
    for (let greeting .. greetings) {
        let bytes = strings::toutf8(greeting);
        rt::write(1, bytes: *[*]u8, len(bytes));
        greet_count += 1z;
    };
    assert(greet_count == len(greetings));

    // For-each by reference over array
    let values: [3]int = [10, 20, 30];
    for (let ptr &.. values) {
        *ptr = *ptr + 1;
    };
    assert(values[0] == 11);
    assert(values[1] == 21);
    assert(values[2] == 31);

    // For-each iterator
    let iter_count = 0z;
    for (let item => next()) {
        assert(len(item) > 0z);
        iter_count += 1z;
    };
    assert(iter_count == len(items));
};
