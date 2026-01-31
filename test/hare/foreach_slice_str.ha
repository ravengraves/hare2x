use rt;
use strings;

export fn main() void = {
    const greetings: []str = [
        "Hello, world!",
        "¡Hola Mundo!",
        "Γειά σου Κόσμε!",
        "Привіт, світе!",
        "こんにちは世界！",
    ];

    for (let greeting .. greetings) {
        print(greeting);
    };
};

fn print(msg: str) void = {
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
