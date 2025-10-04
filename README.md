# yulark
A virtual machine written in C++

With a FORTH engine written in assembly language.

## Work in Progress

I've recently begun this project to test some ideas.

The FORTH subsystem is almost ready for use, but there's still some stuff missing.
Some of its features are:
- 64 bit integers in base 2 to 36, signed and unsigned arithmetic
- 64 bit floating-point in base 2 to 36 (printing numbers in arbitrary base is still in the works, "F." is decimal only at the moment)
- Supports defining words with CREATE ... DOES>
- Supports control structure IF ... ELSE ... THEN, and also UNLESS ... ELSE ... THEN
- Written in x86-64 assembly code
- Classic indirect threaded FORTH code model
- Large nucleus word set

The FORTH subsystem will only work on x86-64 CPUs or compatibles (which most of the modern desktop and server CPUs are). An on-chip FPU is required for using floating-point (most of the current CPUs have that).
