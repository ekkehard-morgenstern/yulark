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
CCOPT="-Wall -Werror -O3 -march=native -mtune=native"
gcc $CCOPT -o compressf compressf.c
./compressf <fvm_library.f >fvm_library_comp.f
gcc $CCOPT -o compf2src compf2src.c
./compf2src <fvm_library_comp.f >fvm_library_c.c
gcc $CCOPT -c -o fvm_library_c.o fvm_library_c.c
gcc $CCOPT $LNKOPT -o test_fvm test_fvm.c fvm_asm.o fvm_library_c.o -lm
nm -a test_fvm >test_fvm.lst
