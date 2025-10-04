#!/bin/bash
nasm -f elf64 -w+all -w+error -o test_nconv_asm.o test_nconv_asm.nasm
gcc -Wall -Werror -O3 -march=native -mtune=native -o test_nconv test_nconv.c \
test_nconv_asm.o -lm

