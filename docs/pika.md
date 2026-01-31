# Pika Language Specification

Pika is a systems programming language derived from Hare, designed for **high-performance computing** and **high-reliability embedded systems**. It prioritizes determinism, analyzability, and compile-time guarantees over runtime flexibility. (And admittedly it aims to have a simpler transpiler than full Hare)

> Disclaimer, I build robots, so I made Pika to run Hare on embedded systems and supercomputers.

### Summary of Pika vs Hare:
- Features retained: Nullable pointer safety, bounds checking, str handling, tagged unions, structs/unions/enums, fixed
arrays/slices
- Types removed: rune, never, !T error types (except !void), tuples, function pointers
- Control flow removed: Recursion, defer, labeled break/continue, for-each iterations, yield in if blocks, as type
assertion, if/switch expressions
- Memory features removed: alloc, free, append, insert, delete
- Declaration features removed: Variadic functions, @init, @fini, @test
- Other removals: Anonymous struct literals, slice assignment, variable shadowing, multi-file packages
- Safety restrictions added: No shadowing, no duplicate definitions, no recursi

## Philosophy

### Design Principles

1. **Predictable Execution** - No hidden control flow, no implicit allocations, no runtime surprises. Every operation has obvious, bounded cost.

2. **Static Analyzability** - The compiler can verify memory bounds, detect unreachable code, and prove termination for all loops (no recursion).

3. **Zero Runtime Overhead** - No garbage collector, no runtime type information beyond tagged union tags. Compiles to minimal C11.

4. **Fail-Fast Development** - Strict compile-time checks catch errors early. Variable shadowing, duplicate definitions, and nullable pointer misuse are compile errors.

5. **Deterministic Memory** - Stack and static allocation only. No heap fragmentation, no allocation failures at runtime, no memory leaks.

### Target Domains

- **Embedded systems** - Microcontrollers, DSPs, real-time control systems
- **Safety-critical software** - Where formal verification and bounded execution matter
- **High-performance computing** - Numeric code that needs predictable performance
- **GPU/Accelerator targets** - Harvard architecture devices without unified address space
- **Long-lived systems** - 100-year software that must remain maintainable

### What Pika Is Not

Pika is not a general-purpose language. It deliberately sacrifices flexibility for reliability:

- Not suitable for applications requiring dynamic memory
- Not suitable for highly recursive algorithms (use iteration)
- Not suitable for plugin architectures (no function pointers)
- Not suitable for complex string processing (no built-in string type)

---

## Features Removed from Hare

### Types Removed

| Feature | Rationale |
|---------|-----------|
| `rune` | Unicode processing is application-specific. Use `u32` if needed. |
| `char` | Ambiguous (C's char varies). Use `u8` explicitly. |
| `!T` (error types) | Use tagged unions `(T \| ErrorType)` for explicit error handling. only !void is supported as a named error type. |
| `(T, U)` (tuples) | Use named structs. Anonymous types hurt readability. |
| `*fn(...) T` (function pointers) | Incompatible with Harvard architectures (GPUs, some MCUs). Use switch dispatch. |

### Control Flow Removed

| Feature | Rationale |
|---------|-----------|
| Recursion | Unbounded stack growth. All recursive algorithms have iterative equivalents. |
| `defer` | Complex codegen for unwinding. Manually manage cleanup. |
| Labeled `break`/`continue` | Complexity. Restructure nested loops instead. |
| `for (x .. items)` | Syntactic sugar. Use index-based loops: `for (let i = 0z; i < len(items); i += 1)` |
| `for (x => iter())` | Requires function pointers or closures. Use explicit iteration. |
| `yield` in if/general blocks | Only allowed in `match` expressions. Use assignment for other cases. |
| `never` | Prefer to use an explicit `abort` if you know a match expression will never reach some branch. |
| `as` (type assertion) | Risky silent failure. Use `match` for safe type dispatch. |

### Memory Features Removed

| Feature | Rationale |
|---------|-----------|
| `alloc()` | No heap allocation. Use static buffers or arena patterns. |
| `free()` | No heap deallocation. Memory is stack/static only. |
| `append()`, `insert()`, `delete()` | No growable slices. Pre-allocate fixed buffers. |
| Heap allocation | Eliminates fragmentation, allocation failures, and memory leaks. |

### Function Features Removed

| Feature | Rationale |
|---------|-----------|
| Variadic functions | Type safety issues. Use fixed parameters or arrays. |
| Variadic spread | Complexity. Pass slices explicitly. |

### Module Features Removed

| Feature | Rationale |
|---------|-----------|
| Multi-file packages | Build system handles file concatenation. |

### Attribute Features Removed

| Feature | Rationale |
|---------|-----------|
| `@init` | Implicit startup code. Call initialization explicitly. |
| `@fini` | Implicit cleanup code. Call cleanup explicitly. |
| `@test` | Use external test harness. |

### Other Removals

| Feature | Rationale |
|---------|-----------|
| Anonymous struct literals | Use named types for clarity. |
| Slice assignment `x[a..b] = y` | Use explicit loops. |

---

## Safety Restrictions

### No Variable Shadowing

Pika strictly forbids variable shadowing at any scope level:

```pika
let x = 1;
{
    let x = 2;  // ERROR: variable shadowing is not allowed in pika
};
```

This prevents subtle bugs where inner variables accidentally hide outer ones.

### No Duplicate Definitions

Function names, global variables, and type names must be unique:

```pika
let counter = 0;
fn counter() void = {};  // ERROR: duplicate function name
```

### Nullable Pointer Safety

Nullable pointers cannot be dereferenced without checking:

```pika
fn bad(p: nullable *i32) i32 = {
    return *p;  // ERROR: cannot dereference nullable pointer
};

fn good(p: nullable *i32) i32 = {
    match (p) {
    case let ptr: *i32 => return *ptr;
    case null => return 0;
    };
};
```

### Bounds Checking

Sized array and slice accesses are bounds-checked at runtime:

```pika
let arr: [_]i32 = [1, 2, 3, 4];
let x = arr[10];  // Runtime abort: slice or array access out of bounds
```

### No Recursion

Direct recursion is detected at compile time; indirect recursion should be avoided.

```pika
fn factorial(n: i64) i64 = {
    if (n <= 1) { return 1; };
    return n * factorial(n - 1);  // ERROR: recursion is not allowed
};
```

---

## What's Included

### Primitive Types

```
int uint              Platform-sized integers
i8 i16 i32 i64        Signed fixed-width integers
u8 u16 u32 u64        Unsigned fixed-width integers
f32 f64               Floating point
bool                  Boolean
size                  Size/index type
uintptr               Pointer-sized integer
void                  No value
```

### Composite Types

```
[N]T                  Fixed-size array
[_]T                  Inferred-size array (from initializer)
[]T                   Slice (view, no growth)
*[*]T                 Unbounded array pointer (C interop)
struct { ... }        Structure
union { ... }         Untagged union (memory reinterpretation)
(T | U)               Tagged union (safe variant)
enum { A, B = 1 }     Enumeration
```

### Pointer Types

```
*T                    Non-nullable pointer
nullable *T           Nullable pointer (must check before use)
```

### Declarations

```pika
fn name(x: T) R = { ... };        // Function
export fn name() void = { };       // Exported function
type Name = T;                     // Type alias
def NAME: T = value;               // Compile-time constant
let name: T = value;               // Global variable
const name: T = value;             // Global constant
static let name: T = value;        // Static local
```

### Control Flow

```pika
if (cond) { ... } else { ... };
for (init; cond; after) { ... };
for (cond) { ... };                // While loop
for (true) { ... };                // Infinite loop
switch (val) { case X => ..., case => ... };
match (val) { case let x: T => ..., case null => ... };
return expr;
break;
continue;
yield expr;                        // In match expressions only
```

### Operators

```
Arithmetic:   + - * / % (unary -)
Compound:     += -= *= /= %=
Bitwise:      & | ^ ~ << >>
Bit-assign:   &= |= ^= <<= >>=
Comparison:   == != < > <= >=
Logical:      && || ^^ !
Type:         expr: T (cast), expr is T (type test)
Pointer:      &x (address), *p (deref), p.field (auto-deref)
Array:        arr[i], arr[a..b], arr[..b], arr[a..], arr[..]
```

### Builtins

```pika
len(x)                // Array/slice length
size(T)               // Type size in bytes (planned)
assert(cond)          // Runtime assertion
assert(cond, msg)     // Assertion with message
abort()               // Terminate program
```

### Literals

```pika
42, 0xFF, 0b1010, 0o77           // Integers (decimal, hex, binary, octal)
42i32, 10u8, 0z                   // Typed integers
3.14, 1e-5                        // Floats
3.14f32                           // Typed float
true, false                       // Booleans
null                              // Null pointer
void                              // Void value (for tagged unions)
"hello\n"                         // String (becomes *[*]u8)
'a', '\n'                         // Character (becomes integer)
[1, 2, 3]                         // Array literal
[0...]                            // Array fill
[1, 2, 0...]                      // Partial fill
T { field = value }               // Struct literal
```

### Modules

```pika
use rt;              // Runtime: rt::read, rt::write, rt::exit, rt::abort (optional)
use strings;         // String utilities (optional)
```

---

## Runtime Library

The `rt` module provides minimal system interface:

```pika
rt::read(fd: i32, buf: *void, count: size) i64
rt::write(fd: i32, buf: *void, count: size) i64
rt::exit(status: i32) void
rt::abort() void
rt::memcpy(dest: *void, src: *void, n: size) *void
rt::memmove(dest: *void, src: *void, n: size) *void
rt::memset(dest: *void, val: i32, n: size) *void
```

---

## Comparison: Pika vs Hare vs C

| Aspect | Pika | Hare | C |
|--------|------|------|---|
| Memory safety | Bounds-checked, no null deref | Bounds-checked, no null deref | Manual |
| (std. lib) heap allocation | None | alloc/free | malloc/free |
| Error handling | Tagged unions | Error types (!T) | Return codes |
| Recursion | Forbidden | Allowed | Allowed |
| Variable shadowing | Forbidden | Allowed | Allowed |
| Nullable pointers | Explicit type | Explicit type | Implicit |
| Function pointers | None | Supported | Supported |
| Build system | Concatenate + transpile | hare build | make/cmake |

---

## Example Program

```pika
use rt;
use strings;

type point = struct {
    x: i32,
    y: i32,
};

fn distance_squared(a: *point, b: *point) i64 = {
    let dx: i64 = (b.x - a.x): i64;
    let dy: i64 = (b.y - a.y): i64;
    return dx * dx + dy * dy;
};

fn print_int(n: i64) void = {
    let buf: [20]u8 = [0...];
    let i = 19z;
    let val: u64 = n:u64;
    if (n < 0) {
        val = 0u64;
    };

    for (true) {
        i -= 1;
        buf[i] = '0': u8 + (val % 10): u8;
        val /= 10;
        if (val == 0) { break; };
    };

    if (n < 0) {
        i -= 1;
        buf[i] = '-';
    };

    rt::write(1, (&buf[i]): *[*]u8, 20 - i);
    rt::write(1, strings::toutf8("\n"): *[*]u8, 1);
};

export fn _main() void = {
    let p1 = point { x = 0, y = 0 };
    let p2 = point { x = 3, y = 4 };
    let dist_sq = distance_squared(&p1, &p2);
    print_int(dist_sq);  // Prints: 25
};
```

---

## Implementation Status

Pika is implemented as a transpiler (`pika2c`) that converts Pika source to C11. The transpiler is self-hosting: it can compile itself.

### Verified Features (46+ tests passing)

- All primitive types
- Fixed arrays with bounds checking
- Slices with bounds checking
- Unbounded array pointers without bounds checking
- Structs, unions, tagged unions, enums
- Non-nullable and nullable pointers with safety checks
- All control flow constructs
- All operators
- Match expressions with type inference
- Variable shadowing detection
- Duplicate definition detection
- Simple recursion detection
- Self-hosting transpiler (Pika -> GNU C11) (gen1, gen2, gen3 fixed-point)

### Intentionally left-out
Removed Types:      `rune, char, never, !T (except !void), (T,U), *fn()T`

Removed Features:   recursion, variadic, defer, for-each
              dynamic memory: alloc free append insert delete
              as (type assertion), slice assignment, yield in if blocks, yield never,
              multidimensional arrays, if expressions,
              repeated variable names in a function (shadowing)
              @init @fini @test

Pika makes deliberate tradeoffs that may seem limiting but serve critical reliability goals:

| Restriction | Benefit |
|-------------|---------|
| No dynamic memory | No heap fragmentation, no allocation failure, no leaks |
| No recursion | Bounded stack, provable termination |
| No function pointers | Harvard architecture compatible, no indirect calls |
| No shadowing | Clear variable scope, no accidental hiding |
| No defer | Explicit control flow, no hidden cleanup |
| No error propagation / ? / ! | Explicit error handling via match, simpler control flow |
| Nullable explicit | No null pointer dereference bugs |

For applications where these restrictions are acceptable, Pika provides stronger guarantees than C with similar (better?) performance and a simpler syntax than Rust.

### Compilation

```bash
# Concatenate source files and transpile
cat cmd/*.pka | ./pika2c > pika2c.c

# Compile with any C11 compiler
gcc -std=c11 -O2 pika2c.c rt.c -o program
clang -std=c11 -O2 pika2c.c rt.c -o program
```
