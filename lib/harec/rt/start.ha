// Entry point - lib/hare/rt.c's rt_start_c() calls _main

@symbol("main") fn main() void;

export @symbol("_main") fn _main() void = main();
