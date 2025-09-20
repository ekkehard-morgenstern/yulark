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

                        DEFASM  "F+",ADDFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        faddp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F-",SUBFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fsubp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F*",MULFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fmulp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F/",DIVFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fdivp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "FMOD",MODFLT,0
                        CHKUNF  2
                        fld     qword [r15]     ; st1
                        fld     qword [r15+8]   ; st0
                        xor     rax,rax
                        push    rax
.repeat                 fprem1              ; compute partial remainder
                        fstcw   word [rsp]  ; get FPU status word
                        mov     ax,[rsp]
                        and     ax,0x0400   ; test C2 FPU flag
                        jnz     .repeat     ; loop until zero
                        pop     rax
                        add     r15,8
                        fstp    qword [r15]
                        ffree   st0
                        fincstp
                        NEXT

                        DEFASM  "FCOMP",COMPFLT,0
                        CHKUNF  2
                        fld     qword [r15+8]   ; st0
                        fcomp   qword [r15]     ; cmp st0,src
                        xor     rax,rax
                        push    rax
                        fstcw   word [rsp]      ; get FPU status word
                        pop     rax
                        and     ax,0x4500
                        jz      .grt
                        cmp     ax,0x0100
                        je      .lwr
                        cmp     ax,0x4000
                        je      .eql
                        mov     rax,-2          ; indicate error
                        jmp     .end
.grt                    mov     rax,1           ; greater
                        jmp     .end
.lwr                    mov     rax,-1          ; lower
                        jmp     .end
.eql                    mov     rax,0           ; equal
.end                    add     r15,8
                        mov     [r15],rax
                        NEXT

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
.nextchar               dd      TOIN,FETCH      ;   >IN @
                        dd      TOMAX,FETCH     ;   >MAX @
                        dd      LTINT           ;   <
                        ; if not, jump to continue
                        dd      CONDJUMP,.cont  ;   ?JUMP[.cont]
                        ; read a new block
                        dd      PADREAD         ;   PADREAD
                        ; check if the block size is zero
                        dd      TOMAX,FETCH     ;   >MAX @
                        dd      NEZEROINT       ;   <>0
                        ; if not, skip the following block
                        dd      CONDSKIP,3      ;   ?SKIP[+3]
                        ; otherwise, push a -1 and exit
                        dd      LIT,-1          ;   -1
                        dd      EXIT            ;   EXIT
                        ; fetch a character at the input position
                        ; then advance input position
.cont                   dd      TOIN,FETCH      ;   >IN @
                        dd      PAD,ADDINT      ;   PAD +
                        dd      CHARFETCH       ;   C@
                        dd      TOIN,INCR       ;   >IN INCR
                        ; ( char )
                        dd      EXIT

                        ; read a word from input into NAME buffer ( -- )
                        DEFCOL  "WORD",READWORD,0
                        ; clear name length
                        dd      LIT,0           ;   0
                        dd      PUSHNAME        ;   NAME
                        dd      CHARSTORE       ;   C@
                        ; read a character from the PAD
.nextchar               dd      PADGETCH,DUP    ;   PADGETCH DUP
                        dd      LIT,-1,EQINT    ;   -1 =
                        dd      CONDSKIP,7      ;   ?SKIP[+7]
                        ; ( char )
                        ; compare it to one of the terminator characters
                        ; (SPC, TAB, NEWLINE, NUL)
                        dd      DUP,ISSPC,BINNOT ;  DUP ?SPC NOT
                        dd      CONDSKIP,5      ;   ?SKIP[+5]
                        ; decrement character position for PAD
                        dd      TOIN,DECR       ;   >IN DECR
                        ; end
                        dd      DROP            ;   DROP (char)
                        dd      PUSHNAME        ;   leave NAME address
                        dd      EXIT
                        ; ( char )
                        ; increment name length and leave a copy of it
                        dd      PUSHNAME,DUP,CINCR  ; NAME DUP CINCR
                        dd      CHARFETCH       ;   C@
                        ; ( char count )
                        ; store the character into the new position
                        dd      PUSHNAME,ADDINT ;   NAME +
                        dd      CHARSTORE       ;   C!
                        ; ( )
                        ; read the count back
                        dd      PUSHNAME,CHARFETCH ;    NAME C@
                        ; ( count )
                        ; compare it to 31
                        ; if not reached, jump back to beginning
                        ; (i.e. check input position)
                        dd      LIT,31          ;   31
                        dd      LTINT           ;   <
                        dd      CONDJUMP,.nextchar  ; ?JUMP[.nextchar]
                        ; done
                        dd      PUSHNAME        ;   leave NAME address
                        dd      EXIT

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
                        dd      TOLATEST,FETCH  ;   >LATEST @
                        ; ( defptr )
                        ; see if the current definition matches the
                        ; word in NAME.
.next                   dd      DUP,MATCHDEF    ;   DUP ?MATCHDEF
                        dd      CONDJUMP,.done  ;   ?JUMP[.done]
                        ; doesn't match: move to previous definition
                        dd      FETCH           ;   @
                        ; ( defptr )
                        ; check if entries are used up
                        dd      DUP,EQZEROINT   ;   DUP =0
                        dd      CONDJUMP,.done  ;   ?JUMP[.done]
                        ; nope, compare ->
                        dd      JUMP,.next      ;   JUMP[.next]
                        ; ( defptr )
.done                   dd      EXIT

                        ; convert number in NAME using BASE
                        ; ( -- number bool )
                        DEFASM  "?MATCHNUM",MATCHNUM,0
                        CHKOVF  2
.retry                  mov     rax,[rbp-BASE]
                        cmp     rax,2
                        jl      .badbase
                        cmp     rax,36
                        jle     .baseok1
.badbase                call     fvm_badbase
                        mov     rax,10
                        mov     [rbp-BASE],rax
                        jmp     .retry
.baseok1                jmp     .baseok2
.zerolen                sub     r15,16
                        xor     rax,rax
                        mov     [r15+8],rax ; number = 0
                        mov     [r15],rax   ; bool = false
                        NEXT
                        ; subroutine to get the next char
.nextchar               jrcxz   .nochar
                        lodsb
                        dec     rcx
                        movzx   rax,al
                        ret
.nochar                 xor     rax,rax
                        not     rax
                        ret
                        ; subroutine to get the next digit
.nextdigit              call    .nextchar
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
.enddigit2              ret
                        ; subroutine to back up one character
.backuponechar          dec     rsi
                        inc     rcx
                        ret
                        ; get name length
.baseok2                lea     rsi,[rbp-NAME]
                        cld
                        lodsb
                        ; set counter, stop if zero
                        mov     cl,al
                        movzx   rcx,cl
                        jrcxz   .zerolen2
                        jmp     .nonzerolen
.zerolen2               jmp     .zerolen
                        ; scan for '.' character
.nonzerolen             mov     rdi,rsi
                        mov     al,'.'
                        mov     rdx,rcx
                        repne   scasb
                        jne     .notfloat
                        ; floating-point conversion
                        ; not implemented at this time
                        jmp     .dofloat
                        ; integer conversion
                        ; read first character to see if it's a sign
.notfloat               mov     rcx,rdx
                        mov     r8,1        ; sign = positive
                        call    .nextchar
                        cmp     rax,-1
                        je      .zerolen2
                        cmp     al,'-'
                        je      .negative
                        cmp     al,'+'
                        je      .readint
                        call    .backuponechar
                        jmp     .readint
.negative               neg     r8          ; sign = negative
                        ; read first digit
.readint                call    .nextdigit
                        cmp     rax,-1
                        je      .zerolen2
                        mov     r9,rax      ; r9 = result
                        ; read follow-up digits
.readint2               call    .nextdigit
                        cmp     rax,-1
                        je      .readintend
                        xchg    r9,rax      ; r9=digit, rax=result
                        mul     qword [rbp-BASE]    ; * BASE
                        add     r9,rax      ; r9 += result*BASE
                        jmp     .readint
.readintend             mov     rax,r9      ; rax=result*r8 (r8=sign)
                        imul    r8
                        sub     r15,16
                        mov     [r15+8],rax ; number = result
                        mov     rax,-1
                        mov     [r15],rax   ; bool = true
                        NEXT
.zerolen3               jmp     .zerolen
                        ; floating-point conversion
                        ; read first character to see if it's a sign
.dofloat                mov     rcx,rdx
                        mov     r8,1    ; sign = positive
                        call    .nextchar
                        cmp     rax,-1
                        je      .zerolen3
                        cmp     al,'-'
                        je      .negative2
                        cmp     al,'+'
                        je      .readfloat
                        call    .backuponechar
                        jmp     .readfloat
.negative2              neg     r8      ; sign = negative
.readfloat              mov     r10,0   ; has fraction
                        mov     r11,0   ; exponent
                        call    .nextchar
                        cmp     rax,-1
                        je      .zerolen3
                        cmp     al,'.'
                        jne     .notdot
                        ; begins with '.'
                        mov     r10,1   ; has fraction = 1
                        jmp     .readfloat2
.notdot                 call    .backuponechar
                        ; read first digit
                        call    .nextdigit
                        cmp     rax,-1
                        je      .zerolen3
                        mov     r9,rax
                        ; read follow-up digits
.readfloat2             call    .nextchar
                        cmp     rax,-1
                        je      .floatend
                        cmp     al,'.'
                        jne     .notdot2
                        ; contains '.'
                        mov     r10,1   ; has fraction = 1
                        jmp     .readfloat2
.notdot2                call    .backuponechar
                        call    .nextdigit
                        cmp     rax,-1
                        je      .floatend
                        xchg    r9,rax      ; r9=digit, rax=result
                        mul     qword [rbp-BASE]    ; * BASE
                        add     r9,rax      ; r9 += result*BASE
                        test    r10,r10
                        jz      .readfloat2
                        dec     r11         ; decrease exponent (BASE^x)
                        jmp     .readfloat2
                        ; add sign
.floatend               mov     rax,r9      ; rax=result*r8 (r8=sign)
                        imul    r8
                        ; store mantissa for later
                        mov     [rbp-MANTISSA],rax
                        ; clear sign and value
                        xor     r8,r8
                        xor     r9,r9
                        ; check if there is another character that indicates
                        ; exponent notation. this will be either E e or '.






                        jmp     fvm_notimpl




                        section .rodata

                        align   8
fvm_last_sysword        dq      LINKBACK
