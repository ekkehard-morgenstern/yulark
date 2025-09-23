#!/bin/bash

nasm -f elf64 -l fvm_asm.lst -o test_fpowl_asm.o test_fpowl_asm.nasm
gcc -Wall -Werror -O3 -march=native -mtune=native -o test_fpowl test_fpowl_c.c \
test_fpowl_asm.o
