// Mandelbrot set computation test
use rt;
use strings;

// Check if point (cr, ci) is in mandelbrot set
// Returns iteration count when escaped, or max_iter if didn't escape
fn mandelbrot(cr: f64, ci: f64, max_iter: int) int = {
    let zr: f64 = 0.0;
    let zi: f64 = 0.0;

    for (let i = 0; i < max_iter; i += 1) {
        let zr2 = zr * zr;
        let zi2 = zi * zi;

        // Check escape: |z|^2 > 4
        if (zr2 + zi2 > 4.0) {
            return i;
        };

        // z = z^2 + c
        let new_zr = zr2 - zi2 + cr;
        zi = 2.0 * zr * zi + ci;
        zr = new_zr;
    };

    return max_iter;
};

// Absolute value for f64
fn abs_f64(x: f64) f64 = {
    return if (x < 0.0) -x else x;
};

export fn main() void = {
    let max_iter = 1000;

    // Point (0, 0) is in the set - should not escape
    assert(mandelbrot(0.0, 0.0, max_iter) == max_iter);

    // Point (-1, 0) is in the set - should not escape
    assert(mandelbrot(-1.0, 0.0, max_iter) == max_iter);

    // Point (0.25, 0) is on the boundary - should not escape
    assert(mandelbrot(0.25, 0.0, max_iter) == max_iter);

    // Point (2, 0) escapes after 2 iterations
    assert(mandelbrot(2.0, 0.0, max_iter) == 2);

    // Point (0, 2) escapes after 2 iterations
    assert(mandelbrot(0.0, 2.0, max_iter) == 2);

    // Point (-2, 0) is in the set
    assert(mandelbrot(-2.0, 0.0, max_iter) == max_iter);

    // Point (1, 0) escapes quickly
    let esc1 = mandelbrot(1.0, 0.0, max_iter);
    assert(esc1 < 10);
    assert(esc1 > 0);

    // Point (-0.5, 0.5) is in the set (main cardioid)
    assert(mandelbrot(-0.5, 0.5, max_iter) == max_iter);

    // Point (0.5, 0.5) escapes
    let esc2 = mandelbrot(0.5, 0.5, max_iter);
    assert(esc2 < max_iter);
    assert(esc2 > 0);

    // Test symmetry: mandelbrot is symmetric about real axis
    let p1 = mandelbrot(0.1, 0.6, max_iter);
    let p2 = mandelbrot(0.1, -0.6, max_iter);
    assert(p1 == p2);

    // Count points in a small grid that are in the set
    let in_set = 0;
    let total = 0;
    let step: f64 = 0.1;
    let y: f64 = -2.0;
    for (y < 2.0) {
        let x: f64 = -2.0;
        for (x < 2.0) {
            if (mandelbrot(x, y, 100) == 100) {
                in_set += 1;
            };
            total += 1;
            x += step;
        };
        y += step;
    };

    // Roughly 5-10% of points in [-2,2]x[-2,2] are in the set
    // Area of mandelbrot is about 1.5, area of square is 16
    // So expect around 9-10% to be in set
    assert(total == 1600);  // 40x40 grid
    assert(in_set > 100);   // At least ~6%
    assert(in_set < 300);   // At most ~19%

    let msg: str = "Mandelbrot tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
