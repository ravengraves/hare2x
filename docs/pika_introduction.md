# Introduction to the Pika Programming Language
---

## Summary
Pika is a small, safety-oriented subset of Hare designed for predictable
systems programming. In this repository, Pika is transpiled to GNU C11 by
`pika2c`, then compiled with a normal C compiler and linked with a tiny
runtime.

> Disclaimer, I build robots, so I made Pika to run Hare on embedded systems.

---

Pika is intentionally small: fewer features, fewer sharp edges, and fewer ways
to surprise yourself six months later. If you've read Hare's "100-year language"
essay, you've already know the goals: conservative design and long-term
maintainability first. (And admittedly a simpler transpiler than full Hare)

This guide is written for the `pika2c` implementation in this repository.

## Setup and Compilation

**Overview**  
Pika source code (`.pka`) is transpiled to GNU C11 by `pika2c`. You then compile
the generated C with `gcc` or `clang` (or any C11 compiler supporting GNU extensions), 
and link it with `lib/pika/rt.c` (the runtime used by the tests). Pika programs are 
written with an `export fn main()` entry point; `pika2c` emits it as a C symbol 
named `_main`, which the runtime calls.

**Description**  
The workflow is "Pika in, safe GNU C11 out." The `pika2c` binary reads
from stdin and writes C to stdout, so you can compile single files or
concatenated multi-file programs with the same pipeline. The strict warning
flags below match the project's test harness and are strongly recommended: they
help catch mistakes that are outside the scope of Pika's minimal checker.

For more examples, browse `test/pika/*.pka`. To run the full suite, use
`make check` or `bash test/test_pika2c.sh`. For reference material, see
`docs/pika.md`, `docs/pikav1.md`, `docs/hare_info.md`, and
`docs/hare_language_examples.md`.

**Example**
```pika
// hello.pka
use rt;
use strings;

export fn main() void = {
	let msg = "Hello, Pika! 🐇\n";
	rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
```

```bash
# Build the transpiler (once)
make pika2c

# Transpile Pika -> C11
./build/pika2c < hello.pka > hello.c

# Compile + link (gcc)
CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wfloat-conversion \
  -Wno-gnu-auto-type -Wno-unused-function -Wno-unused-variable \
  -Wno-gnu-statement-expression -Wno-parentheses-equality"
gcc $CFLAGS hello.c lib/pika/rt.c -o hello

# Or clang
clang $CFLAGS hello.c lib/pika/rt.c -o hello

./hello
```

## The Pika Mindset (Pika is a Hare Subset)

**Overview**  
Pika is a stricter subset of Hare. It keeps familiar syntax (functions, structs,
arrays, enums, tagged unions) but removes features that complicate reasoning
about correctness and resource usage (recursion, dynamic allocation keywords,
function pointers, and more).

**Description**  
Pika's design goal is not "max power," it's "max confidence." You can still
write low-level code, but you do so with a tighter set of tools that encourage
explicitness: fixed-size arrays, slices as views, and pattern matching instead
of implicit error propagation. When Pika says "no," it's usually because the
feature would make control flow harder to audit or memory behavior harder to
predict.

**Example**
```pika
// Iteration is the default; recursion is rejected by pika2c.
fn factorial(n: i32) i32 = {
	let result: i32 = 1;
	for (let i: i32 = 2; i <= n; i += 1) {
		result *= i;
	};
	return result;
};

export fn main() void = {
	assert(factorial(0) == 1);
	assert(factorial(5) == 120);
};
```

## Bindings: `def`, `const`, `let`, and `static let`

**Overview**  
Pika has four common "ways to name a value":

- `def NAME: T = ...;` - compile-time constant (useful for sizes and flags)
- `const name: T = ...;` - immutable binding (global or local)
- `let name: T = ...;` - mutable binding (global or local)
- `static let name: T = ...;` - function-local static storage (persists across calls)

Pika forbids variable shadowing: you can't reuse a name in an inner scope.

**Description**  
The no-shadowing rule is one of Pika's biggest readability wins. You never have
to wonder "which `count` is this?" because there is only one `count` in scope.
For state, prefer plain locals first, then `static let` for persistent
function-local state, and only then globals when the state is truly global.

**Example**
```pika
def MAX_TICKS: i32 = 4;
const START_AT: i32 = 10;
let global_ticks: i32 = 0;

fn tick() i32 = {
	static let local_ticks: i32 = 0;
	local_ticks += 1;
	global_ticks += 1;
	return START_AT + local_ticks + global_ticks;
};

export fn main() void = {
	let sum: i32 = 0;
	for (let i: i32 = 0; i < MAX_TICKS; i += 1) {
		sum += tick();
	};
	assert(global_ticks == MAX_TICKS);
	assert(sum == 60);
};
```

## Types and Literals

**Overview**  
Pika supports the usual set of systems-language types: fixed-width integers
(`i32`, `u64`), `bool`, floats (`f32`, `f64`), pointer-sized types (`size`,
`uintptr`), plus composite types like arrays, slices, structs, unions, enums,
and tagged unions. Integer literals can be suffixed (`10u8`, `0z`), and you cast
with `expr: Type`.

**Description**  
You'll spend most of your time in the "boring" part of the type system:
integers, arrays, pointers, and structs. When you need something fancier, Pika
still gives you it-just explicitly. For example, `size(T)` tells you how many
bytes a type takes, and casts are always written with `:` so they stand out in
reviews.

**Example**
```pika
type point = struct {
	x: i32,
	y: i32,
};

export fn main() void = {
	let answer: i32 = 42;
	let byte: u8 = 10u8;
	let count: size = 0z;
	let piish: f32 = 3: f32;
	let newline: u8 = '\n';
	let good = true;

	let p = point { x = answer, y = 1 };
	let name: [_]u8 = ['P', 'i', 'k', 'a'];

	assert(len(name) == 4);
	assert(size(i32) == 4);
	assert(byte == 10);
	assert(count == 0);
	assert(piish: i32 == 3);
	assert(newline == 10u8);
	assert(p.x == 42);
	assert(good == true);
};
```

## Functions

**Overview**  
Functions are declared with `fn name(params...) ReturnType = { ... };`. Use
`export fn` to expose a function to the generated C interface. The program's
entry point is `export fn main() void`, which `pika2c` maps to `_main` for the
runtime.

**Description**  
Pika functions look like Hare functions, but with fewer "magical" features:
no default parameters, no variadics, and no function pointers. The result is
that call sites are always explicit: if a function needs data, you pass it.
If you want "pick one of several behaviors," you usually model it with an enum
and a `switch`.

**Example**
```pika
type op = enum {
	ADD,
	SUB,
};

fn apply(kind: op, a: i32, b: i32) i32 = {
	switch (kind) {
	case op::ADD => return a + b;
	case op::SUB => return a - b;
	};
};

export fn main() void = {
	assert(apply(op::ADD, 10, 20) == 30);
	assert(apply(op::SUB, 10, 20) == -10);
};
```

## Control Flow (and Why `if` Isn't an Expression)

**Overview**  
Pika keeps control flow simple: `if`/`else`, `for` loops, `switch`, and `match`.
`if` is a statement (not an expression), and `yield` is only used inside `match`
expressions.

**Description**  
If you're coming from languages where `if` returns a value, the Pika approach is
to spell it out: assign in each branch or use `match` when you want a single
expression value. This keeps control flow easy to read (and easy to map to the underlying hardware instructions) at the cost of a little verbosity-usually a good tradeoff in systems
code.

**Example**
```pika
fn sum_even_under(limit: i32) i32 = {
	let total: i32 = 0;
	let i: i32 = 0;
	for (true) {
		if (i >= limit) {
			break;
		};
		if ((i & 1) != 0) {
			i += 1;
			continue;
		};
		total += i;
		i += 1;
	};
	return total;
};

export fn main() void = {
	assert(sum_even_under(6) == 0 + 2 + 4);
};
```

## Arrays and Slices (Checked by Default)

**Overview**  
Arrays (`[N]T` and `[_]T`) are fixed-size values. Slices (`[]T`) are views into
arrays (or other slices). Indexing arrays and slices is bounds-checked at
runtime: out-of-range access aborts.

**Description**  
The standard pattern is: keep data in an array, take slices of it to pass into
functions. Slices don't allocate and don't own memory; they simply point at an
existing region. You can slice an array (`arr[2..]`), slice a slice
(`view[1..4]`), and pass slices to helper functions without copying the data.

**Example**
```pika
fn sum(items: []i32) i32 = {
	let total: i32 = 0;
	for (let i = 0z; i < len(items); i += 1) {
		total += items[i];
	};
	return total;
};

export fn main() void = {
	let data: [6]i32 = [10, 20, 30, 40, 50, 60];
	let middle = data[2..5]; // [30, 40, 50]
	let tail = data[3..];    // [40, 50, 60]

	assert(len(middle) == 3);
	assert(middle[0] == 30);
	assert(sum(middle) == 120);
	assert(sum(tail) == 150);
};
```

## Pointers and Auto-Dereference

**Overview**  
Pointers are written `*T`, address-of is `&x`, dereference is `*p`. For field
access, Pika auto-dereferences pointers: if `p: *point`, then `p.x` works (it
generates `p->x` in C). This applies through multiple pointer indirections and
to pointers-to-arrays.

**Description**  
This is one of the "make the common case easy" features. You still have to opt
into pointers explicitly, but once you do, accessing fields doesn't become a
sea of `*` and parentheses. The auto-deref behavior stays predictable because
it only applies where it's unambiguous: field access and indexing.

**Example**
```pika
type point = struct {
	x: i32,
	y: i32,
};

fn manhattan(p: *point) i32 = {
	return p.x + p.y;
};

export fn main() void = {
	let pt = point { x = 3, y = 4 };
	assert(manhattan(&pt) == 7);

	let nums: [3]i32 = [10, 20, 30];
	let pnums: *[3]i32 = &nums;
	assert(pnums[1] == 20);
};
```

## Nullable Pointers and Narrowing with `match`

**Overview**  
Pointers are non-nullable by default. If a pointer may be absent, you must say
so with `nullable *T`. Nullable pointers cannot be dereferenced directly; you
must narrow them via `match`, typically by binding a non-null pointer with
`case let p: *T => ...`.

**Description**  
The rule is simple: you may only dereference `*T`, never `nullable *T`. The
idiom is to `match` once at the boundary (e.g. right after a lookup), bind the
non-null pointer in the non-null arm, and then use it freely inside that arm.
This turns "maybe null" into "definitely not null" in a way the compiler can
enforce.

**Example**
```pika
fn deref_or(p: nullable *i32, fallback: i32) i32 = {
	return match (p) {
	case let q: *i32 =>
		yield *q;
	case null =>
		yield fallback;
	};
};

export fn main() void = {
	let x: i32 = 42;
	assert(deref_or(&x, 0) == 42);
	assert(deref_or(null, 0) == 0);
};
```

## Tagged Unions and `match` on Type

**Overview**  
Tagged unions are written `(T | U | ...)`. You construct a variant with a cast
to the union type (`value: union_type`). You inspect a tagged union with
`match`, using `case Type => ...` arms. A `match` must be exhaustive unless you
include a default `case =>`.

**Description**  
Tagged unions are Pika's main tool for "either/or" values: optional results,
explicit errors, and polymorphic data. Unlike C unions, tagged unions are safe:
they carry a tag, and `match` forces you to handle every possibility.

If you want a specific numeric variant, cast the value to that type first
(e.g. `(3.5: f32): number`). If you need multiple integer-like variants in one
union (for example `i32` and `u32`), it’s a good idea to wrap one of them in a
small struct — and in this repository’s current `pika2c`, it’s also a practical
workaround, because integer-to-union construction currently prefers the first
integer-like variant.

**Example**
```pika
type err = !void;

type u32_box = struct {
	v: u32,
};

type number = (i32 | f32 | u32_box | err);

fn to_i32(n: number) i32 = {
	match (n) {
	case i32 => return n: i32;
	case f32 => return (n: f32): i32;
	case u32_box => return (n: u32_box).v: i32;
	case err => return -1;
	};
};

export fn main() void = {
	let a: number = 42: number;
	let b: number = (3.5: f32): number;
	let c = u32_box { v = 7u32 }: number;
	let d = err;

	assert(to_i32(a) == 42);
	assert(to_i32(b) == 3);
	assert(to_i32(c) == 7);
	assert(to_i32(d) == -1);
};
```

## Enums and `switch`

**Overview**  
Enums are declared with `enum { ... }` (optionally with an underlying integer
type, e.g. `enum u8 { ... }`). Use `switch` to branch on enum values. Like
`match`, `switch` is designed to be exhaustive: either cover every case or add
`case =>` as a default.

**Description**  
Enums are a great fit for "small set of states." They pair naturally with
`switch` and make code review easy: you can see all possible states and how
they're handled in one place. When you want "pick behavior at runtime" (but
without function pointers), an enum + switch is the go-to pattern.

**Example**
```pika
type mood = enum {
	SUN,
	RAIN,
};

fn mood_score(m: mood) i32 = {
	switch (m) {
	case mood::SUN => return 10;
	case mood::RAIN => return 2;
	};
};

export fn main() void = {
	assert(mood_score(mood::SUN) == 10);
	assert(mood_score(mood::RAIN) == 2);
};
```

## Strings (`str`) and the `strings` Module

**Overview**  
In Pika, `str` is a first-class string type with a known byte
length. String literals support escapes (`"\n"`, `"\x41"`, `"\u00E9"`,
`"\U0001F600"`), raw strings using backticks, multi-line strings, concatenation
by adjacency (`"a" "b"`), and equality (`==`, `!=`). Strings don't expose a
`.data` field; to work with bytes, use `strings::toutf8` and
`strings::fromutf8_unsafe`.

**Description**  
Treat `str` as "bytes + length," but don't reach inside it directly. If you want
to index bytes (or pass a string to `rt::write`), convert to `[]u8` with
`strings::toutf8`. The conversion is a view (no allocation, no copy), so the
bytes remain valid as long as the original string does.

**Example**
```pika
use strings;

fn first_byte(s: str) u8 = {
	let bytes: []u8 = strings::toutf8(s);
	return bytes[0];
};

export fn main() void = {
	let a = "Hello, " "world!";
	let b= `Hello, world!`;

	assert(a == b);
	assert(len(a) == 13);
	assert(first_byte(a) == 'H');
};
```

## Input and Output with `rt::read` / `rt::write`

**Overview**  
The `rt` module provides minimal system calls. The two you'll reach for most
often are:

- `rt::read(fd: i32, buf: *opaque, count: size) i64`
- `rt::write(fd: i32, buf: *opaque, count: size) i64`

These mirror Unix `read(2)`/`write(2)`: return a byte count, `0` for EOF (read),
or a negative value on error. On non-Linux platforms in this repo, they may be
stubbed to return `-1`.

**Description**  
Pika doesn't hide I/O behind a big standard library: you pass explicit buffers
and lengths. This makes it easy to audit memory usage: you can see exactly where
bytes go and how many are allowed. The common pattern is "fixed stack buffer,
read, check, then process only the bytes you actually got."

**Example**
```pika
use rt;

fn echo_once() void = {
	let buf: [64]u8 = [0...];
	let n = rt::read(0, &buf[0]: *opaque, len(buf));
	if (n < 0) {
		abort();
	};
	if (n == 0) {
		return;
	};
	let count: size = n: size;
	rt::write(1, &buf[0]: *opaque, count);
};

export fn main() void = {
	echo_once();
};
```

## Safety Guarantees and Safety Limits

**Overview**  
Pika tries to make "the safe thing" the default:

- Bounds checks for array/slice indexing
- Compile-time rejection of recursion and function pointers
- Compile-time enforcement of nullable-pointer checks via `match`
- Exhaustive `match` and `switch` (unless you add a default case)
- No variable shadowing (fewer scope surprises)

Pika also has escape hatches you should treat as "unsafe by review," such as
untagged `union` and unbounded pointers `*[*]T`.

**Description**  
Safety in Pika isn't about making bugs impossible; it's about making bugs loud.
An out-of-bounds access aborts instead of silently corrupting memory, and a
nullable pointer forces you to write the null case down explicitly. When you do
need to dip into lower-level interop (like `*[*]u8`), do it at the edges of your
program and keep the unsafe surface area small.

**Example**
```pika
use strings;

// Unbounded pointers are useful for C-style interop, but they are not
// bounds-checked. Slicing them gives you a checked []u8 view, but the caller
// must still ensure start/end are valid for the underlying buffer.
fn prefix(raw: *[*]u8, start: size, end: size) str = {
	let view: []u8 = raw[start..end];
	return strings::fromutf8_unsafe(view);
};

export fn main() void = {
	let buf: [5]u8 = ['P', 'I', 'K', 'A', '!'];
	let raw: *[*]u8 = &buf: *[*]u8;
	assert(prefix(raw, 0, 4) == "PIKA");
};
```
