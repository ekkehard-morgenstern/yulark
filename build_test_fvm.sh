#!/bin/bash
nasm -f elf64 -w+all -w+error -l fvm_asm.lst -o fvm_asm.o fvm_asm.nasm
objdump --reloc fvm_asm.o >>fvm_asm.lst
gcc -Wall -Werror -O3 -march=native -mtune=native -no-pie -o test_fvm \
test_fvm.c fvm_asm.o -lm
