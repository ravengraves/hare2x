# Pika x86_64 Backend Bring-Up

Goal: emit AT&T GAS x86_64 (System V, SSE4.2) directly from Pika and pass the full `test/test_pika2c.sh` suite using only generated assembly plus a tiny self-hosted runtime shim.

## Utility scripts
All scripts live in this directory and assume you run them from anywhere in the repo.

- `assemblerO0.sh <c-file> [out.s]` – emit readable `-O0` assembly; prints line count then the file.
- `assembler.sh <c-file> [out.s]` – emit optimized `-Os` assembly with the same flags as above.
- `assemblerrt.sh <c-file> [out.o]` – build a freestanding object against `lib/pika/rt.c`, then dump it with `objdump -D` (line count + disassembly). Uses `lld` and SSE4.2.

Outputs default to `x86_64/test.s` or `x86_64/test.o`; override with the optional second argument. Example:

```sh
echo "int _main(){ return 0; }" > /tmp/pika_smoke.c
./x86_64/assemblerO0.sh /tmp/pika_smoke.c
./x86_64/assembler.sh /tmp/pika_smoke.c /tmp/pika_smoke.s
./x86_64/assemblerrt.sh /tmp/pika_smoke.c /tmp/pika_smoke.o
```

## Bring-up test order (recommended)
Work from smallest surface area to full self-hosting. Use `test/test_pika2c.sh` as the reference for expectations; mirror the order below when driving the new asm backend.

1. **Lexing & arithmetic core**: `basic`, `literals`, `expressions`, `numeric_underscores`, `ops_stress`, `void_type`.
2. **Control flow & matches**: `control`, `break_in_match`, `match_with_default`, `types`, `defaults`.
3. **Type inference & builtins**: `infer`, `features` (size(T), inferred arrays), `builtins`.
4. **Data structures**: `arrays`, `array_fill`, `slices`, `unbounded_slice`, `strings`, `string_features`, `string_escapes`, `str_firstclass`.
5. **Aggregates & tags**: `struct`, `tagged`, `void_alias_tagged`, `arena`, `globals`, `static`, `extra`.
6. **Pointers & nullables**: `nullable`, `autoderef`, `pointer_safety_comprehensive`, `interop` (@symbol), `runtime` (memcpy/memset), plus a quick re-run of `array_fill` for mutation-by-reference.
7. **Negative compile-time suite**: everything under `test/pika/fail` except `runtime_*` files (coverage of nullables, exhaustiveness, invalid casts, recursion, etc.).
8. **Runtime failure suite**: `runtime_abort`, `runtime_bounds*`, `runtime_unbounded_escape`, `pikabad_runtime`.
9. **Self-hosting ladder**: `gen1`→`gen2`→`gen3` plus fixed-point diffs from `test/test_pika2c.sh`.

Tackle each band only after the previous one passes to localize backend regressions.

## Phase checklist (current)
Phase 1 focuses on core expressions, control flow, and basic runtime calls. Phase 2 extends to structured data and defaults. Enums are temporarily skipped (treat as `int` later).

Phase 1 tasks:
- Emit scalar literals (int/char/bool/float) + arithmetic/compare ops.
- Support `let`, assignment, `if`, `for`, `break`, `continue`, `return`, `assert`, `abort`.
- Support pointers (`&`, `*`) and simple indexing/field access.
- Validate with: `basic`, `literals`, `expressions`, `numeric_underscores`, `ops_stress`, `void_type`, `control`, `break_in_match`, `match_with_default`, `defaults`.
- Local smoke tests: `test/x86_64/001_main_arith.pka`, `test/x86_64/002_runtime_assert_fail.pka`, `test/x86_64/003_control_flow.pka`, `test/x86_64/004_float_ops.pka`, `test/x86_64/005_vector_smoke.pka`.

Phase 2 tasks:
- Struct layout, field access, and struct literals.
- Tagged unions (wrap/unwrap) for `match` paths that don't require enum tags.
- Call ABI correctness for mixed int/float arguments.
- Arrays + loops (fixed-size array literals, indexing, and stores).
- Validate with: `test/x86_64/200_structs_basic.pka`, `test/x86_64/210_arrays_loop.pka`, plus Phase 1 tests.

Phase 4: Tagged unions + nullable + globals/static
- Full tagged union lowering + `match` on tagged unions (`tagged`, `void_alias_tagged`).
- Nullable pointers: null checks, match narrowing, and codegen paths (`nullable`, `autoderef`, `pointer_safety_comprehensive`).
- Globals/statics: layout, init order, and addressability (`globals`, `static`).
- Arena/global structs and richer aggregates (`arena`, `struct`, `extra`).

Phase 4 status:
- Added `test/x86_64/4xx_*.pka` coverage for tagged/nullable/globals/arena/structs and all pass.
- Main-suite tests for `tagged`, `void_alias_tagged`, `nullable`, `autoderef`, `pointer_safety_comprehensive`, `globals`, `static`, `arena`, `struct`, `extra` pass on the x86_64 backend.
Remaining Phase 4 tasks: none known; move to Phase 5 fail/runtime tests.

Phase 5: Exhaustiveness + fail tests + runtime fail tests
- Ensure backend emits correct abort paths and preserves compile-time diagnostics (`test/pika/fail/*`).
- Runtime abort/bounds tests with correct error payloads (`runtime_abort`, `runtime_bounds*`, `runtime_unbounded_escape`).

Phase 6: Self-hosting ladder
- Stabilize codegen for gen1/gen2/gen3 output parity and fixed-point tests.
  (`test/test_pika2c.sh` self-hosting section).

# x86_64 AT&T ASM Generation Stage Breakdown
Notes regarding the planned implementation:
pkparse.pka -> pkgen_ir.pka -> pkgen_virtreg.pka -> pkgen_x86_64.pka

1. pkgen_ir.pka - a typed IR representation detailing individual operations
2. pkgen_virtreg.pka - packing operations efficiently into minimal virtual vector and regular registers based on type (using fixed-iteration greedy + brute-force + monte carlo packing); this will be very basic at first, just trying to minimize the number of registers used for operations.
3. pkgen_x86_64.pka - taking our virtual register allocations and actually distributing them across the available registers, handling things like register movement, 


updated pipeline:

Integrated a DFG‑window linear‑scan allocator (with param live‑ins) into virtreg_pack, fixed x86_64
call arg shuffles, and updated x86_64/README.md for the test/x86_64 move. This resolves the
600_defaults_casts failure and keeps the x86_64 matmul tests green with vector ops emitted.

Manual test loop (Phase 1/2):
```sh
# Phase 1/2 success tests
for f in test/pika/basic.pka test/pika/literals.pka test/pika/expressions.pka \
         test/pika/numeric_underscores.pka test/pika/ops_stress.pka test/pika/void_type.pka \
         test/pika/control.pka test/pika/break_in_match.pka test/pika/match_with_default.pka \
         test/pika/defaults.pka test/x86_64/003_control_flow.pka test/x86_64/004_float_ops.pka \
         test/x86_64/005_vector_smoke.pka test/x86_64/006_vector_reuse.pka test/x86_64/007_vector_reuse_chain.pka \
         test/x86_64/008_vector_pack_final.pka \
         test/x86_64/220_if_else_basic.pka test/x86_64/230_for_sum.pka \
         test/x86_64/240_for_break_continue.pka test/x86_64/250_else_if_chain.pka \
         test/x86_64/260_while_style.pka test/x86_64/270_nested_loops.pka \
         test/x86_64/200_structs_basic.pka \
         test/x86_64/210_arrays_loop.pka test/x86_64/280_nested_loops_arrays.pka; do
  { printf '%s\n' '-T x86_64'; cat "$f"; } | ./pika2c > /tmp/pika_test.s
  clang -nostdlib -static -fno-pie /tmp/pika_test.s rt.s -o /tmp/pika_test.bin
  /tmp/pika_test.bin
done

# Runtime assert fail (should abort)
{ printf '%s\n' '-T x86_64'; cat test/x86_64/002_runtime_assert_fail.pka; } | ./pika2c > /tmp/pika_fail.s
clang -nostdlib -static -fno-pie /tmp/pika_fail.s rt.s -o /tmp/pika_fail.bin
! /tmp/pika_fail.bin

# Runtime bounds fail (should abort)
{ printf '%s\n' '-T x86_64'; cat test/x86_64/211_array_bounds_fail.pka; } | ./pika2c > /tmp/pika_bounds.s
clang -nostdlib -static -fno-pie /tmp/pika_bounds.s rt.s -o /tmp/pika_bounds.bin
! /tmp/pika_bounds.bin
```

## Build helpers for assembly backend
- Keep the stage breakdown handy: `pkgen_ir` → `pkgen_virtreg` → `pkgen_x86_64` (global allocation; SSE packing where possible).
- For rapid iteration, regenerate the assembler driver via the `rebuild` flow in the task notes (copy `build/pika2c` to `pika2c0`, run `cat cmd/*.pk | pika2c0 > pika2asm.c`, then compile with clang + `lib/pika/rt.c`).
- Link asm outputs with a minimal `rt.s` or the object from `assemblerrt.sh` using standard System V calling conventions.

## Register inventory (phase 2 planning)
Use counts and classes for allocation planning; actual instruction assignment happens in phase 3.

- GPR total: 16 (reserve `%rsp`, `%rbp`; 14 allocatable).
- GPR caller-saved: 9 (`%rax`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%r8`, `%r9`, `%r10`, `%r11`).
- GPR callee-saved: 5 (`%rbx`, `%r12`–`%r15`).
- XMM total: 16 (all caller-saved).
- Arg regs: int `%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`; float `%xmm0`–`%xmm7`.

## Scheduler debug (phase 2)
The virtual register scheduler tracks per-window scores. To emit scores as asm comments, set `X86_SCHED_DEBUG = 1` in `cmd/pika2c/pkgen_x86_64.pka` and rebuild. Comments look like:
```
# sched f=0 win=0 line=0 score=123
```

## Fast dev workflow (asm backend)
Use the static `pika2c0` to rebuild the current Pika compiler without involving `hare2c.py`, then exercise the new x86_64 target.

```sh
# one-time: build pika2c0 from an existing compiler
cp build/pika2c pika2c0

# rebuild current pika2c (fast path)
./rebuild.sh
# or: make rebuild

# generate x86_64 asm from Pika
echo "-T x86_64\nexport fn main() void = { return; };" | ./pika2c > /tmp/pika.s
clang -nostdlib -static /tmp/pika.s lib/pika/rt.c -o /tmp/pika
```

## Enum note (temporary)
Enums are not supported in the x86_64 backend yet. For Phase 1/2 testing, use `test/x86_64/200_structs_basic.pka`, which removes enum usage while still covering structs and pointers. The eventual model is to lower enums to integer constants.

## x86_64 test ladder (working set)
Phase 1:
- `test/x86_64/001_main_arith.pka` — minimal arithmetic + assert.
- `test/x86_64/002_runtime_assert_fail.pka` — assert abort sanity.
- `test/x86_64/003_control_flow.pka` — if/for/switch/break/continue.
- `test/x86_64/004_float_ops.pka` — scalar float ops (XMM smoke test).
- `test/x86_64/005_vector_smoke.pka` — vectorizable scalar chains (autovectorization smoke).
- `test/x86_64/006_vector_reuse.pka` — chained vector ops that should reuse packs.
- `test/x86_64/007_vector_reuse_chain.pka` — longer float/int chains to stress pack reuse.
- `test/x86_64/008_vector_pack_final.pka` — final pack/unpack reuse coverage.
- `test/x86_64/220_if_else_basic.pka` — basic if/else control flow (IR branch).
- `test/x86_64/230_for_sum.pka` — simple for-loop sum (IR loop).
- `test/x86_64/240_for_break_continue.pka` — for loop with break/continue (IR loop control).
- `test/x86_64/250_else_if_chain.pka` — else-if chain (nested IR if).
- `test/x86_64/260_while_style.pka` — while-style loop form (IR loop control).
- `test/x86_64/270_nested_loops.pka` — nested loops with accumulation.
Phase 2:
- `test/x86_64/200_structs_basic.pka` — struct literal, field loads, pointer update.
- `test/x86_64/210_arrays_loop.pka` — fixed-size arrays + looped indexing/stores.
- `test/x86_64/211_array_bounds_fail.pka` — bounds check abort.
- `test/x86_64/280_nested_loops_arrays.pka` — nested loops + array indexing with break/continue.
Phase 3:
- `test/x86_64/300_array_fill_basic.pka` — variadic array fill semantics (`[x...]`, `[a,b,c...]`).
- `test/x86_64/310_runtime_calls.pka` — runtime interop (`rt::memcpy`, `rt::memset`).
- `test/x86_64/311_symbol_interop.pka` — `@symbol` interop call path.
- `test/x86_64/312_rt_write_output.pka` — `rt::write` output path sanity.
- `test/x86_64/320_slices_basic.pka` — slice creation, len, indexing, and unbounded slice.
- `test/x86_64/330_strings_basic.pka` — str literals, len, equality, and strings:: interop.
- `test/x86_64/340_match_nullable_expr.pka` — nested match expressions with nullable pointers.
- `test/x86_64/331_string_escapes.pka` — string/char escape coverage.

## Current limitations
- Struct return-by-value and nested struct copies are not implemented yet; keep struct literals in `let` initializers for now.
- Arrays are limited to fixed-size locals with array literals and indexing (bounds checks are emitted for fixed-size array accesses; no slices/len yet in x86_64).
- Strings/slices/nullable/tagged unions require Phase 3+ work before full suite coverage.
