#!/bin/bash
if [ "$1" == "DEBUG" ]; then
    ASMOPT="-g -F dwarf"
    LNKOPT="-g -no-pie"
echo "debug build"
else
    ASMOPT=
    LNKOPT="-s -no-pie"
echo "release build"
fi
nasm -f elf64 -w+all -w+error $ASMOPT -l fvm_asm.lst -o fvm_asm.o fvm_asm.nasm
objdump --reloc fvm_asm.o >>fvm_asm.lst
gcc -Wall -Werror -O3 -march=native -mtune=native $LNKOPT -o test_fvm \
test_fvm.c fvm_asm.o -lm
nm -a test_fvm >test_fvm.lst
