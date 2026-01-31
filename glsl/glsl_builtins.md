# GLSL Builtins Reference (Pika GLSL Target)

This reference lists the GLSL ES 1.00 built-in types and functions supported
by the Pika GLSL backend. Use the `gl::` namespace for built-in types and
functions.

## Built-in Types

Scalar:
- `f32` -> `float`
- `i32` -> `int`
- `bool` -> `bool`

Vector:
- `gl::vec2`, `gl::vec3`, `gl::vec4`
- `gl::ivec2`, `gl::ivec3`, `gl::ivec4`
- `gl::bvec2`, `gl::bvec3`, `gl::bvec4`

Matrix:
- `gl::mat2`, `gl::mat3`, `gl::mat4`

Samplers:
- `gl::sampler2D`, `gl::samplerCube`

## Storage Qualifier Attributes

Declare global shader inputs/outputs with attributes:
- `@attribute` (vertex only)
- `@uniform`
- `@varying`
- `@builtin` (for `gl_Position`, `gl_FragColor`, etc.)

Examples:
```
@attribute let position = gl::vec3 { ... };
@varying let color = gl::vec4 { ... };
@uniform let model = gl::mat4 { ... };
@builtin let gl_Position = gl::vec4 { ... };
```

## Built-in Variables (@builtin)

Vertex:
- `gl_Position` (gl::vec4)
- `gl_PointSize` (f32)

Fragment:
- `gl_FragColor` (gl::vec4)
- `gl_FragCoord` (gl::vec4)
- `gl_FrontFacing` (bool)

## Built-in Functions (gl::)

Angles/Trig:
- `gl::radians(degrees)`
- `gl::degrees(radians)`
- `gl::sin(x)`
- `gl::cos(x)`
- `gl::tan(x)`
- `gl::asin(x)`
- `gl::acos(x)`
- `gl::atan(x)`
- `gl::atan2(y, x)` -> GLSL `atan(y, x)`

Exponential:
- `gl::pow(x, y)`
- `gl::exp(x)`
- `gl::log(x)`
- `gl::exp2(x)`
- `gl::log2(x)`
- `gl::sqrt(x)`
- `gl::inversesqrt(x)`

Common:
- `gl::abs(x)`
- `gl::sign(x)`
- `gl::floor(x)`
- `gl::ceil(x)`
- `gl::fract(x)`
- `gl::mod(x, y)`
- `gl::min(x, y)`
- `gl::max(x, y)`
- `gl::clamp(x, min, max)`
- `gl::mix(x, y, a)`
- `gl::step(edge, x)`
- `gl::smoothstep(edge0, edge1, x)`

Geometric:
- `gl::length(v)`
- `gl::distance(p0, p1)`
- `gl::dot(v1, v2)`
- `gl::cross(v1, v2)`
- `gl::normalize(v)`
- `gl::faceforward(n, i, nref)`
- `gl::reflect(i, n)`
- `gl::refract(i, n, eta)`

Matrix:
- `gl::matrixCompMult(m1, m2)`

Vector relational:
- `gl::lessThan(v1, v2)`
- `gl::lessThanEqual(v1, v2)`
- `gl::greaterThan(v1, v2)`
- `gl::greaterThanEqual(v1, v2)`
- `gl::equal(v1, v2)`
- `gl::notEqual(v1, v2)`
- `gl::any(v)`
- `gl::all(v)`
- `gl::not(v)`

Texture:
- `gl::texture2D(sampler, coord)`
- `gl::texture2D_bias(sampler, coord, bias)` -> GLSL `texture2D`
- `gl::textureCube(sampler, coord)`

## Suffix Overloads

Pika does not support function overloads, so the GLSL backend accepts
suffix-based names and strips the suffix when emitting GLSL. Examples:
- `gl::sinf`, `gl::sinv2`, `gl::sinv3`, `gl::sinv4`
- `gl::minv2`, `gl::minv3`, `gl::minv4`
- `gl::dotv2`, `gl::dotv3`, `gl::dotv4`

Supported suffixes: `f`, `v2`, `v3`, `v4`, `m2`, `m3`, `m4`, `i2`, `i3`,
`i4`, `b2`, `b3`, `b4`.

Notes:
- GLSL has overloads for many functions (vector/matrix variants). The backend
  accepts them; `glsl/gl.pka` provides scalar-biased stubs for hints only.
- Int vector overloads are provided for `abs`, `sign`, `min`, `max`, `clamp`.
- Legacy `_vec2`/`_mat4` style suffixes are still accepted.
- `gl::texture2D_bias` and `gl::atan2` map to GLSL `texture2D` / `atan`.
