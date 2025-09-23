;   YULARK - a virtual machine written in C++
;   Copyright (C) 2025  Ekkehard Morgenstern
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <https://www.gnu.org/licenses/>.
;
;   NOTE: Programs created with YULARK do not fall under this license.
;
;   CONTACT INFO:
;       E-Mail: ekkehard@ekkehardmorgenstern.de
;       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
;             Germany, Europe

                        cpu         x64
                        bits        64

                        section     .text

                        global      fvm_run

; Registers:
;       PSP     - parameter stack pointer   (r15)
;       RSP     - return stack pointer      (r14)
;       WP      - word pointer              (r13)
;       WA      - word address              (r12)
;       DP      - dictionary pointer        (rbx)

; This implements the classic threaded-code model of FORTH
; based on information from the file "jonesforth/jonesforth.S"
; by Richard W. M. Jones in the repository of Dave Gauer's
; NASMJF port, which can be found at
; https://ratfactor.com/repos/nasmjf/files.html
; Both are in the Public Domain.
; My implementation uses x86-64 assembly code, and I'm using
; registers not affected by calling library functions.
; These are r12-r15 and rbx. Also, I refrained from using the
; CPU's stack pointer rsp and frame pointer rbp, since using them
; for any other purpose than C context would make debugging the
; code using gdb really hard. I accepted the small performance
; hit that comes with that. Originally, I implemented it all in
; C++, but wasn't satisfied with the results.
; This code contains no global variables, and is hence multithread-
; capable. If you make modifications, keep that in mind.

                        ; terminates every FORTH word written in machine code
                        %macro  NEXT 0
                        mov     r12,[r13]   ; WA := [WP]+
                        add     r13,8
                        mov     rax,[r12]   ; JUMP [WA]
                        jmp     rax
                        %endmacro

                        ; code is ideally aligned on 32-byte boundary
                        align   32

                        ; rsi - memory block
                        ; rdi - memory size
                        ; rdx - return stack size
                        ; rcx - initial word address
fvm_run                 enter   0x200,0     ; 512 bytes of local storage

                        ; rbp-0x100     beginning of 256 bytes PAD space
%define PAD             0x100
                        ; rbp-0x120     beginning of 32 bytes of NAME space
%define NAME            0x120

                        ; rbp-0x1a8     floating-point exponent (conversion)
%define EXPONENT        0x1a8
                        ; rbp-0x1b0     floating-point fraction numdigits
%define FRACNDIG        0x1b0
                        ; rbp-0x1b8     floating-point fraction (conversion)
%define FRACTION        0x1b8
                        ; rbp-0x1c0     floating-point mantissa (conversion)
%define MANTISSA        0x1c0
                        ; rbp-0x1c8     BASE
%define BASE            0x1c8
                        ; rbp-0x1d0     STKLWR bound
%define STKLWR          0x1d0
                        ; rbp-0x1d8     STKUPR bound
%define STKUPR          0x1d8
                        ; rbp-0x1e0     OFILE handle
%define OFILE           0x1e0
                        ; rbp-0x1e8     PFILE handle for PAD buffer
%define PFILE           0x1e8
                        ; rbp-0x1f0     FILL state of PAD buffer
%define PFILL           0x1f0
                        ; rbp-0x1f8     POSition in PAD buffer
%define PPOS            0x1f8
                        ; rbp-0x200     LATEST word definition
%define LATEST          0x200

                        push    r15
                        push    r14
                        push    r13
                        push    r12
                        push    rbx

                        ; set up RSP
                        mov     r14,rsi
                        add     r14,rdi

                        ; set up PSP
                        mov     r15,r14
                        sub     r15,rdx
                        mov     [rbp-STKUPR],r15

                        ; set up DP
                        mov     rbx,rsi

                        ; the middle between PSP and DP is the stack lower bound
                        mov     rax,r15
                        sub     rax,rbx
                        shr     rax,1
                        add     rax,rbx
                        mov     [rbp-STKLWR],rax

                        ; set up WP
                        mov     r13,rcx

                        ; set up LATEST
                        mov     rax,[fvm_last_sysword]
                        mov     [rbp-LATEST],rax

                        ; set up PPOS / PFILL
                        xor     rax,rax
                        mov     [rbp-PFILL],rax
                        mov     [rbp-PPOS],rax

                        ; set up PFILE
                        mov     [rbp-PFILE],rax     ; 0 = STDIN

                        ; set up OFILE
                        inc     rax
                        mov     [rbp-OFILE],rax     ; 1 = STDOUT

                        ; set up BASE
                        mov     rax,10
                        mov     [rbp-BASE],rax

                        ; go to NEXT
                        NEXT

                        ; code is ideally aligned on 32-byte boundary
                        align   32

                        ; terminates the execution of FORTH code
fvm_term                pop     rbx
                        pop     r12
                        pop     r13
                        pop     r14
                        pop     r15
                        leave
                        ret

%define __NR_write      1

                        %macro  ERREND 1
                        mov     rsi,2   ; STDERR
                        lea     rdi,%%errtext
%define ERRTEXT         %1
                        %strlen cnt ERRTEXT
                        mov     rdx,cnt+1
                        mov     rax,__NR_write
                        syscall
                        jmp     fvm_term
                        section .rodata
%%errtext               db      ERRTEXT,10
                        section .text
                        %endmacro

                        %macro  ERRMSG 1
                        mov     rsi,2   ; STDERR
                        lea     rdi,%%errtext
%define ERRTEXT         %1
                        %strlen cnt ERRTEXT
                        mov     rdx,cnt+1
                        mov     rax,__NR_write
                        syscall
                        ret
                        section .rodata
%%errtext               db      ERRTEXT,10
                        section .text
                        %endmacro

fvm_stkovf              ERREND  "? stack overflow"
fvm_stkunf              ERREND  "? stack underflow"
fvm_divzro              ERREND  "? division by zero"
fvm_nofpu               ERREND  "? FPU not found"
fvm_badbase             ERRMSG  "? bad number base, reset to 10"
fvm_notimpl             ERRMSG  "? not implemented"

                        ; check for stack overflow
                        %macro  CHKOVF 1
                        lea     r8,[r15 - (%1 * 8)]
                        cmp     r8,qword [rbp - STKLWR]
                        jae     %%okay
                        jmp     fvm_stkovf
%%okay:
                        %endmacro

                        ; check for stack underflow
                        %macro  CHKUNF 1
                        lea     r8,[r15 + (%1 * 8)]
                        cmp     r8,qword [rbp - STKUPR]
                        jbe     %%okay
                        jmp     fvm_stkunf
%%okay:
                        %endmacro

;                       +--------------------+
;                       |  link to previous  |
;                       +-----+--------------+
;                       | NLF | NAME ...     |
;                       +--------------------+
;                       | NAME ... PAD 0 0 0 | (optional name/pad bytes)
;                       +--------------------+
;                       |       DOCOL        |
;                       +--------------------+
;                       |  definition ...    | word-addresses
;                       +--------------------+

                        ; code is ideally aligned on 32-byte boundary
                        align   32

                        ; starts the processing of every FORTH implemented word
fvm_docol               sub     r14,8       ; -[RSP] := WP
                        mov     [r14],r13
                        lea     r13,[r12+8] ; WP := WA + 1
                        ; begin processing word definition
                        NEXT

%define LINKBACK        0
%define IMMEDIATE       0x20    ; immediate mode word, always executed

                        ; define a colon definition
                        ; parameters: name, label, flags
                        %macro DEFCOL 3
                        %strlen cnt %1
                        section .rodata
                        align   8
%%begin                 dq      LINKBACK
%define LINKBACK        %%begin
                        db      %3 + cnt
                        db      %1
                        align   8
                        global  %2
%2                      dq      fvm_docol
                        ; rest defined by user
                        %endmacro

                        ; define an assembly code definition
                        ; parameters name, label, flags
                        %macro DEFASM 3
                        %strlen cnt %1
                        section .rodata
                        align   8
%%begin                 dq      LINKBACK
%define LINKBACK        %%begin
                        db      %3 + cnt
                        db      %1
                        align   8
                        global  %2
%2                      dq      %%implementation
                        section .text
                        ; code is ideally aligned on 32-byte boundary
                        align   32
%%implementation:
                        ; rest defined by user
                        %endmacro

                        ; in this implementation, QUIT actually quits FORTH
                        DEFASM  "QUIT",QUIT,0
                        jmp     fvm_term

                        ; terminates any FORTH implemented word
                        DEFASM  "EXIT",EXIT,0
                        mov     r13,[r14]   ; WP := [RSP]+
                        add     r14,8
                        NEXT

                        ; pushes a literal (stored in the following word)
                        ; onto the parameter stack
                        DEFASM  "LIT",LIT,0
                        CHKOVF  1
                        mov     rax,[r13]
                        add     r13,8
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; basic computations

                        DEFASM  "+",ADDINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        add     rax,[r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "1+",ADDONE,0
                        CHKUNF  1
                        inc     qword [r15]
                        NEXT

                        DEFASM  "1-",SUBONE,0
                        CHKUNF  1
                        dec     qword [r15]
                        NEXT

                        DEFASM  "-",SUBINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        sub     rax,[r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "*",MULINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        imul    qword [r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        %macro  CHKZRO 0
                        xor     rax,rax
                        cmp     qword [r15],rax ; test for zero
                        jne     %%okay
                        jmp     fvm_divzro
%%okay:
                        %endmacro

                        DEFASM  "/",DIVINT,0
                        CHKUNF  2
                        CHKZRO
                        mov     rax,[r15+8]
                        cqo                     ; sign-extend into rdx
                        idiv    qword [r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "*/",MULDIVINT,0
                        CHKUNF  3
                        CHKZRO
                        mov     rax,[r15+16]
                        imul    qword [r15+8]
                        idiv    qword [r15]
                        add     r15,16
                        mov     [r15],rax
                        NEXT

                        DEFASM  "/MOD",DIVMODINT,0
                        CHKUNF  2
                        CHKZRO
                        mov     rax,[r15+8]
                        cqo                     ; sign-extend into rdx
                        idiv    qword [r15]
                        mov     [r15+8],rax
                        mov     [r15],rdx
                        NEXT

                        DEFASM  "MOD",MODINT,0
                        CHKUNF  2
                        CHKZRO
                        mov     rax,[r15+8]
                        cqo                     ; sign-extend into rdx
                        idiv    qword [r15]
                        add     r15,8
                        mov     [r15],rdx
                        NEXT

                        DEFASM  "<0",LTZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        setl    al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<=0",LEZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        setle   al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">0",GTZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        setg    al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">=0",GEZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        setge   al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "=0",EQZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        sete    al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<>0",NEZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        setne   al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<",LTINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setl    al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<=",LEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setle   al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">",GTINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setg    al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">=",GEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setge   al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "=",EQINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        sete    al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<>",NEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setne   al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "NEG",NEGATE,0
                        CHKUNF  1
                        neg     qword [r15]
                        NEXT

                        DEFASM  "NOT",BINNOT,0
                        CHKUNF  1
                        not     qword [r15]
                        NEXT

                        DEFASM  "AND",BINAND,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        and     [r15],rax
                        NEXT

                        DEFASM  "OR",BINOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        or      [r15],rax
                        NEXT

                        DEFASM  "XOR",BINXOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        xor     [r15],rax
                        NEXT

                        DEFASM  "NAND",BINNAND,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        and     [r15],rax
                        not     qword [r15]
                        NEXT

                        DEFASM  "NOR",BINNOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        or      [r15],rax
                        not     qword [r15]
                        NEXT

                        DEFASM  "XNOR",BINXNOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        xor     [r15],rax
                        not     qword [r15]
                        NEXT

                        DEFASM  "@",FETCH,0
                        CHKUNF  1
                        mov     rax,[r15]
                        mov     rax,[rax]
                        mov     [r15],rax
                        NEXT

                        DEFASM  "!",STORE,0
                        CHKUNF  2
                        mov     rdx,[r15+8]
                        mov     rax,[r15]
                        mov     [rax],rdx
                        add     r15,16
                        NEXT

                        DEFASM  "CELL",CELL,0
                        CHKOVF  1
                        mov     rax,8   ; return size of memory cell
                        sub     r15,rax
                        mov     [r15],rax
                        NEXT

                        DEFASM  "CELLS",CELLS,0
                        CHKUNF  1
                        mov     rax,[r15]   ; compute size of n cells
                        shl     rax,3
                        mov     [r15],rax
                        NEXT

                        ; duplicate word on the stack
                        DEFASM  "DUP",DUP,0
                        CHKUNF  1
                        CHKOVF  1
                        mov     rax,[r15]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; swap words on stack
                        DEFASM  "SWAP",SWAP,0
                        CHKUNF  2
                        mov     rax,[r15]
                        mov     rdx,[r15+8]
                        mov     [r15+8],rax
                        mov     [r15],rdx
                        NEXT

                        ; rotate words on stack
                        DEFASM  "ROT",ROT,0
                        CHKUNF  3
                        ; (n1 n2 n3) -- (n2 n3 n1)
                        mov     rax,[r15+16]    ; n1
                        mov     rdx,[r15+8]     ; n2
                        mov     rcx,[r15]       ; n3
                        mov     [r15+16],rdx    ; n2
                        mov     [r15+8],rcx     ; n3
                        mov     [r15],rax       ; n1
                        NEXT

                        ; over
                        DEFASM  "OVER",OVER,0
                        CHKUNF  2
                        CHKOVF  1
                        mov     rax,[r15+8]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; pick word from stack
                        DEFASM  "PICK",PICK,0
                        CHKUNF  1
                        mov     rax,[r15]
                        dec     rax
                        CHKUNF  rax
                        mov     rax,[r15+rax*8]
                        mov     [r15],rax
                        NEXT

                        ; drop
                        DEFASM  "DROP",DROP,0
                        CHKUNF  1
                        add     r15,8
                        NEXT

                        DEFASM  "FPUINIT",FPUINIT,0
                        push    rbx
                        mov     rax,1
                        cpuid
                        pop     rbx
                        and     rdx,1
                        jnz     .okay
                        jmp     fvm_nofpu
.okay                   finit
                        NEXT

                        DEFASM  "I2F",I2F,0
                        CHKUNF  1
                        fild    qword [r15]
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F2I",F2I,0
                        CHKUNF  1
                        fld     qword [r15]
                        frndint
                        fistp   qword [r15]
                        NEXT

                        DEFASM  "FRNDINT",FROUNDINT,0
                        CHKUNF  1
                        fld     qword [r15]
                        frndint
                        fstp    qword [r15]
                        NEXT

                        ; floating-point addition
                        ; ( n1 n2 -- res )
                        DEFASM  "F+",ADDFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        faddp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        ; floating-point subtraction
                        ; ( n1 n2 -- res )
                        DEFASM  "F-",SUBFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fsubp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        ; floating-point multiplication
                        ; ( n1 n2 -- res )
                        DEFASM  "F*",MULFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fmulp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        ; floating-point divide
                        ; ( n1 n2 -- res )
                        DEFASM  "F/",DIVFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fdivp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        ; compute floating-point remainder
                        ; ( n1 n2 -- res )
                        DEFASM  "FMOD",MODFLT,0
                        CHKUNF  2
                        mov     rdi,[r15+8]
                        mov     rsi,[r15]
                        call    _fmod
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        ; subroutine _fmod( value1, value2 )
                        ; compute floating-point remainder
                        ; rdi - value1, rsi - value2
_fmod                   push    rsi
                        push    rdi
                        fld     qword [rsp+8]     ; st1 - value2
                        fld     qword [rsp]       ; st0 - value1
                        add     rsp,16
.repeat                 fprem               ; compute partial remainder
                        fstsw   ax          ; get FPU status word
                        and     ax,0x0400   ; test C2 FPU flag
                        jnz     .repeat     ; loop until zero
                        xor     rax,rax
                        push    rax
                        fstp    qword [rsp]
                        pop     rax
                        ffree   st0
                        fincstp
                        ret

                        ; compare two floating point numbers
                        ; ( n1 n2 -- res )
                        ; returns -2 for errors
                        DEFASM  "FCOMP",COMPFLT,0
                        CHKUNF  2
                        mov     rdi,[r15+8]
                        mov     rsi,[r15]
                        call    _fcomp
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        ; compare two floating-point numbers
                        ; rdi - value1, rsi - value2
                        ; rax - result
                        ; returns -2 for errors
_fcomp                  push    rsi
                        push    rdi
                        fld     qword [rsp]     ; st0 - value1
                        fcomp   qword [rsp+8]   ; cmp st0,src(=value2)
                        add     rsp,16
                        fstsw   ax              ; get FPU status word
                        and     ax,0x4500       ; C3/C2/C0
                        jz      .grt
                        cmp     ax,0x0100       ; C0
                        je      .lwr
                        cmp     ax,0x4000       ; C3
                        je      .eql
                        mov     rax,-2          ; indicate error
                        jmp     .end
.grt                    mov     rax,1           ; greater
                        jmp     .end
.lwr                    mov     rax,-1          ; lower
                        jmp     .end
.eql                    mov     rax,0           ; equal
.end                    ret

                        ; compute power x^y (limited)
                        ; ( x y -- res )
                        ; LIMITATION: x must be positive and non-zero
                        ; TODO: handle special cases
                        DEFASM  "FPOWL",FPOWL,0
                        CHKUNF  2
                        mov     rdi,[r15+8]
                        mov     rsi,[r15]
                        call    _fpowl
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        ; compute power x^y (limited)
                        ; rdi - value1 (x), rsi - value2 (y)
                        ; rax - result
                        ; LIMITATION: x must be positive and non-zero
                        ; TODO: handle special cases
_fpowl                  push    rsi
                        push    rdi
                        ; formula for computing x^y
                        ; x^y := 2^(y * log2(x))
                        ; first, compute y * log2(x)
                        fld     qword [rsp+8]   ; st1 - value2 (y)
                        fld     qword [rsp]     ; st0 - value1 (x)
                        fyl2x
                        ; st0 - result
                        ; now we need to compute 2^result
                        ; easier said than done ...
                        ; first we have to do fmod(result,1) to extract a
                        ; fraction in the form -1 .. +1 (for f2xm1), and then
                        ; do fscale on the computation result using the
                        ; integral part of the previous result.
                        fld1
                        fld     st1     ; save int part for scale
                        ; at this point, the FPU stack should look like this:
                        ;   st2     (previous result)
                        ;   st1     1
                        ;   st0     (previous result)
.loop_prem              fprem               ; n=fmod(result,1)
                        fstsw   ax
                        test    ax,0x0400
                        jnz     .loop_prem
                        ;   st2     (previous result)
                        ;   st1     1
                        ;   st0     (fprem result)
                        f2xm1               ; (2^n-1)+1
                        faddp
                        ;   st1     (previous result)
                        ;   st0     (fixed-up f2xm1 result)
                        ; fscale takes the int part of st1 and adds it to the
                        ; exponent of st0, effectively yielding the desired
                        ; result.
                        fscale
                        ;   st1     (previous result)
                        ;   st0     (final result)
                        fstp    qword [rsp+8]
                        ;   st0     (previous result)
                        ffree   st0
                        fincstp
                        add     rsp,8
                        pop     rax
                        ret

                        ; change sign of floating-point number
                        ; ( n -- n )
                        DEFASM  "FNEG",FNEGATE,0
                        CHKUNF  1
                        fld     qword [r15]
                        fchs
                        fstp    qword [r15]
                        NEXT

                        ; compute absolute value of floating-point number
                        ; ( n -- n )
                        DEFASM  "FABS",FABSOLUTE,0
                        CHKUNF  1
                        fld     qword [r15]
                        fabs
                        fstp    qword [r15]
                        NEXT

                        ; compute power x^y
                        ; ( x y -- n )
                        DEFCOL  "FPOW",FPOWER,0
                        ; check if x is below zero
                        dq      LIT,2,PICK  ; 2 PICK
                        dq      LIT,0.0     ; 0.0
                        dq      COMPFLT     ; FCOMP
                        dq      LEZEROINT   ; <=0
                        dq      DUP         ; DUP
                        dq      CONDJUMP,.lezero ; ?JUMP[.lezero]
                        ; not below zero: compute power
                        dq      DROP        ; DROP
.finish                 dq      FPOWL       ; FPOWL
                        dq      EXIT
                        ; ( x y sign )
                        ; below zero
.lezero                 dq      EQZEROINT   ; =0
                        dq      CONDJUMP,.zero ; ?JUMP[.zero]
                        ; ( x y )
                        ; x is negative
                        ; round y to integer
                        dq      FROUNDINT   ; FRNDINT
                        ; compute absolute value of x
                        dq      SWAP,FABSOLUTE,SWAP ; SWAP FABS SWAP
                        ; test if y is odd
                        ; if even, the signs cancel each other out
                        ; if odd, the sign prevails
                        dq      DUP,LIT,1,BINAND ; DUP 1 AND
                        dq      EQZEROINT       ; =0 (even)
                        dq      CONDJUMP,.finish ; ?JUMP[.finish]
                        ; odd: compute then invert sign
                        dq      FPOWL,FNEGATE   ; FPOWL FNEG
                        dq      EXIT
                        ; ( x y )
                        ; x is 0, 0^y is always zero
.zero                   dq      DROP,DROP   ; DROP DROP
                        dq      LIT,0.0     ; 0.0
                        dq      EXIT

                        ; to-latest: returns the address of the LATEST variable
                        DEFASM  ">LATEST",TOLATEST,0
                        CHKOVF  1
                        lea     rax,[rbp-LATEST]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the next dictionary location
                        DEFASM  "HERE",PUSHHERE,0
                        CHKOVF  1
                        sub     r15,8
                        mov     [r15],rbx
                        NEXT

                        ; to-in returns the address of the PAD offset
                        DEFASM  ">IN",TOIN,0
                        CHKOVF  1
                        lea     rax,[rbp-PPOS]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the number of chars in the PAD
                        DEFASM  ">MAX",TOMAX,0
                        CHKOVF  1
                        lea     rax,[rbp-PFILL]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the file handle for the PAD
                        DEFASM  ">FILE",TOFILE,0
                        CHKOVF  1
                        lea     rax,[rbp-PFILE]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the file handle for output
                        DEFASM  ">OUT",TOOUT,0
                        CHKOVF  1
                        lea     rax,[rbp-OFILE]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the BASE variable
                        DEFASM  "BASE",PUSHBASE,0
                        CHKOVF  1
                        lea     rax,[rbp-BASE]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the PAD buffer
                        DEFASM  "PAD",PUSHPAD,0
                        CHKOVF  1
                        lea     rax,[rbp-PAD]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the NAME buffer
                        DEFASM  "NAME",PUSHNAME,0
                        CHKOVF  1
                        lea     rax,[rbp-NAME]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the MANTISSA variable
                        DEFASM  ">MANTISSA",TOMANTISSA,0
                        CHKOVF  1
                        lea     rax,[rbp-MANTISSA]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the FRACTION variable
                        DEFASM  ">FRACTION",TOFRACTION,0
                        CHKOVF  1
                        lea     rax,[rbp-FRACTION]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the FRACNDIG variable
                        DEFASM  ">FRACNDIG",TOFRACNDIG,0
                        CHKOVF  1
                        lea     rax,[rbp-FRACNDIG]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the EXPONENT variable
                        DEFASM  ">MANTISSA",TOEXPONENT,0
                        CHKOVF  1
                        lea     rax,[rbp-EXPONENT]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; converts error code to 0
                        DEFASM  "?ERR0",ERR2ZERO,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     rax,0
                        jge     .good
                        xor     rax,rax
.good                   mov     [r15],rax
                        NEXT

                        ; read bytes from a system file
                        DEFASM  "SYSREAD",SYSREAD,0
                        CHKUNF  3
                        mov     rsi,[r15+16]    ; file handle
                        mov     rdi,[r15+8]     ; buffer
                        mov     rdx,[r15]       ; count
                        add     r15,16
%define __NR_read       0
                        mov     rax,__NR_read
                        syscall
                        mov     [r15],rax
                        NEXT

                        ; write bytes to a system file
                        DEFASM  "SYSWRITE",SYSWRITE,0
                        CHKUNF  3
                        mov     rsi,[r15+16]    ; file handle
                        mov     rdi,[r15+8]     ; buffer
                        mov     rdx,[r15]       ; count
                        add     r15,16
                        mov     rax,__NR_write
                        syscall
                        mov     [r15],rax
                        NEXT

                        ; read entire PAD
                        DEFCOL  "PADREAD",PADREAD,0
                        dq      TOFILE      ; >FILE
                        dq      FETCH       ; @
                        dq      PUSHPAD     ; PAD
                        dq      LIT,256     ; 256
                        dq      SYSREAD     ; SYSREAD
                        dq      ERR2ZERO    ; ?ERR0
                        dq      TOMAX       ; >MAX
                        dq      STORE       ; !
                        dq      LIT,0       ; 0
                        dq      TOIN        ; >IN
                        dq      STORE       ; !
                        dq      EXIT

                        ; type text to output
                        DEFCOL  "TYPE",TYPEOUT,0    ; ( addr n )
                        dq      TOOUT       ; >OUT
                        dq      FETCH       ; @
                        ; ( addr n ofile )
                        ; ( n ofile addr ) after 1st ROT
                        ; ( ofile addr n ) after 2nd ROT
                        dq      ROT,ROT     ; ROT ROT
                        dq      SYSWRITE
                        dq      DROP        ; DROP
                        dq      EXIT

                        ; adjust word pointer
                        ; -------------------
                        ; The offset must be encoded in the colon definition
                        ; right after the SKIP instruction.
                        ; If offset is 0, no word is skipped, if it's 1, one
                        ; word is skipped, and so on. If offset is -2, an
                        ; endless loop occurs in the SKIP instruction if it is
                        ; called from a colon definition. If it's -3, the
                        ; instruction before the SKIP gets executed (if there
                        ; is one). And so on.
                        ; This instruction is used by the compiler to compile
                        ; IF ... THEN statements etc. It should not be called
                        ; by user code.
                        DEFASM  "SKIP",SKIP,0   ; ( -- )
                        mov     rax,[r13]
                        add     r13,8
                        lea     r13,[r13+rax*8]
                        NEXT

                        ; jump to specific word address encoded in the word
                        ; following the jump instruction.
                        DEFASM  "JUMP",JUMP,0
                        mov     r13,[r13]
                        NEXT

                        ; same as SKIP but jumps only if the value on the stack
                        ; is true (i.e. nonzero).
                        DEFASM  "?SKIP",CONDSKIP,0  ; ( bool -- )
                        CHKUNF  1
                        mov     rax,[r13]
                        add     r13,8
                        mov     rdx,[r15]
                        add     r15,8
                        test    rdx,rdx
                        jz      .noskip
                        lea     r13,[r13+rax*8]
.noskip                 NEXT

                        ; same as JUMP but jumps only if the value on the stack
                        ; is true (i.e. nonzero)
                        DEFASM  "?JUMP",CONDJUMP,0  ; ( bool -- )
                        CHKUNF  1
                        mov     rdx,[r15]
                        add     r15,8
                        test    rdx,rdx
                        jz      .nojump
                        mov     r13,[r13]
.nojump                 NEXT

                        ; reads an unsigned char from specified address
                        ; and places it as a word on the stack
                        DEFASM  "C@",CHARFETCH,0    ; ( addr -- char )
                        CHKUNF  1
                        mov     rax,[r15]
                        mov     al,[rax]
                        movzx   rax,al
                        mov     [r15],rax
                        NEXT

                        ; stores a character at the specified address
                        DEFASM  "C!",CHARSTORE,0    ; ( char addr -- )
                        CHKUNF  2
                        mov     rdx,[r15+8]
                        mov     rax,[r15]
                        add     r15,16
                        mov     [rax],dl
                        NEXT

                        DEFASM  "INCR",INCR,0       ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        inc     qword [r15]
                        add     r15,8
                        NEXT

                        DEFASM  "CINCR",CINCR,0     ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        inc     byte [r15]
                        add     r15,8
                        NEXT

                        DEFASM  "DECR",DECR,0       ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        dec     qword [r15]
                        add     r15,8
                        NEXT

                        DEFASM  "CDECR",CDECR,0     ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        dec     byte [r15]
                        add     r15,8
                        NEXT

                        DEFASM  "?SPC",ISSPC,0      ; ( char -- bool )
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     al,0x20 ; SPC
                        je      .isspc
                        cmp     al,0x09 ; HT
                        je      .isspc
                        cmp     al,0x0a ; LF
                        je      .isspc
                        cmp     al,0x0d ; CR
                        je      .isspc
                        cmp     al,0x00 ; NUL
                        je      .isspc
                        ; not space
                        xor     al,al
                        jmp     .end
.isspc                  xor     al,al
                        not     al
.end                    movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        ; read a character from the PAD input
                        DEFCOL  "PADGETCH",PADGETCH,0
                        ; check if input position is beyond maximum
.nextchar               dq      TOIN,FETCH      ;   >IN @
                        dq      TOMAX,FETCH     ;   >MAX @
                        dq      LTINT           ;   <
                        ; if not, jump to continue
                        dq      CONDJUMP,.cont  ;   ?JUMP[.cont]
                        ; read a new block
                        dq      PADREAD         ;   PADREAD
                        ; check if the block size is zero
                        dq      TOMAX,FETCH     ;   >MAX @
                        dq      NEZEROINT       ;   <>0
                        ; if not, skip the following block
                        dq      CONDSKIP,3      ;   ?SKIP[+3]
                        ; otherwise, push a -1 and exit
                        dq      LIT,-1          ;   -1
                        dq      EXIT            ;   EXIT
                        ; fetch a character at the input position
                        ; then advance input position
.cont                   dq      TOIN,FETCH      ;   >IN @
                        dq      PAD,ADDINT      ;   PAD +
                        dq      CHARFETCH       ;   C@
                        dq      TOIN,INCR       ;   >IN INCR
                        ; ( char )
                        dq      EXIT

                        ; read a word from input into NAME buffer ( -- )
                        DEFCOL  "WORD",READWORD,0
                        ; clear name length
                        dq      LIT,0           ;   0
                        dq      PUSHNAME        ;   NAME
                        dq      CHARSTORE       ;   C@
                        ; read a character from the PAD
.nextchar               dq      PADGETCH,DUP    ;   PADGETCH DUP
                        dq      LIT,-1,EQINT    ;   -1 =
                        dq      CONDSKIP,7      ;   ?SKIP[+7]
                        ; ( char )
                        ; compare it to one of the terminator characters
                        ; (SPC, TAB, NEWLINE, NUL)
                        dq      DUP,ISSPC,BINNOT ;  DUP ?SPC NOT
                        dq      CONDSKIP,5      ;   ?SKIP[+5]
                        ; decrement character position for PAD
                        dq      TOIN,DECR       ;   >IN DECR
                        ; end
                        dq      DROP            ;   DROP (char)
                        dq      PUSHNAME        ;   leave NAME address
                        dq      EXIT
                        ; ( char )
                        ; increment name length and leave a copy of it
                        dq      PUSHNAME,DUP,CINCR  ; NAME DUP CINCR
                        dq      CHARFETCH       ;   C@
                        ; ( char count )
                        ; store the character into the new position
                        dq      PUSHNAME,ADDINT ;   NAME +
                        dq      CHARSTORE       ;   C!
                        ; ( )
                        ; read the count back
                        dq      PUSHNAME,CHARFETCH ;    NAME C@
                        ; ( count )
                        ; compare it to 31
                        ; if not reached, jump back to beginning
                        ; (i.e. check input position)
                        dq      LIT,31          ;   31
                        dq      LTINT           ;   <
                        dq      CONDJUMP,.nextchar  ; ?JUMP[.nextchar]
                        ; done
                        dq      PUSHNAME        ;   leave NAME address
                        dq      EXIT

                        ; check if a definition matches the current NAME
                        ; ( defptr -- bool )
                        DEFASM  "?MATCHDEF",MATCHDEF,0
                        CHKUNF  1
                        mov     rax,[r15]
                        lea     rsi,[rax+8]     ; beginning of name field in def
                        lea     rdi,[rbp-NAME]  ; NAME buffer
                        cld
                        ; load length from definition
                        lodsb   ; al = [rsi]+
                        and     al,0x1f ; length is low 5 bits
                        ; compare with length in NAME field
                        cmp     al,[rdi]
                        jne     .false
                        inc     rdi
                        ; same length: compare strings
                        movzx   rcx,al
                        jrcxz   .true
                        repe    cmpsb
                        jne     .false
.true                   xor     rax,rax
                        not     rax
                        mov     [r15],rax
                        NEXT
.false                  xor     rax,rax
                        mov     [r15],rax
                        NEXT

                        ; find word in NAME buffer in dictionary
                        ; ( -- addr )
                        ; if not found, returns a NULL pointer
                        DEFCOL  "FIND",FINDWORD,0
                        ; get LATEST variable onto the stack
                        dq      TOLATEST,FETCH  ;   >LATEST @
                        ; ( defptr )
                        ; see if the current definition matches the
                        ; word in NAME.
.next                   dq      DUP,MATCHDEF    ;   DUP ?MATCHDEF
                        dq      CONDJUMP,.done  ;   ?JUMP[.done]
                        ; doesn't match: move to previous definition
                        dq      FETCH           ;   @
                        ; ( defptr )
                        ; check if entries are used up
                        dq      DUP,EQZEROINT   ;   DUP =0
                        dq      CONDJUMP,.done  ;   ?JUMP[.done]
                        ; nope, compare ->
                        dq      JUMP,.next      ;   JUMP[.next]
                        ; ( defptr )
.done                   dq      EXIT

                        ; check BASE
                        DEFASM  "CHECKBASE",CHECKBASE,0
                        mov     rax,[rbp-BASE]
                        cmp     rax,2
                        jl      .badbase
                        cmp     rax,36
                        jle     .baseok
.badbase                call    fvm_badbase
                        mov     rax,10
                        mov     [rbp-BASE],rax
.baseok                 NEXT

                        ; initialize numeric conversion
                        ;   ( -- addr len )
                        DEFCOL  "INITNCONV",INITNCONV,0
                        dq      CHECKBASE           ;   CHECKBASE
                        dq      NAME,DUP,CHARFETCH  ;   NAME DUP C@
                        ;   ( addr len )
                        dq      SWAP,ADDONE,SWAP    ;   SWAP +1 SWAP
                        ;   ( addr len )
                        dq      EXIT

                        ; get a character for numeric conversion
                        ;   ( addr len -- addr len char )
                        ; on error, the character will be -1
                        DEFCOL  "CGETNCONV",CGETNCONV,0
                        dq      DUP,EQZEROINT       ;   DUP =0
                        dq      CONDJUMP,.nochar    ;   ?JUMP[.nochar]
                        ;   ( addr len )
                        dq      SWAP,DUP,CHARFETCH  ;   SWAP DUP C@
                        ;   ( len addr char )
                        dq      ROT                 ;   ROT
                        ;   ( addr char len )
                        dq      SUBONE              ;   -1
                        dq      ROT                 ;   ROT
                        ;   ( char len addr )
                        dq      ADDONE              ;   +1
                        dq      SWAP                ;   SWAP
                        ;   ( char addr len )
                        dq      ROT
                        ;   ( addr len char )
                        dq      EXIT
.nochar                 dq      LIT,-1              ;   -1
                        dq      EXIT

                        ; convert a character to a digit using the
                        ; current number BASE
                        ;   ( char -- char digit )
                        ; digit will be -1 upon error
                        ; the original character remains to allow detection
                        ; of the cause of the error
                        DEFASM  "DIGIT",DIGIT,0
                        CHKUNF  1
                        CHKOVF  1
                        mov     rax,[r15]
                        cmp     rax,-1
                        je      .enddigit2
                        cmp     al,'0'
                        jb      .nodigit
                        cmp     al,'9'
                        ja      .beyondnine
                        sub     al,'0'
                        jmp     .enddigit
.beyondnine             cmp     al,'A'
                        jb      .nodigit
                        cmp     al,'Z'
                        ja      .beyondZ
                        sub     al,'A'
                        add     al,10
                        jmp     .enddigit
.beyondZ                cmp     al,'a'
                        jb      .nodigit
                        cmp     al,'z'
                        ja      .nodigit
                        sub     al,'a'
                        add     al,10
.enddigit               cmp     rax,[rbp-BASE]
                        jae     .nodigit
                        jmp     .enddigit2
.nodigit                mov     rax,-1
.enddigit2              sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; if possible, go back one char
                        ; ( addr len )
                        DEFCOL  "BACKNCONV",BACKNCONV,0
                        dq      SWAP,DUP            ;   SWAP DUP
                        ; ( len addr addr )
                        dq      PUSHNAME,ADDONE     ;   NAME +1
                        ; ( len addr addr name1 )
                        dq      EQINT               ;   =
                        ; ( len addr bool )
                        dq      CONDJUMP,.abort     ;   ?JUMP[.abort]
                        ; all ok
                        ; decrement addr and increment length
                        dq      SUBONE,SWAP,ADDONE  ;   -1 SWAP +1
                        ; ( addr len )
                        dq      EXIT
                        ; ( len addr )
.abort                  dq      SWAP,EXIT           ;   SWAP

                        ; rotate stack similar to ROT, but with a
                        ; specifiable length. 3 ROLL is same as ROT
                        ; a zero value of N or value of 1 does nothing.
                        ; a negative value of N rotates in the opposite
                        ; direction.
                        ; ( n1 .. nN +N -- n2 .. nN n1   )  N > 0
                        ; ( n1 .. nN -N -- nN n1 .. nN-1 )  N < 0
                        DEFASM  "ROLL",ROLL,0
                        CHKUNF  1
                        mov     rcx,[r15]
                        add     r15,8
                        jrcxz   .noop
                        cmp     rcx,0
                        jl      .negative
                        dec     rcx
                        jrcxz   .noop
                        CHKUNF  rcx
                        ; example 3 ROLL (ROT) :
                        ; [r15+16] [r15+8] [r15]
                        ;    rsi
                        ;    rdi
                        lea     rsi,[r15+rcx*8]
                        mov     rdi,rsi
                        cld
                        lodsq
                        ; rax = [r15+16]
                        ; [r15+16] [r15+8] [r15]
                        ;            rsi
                        ;    rdi
                        rep     movsq
                        ; with rcx = 2:
                        ; [r15+16] [r15+8] [r15]
                        ;                         rsi
                        ; [r15+8] [r15] [r15]
                        ;                rdi
                        stosq
                        ; [r15+8] [r15] [r15+16]
                        ;                         rdi
.noop                   NEXT
                        ; count is negative, turn it to positive
                        ; then subtract 1
.negative               neg     rcx
                        dec     rcx
                        jrcxz   .noop
                        CHKUNF  rcx
                        ; example -3 ROLL :
                        ; [r15+16] [r15+8] [r15]
                        ;                   rsi
                        ;                   rdi
                        mov     rsi,r15
                        mov     rdi,rsi
                        std
                        lodsq
                        ; rax = [r15]
                        ; [r15+16] [r15+8] [r15]
                        ;            rsi
                        ;                   rdi
                        rep     movsq
                        ;        [r15+16] [r15+8] [r15]
                        ;  rsi
                        ;        [r15+16] [r15+16] [r15+8]
                        ;          rdi
                        stosq
                        ;        [r15] [r15+16] [r15+8]
                        ;  rdi
                        cld
                        NEXT

                        ; convert a digit sequence to a number,
                        ; returning its value and number of digits
                        ; ( addr len -- addr len numdig value )
                        ; on error, both values will be zero
                        DEFCOL  "DSEQNCONV",DSEQNCONV,0
                        ; get first char
                        dq      CGETNCONV       ;   CGETNCONV
                        ; ( addr len char )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.badlead   ; ?JUMP[.badlead]
                        ; convert to digit
                        dq      DIGIT               ; DIGIT
                        ; ( addr len char digit )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.badlead2  ; ?JUMP[.badlead2]
                        ; ok starts with a digit; this becomes the
                        ; value field
                        ; ( addr len char value )
                        ; get rid of the char
                        dq      SWAP,DROP           ; SWAP DROP
                        ; ( addr len value )
                        ; rotate stack to move value down
                        dq      ROT
                        ; ( len value addr )
                        dq      ROT
                        ; ( value addr len )
                        ; read next char
.nextchar               dq      CGETNCONV       ;   CGETNCONV
                        ; ( value addr len char )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.finish    ; ?JUMP[.finish]
                        ; convert to digit
                        dq      DIGIT               ; DIGIT
                        ; ( value addr len char digit )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.finish2   ; ?JUMP[.finish2]
                        ; have a valid digit: drop char
                        dq      SWAP,DROP           ; SWAP DROP
                        ; ( value addr len digit )
                        dq      LIT,4,ROLL          ; 4 ROLL
                        ; ( addr len digit value )
                        dq      PUSHBASE,FETCH      ; BASE @
                        ; ( addr len digit value base )
                        dq      MULINT,ADDINT       ; * +
                        ; ( addr len newvalue )
                        dq      ROT                 ; ROT
                        ; ( len newvalue addr )
                        dq      ROT                 ; ROT
                        ; ( newvalue addr len )
                        dq      JUMP,.nextchar      ; JUMP[.nextchar]
                        ; not digit: back up one char
                        ; ( value addr len char digit )
                        ; get rid of digit and char
.finish2                dq      DROP,DROP           ; DROP DROP
                        ; ( value addr len )
                        ; go back one character
                        dq      BACKNCONV           ; BACKNCONV
                        ; ( value addr len )
                        ; get value on top
.finish                 dq      ROT                 ; ROT
                        ; ( addr len value )
                        ; get address on stack
                        dq      LIT,3,PICK          ; 3 PICK
                        ; ( addr len value addr )
                        ; compute number of digits
                        dq      PUSHNAME,ADDONE     ; NAME +1
                        dq      SUBINT              ; -
                        ; ( addr len value numdigits )
                        dq      SWAP
                        ; ( addr len numdigits value )
                        dq      EXIT
                        ; bad leading char:
                        ; ( addr len char digit )
.badlead2               dq      DROP                ; DROP
                        ; ( addr len char )
.badlead                dq      DROP                ; DROP
                        ; ( addr len )
                        dq      LIT,0,LIT,0         ; 0 0
                        ; ( addr len 0 0 )
                        dq      EXIT

                        ; convert a signed digit sequence to a number
                        ; returning its value and number of digits
                        ; ( addr len -- addr len numdig value )
                        ; on error, both values will be zero
                        DEFCOL  "SSEQNCONV",SSEQNCONV,0
                        ; ( addr len )
                        dq      CGETNCONV           ; CGETNCONV
                        ; ( addr len char )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.badlead   ; ?JUMP[.badlead]
                        ; check for sign ('-' or '+')
                        dq      DUP,LIT,'-',EQINT   ; DUP '-' =
                        dq      CONDJUMP,.negative  ; ?JUMP[.negative]
                        dq      DUP,LIT,'+',EQINT   ; DUP '+' =
                        dq      CONDJUMP,.positive  ; ?JUMP[.positive]
                        ; neither, go back one character
                        ; ( addr len char )
                        dq      DROP,BACKNCONV      ; DROP BACKNCONV
                        ; ( addr len )
                        ; push a positive sign and continue
                        dq      LIT,1               ; 1
                        dq      JUMP,.continue      ; JUMP[.continue]
                        ; ( addr len char )
                        ; push a negative sign and continue
.negative               dq      DROP,LIT,-1         ; DROP -1
                        dq      JUMP,.continue      ; JUMP[.continue]
.positive               dq      DROP,LIT,1          ; DROP 1
                        ; ( addr len sign )
                        ; rotate to get sign to the bottom
.continue               dq      ROT                 ; ROT
                        ; ( len sign addr )
                        dq      ROT                 ; ROT
                        ; ( sign addr len )
                        ; convert remainder to digit sequence
                        dq      DSEQNCONV           ; DSEQNCONV
                        ; ( sign addr len numdigits value )
                        ; check numdigits value
                        dq      LIT,2,PICK,EQZEROINT ; 2 PICK =0
                        dq      CONDJUMP,.convfail  ; ?JUMP[.convfail]
                        ; looking good
                        ; ( sign addr len numdigits value )
                        ; roll the stack to get sign on top
                        dq      LIT,5,ROLL          ; 5 ROLL
                        ; ( addr len numdigits value sign )
                        ; multiply sign and value
                        dq      MULINT              ; *
                        ; ( addr len numdigits newvalue )
                        ; done!
                        dq      EXIT
                        ; ( sign addr len numdigits value )
                        ; conversion failure:
                        ; get rid of value and numdigits
.convfail               dq      DROP,DROP           ; DROP DROP
                        ; ( sign addr len )
                        ; rotate to get the sign in front then drop it
                        dq      ROT
                        ; ( addr len sign )
                        ; same
                        ; ( addr len char )
.badlead                dq      DROP                ; DROP
                        ; ( addr len )
                        dq      LIT,0,LIT,0         ; 0 0
                        ; ( addr len 0 0 )
                        dq      EXIT

                        ; convert number in floating-point fields
                        ; to actual floating-point and return it
                        ; ( -- number bool )
                        DEFASM  "GETREAL",GETREAL,0
                        CHKOVF  2
                        ; compute BASE to the power of exponent
                        mov     rdi,[rbp-BASE]
                        mov     rsi,[rbp-EXPONENT]
                        call    _fpowl
                        ; multiply the result with the mantissa
                        push    rax
                        fld     qword [rsp]
                        pop     rax
                        fld     qword [rbp-MANTISSA]
                        fmulp
                        ; st0 = mantissa * ( BASE ^ exponent )
                        ; compute the fraction by 1 / ( BASE ^ fracndig )
                        fld1
                        mov     rdi,[rbp-BASE]
                        mov     rsi,[rbp-FRACNDIG]  ; integer
                        ; convert FRACNDIG to floating-point
                        push    rsi
                        fild    qword [rsp]
                        fstp    qword [rsp]
                        pop     rsi
                        ; computer power BASE ^ fracndig
                        call    _fpowl
                        push    rax
                        fld     qword [rsp]
                        pop     rax
                        ; st2 = mantissa * ( BASE ^ exponent )
                        ; st1 = 1
                        ; st0 = BASE ^ fracndig
                        ; compute 1 / ( BASE ^ fracndig )
                        fdivp
                        ; st1 = mantissa * ( BASE ^ exponent )
                        ; st0 = 1 / ( BASE ^ fracndig )
                        ; add fraction to result
                        faddp
                        ; output result
                        sub     r15,16
                        fstp    qword [r15+8] ; result
                        xor     rax,rax
                        not     rax
                        mov     [r15],rax   ; true
                        NEXT

                        ; convert number in NAME using BASE
                        ; ( -- number bool )
                        DEFCOL  "?MATCHNUM",MATCHNUM,0
                        ; initialize numeric conversion
                        dq      INITNCONV           ; INITNCONV
                        ; ( addr len )
                        ; attempt to convert the leading characters
                        ; into a signed number
                        dq      SSEQNCONV           ; SSEQNCONV
                        ; ( addr len numdigits value )
                        ; check numdigits for 0
                        dq      LIT,2,PICK,EQZEROINT ; 2 PICK =0
                        dq      CONDJUMP,.convfail2  ; ?JUMP[.convfail2]
                        ; ( addr len numdigits value )
                        ; store the value into the mantissa
                        ; and drop the numdigits field
                        dq      TOMANTISSA,STORE    ; >MANTISSA !
                        dq      DROP                ; DROP
                        ; clear fraction and exponent
                        dq      LIT,0               ; LIT 0
                        dq      DUP,TOFRACTION,STORE ; DUP >FRACTION !
                        dq      DUP,TOFRACNDIG,STORE ; DUP >FRACNDIG !
                        dq      TOEXPONENT,STORE    ; >EXPONENT !
                        ; ( addr len )
                        ; See if the following character introduces a fraction
                        ; or exponent. Only if there's no more characters right
                        ; now, it's an integer. Otherwise, it's a conversion
                        ; error, if there's no fraction or exponent.
                        dq      CGETNCONV           ; CGETNCONV
                        ; ( addr len char )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.integer   ; ?JUMP[.integer]
                        ; ( addr len char )
                        dq      DUP,LIT,'.',EQINT   ; DUP '.' =
                        dq      CONDJUMP,.fraction  ; ?JUMP[.fraction]
                        dq      DUP,LIT,'e',EQINT   ; DUP 'e' =
                        dq      CONDJUMP,.exponent  ; ?JUMP[.exponent]
                        dq      DUP,LIT,'E',EQINT   ; DUP 'E' =
                        dq      CONDJUMP,.exponent  ; ?JUMP[.exponent]
                        dq      DUP,LIT,"'",EQINT   ; DUP "'" =
                        dq      CONDJUMP,.exponent  ; ?JUMP[.exponent]
                        ; neither: this means conversion error
                        ; drop the character, length and address
.convfail               dq      DROP                ; DROP
                        ; ( addr len )
.convfail3              dq      DROP,DROP           ; DROP DROP
                        ; ( )
                        ; push 0 0 as number/bool
.convfail4              dq      LIT,0,LIT,0         ; 0 0
                        ; ( 0 0 )
                        dq      EXIT
                        ; conversion error from fraction
                        ; ( addr len numdigits value )
.convfail2              dq      DROP                ; DROP
                        dq      JUMP,.convfail      ; JUMP[.convfail]
                        ; integer case
                        ; ( addr len char )
                        ; drop the character, length and address
.integer                dq      DROP,DROP,DROP      ; DROP DROP DROP
                        ; ( )
                        ; push number and true
                        dq      TOMANTISSA,FETCH    ; >MANTISSA @
                        dq      LIT,-1              ; -1
                        dq      EXIT
                        ; fraction case:
                        ; ( addr len char )
                        ; drop the character
.fraction               dq      DROP                ; DROP
                        ; ( addr len )
                        ; get unsigned number as fraction digits
                        dq      DSEQNCONV           ; DSEQNCONV
                        ; ( addr len numdigits value )
                        ; check the numdigits
                        dq      LIT,2,PICK,EQZEROINT ; 2 PICK =0
                        dq      CONDJUMP,.convfail2  ; ?JUMP[.convfail2]
                        ; ( addr len numdigits value )
                        ; we are all go, set the variables
                        dq      TOFRACTION,STORE    ; >FRACTION !
                        dq      TOFRACNDIG,STORE    ; >FRACNDIG !
                        ; ( addr len )
                        ; now we have to check whether there's an
                        ; exponent being introduced (if not, it's OK)
                        dq      CGETNCONV           ; CGETNCONV
                        ; ( addr len char )
                        dq      DUP,LIT,-1,EQINT    ; DUP -1 =
                        dq      CONDJUMP,.floatingpoint ; ?JUMP[.floatingpoint]
                        ; ( addr len char )
                        dq      DUP,LIT,'e',EQINT   ; DUP 'e' =
                        dq      CONDJUMP,.exponent  ; ?JUMP[.exponent]
                        dq      DUP,LIT,'E',EQINT   ; DUP 'E' =
                        dq      CONDJUMP,.exponent  ; ?JUMP[.exponent]
                        dq      DUP,LIT,"'",EQINT   ; DUP "'" =
                        dq      CONDJUMP,.exponent  ; ?JUMP[.exponent]
                        ; unrecognized character means conversion error
                        dq      JUMP,.convfail      ; ?JUMP[.convfail]
                        ; ( addr len char )
                        ; if we have an exponent:
                        ; drop the character
.exponent               dq      DROP                ; DROP
                        ; ( addr len )
                        ; read a signed number
                        dq      SSEQNCONV           ; SSEQNCONV
                        ; ( addr len numdigits value )
                        ; check the numdigits
                        dq      LIT,2,PICK,EQZEROINT ; 2 PICK =0
                        dq      CONDJUMP,.convfail2  ; ?JUMP[.convfail2]
                        ; seems valid, store the exponent, drop numdigits
                        dq      TOEXPONENT,STORE    ; >EXPONENT !
                        dq      DROP                ; DROP
                        ; ( addr len )
                        ; there should be no more characters now
                        dq      DUP,EQZEROINT       ; DUP =0
                        dq      CONDJUMP,.convfail3 ; ?JUMP[.convfail3]
                        ; otherwise, we're finished reading a
                        ; floating-point number
                        ; ( addr len )
                        dq      JUMP,.floatingpoint2 ; JUMP[.floatingpoint2]
                        ; ( addr len char )
                        ; drop fields
.floatingpoint          dq      DROP
.floatingpoint2         dq      DROP,DROP
                        ; ( )
                        ; convert to real number and push it and the truth value
                        dq      GETREAL
                        ; ( number bool )
                        dq      EXIT

                        section .rodata

                        align   8
fvm_last_sysword        dq      LINKBACK

                        section .note.GNU-stack

