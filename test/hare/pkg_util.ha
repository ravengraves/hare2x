// Utility functions for package test

fn internal_add(a: int, b: int) int = a + b;

export fn add(a: int, b: int) int = internal_add(a, b);

export fn multiply(a: int, b: int) int = a * b;
