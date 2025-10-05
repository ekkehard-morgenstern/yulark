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
- Written in x86-64 assembly code for UNIX-like operating systems (tested so far only on Linux)
- Classic indirect threaded FORTH code model
- Large nucleus word set
- Now has CALLC for calling arbitrary C functions conforming to the x86-64 SYSV ABI specification. However, passing of arguments in XMM registers is NOT supported, which precludes direct passing of floating-point parameters. Nonetheless, this allows for the usage of many, if not most, C library or user-defined functions. Supports variable argument lists of arbitrary length.
- Operations meant for defining words like ALLOT aren't allowed in regular word definitions.
- Bounds checking for parameter and return stack pointers (bounds checking for the dictionary pointer is yet to be implemented).
- Uses not a single global variable, thus suitable for multithread execution (with each FORTH instance in its own thread with its own memory).
- Stack frame of FORTH context is comparatively small with currently 1032 bytes of storage (1032 for alignment purposes).
- The whole FORTH nucleus has currently less than 4000 lines of well-documented assembly code and hand-compiled FORTH code.
- No AI was used for implementation.

The FORTH subsystem will only work on x86-64 CPUs or compatibles (which most of the modern desktop and server CPUs are). An on-chip FPU is required for using floating-point (most of the current CPUs have that).
