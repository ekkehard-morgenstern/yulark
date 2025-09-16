# yulark
A virtual machine written in C++

With a FORTH engine written in assembly language.

## Work in Progress

I've recently begun this project to test some ideas.

The FORTH subsystem is almost ready for use, but there's still a considerable amount of stuff missing.

The FORTH subsystem will only work on x86-64 CPUs or compatibles (which most of the modern desktop and server CPUs are). An on-chip FPU is required for using floating-point (most of the current CPUs have that).
