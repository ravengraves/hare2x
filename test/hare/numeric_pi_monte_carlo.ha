// Monte Carlo Pi estimation test
use rt;
use strings;

// Simple linear congruential generator (LCG) PRNG
// Uses parameters from Numerical Recipes
let rng_state: u64 = 12345;

fn seed_rng(s: u64) void = {
    rng_state = s;
};

fn rand_u64() u64 = {
    // LCG: state = (a * state + c) mod m
    // Using m = 2^64 (implicit), a = 6364136223846793005, c = 1
    rng_state = rng_state * 6364136223846793005u64 + 1u64;
    return rng_state;
};

// Returns random f64 in [0, 1)
fn rand_f64() f64 = {
    let r = rand_u64();
    // Divide by 2^64 to get [0, 1)
    return (r: f64) / 18446744073709551616.0;
};

// Estimate pi using Monte Carlo method
// Throw n random points in unit square, count those inside quarter circle
fn estimate_pi(n: int) f64 = {
    let inside = 0;

    for (let i = 0; i < n; i += 1) {
        let x = rand_f64();
        let y = rand_f64();

        // Check if point is inside unit quarter circle
        if (x * x + y * y <= 1.0) {
            inside += 1;
        };
    };

    // pi/4 = inside/n, so pi = 4 * inside/n
    return 4.0 * (inside: f64) / (n: f64);
};

// Absolute value for f64
fn abs_f64(x: f64) f64 = {
    return if (x < 0.0) -x else x;
};

export fn main() void = {
    // Test PRNG produces different values
    seed_rng(42);
    let r1 = rand_u64();
    let r2 = rand_u64();
    let r3 = rand_u64();
    assert(r1 != r2);
    assert(r2 != r3);
    assert(r1 != r3);

    // Test rand_f64 is in [0, 1)
    seed_rng(12345);
    for (let i = 0; i < 100; i += 1) {
        let r = rand_f64();
        assert(r >= 0.0);
        assert(r < 1.0);
    };

    // Test pi estimation with increasing samples
    // More samples should give better estimate

    seed_rng(31415);
    let pi_100 = estimate_pi(100);
    // Very rough estimate, allow large error
    assert(pi_100 > 2.0);
    assert(pi_100 < 4.5);

    seed_rng(31415);
    let pi_1000 = estimate_pi(1000);
    // Should be closer
    assert(pi_1000 > 2.8);
    assert(pi_1000 < 3.6);

    seed_rng(31415);
    let pi_10000 = estimate_pi(10000);
    // Should be reasonably close
    assert(pi_10000 > 3.0);
    assert(pi_10000 < 3.3);

    seed_rng(31415);
    let pi_100000 = estimate_pi(100000);
    // Should be quite close (within ~1%)
    let error = abs_f64(pi_100000 - 3.14159265358979);
    assert(error < 0.05);  // Within 0.05 of true pi

    // Run multiple trials to verify consistency
    let sum: f64 = 0.0;
    for (let trial = 0; trial < 10; trial += 1) {
        seed_rng((trial: u64) * 1000 + 1);
        let est = estimate_pi(10000);
        sum += est;
    };
    let avg = sum / 10.0;
    // Average of 10 trials should be very close
    let avg_error = abs_f64(avg - 3.14159265358979);
    assert(avg_error < 0.03);

    let msg: str = "Monte Carlo Pi tests passed!\n";
    rt::write(1, strings::toutf8(msg): *[*]u8, len(msg));
};
