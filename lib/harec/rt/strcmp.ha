// String comparison - binding to lib/hare/rt.c

export @symbol("rt_strcmp") fn strcmp(a: str, b: str) bool;
