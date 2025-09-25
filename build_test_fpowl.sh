#!/bin/bash

nasm -f elf64 -l test_fpowl_asm.lst -o test_fpowl_asm.o test_fpowl_asm.nasm
objdump --reloc test_fpowl_asm.o >>test_powl_asm.lst
# -z noexecstack
gcc -Wall -Werror -O3 -march=native -mtune=native -o test_fpowl test_fpowl_c.c \
test_fpowl_asm.o -lm
