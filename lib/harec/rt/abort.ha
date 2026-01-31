// Abort functions - bindings to lib/hare/rt.c

@symbol("rt_abort") fn c_abort(path: *str, line: u64, col: u64, msg: str) never;
@symbol("rt_abort_fixed") fn c_abort_fixed(path: *str, line: u64, col: u64, reason: u64) never;

export @symbol("rt.abort") fn _abort(path: *str, line: u64, col: u64, msg: str) never = c_abort(path, line, col, msg);

export @symbol("rt.abort_fixed") fn abort_fixed(path: *str, line: u64, col: u64, reason: u64) never = c_abort_fixed(path, line, col, reason);
