# SYCL Builtins Reference (Pika SYCL Target)

This reference lists the SYCL 2020 built-in types and functions supported
by the Pika SYCL backend. Use the `sycl::` namespace for built-in functions.

The Pika SYCL backend generates kernel code that can be integrated into
SYCL C++ host programs.

---

## Kernel Entry Point Convention

Functions annotated with `@kernel` are compiled as SYCL kernel entry points.
The first parameter must be an index type which determines the launch style.
```pika
// 1D kernel - one work-item per index
@kernel fn vector_add(idx: sycl::id1, a: global_f32, b: global_f32, c: global_f32) void = {
    c[idx] = a[idx] + b[idx];
};
// Generates: q.parallel_for(range<1>{N}, [=](id<1> idx) { ... });

// 2D kernel with work-group structure
@kernel fn matmul(item: sycl::nd_item2, ...) void = { ... };
// Generates: q.parallel_for(nd_range<2>{global, local}, [=](nd_item<2> item) { ... });
```

### Index Type → Launch Style Mapping

| First Parameter Type | SYCL Launch |
|---------------------|-------------|
| `sycl::id1` | `parallel_for(range<1>{N}, [=](id<1>){...})` |
| `sycl::id2` | `parallel_for(range<2>{M,N}, [=](id<2>){...})` |
| `sycl::id3` | `parallel_for(range<3>{...}, [=](id<3>){...})` |
| `sycl::item1` | `parallel_for(range<1>{N}, [=](item<1>){...})` |
| `sycl::item2` | `parallel_for(range<2>{...}, [=](item<2>){...})` |
| `sycl::nd_item1` | `parallel_for(nd_range<1>{...}, [=](nd_item<1>){...})` |
| `sycl::nd_item2` | `parallel_for(nd_range<2>{...}, [=](nd_item<2>){...})` |
| `sycl::nd_item3` | `parallel_for(nd_range<3>{...}, [=](nd_item<3>){...})` |

---

## Scalar Types

| Pika Type | SYCL Type | Notes |
|-----------|-----------|-------|
| `f32` | `float` | IEEE 754 single precision |
| `f64` | `double` | IEEE 754 double precision (check device support) |
| `i8` | `int8_t` | |
| `i16` | `int16_t` | |
| `i32` | `int32_t` | |
| `i64` | `int64_t` | |
| `u8` | `uint8_t` | |
| `u16` | `uint16_t` | |
| `u32` | `uint32_t` | |
| `u64` | `uint64_t` | |
| `bool` | `bool` | |
| `size` | `size_t` | Platform-dependent |

---

## Half-Precision Float (f16)

Half precision is provided as a struct with explicit operations.
The backend maps these to `sycl::half` operations.
```pika
// f16 is a struct wrapping a 16-bit value
type f16 = struct {
    bits: u16,
};

// Construction / Conversion
fn sycl::f16_from_f32(x: f32) f16;
fn sycl::f16_to_f32(x: f16) f32;
fn sycl::f16_from_bits(bits: u16) f16;
fn sycl::f16_to_bits(x: f16) u16;

// Arithmetic
fn sycl::f16_add(a: f16, b: f16) f16;
fn sycl::f16_sub(a: f16, b: f16) f16;
fn sycl::f16_mul(a: f16, b: f16) f16;
fn sycl::f16_div(a: f16, b: f16) f16;
fn sycl::f16_neg(a: f16) f16;

// Comparisons
fn sycl::f16_eq(a: f16, b: f16) bool;
fn sycl::f16_ne(a: f16, b: f16) bool;
fn sycl::f16_lt(a: f16, b: f16) bool;
fn sycl::f16_le(a: f16, b: f16) bool;
fn sycl::f16_gt(a: f16, b: f16) bool;
fn sycl::f16_ge(a: f16, b: f16) bool;

// Math functions
fn sycl::f16_abs(x: f16) f16;
fn sycl::f16_sqrt(x: f16) f16;
fn sycl::f16_rsqrt(x: f16) f16;
fn sycl::f16_fma(a: f16, b: f16, c: f16) f16;
fn sycl::f16_min(a: f16, b: f16) f16;
fn sycl::f16_max(a: f16, b: f16) f16;
fn sycl::f16_floor(x: f16) f16;
fn sycl::f16_ceil(x: f16) f16;
fn sycl::f16_exp(x: f16) f16;
fn sycl::f16_exp2(x: f16) f16;
fn sycl::f16_log(x: f16) f16;
fn sycl::f16_log2(x: f16) f16;
fn sycl::f16_sin(x: f16) f16;
fn sycl::f16_cos(x: f16) f16;
fn sycl::f16_tanh(x: f16) f16;   // Common in ML
```

Generated SYCL (example):
```cpp
// sycl::f16_add(a, b) generates:
sycl::half(a.bits) + sycl::half(b.bits)
```

---

## Vector Types (Structs)

Vector types are structs with named components. The backend maps
operations to SYCL vec<T,N> for hardware acceleration.

### Float Vectors
```pika
type vec2 = struct { x: f32, y: f32 };
type vec3 = struct { x: f32, y: f32, z: f32 };
type vec4 = struct { x: f32, y: f32, z: f32, w: f32 };

// Extended sizes for SIMD
type vec8 = struct { s0: f32, s1: f32, s2: f32, s3: f32,
                     s4: f32, s5: f32, s6: f32, s7: f32 };
type vec16 = struct { s0: f32, s1: f32, s2: f32, s3: f32,
                      s4: f32, s5: f32, s6: f32, s7: f32,
                      s8: f32, s9: f32, sa: f32, sb: f32,
                      sc: f32, sd: f32, se: f32, sf: f32 };
```

### Double Vectors
```pika
type dvec2 = struct { x: f64, y: f64 };
type dvec3 = struct { x: f64, y: f64, z: f64 };
type dvec4 = struct { x: f64, y: f64, z: f64, w: f64 };
```

### Integer Vectors
```pika
type ivec2 = struct { x: i32, y: i32 };
type ivec3 = struct { x: i32, y: i32, z: i32 };
type ivec4 = struct { x: i32, y: i32, z: i32, w: i32 };

type uvec2 = struct { x: u32, y: u32 };
type uvec3 = struct { x: u32, y: u32, z: u32 };
type uvec4 = struct { x: u32, y: u32, z: u32, w: u32 };

type lvec2 = struct { x: i64, y: i64 };
type ulvec2 = struct { x: u64, y: u64 };
```

### Half Vectors (using f16 struct)
```pika
type hvec2 = struct { x: f16, y: f16 };
type hvec4 = struct { x: f16, y: f16, z: f16, w: f16 };
type hvec8 = struct { s0: f16, s1: f16, s2: f16, s3: f16,
                      s4: f16, s5: f16, s6: f16, s7: f16 };
```

### Vector Construction
```pika
fn sycl::vec2(x: f32, y: f32) vec2;
fn sycl::vec3(x: f32, y: f32, z: f32) vec3;
fn sycl::vec4(x: f32, y: f32, z: f32, w: f32) vec4;
fn sycl::vec4_v2v2(xy: vec2, zw: vec2) vec4;
fn sycl::vec4_v3f(xyz: vec3, w: f32) vec4;
fn sycl::vec3_v2f(xy: vec2, z: f32) vec3;

// Splat (all components same value)
fn sycl::vec2_splat(v: f32) vec2;
fn sycl::vec3_splat(v: f32) vec3;
fn sycl::vec4_splat(v: f32) vec4;

// Integer variants
fn sycl::ivec2(x: i32, y: i32) ivec2;
fn sycl::ivec3(x: i32, y: i32, z: i32) ivec3;
fn sycl::ivec4(x: i32, y: i32, z: i32, w: i32) ivec4;
fn sycl::uvec2(x: u32, y: u32) uvec2;
fn sycl::uvec3(x: u32, y: u32, z: u32) uvec3;
fn sycl::uvec4(x: u32, y: u32, z: u32, w: u32) uvec4;
```

### Vector Arithmetic
```pika
// Component-wise operations
fn sycl::vec2_add(a: vec2, b: vec2) vec2;
fn sycl::vec2_sub(a: vec2, b: vec2) vec2;
fn sycl::vec2_mul(a: vec2, b: vec2) vec2;
fn sycl::vec2_div(a: vec2, b: vec2) vec2;
fn sycl::vec2_neg(a: vec2) vec2;

fn sycl::vec3_add(a: vec3, b: vec3) vec3;
fn sycl::vec3_sub(a: vec3, b: vec3) vec3;
fn sycl::vec3_mul(a: vec3, b: vec3) vec3;
fn sycl::vec3_div(a: vec3, b: vec3) vec3;
fn sycl::vec3_neg(a: vec3) vec3;

fn sycl::vec4_add(a: vec4, b: vec4) vec4;
fn sycl::vec4_sub(a: vec4, b: vec4) vec4;
fn sycl::vec4_mul(a: vec4, b: vec4) vec4;
fn sycl::vec4_div(a: vec4, b: vec4) vec4;
fn sycl::vec4_neg(a: vec4) vec4;

// Scalar operations
fn sycl::vec2_scale(v: vec2, s: f32) vec2;
fn sycl::vec3_scale(v: vec3, s: f32) vec3;
fn sycl::vec4_scale(v: vec4, s: f32) vec4;

fn sycl::vec2_adds(v: vec2, s: f32) vec2;  // Add scalar to all components
fn sycl::vec3_adds(v: vec3, s: f32) vec3;
fn sycl::vec4_adds(v: vec4, s: f32) vec4;
```

### Swizzle Operations
```pika
// Extract sub-vectors (read-only swizzles)
fn sycl::vec3_xy(v: vec3) vec2;
fn sycl::vec3_xz(v: vec3) vec2;
fn sycl::vec3_yz(v: vec3) vec2;
fn sycl::vec4_xy(v: vec4) vec2;
fn sycl::vec4_xz(v: vec4) vec2;
fn sycl::vec4_xw(v: vec4) vec2;
fn sycl::vec4_yz(v: vec4) vec2;
fn sycl::vec4_yw(v: vec4) vec2;
fn sycl::vec4_zw(v: vec4) vec2;
fn sycl::vec4_xyz(v: vec4) vec3;
fn sycl::vec4_xyw(v: vec4) vec3;
fn sycl::vec4_xzw(v: vec4) vec3;
fn sycl::vec4_yzw(v: vec4) vec3;

// Common shuffles
fn sycl::vec4_xxxx(v: vec4) vec4;
fn sycl::vec4_yyyy(v: vec4) vec4;
fn sycl::vec4_zzzz(v: vec4) vec4;
fn sycl::vec4_wwww(v: vec4) vec4;
fn sycl::vec4_wzyx(v: vec4) vec4;  // Reverse
```

---

## Index and Range Types

These represent work-item position in the execution grid.

### Basic Index Types (Position Only)
```pika
// Indices are fixed-size arrays of sycl::id (size)
type sycl::id = size;
type sycl::id1 = [1]sycl::id;
type sycl::id2 = [2]sycl::id;
type sycl::id3 = [3]sycl::id;

// Ranges use the same layout as ids
type sycl::range1 = [1]sycl::id;
type sycl::range2 = [2]sycl::id;
type sycl::range3 = [3]sycl::id;
```

### Item Types (Position + Range)

Item types are opaque. Use the helper functions:
- `sycl::get_id(item)` -> `sycl::idN`
- `sycl::get_range(item)` -> `sycl::idN`
- `sycl::get_linear_id(item)` -> `sycl::id`

### ND-Item Types (Full Work-Group Information)

ND-item types are opaque. Use helpers such as:
- `sycl::get_global_id(item, dim)`
- `sycl::get_local_id(item, dim)`
- `sycl::get_group_id(item, dim)`
- `sycl::get_global_range(item, dim)`
- `sycl::get_local_range(item, dim)`

### Index Accessor Functions
```pika
// id accessors (index via [0]/[1]/[2])

// Linear ID computation
fn sycl::item2_linear_id(item: sycl::item2) size;      // id_y * range_x + id_x
fn sycl::item3_linear_id(item: sycl::item3) size;
fn sycl::nd_item1_global_linear_id(item: sycl::nd_item1) size;
fn sycl::nd_item2_global_linear_id(item: sycl::nd_item2) size;
fn sycl::nd_item2_local_linear_id(item: sycl::nd_item2) size;
fn sycl::nd_item3_global_linear_id(item: sycl::nd_item3) size;
fn sycl::nd_item3_local_linear_id(item: sycl::nd_item3) size;

// SYCL 2020 linear id methods (via nd_item)
fn get_local_linear_id(item: sycl::nd_item1) size;   // item.get_local_linear_id()
fn get_local_linear_id(item: sycl::nd_item2) size;
fn get_local_linear_id(item: sycl::nd_item3) size;
fn get_global_linear_id(item: sycl::nd_item1) size;  // item.get_global_linear_id()
fn get_global_linear_id(item: sycl::nd_item2) size;
fn get_global_linear_id(item: sycl::nd_item3) size;
```

### Sub-Group Type
```pika
// Sub-group info (SIMD lane level)
type sycl::sub_group = struct {
    local_id: u32,        // Lane ID within sub-group
    size: u32,            // Sub-group size (typically 32 or 64)
    group_id: u32,        // Which sub-group within work-group
    num_sub_groups: u32,  // Total sub-groups in work-group
};

// Get sub-group from nd_item
fn sycl::get_sub_group(item: sycl::nd_item1) sycl::sub_group;
fn sycl::get_sub_group2(item: sycl::nd_item2) sycl::sub_group;
fn sycl::get_sub_group3(item: sycl::nd_item3) sycl::sub_group;
```

---

## Memory Spaces

### Understanding Memory Spaces
```
GLOBAL MEMORY (global_*)
├── Accessible by: ALL work-items in ALL work-groups
├── Size: Gigabytes (device DRAM/HBM)
├── Speed: ~1-2 TB/s bandwidth
├── Lifetime: Until host frees it
└── Use: Input arrays, output arrays, large data

LOCAL MEMORY (local_*)
├── Accessible by: Work-items in SAME work-group ONLY
├── Size: ~16-64 KB per work-group
├── Speed: ~10-20 TB/s (on-chip SRAM)
├── Lifetime: Duration of work-group execution
└── Use: Shared scratch space, tiling, cooperation

PRIVATE MEMORY (default)
├── Accessible by: Single work-item ONLY
├── Size: Registers (limited)
├── Speed: Fastest
├── Lifetime: Duration of work-item execution  
└── Use: Local variables, accumulators

CONSTANT MEMORY (constant_*)
├── Accessible by: ALL work-items (read-only)
├── Size: ~64 KB cached
├── Speed: Fast when cached, broadcast to all
└── Use: Lookup tables, constants
```

### Memory-Qualified Pointer Types

Pointer parameters to kernels use prefixes to indicate address space.
```pika
// Global memory pointers (device DRAM - all work-items can access)
type global_f32 = *f32;
type global_f64 = *f64;
type global_i32 = *i32;
type global_i64 = *i64;
type global_u32 = *u32;
type global_u64 = *u64;
type global_vec4 = *vec4;

// Local memory pointers (work-group shared SRAM)
type local_f32 = *f32;
type local_f64 = *f64;
type local_i32 = *i32;
type local_u32 = *u32;
type local_vec4 = *vec4;

// Constant memory pointers (read-only, cached)
type constant_f32 = *f32;
type constant_i32 = *i32;
type constant_u32 = *u32;
```

### Memory Usage Example
```pika
const TILE: size = 16;

// Tiled matrix multiply demonstrating all memory types
@kernel fn matmul_tiled(
    item: sycl::nd_item2,
    
    // Global memory - input/output matrices (all work-items access)
    A: global_f32,
    B: global_f32,
    C: global_f32,
    
    // Local memory - tiles shared within this work-group
    // Work-group 0's tile_A is DIFFERENT from work-group 1's tile_A
    tile_A: local_f32,   // [TILE * TILE] elements
    tile_B: local_f32,   // [TILE * TILE] elements
    
    // Dimensions passed as values (effectively constant)
    M: u32, N: u32, K: u32,
) void = {
    // Private memory - these variables exist per work-item
    let row = item.global_id_y;          // Private
    let col = item.global_id_x;          // Private
    let local_row = item.local_id_y;     // Private
    let local_col = item.local_id_x;     // Private
    let sum: f32 = 0.0;                  // Private accumulator
    
    let num_tiles = (K + TILE - 1) / TILE;
    
    for (let t: size = 0; t < num_tiles; t += 1) {
        // Each work-item loads ONE element into local memory
        // All 256 work-items (16x16) cooperatively load the tile
        let a_idx = local_row * TILE + local_col;
        let b_idx = local_row * TILE + local_col;
        
        let a_col = t * TILE + local_col;
        let b_row = t * TILE + local_row;
        
        // Write to LOCAL memory (visible to work-group)
        if (row < M && a_col < K) {
            tile_A[a_idx] = A[row * K + a_col];
        } else {
            tile_A[a_idx] = 0.0;
        };
        
        if (b_row < K && col < N) {
            tile_B[b_idx] = B[b_row * N + col];
        } else {
            tile_B[b_idx] = 0.0;
        };
        
        // BARRIER: Wait for ALL work-items in group to finish writing
        // After this, tile_A and tile_B are fully populated
        sycl::group_barrier(item);
        
        // Now all work-items READ from local memory
        for (let k: size = 0; k < TILE; k += 1) {
            // Reading from local - fast!
            sum = sycl::fma_f32(
                tile_A[local_row * TILE + k],
                tile_B[k * TILE + local_col],
                sum
            );
        };
        
        // BARRIER: Wait before next tile load overwrites local memory
        sycl::group_barrier(item);
    };
    
    // Write result to GLOBAL memory
    if (row < M && col < N) {
        C[row * N + col] = sum;
    };
};
```

---

## Synchronization

### Work-Group Barriers

All work-items in a work-group must reach the barrier before any can proceed.
```pika
// Basic barrier (local + global memory fence)
fn sycl::group_barrier(item: sycl::nd_item1) void;
fn sycl::group_barrier(item: sycl::nd_item2) void;
fn sycl::group_barrier(item: sycl::nd_item3) void;

// Barrier with specific memory fence
fn sycl::group_barrier_local(item: sycl::nd_item2) void;   // Local memory only
fn sycl::group_barrier_global(item: sycl::nd_item2) void;  // Global memory only
```

### Memory Fences (Without Barrier)

Ensure memory operations are visible, but don't synchronize work-items.
```pika
fn sycl::mem_fence_local() void;
fn sycl::mem_fence_global() void;
fn sycl::mem_fence_all() void;
```

### Sub-Group Barrier

Synchronize within a sub-group (SIMD lane level, very fast).
```pika
fn sycl::sub_group_barrier() void;
```

---

## Atomic Operations

Atomics provide thread-safe access to global or local memory.

### Atomic Load/Store
```pika
fn sycl::atomic_load_u32(ptr: global_u32) u32;
fn sycl::atomic_load_i32(ptr: global_i32) i32;
fn sycl::atomic_load_f32(ptr: global_f32) f32;

fn sycl::atomic_store_u32(ptr: global_u32, val: u32) void;
fn sycl::atomic_store_i32(ptr: global_i32, val: i32) void;
fn sycl::atomic_store_f32(ptr: global_f32, val: f32) void;

// Local memory variants
fn sycl::atomic_load_local_u32(ptr: local_u32) u32;
fn sycl::atomic_store_local_u32(ptr: local_u32, val: u32) void;
```

### Atomic Read-Modify-Write

All return the OLD value before modification.
```pika
// Add
fn sycl::atomic_add_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_add_i32(ptr: global_i32, val: i32) i32;
fn sycl::atomic_add_f32(ptr: global_f32, val: f32) f32;
fn sycl::atomic_add_u64(ptr: global_u64, val: u64) u64;
fn sycl::atomic_add_f64(ptr: global_f64, val: f64) f64;

// Subtract
fn sycl::atomic_sub_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_sub_i32(ptr: global_i32, val: i32) i32;

// Min/Max
fn sycl::atomic_min_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_min_i32(ptr: global_i32, val: i32) i32;
fn sycl::atomic_min_f32(ptr: global_f32, val: f32) f32;
fn sycl::atomic_max_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_max_i32(ptr: global_i32, val: i32) i32;
fn sycl::atomic_max_f32(ptr: global_f32, val: f32) f32;

// Bitwise
fn sycl::atomic_and_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_or_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_xor_u32(ptr: global_u32, val: u32) u32;

// SYCL 2020 fetch_* operations (returns old value)
fn sycl::atomic_fetch_min_i32(ptr: global_i32, val: i32) i32;
fn sycl::atomic_fetch_min_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_fetch_min_f32(ptr: global_f32, val: f32) f32;
fn sycl::atomic_fetch_max_i32(ptr: global_i32, val: i32) i32;
fn sycl::atomic_fetch_max_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_fetch_max_f32(ptr: global_f32, val: f32) f32;
fn sycl::atomic_fetch_and_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_fetch_or_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_fetch_xor_u32(ptr: global_u32, val: u32) u32;

// Exchange
fn sycl::atomic_exchange_u32(ptr: global_u32, val: u32) u32;
fn sycl::atomic_exchange_i32(ptr: global_i32, val: i32) i32;
fn sycl::atomic_exchange_f32(ptr: global_f32, val: f32) f32;

// Compare-and-swap: if *ptr == expected, set *ptr = desired
// Returns true if swap happened
fn sycl::atomic_cas_u32(ptr: global_u32, expected: u32, desired: u32) bool;
fn sycl::atomic_cas_i32(ptr: global_i32, expected: i32, desired: i32) bool;

// Compare-and-swap with old value output
fn sycl::atomic_cas_weak_u32(ptr: global_u32, expected: *u32, desired: u32) bool;

// Local memory atomics
fn sycl::atomic_add_local_u32(ptr: local_u32, val: u32) u32;
fn sycl::atomic_add_local_i32(ptr: local_i32, val: i32) i32;
fn sycl::atomic_add_local_f32(ptr: local_f32, val: f32) f32;
fn sycl::atomic_min_local_u32(ptr: local_u32, val: u32) u32;
fn sycl::atomic_max_local_u32(ptr: local_u32, val: u32) u32;
```

---

## Group Collective Operations

Hardware-accelerated operations across work-groups and sub-groups.

### SYCL 2020 Group Algorithms

The standard SYCL 2020 group algorithm functions. These require a group object
obtained via `item.get_group()` and take a binary operation.

```pika
// reduce_over_group - reduce values across all work-items in a group
fn reduce_over_group(group: sycl::group, val: T, op: binary_op) T;
// Example: reduce_over_group(item.get_group(), my_val, sycl::plus<float>())

// inclusive_scan_over_group - inclusive prefix scan
// Element i gets op(val[0], val[1], ..., val[i])
fn inclusive_scan_over_group(group: sycl::group, val: T, op: binary_op) T;

// exclusive_scan_over_group - exclusive prefix scan
// Element i gets op(val[0], val[1], ..., val[i-1]), element 0 gets identity
fn exclusive_scan_over_group(group: sycl::group, val: T, init: T, op: binary_op) T;

// group_broadcast - broadcast value from one work-item to all
fn group_broadcast(group: sycl::group, val: T, local_id: size_t) T;

// Boolean predicates over group
fn any_of_group(group: sycl::group, pred: bool) bool;   // Any work-item true?
fn all_of_group(group: sycl::group, pred: bool) bool;   // All work-items true?
fn none_of_group(group: sycl::group, pred: bool) bool;  // No work-item true?
```

**Binary Operations:** `sycl::plus<T>()`, `sycl::multiplies<T>()`, `sycl::minimum<T>()`, `sycl::maximum<T>()`, `sycl::bit_and<T>()`, `sycl::bit_or<T>()`, `sycl::bit_xor<T>()`

### Work-Group Reductions (Legacy API)
```pika
// Reduce a value across all work-items in the work-group
// All work-items get the same result
fn sycl::group_reduce_add_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_reduce_add_f32(item: sycl::nd_item2, val: f32) f32;
fn sycl::group_reduce_add_i32(item: sycl::nd_item1, val: i32) i32;
fn sycl::group_reduce_add_u32(item: sycl::nd_item1, val: u32) u32;

fn sycl::group_reduce_min_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_reduce_max_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_reduce_min_i32(item: sycl::nd_item1, val: i32) i32;
fn sycl::group_reduce_max_i32(item: sycl::nd_item1, val: i32) i32;
fn sycl::group_reduce_min_u32(item: sycl::nd_item1, val: u32) u32;
fn sycl::group_reduce_max_u32(item: sycl::nd_item1, val: u32) u32;

fn sycl::group_reduce_mul_f32(item: sycl::nd_item1, val: f32) f32;

// Boolean reductions
fn sycl::group_any(item: sycl::nd_item1, predicate: bool) bool;  // Any true?
fn sycl::group_all(item: sycl::nd_item1, predicate: bool) bool;  // All true?
fn sycl::group_none(item: sycl::nd_item1, predicate: bool) bool; // None true?
```

### Work-Group Scans (Prefix Sum)
```pika
// Exclusive scan: element i gets sum of elements 0..i-1
fn sycl::group_exclusive_scan_add_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_exclusive_scan_add_i32(item: sycl::nd_item1, val: i32) i32;
fn sycl::group_exclusive_scan_add_u32(item: sycl::nd_item1, val: u32) u32;

// Inclusive scan: element i gets sum of elements 0..i
fn sycl::group_inclusive_scan_add_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_inclusive_scan_add_i32(item: sycl::nd_item1, val: i32) i32;
fn sycl::group_inclusive_scan_add_u32(item: sycl::nd_item1, val: u32) u32;

fn sycl::group_exclusive_scan_min_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_exclusive_scan_max_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_inclusive_scan_min_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_inclusive_scan_max_f32(item: sycl::nd_item1, val: f32) f32;
```

### Work-Group Broadcast
```pika
// Send value from one work-item to all others
fn sycl::group_broadcast_f32(item: sycl::nd_item1, val: f32, src_local_id: size) f32;
fn sycl::group_broadcast_i32(item: sycl::nd_item1, val: i32, src_local_id: size) i32;
fn sycl::group_broadcast_u32(item: sycl::nd_item1, val: u32, src_local_id: size) u32;

// Broadcast from local_id 0
fn sycl::group_broadcast_first_f32(item: sycl::nd_item1, val: f32) f32;
fn sycl::group_broadcast_first_i32(item: sycl::nd_item1, val: i32) i32;
```

### Sub-Group Operations (SIMD Level - Fastest)
```pika
// Sub-group reductions (within ~32 lanes, very fast)
fn sycl::sub_group_reduce_add_f32(sg: sycl::sub_group, val: f32) f32;
fn sycl::sub_group_reduce_add_i32(sg: sycl::sub_group, val: i32) i32;
fn sycl::sub_group_reduce_add_u32(sg: sycl::sub_group, val: u32) u32;
fn sycl::sub_group_reduce_min_f32(sg: sycl::sub_group, val: f32) f32;
fn sycl::sub_group_reduce_max_f32(sg: sycl::sub_group, val: f32) f32;

// Sub-group scans
fn sycl::sub_group_exclusive_scan_add_f32(sg: sycl::sub_group, val: f32) f32;
fn sycl::sub_group_inclusive_scan_add_f32(sg: sycl::sub_group, val: f32) f32;
fn sycl::sub_group_exclusive_scan_add_u32(sg: sycl::sub_group, val: u32) u32;
fn sycl::sub_group_inclusive_scan_add_u32(sg: sycl::sub_group, val: u32) u32;

// Sub-group broadcast
fn sycl::sub_group_broadcast_f32(sg: sycl::sub_group, val: f32, src_id: u32) f32;
fn sycl::sub_group_broadcast_i32(sg: sycl::sub_group, val: i32, src_id: u32) i32;

// Sub-group shuffle (exchange values between SIMD lanes)
fn sycl::sub_group_shuffle_f32(sg: sycl::sub_group, val: f32, src_id: u32) f32;
fn sycl::sub_group_shuffle_i32(sg: sycl::sub_group, val: i32, src_id: u32) i32;
fn sycl::sub_group_shuffle_u32(sg: sycl::sub_group, val: u32, src_id: u32) u32;

// XOR shuffle (butterfly pattern for reductions)
fn sycl::sub_group_shuffle_xor_f32(sg: sycl::sub_group, val: f32, mask: u32) f32;
fn sycl::sub_group_shuffle_xor_i32(sg: sycl::sub_group, val: i32, mask: u32) i32;
fn sycl::sub_group_shuffle_xor_u32(sg: sycl::sub_group, val: u32, mask: u32) u32;

// Shift shuffles
fn sycl::sub_group_shuffle_up_f32(sg: sycl::sub_group, val: f32, delta: u32) f32;
fn sycl::sub_group_shuffle_down_f32(sg: sycl::sub_group, val: f32, delta: u32) f32;

// Sub-group predicates
fn sycl::sub_group_any(sg: sycl::sub_group, predicate: bool) bool;
fn sycl::sub_group_all(sg: sycl::sub_group, predicate: bool) bool;
fn sycl::sub_group_none(sg: sycl::sub_group, predicate: bool) bool;

// Ballot (bitmask of predicate across lanes)
fn sycl::sub_group_ballot(sg: sycl::sub_group, predicate: bool) u32;
```

---

## Mathematical Functions

### Basic Math
```pika
// Absolute value
fn sycl::abs_f32(x: f32) f32;
fn sycl::abs_f64(x: f64) f64;
fn sycl::abs_i32(x: i32) i32;
fn sycl::abs_i64(x: i64) i64;

// Sign
fn sycl::sign_f32(x: f32) f32;
fn sycl::sign_f64(x: f64) f64;

// Min/Max
fn sycl::min_f32(x: f32, y: f32) f32;
fn sycl::min_f64(x: f64, y: f64) f64;
fn sycl::min_i32(x: i32, y: i32) i32;
fn sycl::min_i64(x: i64, y: i64) i64;
fn sycl::min_u32(x: u32, y: u32) u32;
fn sycl::min_u64(x: u64, y: u64) u64;

fn sycl::max_f32(x: f32, y: f32) f32;
fn sycl::max_f64(x: f64, y: f64) f64;
fn sycl::max_i32(x: i32, y: i32) i32;
fn sycl::max_i64(x: i64, y: i64) i64;
fn sycl::max_u32(x: u32, y: u32) u32;
fn sycl::max_u64(x: u64, y: u64) u64;

// Clamp
fn sycl::clamp_f32(x: f32, lo: f32, hi: f32) f32;
fn sycl::clamp_f64(x: f64, lo: f64, hi: f64) f64;
fn sycl::clamp_i32(x: i32, lo: i32, hi: i32) i32;
fn sycl::clamp_u32(x: u32, lo: u32, hi: u32) u32;

// Rounding
fn sycl::floor_f32(x: f32) f32;
fn sycl::floor_f64(x: f64) f64;
fn sycl::ceil_f32(x: f32) f32;
fn sycl::ceil_f64(x: f64) f64;
fn sycl::round_f32(x: f32) f32;
fn sycl::round_f64(x: f64) f64;
fn sycl::trunc_f32(x: f32) f32;
fn sycl::trunc_f64(x: f64) f64;
fn sycl::rint_f32(x: f32) f32;

// Fractional
fn sycl::fract_f32(x: f32) f32;
fn sycl::fmod_f32(x: f32, y: f32) f32;
fn sycl::fmod_f64(x: f64, y: f64) f64;
fn sycl::remainder_f32(x: f32, y: f32) f32;

// Interpolation
fn sycl::mix_f32(x: f32, y: f32, a: f32) f32;  // x + (y-x)*a
fn sycl::mix_f64(x: f64, y: f64, a: f64) f64;

// Step functions
fn sycl::step_f32(edge: f32, x: f32) f32;
fn sycl::smoothstep_f32(edge0: f32, edge1: f32, x: f32) f32;
```

### Exponential/Logarithmic
```pika
fn sycl::exp_f32(x: f32) f32;
fn sycl::exp_f64(x: f64) f64;
fn sycl::exp2_f32(x: f32) f32;
fn sycl::exp10_f32(x: f32) f32;
fn sycl::expm1_f32(x: f32) f32;

fn sycl::log_f32(x: f32) f32;
fn sycl::log_f64(x: f64) f64;
fn sycl::log2_f32(x: f32) f32;
fn sycl::log10_f32(x: f32) f32;
fn sycl::log1p_f32(x: f32) f32;

fn sycl::pow_f32(x: f32, y: f32) f32;
fn sycl::pow_f64(x: f64, y: f64) f64;
fn sycl::pown_f32(x: f32, n: i32) f32;

fn sycl::sqrt_f32(x: f32) f32;
fn sycl::sqrt_f64(x: f64) f64;
fn sycl::rsqrt_f32(x: f32) f32;
fn sycl::cbrt_f32(x: f32) f32;
fn sycl::hypot_f32(x: f32, y: f32) f32;
```

### Trigonometric
```pika
fn sycl::sin_f32(x: f32) f32;
fn sycl::sin_f64(x: f64) f64;
fn sycl::cos_f32(x: f32) f32;
fn sycl::cos_f64(x: f64) f64;
fn sycl::tan_f32(x: f32) f32;
fn sycl::tan_f64(x: f64) f64;

fn sycl::asin_f32(x: f32) f32;
fn sycl::acos_f32(x: f32) f32;
fn sycl::atan_f32(x: f32) f32;
fn sycl::atan2_f32(y: f32, x: f32) f32;
fn sycl::atan2_f64(y: f64, x: f64) f64;

fn sycl::sinh_f32(x: f32) f32;
fn sycl::cosh_f32(x: f32) f32;
fn sycl::tanh_f32(x: f32) f32;
fn sycl::asinh_f32(x: f32) f32;
fn sycl::acosh_f32(x: f32) f32;
fn sycl::atanh_f32(x: f32) f32;

// Combined sin/cos (more efficient)
fn sycl::sincos_f32(x: f32, sin_out: *f32, cos_out: *f32) void;

// Angle conversion
fn sycl::degrees_f32(radians: f32) f32;
fn sycl::radians_f32(degrees: f32) f32;

// sinpi(x) = sin(π*x) - more accurate for multiples of π
fn sycl::sinpi_f32(x: f32) f32;
fn sycl::cospi_f32(x: f32) f32;
```

### Fused Multiply-Add (Critical for HPC)
```pika
// a*b + c with single rounding (most accurate)
fn sycl::fma_f32(a: f32, b: f32, c: f32) f32;
fn sycl::fma_f64(a: f64, b: f64, c: f64) f64;

// a*b + c (may be unfused, potentially faster)
fn sycl::mad_f32(a: f32, b: f32, c: f32) f32;
```

### Native Math (Fast, Lower Precision)
```pika
fn sycl::native_sin_f32(x: f32) f32;
fn sycl::native_cos_f32(x: f32) f32;
fn sycl::native_tan_f32(x: f32) f32;
fn sycl::native_exp_f32(x: f32) f32;
fn sycl::native_exp2_f32(x: f32) f32;
fn sycl::native_log_f32(x: f32) f32;
fn sycl::native_log2_f32(x: f32) f32;
fn sycl::native_powr_f32(x: f32, y: f32) f32;
fn sycl::native_sqrt_f32(x: f32) f32;
fn sycl::native_rsqrt_f32(x: f32) f32;
fn sycl::native_recip_f32(x: f32) f32;
fn sycl::native_divide_f32(x: f32, y: f32) f32;
```

### Integer Functions
```pika
// Bit manipulation
fn sycl::clz_u32(x: u32) u32;       // Count leading zeros
fn sycl::clz_u64(x: u64) u64;
fn sycl::ctz_u32(x: u32) u32;       // Count trailing zeros
fn sycl::ctz_u64(x: u64) u64;
fn sycl::popcount_u32(x: u32) u32;  // Count set bits
fn sycl::popcount_u64(x: u64) u64;
fn sycl::rotate_u32(x: u32, n: u32) u32;
fn sycl::rotate_u64(x: u64, n: u64) u64;
fn sycl::bitreverse_u32(x: u32) u32;

// Saturating arithmetic
fn sycl::add_sat_i32(x: i32, y: i32) i32;
fn sycl::add_sat_u32(x: u32, y: u32) u32;
fn sycl::sub_sat_i32(x: i32, y: i32) i32;
fn sycl::sub_sat_u32(x: u32, y: u32) u32;

// Multiply-high (upper bits)
fn sycl::mul_hi_i32(x: i32, y: i32) i32;
fn sycl::mul_hi_u32(x: u32, y: u32) u32;
fn sycl::mul_hi_i64(x: i64, y: i64) i64;
fn sycl::mul_hi_u64(x: u64, y: u64) u64;

// 24-bit multiply (faster on some GPUs)
fn sycl::mul24_i32(x: i32, y: i32) i32;
fn sycl::mul24_u32(x: u32, y: u32) u32;
fn sycl::mad24_i32(a: i32, b: i32, c: i32) i32;
fn sycl::mad24_u32(a: u32, b: u32, c: u32) u32;

// Absolute difference
fn sycl::abs_diff_i32(x: i32, y: i32) u32;
fn sycl::abs_diff_u32(x: u32, y: u32) u32;
```

### Geometric (Vector)
```pika
fn sycl::dot_v2(a: vec2, b: vec2) f32;
fn sycl::dot_v3(a: vec3, b: vec3) f32;
fn sycl::dot_v4(a: vec4, b: vec4) f32;

fn sycl::cross_v3(a: vec3, b: vec3) vec3;

fn sycl::length_v2(v: vec2) f32;
fn sycl::length_v3(v: vec3) f32;
fn sycl::length_v4(v: vec4) f32;

fn sycl::distance_v2(a: vec2, b: vec2) f32;
fn sycl::distance_v3(a: vec3, b: vec3) f32;
fn sycl::distance_v4(a: vec4, b: vec4) f32;

fn sycl::normalize_v2(v: vec2) vec2;
fn sycl::normalize_v3(v: vec3) vec3;
fn sycl::normalize_v4(v: vec4) vec4;

// Fast variants
fn sycl::fast_length_v3(v: vec3) f32;
fn sycl::fast_normalize_v3(v: vec3) vec3;
fn sycl::fast_distance_v3(a: vec3, b: vec3) f32;
```

### Relational/Classification
```pika
fn sycl::isnan_f32(x: f32) bool;
fn sycl::isnan_f64(x: f64) bool;
fn sycl::isinf_f32(x: f32) bool;
fn sycl::isinf_f64(x: f64) bool;
fn sycl::isfinite_f32(x: f32) bool;
fn sycl::isfinite_f64(x: f64) bool;
fn sycl::isnormal_f32(x: f32) bool;
fn sycl::signbit_f32(x: f32) bool;

fn sycl::select_f32(a: f32, b: f32, c: bool) f32;
fn sycl::select_i32(a: i32, b: i32, c: bool) i32;
fn sycl::select_u32(a: u32, b: u32, c: bool) u32;
```

### Conversion
```pika
// Float to int (truncate toward zero)
fn sycl::f32_to_i32(x: f32) i32;
fn sycl::f32_to_u32(x: f32) u32;
fn sycl::f64_to_i64(x: f64) i64;

// Float to int (round to nearest)
fn sycl::f32_to_i32_rte(x: f32) i32;

// Float to int (saturating)
fn sycl::f32_to_i32_sat(x: f32) i32;
fn sycl::f32_to_u32_sat(x: f32) u32;

// Int to float
fn sycl::i32_to_f32(x: i32) f32;
fn sycl::u32_to_f32(x: u32) f32;
fn sycl::i64_to_f64(x: i64) f64;

// Float precision
fn sycl::f32_to_f64(x: f32) f64;
fn sycl::f64_to_f32(x: f64) f32;

// Bit reinterpretation (no conversion)
fn sycl::f32_as_u32(x: f32) u32;
fn sycl::u32_as_f32(x: u32) f32;
fn sycl::f32_as_i32(x: f32) i32;
fn sycl::i32_as_f32(x: i32) f32;
fn sycl::f64_as_u64(x: f64) u64;
fn sycl::u64_as_f64(x: u64) f64;
```

---

## Complete Examples

### Simple Vector Add
```pika
@kernel fn vector_add(
    idx: sycl::id1,
    a: global_f32,
    b: global_f32,
    c: global_f32,
) void = {
    let i = idx[0];
    c[i] = a[i] + b[i];
};
```

### SAXPY
```pika
@kernel fn saxpy(
    idx: sycl::id1,
    alpha: f32,
    x: global_f32,
    y: global_f32,
    result: global_f32,
) void = {
    let i = idx[0];
    result[i] = sycl::fma_f32(alpha, x[i], y[i]);
};
```

### Dot Product with Reduction
```pika
@kernel fn dot_partial(
    item: sycl::nd_item1,
    x: global_f32,
    y: global_f32,
    partial_sums: global_f32,
    scratch: local_f32,
    N: size,
) void = {
    let gid = item.global_id;
    let lid = item.local_id;
    let group = item.group_id;
    let local_size = item.local_range;
    
    // Load and multiply
    let prod: f32 = 0.0;
    if (gid < N) {
        prod = x[gid] * y[gid];
    };
    
    // Store to local memory
    scratch[lid] = prod;
    sycl::group_barrier(item);
    
    // Tree reduction
    let stride = local_size / 2;
    for (stride > 0; stride /= 2) {
        if (lid < stride) {
            scratch[lid] = scratch[lid] + scratch[lid + stride];
        };
        sycl::group_barrier(item);
    };
    
    // Write group result
    if (lid == 0) {
        partial_sums[group] = scratch[0];
    };
};
```

### 2D Convolution
```pika
@kernel fn conv2d(
    item: sycl::nd_item2,
    input: global_f32,
    kernel_weights: constant_f32,
    output: global_f32,
    width: u32, height: u32,
    kernel_size: u32,
) void = {
    let x = item.global_id_x;
    let y = item.global_id_y;
    let half_k = kernel_size / 2;
    
    if (x >= width || y >= height) {
        return;
    };
    
    let sum: f32 = 0.0;
    for (let ky: u32 = 0; ky < kernel_size; ky += 1) {
        for (let kx: u32 = 0; kx < kernel_size; kx += 1) {
            let ix = x + kx - half_k;
            let iy = y + ky - half_k;
            
            if (ix < width && iy < height) {
                let pixel = input[iy * width + ix];
                let weight = kernel_weights[ky * kernel_size + kx];
                sum = sycl::fma_f32(pixel, weight, sum);
            };
        };
    };
    
    output[y * width + x] = sum;
};
```

---

## Unsupported Features

The Pika SYCL backend focuses on **portable SYCL 2020** features. The following
features are explicitly unsupported to ensure code works across all SYCL
implementations (Intel DPC++, AdaptiveCpp, open-source LLVM SYCL).

### Hard Errors (Non-Portable)

These features will cause a compilation error with a clear message:

| Feature | Error Message |
|---------|---------------|
| `ext::intel::*` | Intel-specific extension not supported. Use portable SYCL 2020 features instead. |
| `ext::oneapi::*` | OneAPI extension not supported. Use portable SYCL 2020 features instead. |
| `ext::codeplay::*` | Codeplay extension not supported. Use portable SYCL 2020 features instead. |
| `malloc_device` | malloc_device not supported. Use buffers and accessors for portable memory management. |
| `malloc_shared` | malloc_shared not supported. Use buffers and accessors for portable memory management. |
| `malloc_host` | malloc_host not supported. Use buffers and accessors for portable memory management. |
| `aligned_alloc_*` | USM aligned_alloc not supported. Use buffers and accessors. |
| `sycl::free` | sycl::free (USM) not supported. Use buffers and accessors. |

**Rationale:** Vendor extensions are not portable across SYCL implementations.
USM (Unified Shared Memory) pointer allocations, while part of SYCL 2020, have
inconsistent support across backends and FPGA targets. The buffer/accessor model
provides better portability and allows the runtime to optimize memory placement.

### Warnings (Not Yet Implemented)

These features will emit a warning but compilation continues:

| Feature | Alternative |
|---------|-------------|
| `sub_group` operations | Use work-group operations instead |
| `sub_group_barrier` | Use `barrier()` for work-group sync |
| `parallel_for_work_group` / `parallel_for_work_item` | Use `nd_range` kernels |
| `sycl::image` / `sycl::sampler` | Use buffer-based approaches |
| `sycl::vec` / `sycl::float4` / `sycl::int4` | Use arrays or scalar operations |
| `group_async_copy` / `async_copy` | Use direct memory copies with barriers |

### Not Included (By Design)

| Feature | Reason |
|---------|--------|
| Host-side APIs (queue, buffer, accessor) | Kernel-only backend |
| Dynamic allocation | Pika design constraint |
| Images/samplers | Not core HPC compute |
| Pipes | Inter-kernel communication |
| Device-side enqueue | Requires dynamic features |
| Printf/stream | Debug only, not portable |
| Specialization constants | Compile-time only |
