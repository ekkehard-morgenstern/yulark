#!/bin/bash
. build_test_fvm.sh
./compressf <fvm_yulark.f >fvm_yulark_comp.f
./compf2src fvm_yulark fvm_yulark_size <fvm_yulark_comp.f >fvm_yulark_c.c
gcc $CCOPT -c -o fvm_yulark_c.o fvm_yulark_c.c
gcc $CCOPT $LNKOPT -o test_yulark test_yulark.c fvm_asm.o fvm_library_c.o fvm_yulark_c.o -lm
nm -a test_yulark >test_yulark.lst
