# Hare-to-C11 Transpiler - OMeta-style Edition

A Hare to C11 transpiler in **1466 lines** of Python (57% smaller than original 3384 lines).

## Test Results: 10/10 ✅

| Example | Status | Features Tested |
|---------|--------|-----------------|
| ✅ advanced.ha | Pass | Control flow, casts, nested expressions |
| ✅ arrays.ha | Pass | Fixed-size arrays, slices, 2D arrays, slice-of-arrays |
| ✅ basic.ha | Pass | Functions, structs, loops, arithmetic |
| ✅ custom_types.ha | Pass | Type aliases, function pointers, error types |
| ✅ errors.ha | Pass | Error types, tagged unions, match with returns |
| ✅ init_fini.ha | Pass | @init, @fini, @test attributes |
| ✅ memory.ha | Pass | Heap alloc, slices, free, alloc_copy |
| ✅ simple_error.ha | Pass | Simple error types, tagged unions |
| ✅ tagged_union.ha | Pass | Tagged unions, void variants, switch |
| ✅ variadic.ha | Pass | Variadic functions, spread operator, defaults |

## Function Attributes

### @init - Constructor
```hare
@init fn setup() void = {
    counter = 42;
};
```
→ `__attribute__((constructor)) static void setup(void) { ... }`

Runs automatically when program starts (before main).

### @fini - Destructor
```hare
@fini fn teardown() void = {
    counter = 0;
};
```
→ `__attribute__((destructor)) static void teardown(void) { ... }`

Runs automatically when program exits (after main returns).

### @test - Test Function
```hare
@test fn test_counter() void = {
    assert(counter == 42, "counter should be 42");
};
```
→ Wrapped in `#ifdef HARE_TEST ... #endif`

Only compiled when `-DHARE_TEST` is defined.

## Usage

```bash
# Normal compilation
python3 hare2c.py input.ha output.c
gcc -std=c11 -c output.c

# Compile with tests
gcc -std=c11 -DHARE_TEST -c output.c
```

## Key Pattern Transformations

| Pattern | Hare | C11 |
|---------|------|-----|
| @init | `@init fn setup() void` | `__attribute__((constructor))` |
| @fini | `@fini fn teardown() void` | `__attribute__((destructor))` |
| @test | `@test fn test_x() void` | `#ifdef HARE_TEST` |
| Tagged return | `return myerror;` | `return Union_from_myerror();` |
| Variadic call | `fn(1, 2, 3)` | `fn((slice){1,2,3})` |
| Default params | `greet()` | `greet("Hello", "World")` |
| Slice-of-array | `[][3]int` | `typedef struct { int(*data)[3]; ... }` |

## Architecture

```
Source → Tokenizer (regex) → Parser (tuples) → Generator (patterns)
                                    ↓
                              Ctx (types, vars, funcs, ret_type)
```

## Size Evolution

| Version | Lines | Compile Rate |
|---------|-------|--------------|
| Original | 3,384 | - |
| v3 (patterns+ctx) | 1,466 | 10/10 |
