We want to set up a new and exciting backend for Pika. This backend will be the most challenging yet. We want to implement a simple, register-machine translation target for our Pika language. We will target AT&T GAS x86_64 assembly following C call conventions for stacks with a vectorized SSE4.2 model of operations and registers.

Our goal is to pass the full pika2c/ test suite using only generated assembly code (and a couple of functions from RT that we can self-host in minimal vectorized x86_64.

FIRST TASK: Start by analyzing the tests and coming up with an order in which to execut them.

SECOND TASK:

We also want to create utility scripts (assembler.sh) that take in a file and output the assembly that we can reference when we are unsure of generation. Place these scripts in the x86_64 folder and debug them to make sure they work for future development.

e.g. `echo "int _main(){ return 0; }" > test.c`

(assemblerO0.sh)
```sh
clang -O0 $1 -S -o test.s -masm=att -ffreestanding -nostdlib -nostartfiles -nodefaultlibs -fno-builtin -fno-ident -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector -fverbose-asm -fno-PIC -static -msse4.2 -ffunction-sections -fdata-sections

cat test.s | wc -l
cat test.s
```

(assembler.sh)
```sh
clang -Os $1 -S -o test.s -masm=att -ffreestanding -nostdlib -nostartfiles -nodefaultlibs -fno-builtin -fno-ident -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector -fverbose-asm -fno-PIC -static -msse4.2 -ffunction-sections -fdata-sections

cat test.s | wc -l
cat test.s
```

(assemblerrt.sh)
```sh
clang -Os $1 lib/pika/rt.c -o test.o -ffreestanding -nostdlib -nostartfiles -nodefaultlibs -fno-builtin -fno-ident -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-stack-protector -Wl,--build-id=none,-z,noseparate-code -fno-PIC -static -fuse-ld=lld -msse4.2 -ffunction-sections -fdata-sections

objdump -D test.o | wc -l
objdump -D test.o
```

To generate test exe from asm: `clang -o program test.s rt.s -nostdlib -static -fno-pie ...`

THIRD TASK: 
Once done, create a README.md in x86_64 that documents the scripts, the testing phases, and then update AGENTS.md to reflect our current work on this new x86_64 backend.

see the following information to complete the third task:

# x86_64 AT&T ASM Generation Stage Breakdown
Notes regarding the planned implementation:
pkparse.pka -> pkgen_ir.pka -> pkgen_virtreg.pka -> pkgen_x86_64.pka

1. pkgen_ir.pka - a typed IR representation detailing individual operations
2. pkgen_virtreg.pka - packing operations efficiently into minimal virtual vector and regular registers based on type (using fixed-iteration greedy + brute-force + monte carlo packing); this will be very basic at first, just trying to minimize the number of registers used for operations.
3. pkgen_x86_64.pka - taking our virtual register allocations and actually distributing them across the available registers, handling things like register movement, 

Each of these will have a gen_ir, gen_virtreg, or gen_x86_64 utility file for utilty functions regarding allocation.

### Packing Strategy
**The key insight:** without recursion/dynamic allocation, we can do **global** register allocation across the entire program (outside of external C code interface (@symbol / rt)). Every function has a known, fixed set of locals.

### Stage 1: pkgen_ir
v0:i32/1 = Const 10
v1:i32/1 = Const 20
v2:i32/1 = Const 2
v3:i32/1 = Mul v1, v2
v4:i32/1 = Add v0, v3

```
// Stage 1 IR types (example pseudocode)
type scalar_type = enum {
    I8, I16, I32, I64,
    U8, U16, U32, U64,
    F32, F64,
    PTR,
};

type vreg = struct {
    id: u32,
    ty: scalar_type,
    width: u8,          // 1, 2, or 4
};

type cmp_cond = enum {
    EQ, NE, LT, LE, GT, GE,
};

type op_const = struct { dst: vreg, val: u64 };
type op_copy = struct { dst: vreg, src: vreg };
type op_load = struct { dst: vreg, base: vreg, offset: i32 };
type op_store = struct { base: vreg, offset: i32, src: vreg };
type op_binop = struct { dst: vreg, lhs: vreg, rhs: vreg, kind: binop_kind };
type op_unop = struct { dst: vreg, src: vreg, kind: unop_kind };
type op_cmp = struct { dst: vreg, lhs: vreg, rhs: vreg, cond: cmp_cond };
type op_label = struct { id: u32 };
type op_jump = struct { target: u32 };
type op_branch = struct { cond: vreg, if_true: u32, if_false: u32 };
type op_call = struct { dst: nullable *vreg, func: u32, args: []vreg };
type op_ret = struct { val: nullable *vreg };
type op = (op_const | op_copy | ....);

type binop_kind = enum {
    ADD, SUB, MUL, DIV, MOD,
    AND, OR, XOR, SHL, SHR,
};

type unop_kind = enum {
    NEG, NOT,
};

// A function's IR
type ir_func = struct {
    name: str,
    params: []vreg,
    result: nullable *scalar_type,
    ops: []op,
    next_vreg: u32,
};
// end stage1
```

### Stage 2: Monte Carlo Packing:
- SSE lane assignment for vectorizable operations 
- fixed iteration brute force + monte carlo packing: group compatible vregs into physical regs
- cost function based on fixed estimated time to complete each operation (based on the op) and goal to maximize number of instructions completed per 128 clock cycles.

```
RegClass :=
	| GPR64    # rax, rbx, rcx, rdx, rsi, rdi, r8-r15 (minus rsp, rbp)
	| GPR32    # eax, ebx, ... (lower 32 bits)
	| GPR16    # ax, bx, ...
	| GPR8     # al, bl, ...
	| XMM      # xmm0-xmm15 (128-bit, can hold 4×i32, 2×i64, 4×f32, 2×f64)

PhysReg := {
    class: RegClass,
    index: u8,
    lane:  Option<u8>,   # for XMM: which lane (0-3 for 32-bit, 0-1 for 64-bit)
}
```

```
// pseudocode
type reg_class = enum {
    GPR64, GPR32, GPR16, GPR8,
    XMM,
};

type phys_reg = struct {
    class: reg_class,
    index: u8,          // 0-15 for GPR, 0-15 for XMM
    lane: u8,           // 0-3 for XMM lanes, 0 for scalar
};

type allocation = struct {
    vreg_id: u32,
    phys: phys_reg,
};

type emit_ctx = struct {
    out: *io::handle,
    allocs: []allocation,
    func: *ir_func,
    label_counter: u32,
};
```

### Stage 3: AT&T Code Output Generation
- generate needed preamble
- generate register allocations
- Handle C argument interop and stackframe operations with external C code.
- Handle interfacing with RT, static memory, etc.

### -Os Style Emission Preferences
```
# Prefer shorter encodings:

# Zero a register (2 bytes vs 5-7 bytes)
xorl %eax, %eax           # not: movl $0, %eax

# Small constants via lea when beneficial
leal 1(%rax), %eax        # sometimes smaller than: addl $1, %eax

# Use push/pop for single-register save/restore
pushq %rbx                # 1 byte
popq %rbx                 # 1 byte

# Prefer 32-bit ops when possible (implicit zero-extend to 64-bit)
movl %eax, %eax           # zero-extends, smaller encoding

# Use test for comparison with zero
testl %eax, %eax          # not: cmpl $0, %eax

# Multiply by small constants via lea
leal (%rax,%rax,2), %eax  # x * 3
leal (%rax,%rax,4), %eax  # x * 5
```

And compile test programs frequently with our clang to determine good registers to use.


### SSE4.2 Instruction Selection
(expand this list as discovered with clang / as needed)
```
# Packed integer operations (4 × i32 in xmm)
paddd   %xmm1, %xmm0      # 4 × i32 add
psubd   %xmm1, %xmm0      # 4 × i32 sub
pmulld  %xmm1, %xmm0      # 4 × i32 mul (SSE4.1)
pand    %xmm1, %xmm0      # bitwise and
por     %xmm1, %xmm0      # bitwise or
pxor    %xmm1, %xmm0      # bitwise xor
pcmpeqd %xmm1, %xmm0      # 4 × i32 equality compare

# Packed i64 (2 × i64)
paddq   %xmm1, %xmm0
psubq   %xmm1, %xmm0
# (no pmullq until AVX-512, use scalar for i64 mul)

# Packed float (4 × f32)
addps   %xmm1, %xmm0
subps   %xmm1, %xmm0
mulps   %xmm1, %xmm0
divps   %xmm1, %xmm0

# Packed double (2 × f64)
addpd   %xmm1, %xmm0
subpd   %xmm1, %xmm0
mulpd   %xmm1, %xmm0
divpd   %xmm1, %xmm0

# Scalar in XMM (when we can't pack but have floats)
addss   %xmm1, %xmm0      # scalar f32
addsd   %xmm1, %xmm0      # scalar f64

# Lane manipulation
pshufd  $imm8, %xmm1, %xmm0   # shuffle i32 lanes
pinsrd  $lane, %eax, %xmm0    # insert GPR into XMM lane (SSE4.1)
pextrd  $lane, %xmm0, %eax    # extract XMM lane to GPR (SSE4.1)
```

For fast iteration, create a rebuild.pk script that uses the starting pika compiler (make pika2c) to build the updated program.
cp build/pika2c pika2c0

# rebuild:
```sh
rm pika2asm
cat cmd/*.pk | pika2c0 > pika2asm.c
clang -O0 -std=c11 -Wall -Wextra -Wpedantic -Wconversion -Wfloat-conversion -Wno-overlength-strings -Wno-unused-function -Wno-unused-variable -Wno-gnu-auto-type -Wno-gnu-statement-expression -Wno-parentheses-equality -O0 -ffast-math -march=native -mtune=native -fno-builtin lib/pika/rt.c pika2asm.c -opika2asm
```

Then use pika2asm to generate assembly code to compile and validate.

Create a minimal .s implementation of rt to link in (or generate it with clang from lib/pika/rt.c).

Try to follow C / systemv calling conventions (use our assembly scripts to build example programs if uncertain); - calling register / stack usage logic will go in pkgen_x86_64.pka, along with any required preamble x86_64 asm code not in rt.

Start with the basic programs. You can also generate c code from the tests with our assembly scripts to get started with required code start with a basic empty main linked to rt. Then follow the sequence.
