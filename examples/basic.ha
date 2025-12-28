// Example 1: Basic arithmetic functions
export fn add(x: int, y: int) int = {
    return x + y;
};

export fn subtract(a: int, b: int) int = {
    return a - b;
};

fn multiply(x: int, y: int) int = x * y;

// Example 2: Factorial (recursion)
export fn factorial(n: int) int = {
    if (n <= 1) {
        return 1;
    };
    return n * factorial(n - 1);
};

// Example 3: Fibonacci
fn fib(n: int) int = {
    if (n <= 1) {
        return n;
    };
    return fib(n - 1) + fib(n - 2);
};

// Example 4: For loop
fn sum_to_n(n: int) int = {
    let total: int = 0;
    for (let i: int = 1; i <= n; i += 1) {
        total += i;
    };
    return total;
};

// Example 5: Types and structs
type point = struct {
    x: int,
    y: int,
};

fn distance_squared(p1: point, p2: point) int = {
    let dx: int = p2.x - p1.x;
    let dy: int = p2.y - p1.y;
    return dx * dx + dy * dy;
};

// Example 6: Pointers
fn swap(a: *int, b: *int) void = {
    let tmp: int = *a;
    *a = *b;
    *b = tmp;
};

// Example 7: Arrays  
fn array_sum(arr: [4]int) int = {
    let sum: int = 0;
    for (let i: int = 0; i < 4; i += 1) {
        sum += arr[i];
    };
    return sum;
};

// Example 8: Compile-time constants
def MAX_SIZE: int = 1024;
def PI: f64 = 3.14159265359;

// Example 9: Global variables
let counter: int = 0;
const VERSION: int = 1;

// Example 10: Main entry point
export fn main() void = {
    let a: int = 10;
    let b: int = 20;
    let result: int = add(a, b);
    
    let fact5: int = factorial(5);
    let fib10: int = fib(10);
    
    let p1: point = point { x = 0, y = 0 };
    let p2: point = point { x = 3, y = 4 };
    let dist: int = distance_squared(p1, p2);
};
