// Test: Def constants in array sizes
use rt;

def MAX_SIZE: size = 10;
def ROWS: size = 3;
def COLS: size = 4;

type buffer = struct {
    data: [MAX_SIZE]int,
    count: size,
};

export fn main() void = {
    // Array with def constant size
    let arr: [MAX_SIZE]int = [0...];
    arr[0] = 42;
    arr[9] = 99;
    assert(arr[0] == 42);
    assert(arr[9] == 99);

    // Struct containing array with def size
    let buf: buffer = buffer {
        data = [0...],
        count = 0,
    };
    buf.data[5] = 123;
    assert(buf.data[5] == 123);

    // Multidimensional array with def sizes
    let matrix: [ROWS][COLS]int = [[0...]...];
    matrix[0][0] = 1;
    matrix[2][3] = 42;
    assert(matrix[0][0] == 1);
    assert(matrix[2][3] == 42);
};
