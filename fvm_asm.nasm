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
                        extern      isatty

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
                        ; read the next word address from the word pointer
                        ; then increment the word pointer
                        mov     r12,[r13]   ; WA := [WP]+
                        add     r13,8
                        ; load the "codeword" entry from the word definition
                        ; (which is a runnable piece of assembly code, whose
                        ; address is stored just beneath the word definition's
                        ; name area). this also means that the program will
                        ; crash here if the address is invalid.
                        ; see also the definition of DEFASM/DEFCOL below.
                        jmp     qword [r12]   ; JUMP [WA]
                        %endmacro

                        ; code is ideally aligned on 32-byte boundary
                        align   32

                        ; rdi - memory block
                        ; rsi - memory size
                        ; rdx - return stack size
fvm_run                 enter   0x508,0     ; n bytes of local storage

                        ; rbp-0x100     beginning of 256 bytes PAD space
%define PAD             0x100
                        ; rbp-0x120     beginning of 32 bytes of NAME space
%define NAME            0x120

                        ; rbp-0x150     return stack upper bound
%define RSTKUPR         0x150
                        ; rbp-0x158     return stack lower bound
%define RSTKLWR         0x158
                        ; rbp-0x160     stack pointer before CALLC
%define CALLSTKP        0x160
                        ; rbp-0x168     address of C function for CALLC
%define CALLADDR        0x168
                        ; rbp-0x170     number of arguments to CALLC
%define CALLARGS        0x170
                        ; rbp-0x178     address origin (used by DSEQNCONV)
%define ADDRESS0        0x178
                        ; rbp-0x180     RSP reset address
%define RSPRESET        0x180
                        ; rbp-0x188     system memory size (read-only)
%define MEMSIZE         0x188
                        ; rbp-0x190     system memory address (read-only)
%define MEMADDR         0x190
                        ; rbp-0x198     is in immediate mode
%define ISIMMED         0x198
                        ; rbp-0x1a0     is in compile mode
%define ISCOMP          0x1a0
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
                        ; rbp-0x300     buffer for . subroutine
%define DOTBUF          0x300
                        ; rbp-0x400     preparation buffer for F.
%define PREPBUF         0x400
                        ; rbp-0x500     preparation buffer for F.
%define PREPBUF2        0x500

                        push    r15
                        push    r14
                        push    r13
                        push    r12
                        push    rbx

                        ; set up RSP
                        ; in the beginning, it points just beyond the end of
                        ; the available memory area.
                        mov     r14,rdi
                        add     r14,rsi

                        ; save the memory area's address and size
                        mov     [rbp-MEMADDR],rdi
                        mov     [rbp-MEMSIZE],rsi

                        ; set up PSP
                        ; create the parameter stack pointer by subtracting the
                        ; return stack size from the return stack pointer.
                        ; this will also become the parameter stack's upper
                        ; limit.
                        mov     r15,r14
                        sub     r15,rdx
                        mov     [rbp-STKUPR],r15

                        ; set the return stack lower bound (which is the same)
                        mov     [rbp-RSTKLWR],r15

                        ; record the return stack upper bound
                        mov     [rbp-RSTKUPR],r14

                        ; push QUIT on the return stack so the last EXIT
                        ; will execute that
                        sub     r14,8
                        lea     rax,_QUIT
                        mov     [r14],rax

                        section .rodata
                        global  _QUIT
                        align   8
_QUIT                   dq      QUIT

                        section .text

                        ; store RSP in the RSPRESET field
                        mov     [rbp-RSPRESET],r14

                        ; set up DP
                        ; the dictionary pointer grows forward in memory and
                        ; simply points to be beginning of the memory area.
                        mov     rbx,rdi

                        ; the middle between PSP and DP is the stack lower bound
                        mov     rax,r15
                        sub     rax,rbx
                        shr     rax,1
                        add     rax,rbx
                        mov     [rbp-STKLWR],rax

                        ; set up WP
                        lea     r13,_INTERPRET
                        section .rodata
                        global  _INTERPRET
                        align   8
_INTERPRET              dq      FPUINIT,INTERPRET,EXIT

                        section .text

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

                        ; set immediate mode
                        xor     rax,rax
                        mov     [rbp-ISCOMP],rax
                        not     rax
                        mov     [rbp-ISIMMED],rax

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
                        mov     rdi,2   ; STDERR
                        lea     rsi,%%errtext
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
                        mov     rdi,2   ; STDERR
                        lea     rsi,%%errtext
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

fvm_stkovf              ERREND  "? parameter stack overflow"
fvm_stkunf              ERREND  "? parameter stack underflow"
fvm_rstkovf             ERREND  "? return stack overflow"
fvm_rstkunf             ERREND  "? return stack underflow"
fvm_divzro              ERREND  "? division by zero"
fvm_nofpu               ERREND  "? FPU not found"
fvm_badbase             ERRMSG  "? bad number base, reset to 10"
fvm_notimpl             ERRMSG  "? not implemented"
fvm_nullptr             ERREND  "? NULL pointer"
fvm_unknown             ERREND  "? unknown entity in stream"
fvm_unexpeof            ERREND  "? unexpected end of file"
fvm_notfound            ERREND  "? word not found"
fvm_noparam             ERREND  "? word has no parameter field"
fvm_negallot            ERREND  "? negative allot"

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

                        ; check for return stack overflow
                        %macro  RCHKOVF 1
                        lea     r8,[r14 - (%1 * 8)]
                        cmp     r8,qword [rbp - RSTKLWR]
                        jae     %%okay
                        jmp     fvm_rstkovf
%%okay:
                        %endmacro

                        ; check for return stack underflow
                        %macro  RCHKUNF 1
                        lea     r8,[r14 + (%1 * 8)]
                        cmp     r8,qword [rbp - RSTKUPR]
                        jbe     %%okay
                        jmp     fvm_rstkunf
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
fvm_docol               RCHKOVF 1
                        sub     r14,8       ; -[RSP] := WP
                        mov     [r14],r13
                        lea     r13,[r12+8] ; WP := WA + 1
                        ; begin processing word definition
                        NEXT

%define LINKBACK        0
%define F_IMMEDIATE     0x80    ; immediate mode word, always executed
%define F_HIDDEN        0x20    ; hidden word (don't return with FIND)

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
                        RCHKUNF 1
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

                        DEFASM  "U/",UDIVINT,0
                        CHKUNF  2
                        CHKZRO
                        mov     rax,[r15+8]
                        xor     rdx,rdx         ; zero-extend into rdx
                        div     qword [r15]
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

                        DEFASM  "U*/",UMULDIVINT,0
                        CHKUNF  3
                        CHKZRO
                        mov     rax,[r15+16]
                        mul     qword [r15+8]
                        div     qword [r15]
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

                        ; ( u1 u2 -- result remainder )
                        DEFASM  "U/MOD",UDIVMODINT,0
                        CHKUNF  2
                        CHKZRO
                        mov     rax,[r15+8]
                        xor     rdx,rdx         ; zero-extend into rdx
                        div     qword [r15]
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

                        DEFASM  "UMOD",UMODINT,0
                        CHKUNF  2
                        CHKZRO
                        mov     rax,[r15+8]
                        xor     rdx,rdx         ; zero-extend into rdx
                        div     qword [r15]
                        add     r15,8
                        mov     [r15],rdx
                        NEXT

                        DEFASM  "<0",LTZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        setl    al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<=0",LEZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        setle   al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">0",GTZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        setg    al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "U>0",UGTZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        seta    al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">=0",GEZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        setge   al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "=0",EQZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        sete    al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<>0",NEZEROINT,0
                        CHKUNF  1
                        mov     rax,[r15]
                        xor     rdx,rdx
                        cmp     rax,rdx
                        setne   al
                        neg     al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<",LTINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setl    al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "U<",ULTINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setb    al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<=",LEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setle   al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "U<=",ULEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setbe   al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">",GTINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setg    al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "U>",UGTINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        seta    al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">=",GEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setge   al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "U>=",UGEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setae   al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "=",EQINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        sete    al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<>",NEINT,0
                        CHKUNF  2
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setne   al
                        neg     al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "NEG",NEGATE,0
                        CHKUNF  1
                        neg     qword [r15]
                        NEXT

                        ; ( n -- n )
                        DEFASM  "NOT",BINNOT,0
                        CHKUNF  1
                        not     qword [r15]
                        NEXT

                        ; ( n1 n2 -- n )
                        DEFASM  "AND",BINAND,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        and     [r15],rax
                        NEXT

                        ; ( n1 n2 -- n )
                        DEFASM  "OR",BINOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        or      [r15],rax
                        NEXT

                        ; ( n1 n2 -- n )
                        DEFASM  "XOR",BINXOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        xor     [r15],rax
                        NEXT

                        ; ( n1 n2 -- n )
                        DEFASM  "NAND",BINNAND,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        and     [r15],rax
                        not     qword [r15]
                        NEXT

                        ; ( n1 n2 -- n )
                        DEFASM  "NOR",BINNOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        or      [r15],rax
                        not     qword [r15]
                        NEXT

                        ; ( n1 n2 -- n )
                        DEFASM  "XNOR",BINXNOR,0
                        CHKUNF  2
                        mov     rax,[r15]
                        add     r15,8
                        xor     [r15],rax
                        not     qword [r15]
                        NEXT

                        ; ( addr -- data )
                        DEFASM  "@",FETCH,0
                        CHKUNF  1
                        mov     rax,[r15]
                        mov     rax,[rax]
                        mov     [r15],rax
                        NEXT

                        ; ( data addr -- )
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
                        ; ( n -- nth )
                        DEFASM  "PICK",PICK,0
                        CHKUNF  1
                        mov     rax,[r15]
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

                        ; ( newmode -- oldmode )
                        ; modes:
                        ;   0 - round to nearest (default)
                        ;   1 - round down (toward -inf)
                        ;   2 - round up (towards +inf)
                        ;   3 - round towards zero (truncate)
                        DEFASM  "FRNDMODE",FRNDMODE,0
                        CHKUNF  1
                        ; get new rounding mode (bits 0..1)
                        mov     rax,[r15]
                        and     rax,3
                        shl     ax,10
                        push    rax
                        ; save current settings in top half of rax
                        fstcw   word [rsp+2]
                        ; mask all bits except 10..11 (RC), which are zero
                        mov     dx,word [rsp+2]
                        and     dx,0xf3ff
                        ; or that to the desired settings
                        or      ax,dx
                        ; then write into control register
                        mov     word [rsp],ax
                        fldcw   word [rsp]
                        ; pop rax off the stack
                        pop     rax
                        ; upper half now containes the previous settings
                        ; shift to bit 0..1 and mask off all bits except RC
                        shr     rax,10
                        and     rax,3
                        ; return previous value
                        mov     [r15],rax
                        NEXT

                        ; F2I round-to-nearest
                        ; (same as F2I in default rounding mode)
                        ; ( n -- n )
                        DEFCOL  "F2IN",F2IN,0
                        ; set rounding mode to nearest
                        dq      LIT,0,FRNDMODE      ; 0 FRNDMODE
                        ; ( n oldmode )
                        ; round number
                        dq      SWAP,F2I,SWAP       ; SWAP F2I SWAP
                        ; restore rounding mode
                        dq      FRNDMODE,DROP       ; FRNDMODE DROP
                        dq      EXIT

                        ; F2I round down
                        ; ( n -- n )
                        DEFCOL  "F2ID",F2ID,0
                        ; set rounding mode to nearest
                        dq      LIT,1,FRNDMODE      ; 1 FRNDMODE
                        ; ( n oldmode )
                        ; round number
                        dq      SWAP,F2I,SWAP       ; SWAP F2I SWAP
                        ; restore rounding mode
                        dq      FRNDMODE,DROP       ; FRNDMODE DROP
                        dq      EXIT

                        ; F2I round up
                        ; ( n -- n )
                        DEFCOL  "F2IU",F2IU,0
                        ; set rounding mode to nearest
                        dq      LIT,2,FRNDMODE      ; 2 FRNDMODE
                        ; ( n oldmode )
                        ; round number
                        dq      SWAP,F2I,SWAP       ; SWAP F2I SWAP
                        ; restore rounding mode
                        dq      FRNDMODE,DROP       ; FRNDMODE DROP
                        dq      EXIT

                        ; F2I round-to-zero (truncate)
                        ; ( n -- n )
                        DEFCOL  "F2IT",F2IT,0
                        ; set rounding mode to nearest
                        dq      LIT,3,FRNDMODE      ; 3 FRNDMODE
                        ; ( n oldmode )
                        ; round number
                        dq      SWAP,F2I,SWAP       ; SWAP F2I SWAP
                        ; restore rounding mode
                        dq      FRNDMODE,DROP       ; FRNDMODE DROP
                        dq      EXIT

                        ; round to integer using the current rounding mode
                        ; ( n -- n )
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
.zero                   dq      TWODROP     ; 2DROP
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

                        ; returns the address of the DOT buffer
                        DEFASM  "DOT",PUSHDOT,0
                        CHKOVF  1
                        lea     rax,[rbp-DOTBUF]
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
                        xor     rdx,rdx
                        cmp     rax,rdx
                        jge     .good
                        xor     rax,rax
.good                   mov     [r15],rax
                        NEXT

                        ; read bytes from a system file
                        DEFASM  "SYSREAD",SYSREAD,0
                        CHKUNF  3
                        mov     rdi,[r15+16]    ; file handle
                        mov     rsi,[r15+8]     ; buffer
                        mov     rdx,[r15]       ; count
                        add     r15,16
%define __NR_read       0
                        mov     rax,__NR_read
                        syscall
                        mov     [r15],rax
                        NEXT

                        ; write bytes to a system file
                        ; ( filehnd buffer count -- count )
                        DEFASM  "SYSWRITE",SYSWRITE,0
                        CHKUNF  3
                        mov     rdi,[r15+16]    ; file handle
                        mov     rsi,[r15+8]     ; buffer
                        mov     rdx,[r15]       ; count
                        add     r15,16
                        mov     rax,__NR_write
                        syscall
                        mov     [r15],rax
                        NEXT

                        ; test whether the specified filehandle
                        ; points to a TTY
                        ; ( filehnd -- bool )
                        DEFASM  "SYSISATTY",SYSISATTY,0
                        CHKUNF 1
                        mov     rdi,[r15]
                        xor     al,al
                        call    isatty
                        mov     [r15],rax
                        NEXT

                        ; read entire PAD
                        DEFCOL  "PADREAD",PADREAD,0
                        dq      TOFILE      ; >FILE
                        dq      FETCH       ; @
                        dq      PUSHPAD     ; PAD
                        dq      LIT,256     ; 256
                        ; ( pfile padaddr 256 )
                        dq      SYSREAD     ; SYSREAD
                        ; ( retcode )
                        dq      ERR2ZERO    ; ?ERR0
                        dq      TOMAX       ; >MAX
                        dq      STORE       ; !
                        dq      LIT,0       ; 0
                        dq      TOIN        ; >IN
                        dq      STORE       ; !
                        dq      EXIT

                        ; type text to output
                        ; ( addr n )
                        DEFCOL  "TYPE",TYPEOUT,0
                        dq      TOOUT       ; >OUT
                        dq      FETCH       ; @
                        ; ( addr n ofile )
                        ; ( n ofile addr ) after 1st ROT
                        ; ( ofile addr n ) after 2nd ROT
                        dq      TWOROT      ; 2ROT
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
                        NEXT
.nojump                 add     r13,8
                        NEXT

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
                        inc     qword [rax]
                        add     r15,8
                        NEXT

                        DEFASM  "CINCR",CINCR,0     ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        inc     byte [rax]
                        add     r15,8
                        NEXT

                        DEFASM  "DECR",DECR,0       ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        dec     qword [rax]
                        add     r15,8
                        NEXT

                        DEFASM  "CDECR",CDECR,0     ; ( addr -- )
                        CHKUNF  1
                        mov     rax,[r15]
                        dec     byte [rax]
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
                        ; ( -- char )
                        ; returns -1 on error or EOF
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
                        ; if not, skip the following block
                        dq      CONDJUMP,.cont  ;   ?JUMP[.cont]
                        ; otherwise, push a -1 and exit
                        dq      LIT,-1          ;   -1
                        dq      EXIT            ;   EXIT
                        ; fetch a character at the input position
                        ; then advance input position
.cont                   dq      TOIN,FETCH      ;   >IN @
                        ; ( padpos )
                        dq      PUSHPAD,ADDINT  ;   PAD +
                        ; ( padaddr )
                        dq      CHARFETCH       ;   C@
                        ; ( char )
                        dq      TOIN,INCR       ;   >IN INCR
                        ; ( char )
                        dq      EXIT

                        DEFCOL  "SKIPSPC",SKIPSPC,0
.nextchar               dq      PADGETCH         ;  PADGETCH
                        ; ( char )
                        dq      DUP,LIT,-1,EQINT ;  DUP -1 =
                        dq      CONDJUMP,.finish ;  ?JUMP[.finish]
                        dq      DUP,ISSPC,BINNOT ;   DUP ?SPC NOT
                        dq      CONDJUMP,.finish2 ;  ?JUMP[.finish2]
                        ; ( char )
                        ; check if character was a "\n"
                        dq      DUP,LIT,10,NEINT ;  DUP 10 <>
                        dq      CONDJUMP,.nolf   ;  ?JUMP[.nolf]
                        ; linefeed, output OK if input is from a TTY
                        dq      OKAY
                        ; drop character
.nolf                   dq      DROP            ;   DROP
                        ; read next
                        dq      JUMP,.nextchar  ;   JUMP[.nextchar]
                        ; ( char )
                        ; decrement character position for PAD
.finish2                dq      TOIN,DECR       ;   >IN DECR
                        ; ( char )
.finish                 dq      DROP            ;   DROP
                        dq      EXIT

                        ; jump to specified system routine
                        ; the address has to be specified in the word
                        ; after JMPSYS
                        ; ( -- )
                        DEFASM  "JMPSYS",JMPSYS,0
                        mov     rax,[r13]
                        add     r13,8
                        jmp     rax

                        ; this writes a character to the DOT buffer
                        ; ( char -- )
                        DEFCOL  ">DOT",TODOT,0
                        ; load length field in DOT buffer to see
                        ; if it's 255 or greater
                        dq      PUSHDOT,DUP,CHARFETCH   ; DOT C@
                        ; ( char addr len )
                        dq      DUP,LIT,255,GEINT       ; 255 >=
                        dq      CONDJUMP,.dontstore     ; ?JUMP[.dontstore]
                        ; still have room
                        ; increment length by one
                        ; ( char addr len )
                        dq      ADDONE                  ; 1+
                        dq      TWODUP                  ; 2DUP
                        ; ( char addr len addr len )
                        ; store at addr (length field)
                        dq      SWAP,CHARSTORE          ; SWAP C!
                        ; ( char addr len )
                        ; compute address for char
                        dq      ADDINT                  ; +
                        ; ( char addr )
                        ; store character
                        dq      CHARSTORE               ; C!
                        ; done
                        dq      EXIT
                        ; ( char addr len )
                        ; don't store character
.dontstore              dq      TWODROP,DROP,EXIT       ; 2DROP DROP

                        ; print the contents of the dot buffer
                        DEFCOL  "PRINTDOT",PRINTDOT,0
                        dq      PUSHDOT,DUP,CHARFETCH   ; DOT DUP C@
                        ; ( addr len )
                        ; check length, stop if it's zero
                        dq      DUP,EQZEROINT           ; DUP =0
                        dq      CONDJUMP,.stop          ; ?JUMP[.stop]
                        ; add one to the address
                        dq      SWAP,ADDONE,SWAP        ; SWAP 1+ SWAP
                        ; ( addr len )
                        dq      TYPEOUT,EXIT            ; TYPE
                        ; ( addr len )
.stop                   dq      TWODROP,EXIT            ; 2DROP

                        ; this writes an unsigned integer to the DOT
                        ; buffer without clearing it
                        ; ( n -- )
                        DEFCOL  "U>DOT",UTODOT,0
                        ; check if the number is greater or equal to BASE
                        dq      DUP,PUSHBASE,FETCH,ULTINT ; DUP >BASE @ U<
                        dq      CONDJUMP,.norecurse      ; ?JUMP[.norecurse]
                        ; ( n )
                        ; recursion: number >= BASE, call myself with number
                        ; divided by BASE
                        ; ( n )
                        dq      DUP                     ; DUP
                        dq      PUSHBASE,FETCH,UDIVINT  ; >BASE @ U/
                        dq      UTODOT                  ; U>DOT
                        ; ( n )
                        ; get division remainder of number divided by BASE
                        dq      PUSHBASE,FETCH,UMODINT  ; >BASE @ U/MOD
                        ; ( n )
                        ; the number will be in the range 0..BASE-1
                        ; check if it's greater than 9
.norecurse              dq      DUP,LIT,9,UGTINT     ; DUP 9 U>
                        dq      CONDJUMP,.nondec    ; ?JUMP[.nondec]
                        ; otherwise, it's in decimal range
                        dq      LIT,'0',ADDINT      ; '0' +
                        dq      TODOT               ; >DOT
                        ; done
                        dq      EXIT
                        ; not decimal
.nondec                 dq      LIT,10,SUBINT       ; 10 -
                        dq      LIT,'A',ADDINT      ; 'A' +
                        dq      TODOT               ; >DOT
                        ; done
                        dq      EXIT

                        ; this sends a character straight to the console
                        ; ( n -- )
                        DEFCOL  "EMIT",EMITCHAR,0
                        dq      LIT,0,PUSHDOT,CHARSTORE ; 0 DOT C!
                        dq      TODOT                   ; >DOT
                        dq      PRINTDOT,EXIT           ; PRINTDOT

                        ; this prints an unsigned integer to the
                        ; currently selected output device, using BASE
                        ; ( n -- )
                        DEFCOL  "U.",UDOT,0
                        ; ( n )
                        ; clear length field in DOT buffer
                        dq      LIT,0,PUSHDOT,CHARSTORE ; 0 DOT C!
                        ; store number in buffer
                        dq      UTODOT                  ; U>DOT
                        ; ( )
                        ; output buffer
                        dq      PRINTDOT
                        ; output final blank
                        dq      LIT,' ',EMITCHAR
                        dq      EXIT

                        ; this prints an integer to the currently
                        ; selected output device, using BASE
                        ; ( n -- )
                        DEFCOL  ".",DOT,0
                        ; ( n )
                        ; clear length field in DOT buffer
                        dq      LIT,0,PUSHDOT,CHARSTORE ; 0 DOT C!
                        ; test number for negativity
                        ; ( n )
                        dq      DUP,GEZEROINT       ; DUP >=0
                        dq      CONDJUMP,.output    ; ?JUMP[.output]
                        ; negative, store a minus sign
                        dq      LIT,'-',TODOT       ; '-' >DOT
                        ; negate number
                        dq      NEGATE              ; NEG
                        ; output number to buffer
.output                 dq      UTODOT                  ; U>DOT
                        ; ( )
                        ; output buffer
                        dq      PRINTDOT
                        ; output final blank
                        dq      LIT,' ',EMITCHAR
                        dq      EXIT

                        ; ( char -- char )
                        DEFASM  ">UPPER",TOUPPER,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     al,'a'
                        jb      .notlower
                        cmp     al,'z'
                        ja      .notlower
                        sub     al,'a'
                        add     al,'A'
                        mov     [r15],rax
.notlower               NEXT

                        ; ( char -- char )
                        DEFASM  ">LOWER",TOLOWER,0
                        CHKUNF  1
                        mov     rax,[r15]
                        cmp     al,'A'
                        jb      .notupper
                        cmp     al,'Z'
                        ja      .notupper
                        sub     al,'A'
                        add     al,'a'
                        mov     [r15],rax
.notupper               NEXT

                        ; read a word from input into NAME buffer
                        ; returns address and length
                        ; ( -- addr len )
                        ; if the result would be empty, return 0 0
                        DEFCOL  "?WORD",READWORD,0
                        ; clear name length
                        dq      LIT,0           ;   0
                        dq      PUSHNAME        ;   NAME
                        dq      CHARSTORE       ;   C!
                        ; skip whitespace
                        dq      SKIPSPC         ;   SKIPSPC
                        ; read a character from the PAD
.nextchar               dq      PADGETCH,DUP    ;   PADGETCH DUP
                        dq      LIT,-1,EQINT    ;   -1 =
                        dq      CONDJUMP,.end   ;   ?JUMP[.end]
                        ; ( char )
                        ; compare it to one of the terminator characters
                        ; (SPC, TAB, NEWLINE, NUL)
                        dq      DUP,ISSPC,BINNOT ;  DUP ?SPC NOT
                        dq      CONDJUMP,.storechr ; ?JUMP[.storechr]
                        ; decrement character position for PAD
                        dq      TOIN,DECR       ;   >IN DECR
                        ; end
                        ; (char)
.end                    dq      DROP            ;   DROP
                        ; leave NAME address
.end2                   dq      PUSHNAME        ;   NAME
                        ; ( addr )
                        ; leave length
                        dq      DUP,CHARFETCH   ;   DUP C@
                        ; ( addr len )
                        ; test length if it is zero
                        dq      DUP,EQZEROINT   ;   DUP =0
                        dq      CONDJUMP,.end3  ;   ?JUMP[.end3]
                        ; make sure addr points to first character
                        dq      SWAP,ADDONE,SWAP ;  SWAP +1 SWAP
                        ; ( addr len )
                        dq      EXIT
                        ; ( addr len )
                        ; length is zero: drop address and length
                        ; and leave zero values instead
.end3                   dq      TWODROP         ;   2DROP
                        dq      LIT,0,LIT,0     ;   0 0
                        dq      EXIT
                        ; ( char )
                        ; convert character to upper case
.storechr               dq      TOUPPER
                        ; increment name length and leave a copy of it
                        dq      PUSHNAME,DUP,CINCR  ; NAME DUP CINCR
                        dq      CHARFETCH       ;   C@
                        ; ( char count )
                        ; store the character into the new position
                        dq      PUSHNAME,ADDINT ;   NAME +
                        ; ( char addr )
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
                        dq      JUMP,.end2      ;   JUMP[.end2]

                        ; check if a definition matches the current NAME
                        ; ( addr len defptr -- addr len defptr bool )
                        DEFASM  "?MATCHDEF",MATCHDEF,0
                        CHKUNF  3
                        CHKOVF  1
                        mov     rdi,[r15+16]    ; read addr
                        test    rdi,rdi         ; stop if it's zero
                        jz      .false
                        mov     rdx,[r15+8]     ; read length
                        test    rdx,rdx         ; stop if it's zero
                        jz      .false
                        mov     rax,[r15]       ; read defptr
                        lea     rsi,[rax+8]     ; beginning of name field in def
                        cld
                        ; load length from definition
                        lodsb   ; al = [rsi]+
                        and     al,0x1f ; length is low 5 bits
                        ; compare with length supplied
                        cmp     al,dl
                        jne     .false
                        ; same length: compare strings
                        movzx   rcx,al
                        jrcxz   .true
                        repe    cmpsb
                        jne     .false
.true                   xor     rax,rax
                        not     rax
                        sub     r15,8
                        mov     [r15],rax
                        NEXT
.false                  xor     rax,rax
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; forcibly read the next word
                        ; if none exists, exit FORTH
                        ; otherwise, leave address and length
                        ; ( -- addr len )
                        DEFCOL  "WORD",GETWORD,0
                        dq      READWORD            ; ?WORD
                        dq      DUP,EQZEROINT       ; DUP =0
                        dq      CONDJUMP,.error     ; ?JUMP[.error]
                        ; ( addr len )
                        dq      EXIT
                        ; ( addr len )
.error                  dq      TWODROP             ; 2DROP
                        ; Since this occurs at the end of file, we cannot
                        ; sensibly output an error message here.
                        ; Thus, we simply exit FORTH.
                        dq      JMPSYS,fvm_term     ; JMPSYS[fvm_term]

                        ; find word in dictionary
                        ; ( addr len -- defptr )
                        ; if not found, returns a NULL pointer
                        DEFCOL  "FIND",FINDWORD,0
                        ; get LATEST variable onto the stack
                        dq      TOLATEST,FETCH  ;   >LATEST @
                        ; ( addr len defptr )
                        ; see if the current definition matches the
                        ; specified word
                        ; ( addr len defptr )
.next                   dq      MATCHDEF        ;   ?MATCHDEF
                        ; ( addr len defptr bool )
                        dq      CONDJUMP,.found  ;  ?JUMP[.found]
                        ; doesn't match: move to previous definition
.skipmatch              dq      FETCH           ;   @
                        ; ( addr len defptr )
                        ; check if entries are used up
                        dq      DUP,EQZEROINT   ;   DUP =0
                        dq      CONDJUMP,.notfound ;   ?JUMP[.notfound]
                        ; nope, compare ->
                        dq      JUMP,.next      ;   JUMP[.next]
                        ; ( addr len defptr )
                        ; we didn't find the word (defptr is NULL)
.notfound               dq      TWODROP,DROP    ;   2DROP DROP
                        dq      LIT,0           ;   0
                        dq      EXIT
                        ; ( addr len defptr )
                        ; apparently, we found the word
                        ; if it is has its hidden flag set, we didn't
.found                  dq      DUP,LIT,8,ADDINT ;  DUP 8 +
                        dq      CHARFETCH       ;   C@
                        ; ( addr len defptr char )
                        dq      LIT,F_HIDDEN,BINAND ; [F_HIDDEN] AND
                        ; if set, skip the match
                        dq      CONDJUMP,.skipmatch ; ?JUMP[.skipmatch]
                        ; acceptable
                        ; ( addr len defptr )
                        dq      TWOROT          ;   2ROT
                        ; ( defptr addr len )
                        dq      TWODROP         ;   2DROP
                        ; ( defptr )
                        dq      EXIT

                        section .text
                        align   32

                        ; check number base (BASE)
                        ;
_checkbase              mov     rax,[rbp-BASE]
                        cmp     rax,2
                        jl      .badbase
                        cmp     rax,36
                        jle     .baseok
.badbase                call    fvm_badbase
                        mov     rax,10
                        mov     [rbp-BASE],rax
.baseok                 ret

                        ; check BASE
                        DEFASM  "CHECKBASE",CHECKBASE,0
                        call    _checkbase
                        NEXT

                        ; get a character for numeric conversion
                        ;   ( addr len -- addr len char )
                        ; on error, the character will be -1
                        DEFCOL  "CGETNCONV",CGETNCONV,0
                        dq      DUP,EQZEROINT       ;   DUP =0
                        dq      CONDJUMP,.nochar    ;   ?JUMP[.nochar]
                        ;   ( addr len )
                        dq      SWAP,DUP            ;   SWAP DUP
                        ;   ( len addr addr )
                        dq      CHARFETCH           ;   C@
                        ;   ( len addr char )
                        dq      ROT                 ;   ROT
                        ;   ( addr char len )
                        dq      SUBONE              ;   -1
                        dq      ROT                 ;   ROT
                        ;   ( char len addr )
                        dq      ADDONE              ;   +1
                        dq      SWAP                ;   SWAP
                        ;   ( char addr len )
                        dq      ROT                 ;   ROT
                        ;   ( addr len char )
                        dq      EXIT
                        ;   ( addr len )
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
                        xor     rdx,rdx
                        cmp     rcx,rdx
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
                        std
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
                        cld
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
                        cld
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
                        NEXT

                        DEFASM  ">ADDRESS0",TOADDRESS0,0
                        CHKOVF  1
                        lea     rax,[rbp-ADDRESS0]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; convert a digit sequence to a number,
                        ; returning its value and number of digits
                        ; ( addr len -- addr len numdig value )
                        ; on error, both values will be zero
                        DEFCOL  "DSEQNCONV",DSEQNCONV,0
                        dq      OVER,TOADDRESS0,STORE ; OVER >ADDRESS0 !
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
                        dq      TWOROT              ; 2ROT
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
                        dq      TWOROT              ; 2ROT
                        ; ( newvalue addr len )
                        dq      JUMP,.nextchar      ; JUMP[.nextchar]
                        ; not digit: back up one char
                        ; ( value addr len char digit )
                        ; get rid of digit and char
.finish2                dq      TWODROP             ; 2DROP
                        ; ( value addr len )
                        ; go back one character
                        dq      BACKNCONV           ; BACKNCONV
                        dq      JUMP,.finish1       ; JUMP[.finish1]
                        ; ( value addr len char )
.finish                 dq      DROP
                        ; get value on top
                        ; ( value addr len )
.finish1                dq      ROT            ; ROT
                        ; ( addr len value )
                        ; get address on stack
                        dq      LIT,3,PICK          ; 3 PICK
                        ; ( addr len value addr )
                        ; compute number of digits
                        dq      TOADDRESS0,FETCH    ; >ADDRESS0 @
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
.convfail               dq      TWODROP             ; 2DROP
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

                        section .text
                        align   32

                        ; compute logarithms (floating-point)
                        ; ( rdi:base rsi:number -- rax:output )
_flog                   push    rdi
                        push    rsi
                        ; logb(x) = (1/(log2(b))) * log2(x)
                        fld1
                        fld1
                        fld     qword [rsp+8]   ; base
                        ; st2 - 1
                        ; st1 - 1
                        ; st0 - base
                        fyl2x
                        ; st1 - 1
                        ; st0 - 1*log2(base) = log2(base)
                        fdivp
                        ; st0 - 1/log2(base)
                        fld     qword [rsp]     ; number
                        ; st1 - 1/log2(base)
                        ; st0 - number
                        fyl2x
                        ; st0 - result
                        add     rsp,8
                        fstp    qword [rsp]
                        pop     rax
                        ret

                        ; compute logarithms (floating-point)
                        ; ( base number -- output )
                        DEFASM  "FLOG",FLOATLOG,0
                        CHKUNF  2
                        mov     rdi,[r15+8]
                        mov     rsi,[r15]
                        call    _flog
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        section .rodata
                        align   8
_floatdot_fmt           db      "%g ",0

                        section .text
                        align   32

                        ; rax - int value
                        ; rax - float value
                        ; convert integer to float
_i2f                    push    rax
                        fild    qword [rsp]
                        fstp    qword [rsp]
                        pop     rax
                        ret

                        ; rax - int value
                        ; rax - float value
                        ; convert integer to negative float
_i2nf                   push    rax
                        fild    qword [rsp]
                        fchs
                        fstp    qword [rsp]
                        pop     rax
                        ret

                        ; load integer var as float
                        %macro  LIVASFLT 2
                        mov     rax,[rbp-%2]
                        call    _i2f
                        mov     %1,rax
                        %endmacro

                        ; load integer var as negative float
                        %macro  LIVASNFL 2
                        mov     rax,[rbp-%2]
                        call    _i2nf
                        mov     %1,rax
                        %endmacro

                        ; load integer var as real
                        %macro  LIVASREL 1
                        mov     rax,[rbp-%1]
                        call    _i2f
                        push    rax
                        fld     qword [rsp]
                        pop     rax
                        %endmacro

                        ; exponentiate integer vars as real
                        %macro  EIVASREL 2
                        LIVASFLT    rdi,%1
                        LIVASFLT    rsi,%2
                        call        _fpowl
                        push        rax
                        fld         qword [rsp]
                        pop         rax
                        %endmacro

                        ; exponentiate integer vars as real
                        ; negative exponent
                        %macro  EIVASRLN 2
                        LIVASFLT    rdi,%1
                        LIVASNFL    rsi,%2
                        call        _fpowl
                        push        rax
                        fld         qword [rsp]
                        pop         rax
                        %endmacro

                        align       32
                        ; compute BASE to the power of exponent
_basePowExp             EIVASREL    BASE,EXPONENT
                        ret

                        align       32
                        ; compute BASE to the power of -fracndig
_basePowFracNDig        EIVASRLN    BASE,FRACNDIG
                        ret

                        align       32
                        ; compute fraction multiplier fraction*(base^-fracndig)
_fracMult               LIVASREL    FRACTION
                        call        _basePowFracNDig
                        fmulp
                        ret

                        align       32
                        ; compute +mantissa + fraction
                        ; or      -mantissa - fraction
_multMantFract          LIVASREL    MANTISSA
                        call        _fracMult
                        mov         rax,[rbp-MANTISSA]
                        xor         rdx,rdx
                        cmp         rax,rdx
                        jl          .negative
                        faddp
                        ret
.negative               fsubp
                        ret

                        align       32
                        ; compute number * exponent
_multNumbExp            call        _multMantFract
                        call        _basePowExp
                        fmulp
                        ret

                        ; convert number in floating-point fields
                        ; to actual floating-point and return it
                        ; ( -- number bool )
                        DEFASM  "GETREAL",GETREAL,0
                        CHKOVF  2
                        call    _multNumbExp
                        ; output result
                        sub     r15,16
                        fstp    qword [r15+8] ; result
                        xor     rax,rax
                        not     rax
                        mov     [r15],rax   ; true
                        NEXT

                        ; convert number using BASE
                        ; ( addr len -- number bool )
                        DEFCOL  "?MATCHNUM",MATCHNUM,0
                        ; initialize numeric conversion
                        dq      CHECKBASE           ; CHECKBASE
                        ; ( addr len )
                        ; attempt to convert the leading characters
                        ; into a signed number
                        dq      SSEQNCONV           ; SSEQNCONV
                        ; ( addr len numdigits value )
                        ; check numdigits for 0
                        dq      OVER,EQZEROINT ; OVER =0
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
.convfail3              dq      TWODROP             ; 2DROP
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
.integer                dq      TWODROP,DROP        ; 2DROP DROP
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
                        dq      DUP,NEZEROINT       ; DUP <>0
                        dq      CONDJUMP,.convfail3 ; ?JUMP[.convfail3]
                        ; otherwise, we're finished reading a
                        ; floating-point number
                        ; ( addr len )
                        dq      JUMP,.floatingpoint2 ; JUMP[.floatingpoint2]
                        ; ( addr len char )
                        ; drop fields
.floatingpoint          dq      DROP                ; DROP
.floatingpoint2         dq      TWODROP             ; 2DROP
                        ; ( )
                        ; convert to real number and push it and the truth value
                        dq      GETREAL             ; GETREAL
                        ; ( number bool )
                        dq      EXIT

                        ; check pointer to see if it's NULL
                        ; ( addr -- addr )
                        DEFASM  "CHKPTR",CHKPTR,0
                        CHKUNF  1
                        mov     rax,[r15]
                        test    rax,rax
                        jnz     .ok
                        jmp     fvm_nullptr
.ok                     NEXT

                        ; get address of codeword from dictionary entry
                        ; (codeword from address, CFA)
                        ; ( addr -- addr )
                        DEFASM  ">CFA",TOCFA,0
                        CHKUNF  1
                        ; check pointer
                        mov     rax,[r15]
                        test    rax,rax
                        jnz     .ok
                        jmp     fvm_nullptr
.ok                     mov     rdi,rax
                        call    _tocfa
                        mov     [r15],rax
                        NEXT

                        ; addr - rdi
                        ; (must point to start of word definition)
                        ; move to name field (i.e. skip back pointer)
_tocfa                  add     rdi,8
                        ; get name length
                        mov     al,[rdi]
                        and     al,31   ; mask off flag bits
                        ; add 1+len to addr
                        inc     al
                        movzx   rax,al
                        add     rax,rdi
                        ; add 7 and AND NOT 7
                        mov     rdx,7
                        add     rax,rdx
                        not     rdx
                        and     rax,rdx
                        ; finished
                        ret

                        ; create a new dictionary entry with specified name
                        ; and update the backwards link, leave the value of HERE
                        ; ( addr len -- here )
                        DEFASM  "_CREATE",_CREATE,0
                        CHKUNF  2
                        mov     rsi,[r15+8]
                        mov     rcx,[r15]
                        mov     rdi,rbx             ; HERE
                        mov     rax,[rbp-LATEST]    ; LATEST
                        cld
                        ; set LATEST to HERE
                        mov     [rbp-LATEST],rbx    ; LATEST = HERE
                        ; put the link backwards at the current position
                        stosq
                        ; store the length (make sure its not longer than 31)
                        and     rcx,31
                        mov     al,cl
                        stosb
                        ; check for zero count
                        jrcxz   .zeroname
                        ; copy the name
                        rep     movsb
                        ; round up address to next quadword boundary
.zeroname               add     rdi,7
                        and     rdi,~7
                        ; done, update dictionary pointer
                        mov     rbx,rdi
                        add     r15,8
                        mov     [r15],rbx   ; leave HERE on stack
                        NEXT

                        ; the compiler's CREATE function:
                        ; reads the next word in the input stream
                        ; then creates a new dictionary entry with it
                        ; and leaves its address on the stack.
                        ; ( -- addr )
                        DEFCOL  "CCREATE",CCREATE,0
                        ; make sure we read a word, exit FORTH if we don't (EOF)
                        dq      GETWORD         ; GETWORD
                        ; ( nameaddr len )
                        ; call the internal create function and exit
                        dq      _CREATE         ; _CREATE
                        ; ( defaddr )
                        dq      EXIT

                        section .text
                        align   32

                        ; custom codeword routine:
                        ; drop the address of the parameter field on the stack
                        ; the parameter field is at WA + 2 (the word after the
                        ; codeword field plus the codepointer field)
fvm_douser              CHKOVF  1
                        lea     rax,[r12+16] ; paraddr = WA + 2
                        sub     r15,8
                        mov     [r15],rax
                        ; check the codepointer field. if empty,
                        ; continue at caller's location
                        mov     rax,[r12+8] ; codeptr = [WA + 1]
                        test    rax,rax
                        jz      .tonext
                        ; if non-zero, push the WP onto the return stack
                        ; and then set WP to the new address.
                        RCHKOVF 1
                        sub     r14,8       ; -[RSP] := WP
                        mov     [r14],r13
                        mov     r13,rax     ; WP := codeptr
                        ; begin processing word definition
.tonext                 NEXT

                        ; user CREATE function:
                        ; reads next input word, then creates an empty
                        ; dictionary entry.
                        ; when the entry is invoked, it will drop the address
                        ; of its parameter area (which is the space after
                        ; the automatically generated code, which is still at
                        ; the current position (HERE) in dictionary space.)
                        ; I gathered this from the documentation to Forth-79
                        ; and the implementation of Forth-83 (FiGFORTH on the
                        ; Amstrad CPC), from which I did remember this.
                        ; NOTE that unlike Jonesforth, which I used for
                        ; reference, Yulark's FORTH implementation fully
                        ; supports CREATE ... DOES> .
                        DEFCOL  "CREATE",CREATE,0
                        ; just call the compiler's CREATE function out of
                        ; convenience.
                        dq      CCREATE                 ; CCREATE
                        ; ( defptr )
                        ; we don't need the definition pointer here
                        dq      DROP                    ; DROP
                        ; doesn't contain even a CODEWORD field yet.
                        ; set up a code word that drops the address of the
                        ; following parameter area
                        dq      LIT,fvm_douser,COMMA    ; [fvm_douser] ,
                        ; after that, we're storing a FORTH code pointer
                        ; that gets filled in by DOES> or not, depending
                        ; on the purpose of the word. 0 means "do nothing"
                        dq      LIT,0,COMMA             ; 0 ,
                        ; aaand we're done
                        dq      EXIT

                        ; pass a value from the parameter stack onto the return
                        ; stack
                        DEFASM  ">R",TORET,0
                        CHKUNF  1
                        RCHKOVF 1
                        mov     rax,[r15]
                        add     r15,8
                        sub     r14,8
                        mov     [r14],rax
                        NEXT

                        ; pass a value from the return stack onto the parameter
                        ; stack
                        DEFASM  "R>",FROMRET,0
                        CHKOVF  1
                        RCHKUNF 1
                        mov     rax,[r14]
                        add     r14,8
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; Explanation of what DOES> does:
                        ;
                        ;   : VAR CREATE 0 , ;
                        ;   : VAL VAR DOES> @ ;
                        ;   VAL xy
                        ;
                        ;   Code path during the compilation of VAL:
                        ;   :(immed) [VAL] -> VAR(comp) -> DOES(comp)
                        ;   -> @(comp) -> ;(immed)
                        ;
                        ;           VAL definition:
                        ;               <link back>
                        ;               \3 V A L \0 \0 \0 \0
                        ;   codeword->  <fvm_docol>
                        ;               <VAR reference>
                        ;               <DOES reference>
                        ;               <@ reference>
                        ;               <EXIT reference>
                        ;
                        ;   Code path during the execution of VAL:
                        ;   fvm_docol ->
                        ;       VAR ->
                        ;           fvm_docol ->
                        ;               CREATE ->
                        ;               LIT 0 ->
                        ;               , ->
                        ;            <- EXIT
                        ;       DOES ->
                        ;           (store WP in LATEST word's codeptr field)
                        ;    <----- EXIT
                        ;   WP during DOES> points to the remainder:
                        ;       @ ->
                        ;    <- EXIT
                        ;
                        ; Store the position of the word pointer popped off
                        ; the return stack after the codeword field of the
                        ; definition (only for words created by CREATE).
                        ;
                        ; A good explanation of what is supposed to happen can
                        ; be found at reply #1 to the following article:
                        ; https://softwareengineering.stackexchange.com/questions/339283/forth-how-do-create-and-does-work-exactly
                        ;
                        DEFCOL  "DOES>",DOES,0
                        ; get codeword address of latest definition
                        dq      TOLATEST,FETCH,TOCFA ; >LATEST @ >CFA
                        ; ( addr )
                        ; ensure it is for fvm_douser:
                        dq      DUP,FETCH,LIT,fvm_douser ; DUP @ [fvm_douser]
                        dq      NEINT,CONDJUMP,.cancel  ; <> ?JUMP[.cancel]
                        ; ( addr )
                        ; add 8 to get to the following word
                        dq      LIT,8,ADDINT            ; 8 +
                        ; store the return address into that word
                        dq      FROMRET,SWAP,STORE     ; R> SWAP !
                        ; store new return address pointing to EXIT
                        dq      LIT,.toexit,TORET   ; [.toexit] >R
                        ; done (will pop new address from RSP)
.toexit                 dq      EXIT
                        ; not for fvm_douser: cancel
.cancel                 dq      DROP,EXIT

                        ; store specified data word to the position
                        ; indicated by the dictionary pointer and update it
                        ; ( data -- )
                        DEFASM  ",",COMMA,0
                        CHKUNF  1
                        mov     rax,[r15]
                        mov     rdi,rbx
                        cld
                        stosq
                        mov     rbx,rdi
                        add     r15,8
                        NEXT

                        ; leave compile mode
                        ; (in the interpreter, it will cause the following
                        ; words to be executed rather than compiled)
                        ; it must be marked immediate, otherwise the compiler
                        ; would compile rather than execute it.
                        DEFASM  "[",LBRACKET,F_IMMEDIATE
                        xor     rax,rax
                        mov     [rbp-ISCOMP],rax
                        not     rax
                        mov     [rbp-ISIMMED],rax
                        NEXT

                        ; enter compile mode
                        ; (in the interpreter, it will cause the following
                        ; words to be compiled rather than executed)
                        DEFASM  "]",RBRACKET,0
                        xor     rax,rax
                        mov     [rbp-ISIMMED],rax
                        not     rax
                        mov     [rbp-ISCOMP],rax
                        NEXT

                        ; returns true if we're in immediate mode
                        DEFASM  "?IMMEDIATE",INIMMEDIATE,0
                        CHKOVF  1
                        mov     rax,[rbp-ISIMMED]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; begin word compilation
                        DEFCOL  ":",COLON,0
                        dq      CCREATE      ; CCREATE
                        ; ( defaddr )
                        ; append DOCOL
                        dq      LIT,fvm_docol,COMMA     ; [fvm_docol] COMMA
                        ; mark the latest word (the one just created)
                        ; as hidden so that new implementations of one word
                        ; can call the previous definition.
                        ; ( defaddr )
                        dq      LIT,8,ADDINT        ; 8 +
                        ; ( flagaddr )
                        dq      DUP,CHARFETCH       ; DUP C@
                        dq      LIT,F_HIDDEN,BINOR  ; [F_HIDDEN] OR
                        ; ( flagaddr flags )
                        dq      SWAP,CHARSTORE      ; SWAP C!
                        ; ( )
                        ; enter compile mode and exit
                        dq      RBRACKET,EXIT       ; ]

                        ; mark latest word definition as immediate
                        DEFCOL  "IMMEDIATE",IMMEDIATE,F_IMMEDIATE
                        dq      TOLATEST,FETCH      ; >LATEST @
                        ; ( wordaddr )
                        dq      LIT,8,ADDINT        ; 8 +
                        dq      DUP,CHARFETCH       ; DUP C@
                        ; ( flagaddr flags )
                        dq      LIT,F_IMMEDIATE,BINOR ; [F_IMMEDIATE] OR
                        ; store
                        dq      SWAP,CHARSTORE      ; SWAP C!
                        dq      EXIT

                        ; end of compilation mode
                        ; must be immediate so the interpreter won't
                        ; compile it.
                        DEFCOL  ";",SEMICOLON,F_IMMEDIATE
                        ; store the EXIT word into the word definition
                        ; so a word will return to the calling context
                        ; when it is finished
                        dq      LIT,EXIT,COMMA      ; [EXIT] COMMA
                        ; unmark the latest word (the one currently being
                        ; created) as hidden so that new implementation
                        ; can be seen with FIND.
                        dq      TOLATEST,FETCH      ; >LATEST @
                        ; ( defaddr )
                        dq      LIT,8,ADDINT        ; 8 +
                        ; ( flagaddr )
                        dq      DUP,CHARFETCH       ; DUP C@
                        ; ( flagaddr flags )
                        dq      LIT,F_HIDDEN        ; [F_HIDDEN]
                        dq      BINNOT,BINAND       ; NOT AND
                        ; ( flagaddr flags )
                        dq      SWAP,CHARSTORE      ; SWAP C!
                        ; return to immediate mode
                        dq      LBRACKET            ; [
                        dq      EXIT

                        ; if the input device is a TTY, output "ok"
                        DEFCOL  "OKAY",OKAY,0
                        dq      TOFILE,FETCH        ; >FILE @
                        dq      SYSISATTY           ; SYSISATTY
                        dq      CONDJUMP,.print     ; ?JUMP[.print]
                        dq      EXIT
.print                  dq      LIT,.oktext,LIT,3   ; [.oktext] 3
                        dq      TYPEOUT             ; TYPE
                        dq      EXIT
.oktext                 db      "ok",10
                        align   8

                        ; gets the codeword address from the stack
                        ; and then executes that word
                        ; ( cfa )
                        DEFASM  "RUNCODE",RUNCODE,0
                        CHKUNF  1
                        ; get CFA (the address containing the codeword address)
                        mov     rax,[r15]
                        add     r15,8
                        ; load that into the WA register (r12)
                        mov     r12,rax
                        ; if it's a DOCOL routine:
                        ;   DOCOL will preserve the WP register (r13) on the
                        ;   return stack and then begin processing the word
                        ;   that is pointed to by WA (r12), the EXIT at the end
                        ;   will return to the caller of RUNCODE.
                        ; if it's an assembly subroutine:
                        ;   these do all end with NEXT, thus processing will
                        ;   continue in the context of the caller as long as
                        ;   the WP register (r13) is not changed
                        ; thus, we can jump directly to the assembly routine
                        ; for both cases.
                        jmp     qword [rax]

                        ; ( n1 n2 -- n1 n2 n1 n2 )
                        DEFCOL  "2DUP",TWODUP,0
                        dq      OVER,OVER       ; OVER OVER
                        dq      EXIT

                        ; ( n1 n2 -- )
                        DEFCOL  "2DROP",TWODROP,0
                        dq      DROP,DROP       ; DROP DROP
                        dq      EXIT

                        ; ( n1 n2 n3 -- n3 n1 n2 )
                        DEFCOL  "2ROT",TWOROT,0
                        dq      ROT,ROT         ; ROT ROT
                        dq      EXIT

                        ; In compile mode, LITERAL compiles to code that leaves
                        ; the specified number on the stack. In immediate mode,
                        ; it does nothing.
                        ; ( number -- )
                        DEFCOL  "LITERAL",LITERAL,F_IMMEDIATE
                        ; check if we're in immediate mode
                        dq      INIMMEDIATE         ; ?IMMEDIATE
                        dq      CONDJUMP,.immed     ; ?JUMP[.immed]
                        ; not immediate mode: compile number
                        ; for that, the address of LIT must be stored,
                        ; then the provided number
                        dq      LIT,LIT,COMMA       ; [LIT] ,
                        dq      COMMA               ; ,
                        ; ( )
                        ; finished
                        dq      EXIT
                        ; LITERAL does nothing in immediate mode
                        ; except consume its parameter
.immed                  dq      DROP,EXIT

                        ; leave the address of the parameter field
                        ; of the following word on the stack.
                        ; if compiling, generate code that pushes that
                        ; address on the stack instead.
                        DEFCOL  "'",QUOTE,F_IMMEDIATE
                        ; read next word from input, exit FORTH at EOF
                        dq      GETWORD             ; WORD
                        ; ( addr len )
                        ; find it in the dictionary
                        dq      FINDWORD            ; FIND
                        ; ( defptr )
                        ; check if zero
                        dq      DUP,EQZEROINT       ; DUP =0
                        dq      CONDJUMP,.notfound  ; ?JUMP[.notfound]
                        ; found, compute CFA, and fetch codeword
                        dq      TOCFA,DUP,FETCH     ; >CFA DUP @
                        ; ( cfa codeword )
                        ; check if it's a user word
                        dq      LIT,fvm_douser,NEINT ; [fvm_douser] <>
                        dq      CONDJUMP,.noparam   ; ?JUMP[.noparam]
                        ; ( cfa )
                        ; yes it is, calculate parameter address
                        dq      LIT,16,ADDINT       ; 16 +
                        ; ( paraddr )
                        ; check for immediate mode:
                        dq      INIMMEDIATE         ; ?IMMEDIATE
                        dq      CONDJUMP,.immed     ; ?JUMP[.immed]
                        ; compile mode: store as literal
                        dq      LITERAL
                        dq      EXIT
                        ; immediate mode
                        ; ( paraddr )
                        ; leave address on the stack
.immed                  dq      EXIT
                        ; ( cfa )
                        ; word has no parameter field
.noparam                dq      DROP                ; DROP
                        dq      JMPSYS,fvm_noparam  ; JMPSYS[.noparam]
                        ; ( 0 )
                        ; not found
.notfound               dq      DROP                ; DROP
                        dq      JMPSYS,fvm_notfound ; JMPSYS[.notfound]

                        ; finally, the interpreter
                        ; reads words and runs them until EOF occurs
                        DEFCOL  "INTERPRET",INTERPRET,0
                        ; read next word from input, exit FORTH at EOF
.nextword               dq      GETWORD             ; WORD
                        ; ( addr len )
                        ; duplicate both fields
                        dq      TWODUP              ; 2DUP
                        ; ( addr len addr len )
                        ; find it in the dictionary
                        dq      FINDWORD            ; FIND
                        ; ( addr len defptr )
                        ; if not, we get a 0
                        dq      DUP,EQZEROINT       ; DUP 0=
                        dq      CONDJUMP,.notfound  ; ?JUMP[.notfound]
                        ; ( addr len defptr )
                        ; found, get rid of the addr/len fields
                        dq      TWOROT              ; 2ROT
                        ; ( defptr addr len )
                        dq      TWODROP             ; 2DROP
                        ; ( defptr )
                        ; check if we're in immediate mode
                        dq      INIMMEDIATE         ; ?IMMEDIATE
                        dq      CONDJUMP,.immediate ; ?JUMP[.immediate]
                        ; ( defptr )
                        ; we're in compile mode, check to see if the word
                        ; has an F_IMMEDIATE mark on it. if so, act as if
                        ; we're in immediate mode
                        dq      DUP,LIT,8,ADDINT    ; DUP 8 +
                        dq      CHARFETCH           ; C@
                        dq      LIT,F_IMMEDIATE,BINAND ; [F_IMMEDIATE] AND
                        dq      CONDJUMP,.immediate
                        ; ( defptr )
                        ; we're in compile mode, get code addr and store it
                        dq      TOCFA,COMMA         ; >CFA ,
                        ; ( )
                        ; go to next word
                        dq      JUMP,.nextword      ; JUMP[.nextword]
                        ; in immediate mode: get code word address and run
.immediate              dq      TOCFA,RUNCODE       ; >CFA RUNCODE
                        ; we'll end up here when the word called EXIT (DOCOL)
                        ; or NEXT (assembly).
                        ; so, we'll jump back to the word processing
                        dq      JUMP,.nextword
                        ; the word we searched for wasn't found
                        ; ( addr len defptr )
                        ; drop the NULL word
.notfound               dq      DROP            ; DROP
                        ; ( addr len )
                        ; see if it's a number perhaps
                        dq      MATCHNUM        ; ?MATCHNUM
                        ; ( number bool )
                        dq      CONDJUMP,.number ; ?JUMP[.number]
                        ; drop number field (0)
                        dq      DROP
                        ; not number: it's an error
                        dq      JMPSYS,fvm_unknown ; JMPSYS[.fvm_unknown]
                        ; a number
                        ; ( number )
                        ; check if we're in immediate mode
.number                 dq      INIMMEDIATE         ; ?IMMEDIATE
                        dq      CONDJUMP,.numimmed  ; ?JUMP[.numimmed]
                        ; ( number )
                        ; compile literal
                        dq      LITERAL
                        ; ( )
                        ; back to word processing
                        dq      JUMP,.nextword
                        ; ( number )
                        ; in immediate mode, the number is pushed onto the
                        ; stack (which it already is), so we can jump right
                        ; back into word processing
.numimmed               dq      JUMP,.nextword

                        DEFCOL  "(",LPAREN,F_IMMEDIATE
.nextchar               dq      PADGETCH            ; PADGETCH
                        dq      DUP,LIT,-1,EQINT    ; -1 =
                        dq      CONDJUMP,.eof       ; ?JUMP[.end]
                        dq      DUP,LIT,')',EQINT   ; ')' =
                        dq      CONDJUMP,.end       ; ?JUMP[.end]
                        dq      DROP                ; DROP
                        dq      JUMP,.nextchar      ; JUMP[.nextchar]
.eof                    dq      DROP                ; DROP
                        dq      JMPSYS,fvm_unexpeof ; JMPSYS[.unexpeof]
.end                    dq      DROP                ; DROP
                        dq      EXIT

                        DEFCOL  "\",LINECOMMENT,F_IMMEDIATE
.nextchar               dq      PADGETCH            ; PADGETCH
                        dq      DUP,LIT,-1,EQINT    ; -1 =
                        dq      CONDJUMP,.eof       ; ?JUMP[.end]
                        dq      DUP,LIT,10,EQINT    ; '\n' =
                        dq      CONDJUMP,.end       ; ?JUMP[.end]
                        dq      DROP                ; DROP
                        dq      JUMP,.nextchar      ; JUMP[.nextchar]
.eof                    dq      DROP                ; DROP
                        dq      JMPSYS,fvm_unexpeof ; JMPSYS[.unexpeof]
                        ; ends with a newline, go back one position
                        ; so the newline is read again by SKIPSPC later
.end                    dq      DROP                ; DROP
                        dq      TOIN,DECR           ; >IN DECR
                        dq      EXIT

                        DEFCOL  "VARIABLE",VARIABLE,0
                        dq      CREATE              ; CREATE
                        dq      LIT,0,COMMA         ; 0 ,
                        dq      EXIT

                        ; ( n -- )
                        DEFCOL  "CONSTANT",CONSTANT,0
                        dq      GETWORD,_CREATE     ; WORD _CREATE
                        ; ( n here )
                        dq      DROP
                        ; ( n )
                        ; compile DOCOL
                        dq      LIT,fvm_docol,COMMA ; [fvm_docol] ,
                        ; compile number on stack
                        dq      LIT,LIT,COMMA       ; [LIT] ,
                        dq      COMMA               ; ,
                        ; compile EXIT
                        dq      LIT,EXIT,COMMA      ; [EXIT] ,
                        ; done
                        dq      EXIT

                        ; ( n -- )
                        DEFASM  "ALLOT",ALLOT,0
                        CHKUNF  1
                        mov     rdx,[r15]
                        add     r15,8
                        ; get CFA field for latest definition
                        mov     rdi,[rbp-LATEST]
                        push    rdx
                        call    _tocfa
                        pop     rdx
                        mov     rdi,rax
                        ; check if it's a user definition
                        lea     rax,fvm_douser
                        cmp     [rdi],rax
                        je      .ok
                        ; nope, trigger error
                        jmp     fvm_noparam
                        ; yes, check if increment value
                        ; is negative
.ok                     test    rdx,rdx
                        jl      .negcount
                        ; it's positive, multiply by 8
                        shl     rdx,3
                        ; test again if it's now negative
                        test    rdx,rdx
                        jl      .negcount
                        ; it's positive or zero, add to HERE
                        add     rbx,rdx
                        ; TODO !!memory exhaustion checks!!
                        NEXT
                        ; count to be allotted is negative
.negcount               jmp     fvm_negallot

                        ; ( n -- bool )
                        DEFCOL  "?TRUE",ISTRUE,0
                        dq      NEZEROINT,EXIT      ; <>0

                        ; ( n -- bool )
                        DEFCOL  "?FALSE",ISFALSE,0
                        dq      EQZEROINT,EXIT      ; =0

                        ; <n> IF ... [ ELSE ... ] THEN
                        ; <n> UNLESS ... [ ELSE ... ] THEN
                        ; ( <> stack parameter, [] optional )
                        ;
                        ; work like this:
                        ;
                        ; IF takes truth value from stack.
                        ;   If true, executes block following IF,
                        ;      then continues after THEN.
                        ;   If false, executes block optionally following
                        ;      ELSE, then continues after THEN.
                        ;
                        ; UNLESS takes truth value from stack.
                        ;   If false, executes block following UNLESS,
                        ;      then continues after THEN.
                        ;   If true, executes block optionally following
                        ;      ELSE, then contiues after THEN.
                        ;
                        ; IF compiles to:
                        ;   ?FALSE ?CONDJUMP[.elseorthen] [0]
                        ; then pushes the address of [0] to the return stack
                        ; using >R to be filled out later.
                        ;
                        ; UNLESS compiles to:
                        ;   ?TRUE ?CONDJUMP[.elseorthen] [0]
                        ; then pushes the address of [0] to the return stack
                        ; using >R to be filled out later.
                        ;
                        ; ELSE compiles to:
                        ;   JUMP[.then] [0]
                        ; then pops the return address from the return stack
                        ; using R> storing the address after the JUMP [0] at
                        ; that location.
                        ; then pushes the address of [0] after the JUMP to
                        ; the return stack using >R to be filled out later.
                        ;
                        ; THEN compiles to:
                        ;   (nothing)
                        ; then pops the return address from the return stack
                        ; using R> storing the current address there.
                        ;

                        ; IF compiles to:
                        ;   ?FALSE ?CONDJUMP[.elseorthen] [0]
                        ; then pushes the address of [0] to the return stack
                        ; using >R to be filled out later.
                        DEFASM  "IF",DOIF,F_IMMEDIATE
                        mov     rdi,rbx
                        cld
                        lea     rax,ISFALSE     ; store ISFALSE
                        stosq
                        lea     rax,CONDJUMP    ; store CONDJUMP
                        stosq
                        mov     rdx,rdi         ; remember position
                        xor     rax,rax         ; store 0
                        stosq
                        mov     rbx,rdi
                        RCHKOVF 1
                        sub     r14,8           ; store position on ret stack
                        mov     [r14],rdx
                        NEXT

                        ; UNLESS takes truth value from stack.
                        ;   If false, executes block following UNLESS,
                        ;      then continues after THEN.
                        ;   If true, executes block optionally following
                        ;      ELSE, then contiues after THEN.
                        DEFASM  "UNLESS",DOUNLESS,F_IMMEDIATE
                        mov     rdi,rbx
                        cld
                        lea     rax,ISTRUE      ; store ISTRUE
                        stosq
                        lea     rax,CONDJUMP    ; store CONDJUMP
                        stosq
                        mov     rdx,rdi         ; remember position
                        xor     rax,rax         ; store 0
                        stosq
                        mov     rbx,rdi
                        RCHKOVF 1
                        sub     r14,8           ; store position on ret stack
                        mov     [r14],rdx
                        NEXT

                        ; ELSE compiles to:
                        ;   JUMP[.then] [0]
                        ; then pops the return address from the return stack
                        ; using R> storing the address after the JUMP [0] at
                        ; that location.
                        ; then pushes the address of [0] after the JUMP to
                        ; the return stack using >R to be filled out later.
                        DEFASM  "ELSE",DOELSE,F_IMMEDIATE
                        mov     rdi,rbx
                        cld
                        lea     rax,JUMP        ; store JUMP
                        stosq
                        mov     rdx,rdi         ; remember position
                        xor     rax,rax         ; store 0
                        stosq
                        mov     rbx,rdi
                        RCHKUNF 1
                        mov     rax,[r14]       ; get position from ret stack
                        mov     [rax],rbx       ; put position for after ELSE
                        mov     [r14],rdx       ; leave position of 0 on retstk
                        NEXT

                        ; THEN compiles to:
                        ;   (nothing)
                        ; then pops the return address from the return stack
                        ; using R> storing the current address there.
                        ;
                        DEFASM  "THEN",DOTHEN,F_IMMEDIATE
                        RCHKUNF 1
                        mov     rax,[r14]       ; get position from ret stack
                        add     r14,8
                        mov     [rax],rbx       ; put position for after THEN
                        NEXT

                        ; move bytes
                        ; automatically handle overlapping copies
                        ; ( source target count -- )
                        DEFASM  "CMOVE",_CMOVE,0
                        CHKUNF  3
                        mov     rsi,[r15+16]
                        mov     rdi,[r15+8]
                        mov     rcx,[r15]
                        jrcxz   .done       ; no change (count zero)
                        cmp     rsi,rdi
                        je      .done       ; no change (src/tgt identical)
                        jb      .backwards
                        ; rsi > rdi: forward copy
                        ;       rsi ->
                        ;      /
                        ;   rdi ->
                        cld
                        rep     movsb
                        jmp     .done
                        ; rsi < rdi: backward copy
                        ;                <- rsi
                        ;                      \
                        ;                    <- rdi
.backwards              std
                        ; start with last byte
                        add     rdi,rcx
                        dec     rdi
                        add     rsi,rcx
                        dec     rsi
                        rep     movsb
                        cld
.done                   NEXT

                        ; move cells
                        ; automatically handle overlapping copies
                        ; ( source target count -- )
                        DEFASM  "MOVE",_MOVE,0
                        CHKUNF  3
                        mov     rax,7
                        not     rax
                        mov     rsi,[r15+16]
                        and     rsi,rax         ; quadword align pointer
                        mov     rdi,[r15+8]
                        and     rdi,rax         ; quadword align pointer
                        mov     rcx,[r15]
                        jrcxz   .done           ; no change (count zero)
                        cmp     rsi,rdi
                        je      .done           ; no change (src/tgt identical)
                        jb      .backwards
                        ; rsi > rdi: forward copy
                        ;       rsi ->
                        ;      /
                        ;   rdi ->
                        cld
                        rep     movsq
                        jmp     .done
                        ; rsi < rdi: backward copy
                        ;                <- rsi
                        ;                      \
                        ;                    <- rdi
.backwards              std
                        ; start with last cell
                        lea     rdi,[rdi+rcx*8]
                        sub     rdi,8
                        lea     rsi,[rsi+rcx*8]
                        sub     rsi,8
                        rep     movsq
                        cld
.done                   NEXT

                        DEFCOL  "HEX",_HEX,0
                        dq      LIT,16,PUSHBASE,STORE,EXIT

                        DEFCOL  "DECIMAL",_DEC,0
                        dq      LIT,10,PUSHBASE,STORE,EXIT

                        DEFCOL  "OCTAL",_OCT,0
                        dq      LIT,8,PUSHBASE,STORE,EXIT

                        DEFCOL  "BINARY",_BIN,0
                        dq      LIT,2,PUSHBASE,STORE,EXIT

                        section .text
                        align   32

                        ; load a byte from [rsi] into al, incrementing rsi
                        ; before doing that, check if rsi is equal or beyond r11
                        ; the parameter specifies a label to jump to on failure
                        %macro  LOADB 1
                        cmp     rsi,r11
                        jb      %%skip
                        jmp     %1
%%skip                  lodsb
                        %endmacro

                        ; store a byte from al into [rdi], incrementing rdi
                        ; before doing that, check if rdi is equal or beyond r10
                        %macro  STORB 0
                        cmp     rdi,r10
                        jae     %%skip
                        stosb
%%skip:
                        %endmacro

                        ; same as what REP LOADB would do
                        %macro  REPLOADB 1
%%next                  LOADB   %1
                        loop    %%next
                        %endmacro

                        ; same as what REP STORB would do
                        %macro  REPSTORB 0
%%next                  STORB
                        loop    %%next
                        %endmacro

                        ; equivalent to LOADB %1 followed by STORB
                        %macro  MOVEB 1
                        LOADB   %1
                        STORB
                        %endmacro

                        ; equivalent to REP MOVEB
                        %macro  REPMOVEB 1
%%next                  MOVEB   %1
                        loop    %%next
                        %endmacro

                        ; fix up exponent (also generates new output)
                        ; (algorithm taken from my other project "AsmBASIC",
                        ; module toknum.nasm, function detok_wrnum())
                        ;   rdi - pointer beyond end of target buffer (char*)
                        ;   rsi - pointer to target buffer (char*)
                        ;   rdx - pointer beyond end of source buffer
                        ;         (const char*), this must mark the end of the
                        ;         source string, not the capacity of the buffer
                        ;   rcx - pointer to source buffer (const char*)
                        ;   r8  - maximum number of digits
                        ;   r9  - total number of digits
                        ;   [rsp+8] - exponent
                        ; output:
                        ;   rax - number of bytes remaining in target buffer
                        ;
                        ; prepare arguments for remainder of code
_fixupexp               mov         r10,rdi ; pointer beyond end of target
                        mov         r11,rdx ; pointer beyond end of source
                        mov         rdi,rsi ; pointer to target buffer
                        mov         rsi,rcx ; pointer to source buffer
                        mov         rdx,r8  ; maximum number of digits
                        mov         rcx,r9  ; total number of digits
                        mov         r8,[rsp+8] ; exponent
                        ;
                        ;   rdi - pointer to target buffer (char*)
                        ;   rsi - pointer to source buffer (const char*)
                        ;   rdx - maximum number of digits
                        ;   rcx - total number of digits
                        ;   r8  - exponent
                        ;   r10 - pointer beyond end of target buffer
                        ;   r11 - pointer beyond end of source buffer
                        ;
                        ; get exponent shift
                        mov         rax,r8
                        mov         r9,rdx      ; save maximum number of digits
                        cld
                        ;   r9  - backup of maximum number of digits
                        ; check to see if it's zero, positive or negative
                        cmp         ax,0
                        je          .noshift
                        jg          .exppos
                        ; exp is negative
; what we want here is:
;   1.23 (e-7)
;  |h|    dl   |
;   0.000000123
; total leeway we have is MAXDEC - current number of digits
                        sub         dx,cx
                        cmp         dx,0
                        je          .noshift
                        ; compare exponent against that
                        neg         ax
                        cmp         ax,dx
                        jle         .neglessmax
                        mov         ax,dx   ; limit to dx
                        jmp         .negshift
.neglessmax             mov         dx,ax   ; limit to ax
                        ; reduce exponent by amount
.negshift               sub         ax,dx
                        neg         ax
                        movsx       rax,ax
                        mov         r8,rax ; store new exponent
                        ; dx contains the number of zeros before
                        ; the actual digits, the first one being
                        ; the one before the decimal point.
                        mov         al,'0'
                        STORB
                        mov         al,'.'
                        STORB
                        mov         al,'0'
.leadzero               dec         dl
                        jz          .endlead
                        STORB
                        jmp         .leadzero
                        ; now output the remaining digits
.endlead                movzx       rcx,cx
.endlead2               LOADB       .shiftdone
                        cmp         al,'.'
                        je          .endlead2
                        STORB
                        loop        .endlead2
                        jmp         .shiftdone
                        ; exponent is positive
; what we want here is:
;   1.23 (e+7)
;  |h|    dl   |
;   12300000
.exppos                 mov         rdx,r9  ; maximum number of digits
                        ; compare exponent against that
                        cmp         ax,dx
                        jle         .lessmax
                        mov         dx,cx   ; limit to cx
                        jmp         .shift
.lessmax                mov         dx,ax   ; limit to ax
                        ; reduce exponent by amount
.shift                  sub         ax,dx
                        movsx       rax,ax
                        mov         r8,rax ; store new exponent
                        ; dx contains the number of digits
                        ; either fetched from after the decimal point
                        ; or added as zeroes to the end
                        movzx       rcx,cx
                        ; first, copy the leading digits straight over
.fetchloop              LOADB       .fetchend
                        cmp         al,'.'
                        je          .gotdp
                        cmp         al,'0'
                        je          .skipfetch
                        STORB
.skipfetch              loop        .fetchloop
                        ; finished before reaching a decimal point
                        ; now add dx zeroes
.fetchend               movzx       rcx,dx
                        test        rcx,rcx
                        jz          .shiftdone
                        mov         al,'0'
                        REPSTORB
                        jmp         .shiftdone
                        ; after decimal point
                        ;   cx - available digits in buffer
                        ;   dx - digits to go before decimal point
.gotdp                  cmp         dx,cx
                        jg          .fillzero
                        ; dx <= cx
                        ; copy digits to write before decimal point
                        sub         cx,dx
                        xchg        cx,dx
                        movzx       rcx,cx
                        test        rcx,rcx
                        jz          .skipcopy
                        REPMOVEB    .skipcopy
                        ; write decimal point then remaining digits
.skipcopy               xchg        cx,dx
                        movzx       rcx,cx
                        test        rcx,rcx
                        jz          .shiftdone
                        mov         al,'.'
                        STORB
                        REPMOVEB    .shiftdone
                        jmp         .shiftdone
                        ; integral number (no fraction intended)
                        ; dx > cx, fillcnt = dx - cx
.fillzero               sub         dx,cx
                        ; copy remaining digits
                        movzx       rcx,cx
                        rep         movsb
                        REPMOVEB    .filldo
                        ; then fill with zeroes
.filldo                 movzx       rcx,dx
                        mov         al,'0'
                        REPSTORB
                        jmp         .shiftdone
                        ; no shift: copy result over
.noshift                inc         rcx     ; increase b/c of dot
                        ; copy: note that the source limit must point beyond
                        ;       the end of the source string, or this fails
                        REPMOVEB    .copydone
                        ; if the last character written was a '.', delete it
.copydone               cmp         byte [rdi-1],'.'
                        jne         .shiftdone
                        dec         rdi
                        ; after shifting the number around, examine exponent
                        ; (not done in this implementation, see C code)
.shiftdone              nop
                        ; normally, the code would write a terminating NUL byte,
                        ; but since we don't need that in FORTH, we return the
                        ; number of remaining bytes in the target buffer instead
.complete               mov         rax,r10
                        sub         rax,rdi
                        ; also return new exponent
                        mov         rdx,r8
                        ret

                        ; fix up exponent (also generates new output)
                        ; ( tlimit taddr saddrend saddr maxdig totdig exp
                        ;   -- tremain newexp )
                        DEFASM  "FIXUPEXP",FIXUPEXP,0
                        ;48 rdi - pointer beyond end of target buffer (char*)
                        ;40 rsi - pointer to target buffer (char*)
                        ;32 rdx - pointer beyond end of source buffer
                        ;         (const char*), this must mark the end of the
                        ;         source string, not the capacity of the buffer
                        ;24 rcx - pointer to source buffer (const char*)
                        ;16 r8  - maximum number of digits
                        ;8  r9  - total number of digits
                        ;0  [rsp+8] - exponent
                        ; output:
                        ;   rax - number of bytes remaining in target buffer
                        ;   rdx - new exponent
                        CHKUNF  7
                        mov     rdi,[r15+48]    ; target buffer limit
                        mov     rsi,[r15+40]    ; target buffer
                        mov     rdx,[r15+32]    ; source buffer endptr
                        mov     rcx,[r15+24]    ; source buffer
                        mov     r8,[r15+16]     ; max digits
                        mov     r9,[r15+8]      ; total digits
                        mov     rax,[r15]       ; current exponent
                        push    rax
                        add     r15,40
                        call    _fixupexp
                        mov     [r15+8],rax     ; store tremain
                        mov     [r15],rdx       ; store new exponent
                        NEXT

                        ; truncate number towards zero
                        ; ( n -- n )
                        DEFASM  "FTRUNC",FTRUNC,0
                        CHKUNF  1
                        fld     qword [r15]
                        push    rax
                        ; set rounding towards zero
                        fstcw   word [rsp]
                        mov     ax,[rsp]
                        and     ax,0xf3ff
                        or      ax,0x0c00   ; round towards zero (RC=0b11)
                        mov     word [rsp+2],ax
                        fldcw   word [rsp+2]
                        ; round the number to integer (towards zero)
                        frndint
                        ; restore rounding mode
                        fldcw   word [rsp]
                        pop     rax
                        fstp    qword [r15]
                        NEXT

                        align   32

                        ; convert a digit value to a text character
                        ;   rax - digit
                        ; output:
                        ;   rax - char
_dig2chr                movzx   rax,al
                        cmp     al,9
                        ja      .geten
                        add     al,'0'
                        jmp     .end
.geten                  sub     al,10
                        add     al,'A'
.end                    ret

                        ; convert a digit value to a text character
                        ; (ignores the current number base)
                        ; ( digitval -- textchar )
                        DEFASM  "DIG2CHR",DIG2CHR,0
                        CHKUNF  1
                        mov     rax,[r15]
                        call    _dig2chr
                        mov     [r15],rax
                        NEXT

                        ; stores a digit at the specified address
                        ; then increases that address, as long as the
                        ; address is smaller than the provided limit
                        ; ( limit addr digit -- limit addr )
                        DEFASM  "DIG!",STOREDIG,0
                        CHKUNF  3
                        mov     rsi,[r15+16]
                        mov     rdi,[r15+8]
                        mov     rax,[r15]
                        add     r15,8
                        call    _dig2chr
                        cmp     rdi,rsi
                        jae     .dontstore
                        cld
                        stosb
                        mov     [r15],rdi   ; store new addr
.dontstore              NEXT

                        ; stores a dot at the specified address
                        ; then increases that address, as long as the
                        ; address is smaller than the provided limit
                        ; ( limit addr -- limit addr )
                        DEFASM  "DOT!",STOREDOT,0
                        CHKUNF  2
                        mov     rsi,[r15+8]
                        mov     rdi,[r15]
                        cmp     rdi,rsi
                        jae     .dontstore
                        cld
                        mov     al,'.'
                        stosb
                        mov     [r15],rdi   ; store new addr
.dontstore              NEXT

                        ; stores a minus at the specified address
                        ; then increases that address, as long as the
                        ; address is smaller than the provided limit
                        ; ( limit addr -- limit addr )
                        DEFASM  "MINUS!",STOREMINUS,0
                        CHKUNF  2
                        mov     rsi,[r15+8]
                        mov     rdi,[r15]
                        cmp     rdi,rsi
                        jae     .dontstore
                        cld
                        mov     al,'-'
                        stosb
                        mov     [r15],rdi   ; store new addr
.dontstore              NEXT

                        ; stores an exponent indicator at the specified address
                        ; then increases that address, as long as the
                        ; address is smaller than the provided limit
                        ; ( limit addr -- limit addr )
                        DEFASM  "EXPIND!",STOREEXPIND,0
                        CHKUNF  2
                        mov     rsi,[r15+8]
                        mov     rdi,[r15]
                        cmp     rdi,rsi
                        jae     .dontstore
                        cld
                        mov     rax,[rbp-BASE]
                        cmp     rax,10  ; check if base > 10
                        ja      .largebase
                        mov     al,'E'
                        stosb
                        jmp     .end
.largebase              mov     al,"'"
                        stosb
.end                    mov     [r15],rdi   ; store new addr
.dontstore              NEXT

                        ; Store digits from a floating-point number
                        ; that is in normalized form (i.e. with one leading
                        ; digit at most) using the current number base (BASE).
                        ; Returns the number of bytes remaining in the buffer.
                        ; ( maxdig first limit addr data -- remain )
                        DEFCOL  "DIGITS!",STOREDIGITS,0
                        ; set first to TRUE
                        dq      LIT,4,ROLL,DROP,LIT,-1  ; 4 ROLL DROP -1
                        dq      LIT,-4,ROLL             ; -4 ROLL
                        ; ( maxdig first limit addr data )
.nextchr                dq      LIT,5,PICK,LTZEROINT    ; 5 PICK <=0
                        dq      CONDJUMP,.stop          ; ?JUMP[.stop]
                        ; ( maxdig first limit addr data )
                        ; decrement maxdig
                        dq      LIT,5,ROLL,SUBONE       ; 5 ROLL 1-
                        dq      LIT,-5,ROLL             ; -5 ROLL
                        ; ( maxdig first limit addr data )
                        dq      DUP,FTRUNC,PUSHBASE,FETCH ; DUP FTRUNC BASE @
                        ; ( maxdig first limit addr data truncdata base )
                        dq      I2F,MODFLT,F2I          ; I2F FMOD F2I
                        ; ( maxdig first limit addr data digit )
                        dq      SWAP                    ; SWAP
                        ; ( maxdig first limit addr digit data )
                        dq      LIT,-6,ROLL             ; -6 ROLL
                        ; ( data maxdig first limit addr digit )
                        dq      STOREDIG                ; DIG!
                        ; ( data maxdig first limit addr )
                        ; test 'first' flag
                        dq      LIT,3,PICK,BINNOT       ; 3 PICK NOT
                        dq      CONDJUMP,.skip          ; ?JUMP[.skip]
                        ; first digit: clear first flag
                        dq      ROT                     ; ROT
                        ; ( data maxdig limit addr first )
                        dq      BINNOT                  ; NOT
                        dq      LIT,-3,ROLL             ; -3 ROLL
                        ; ( data maxdig first limit addr )
                        ; first digit: store dot
                        dq      STOREDOT                ; DOT!
                        ; ( data maxdig first limit addr )
                        ; multiply data by BASE
.skip                   dq      LIT,5,ROLL              ; 5 ROLL
                        ; ( maxdig first limit addr data )
                        dq      PUSHBASE,FETCH,I2F      ; BASE @ I2F
                        dq      MULFLT                  ; F*
                        dq      JUMP,.nextchr           ; JUMP[.nextchr]
                        ; ( maxdig first limit addr data )
.stop                   dq      DROP                    ; DROP
                        ; ( maxdig first limit addr )
                        dq      SUBINT                  ; -
                        ; ( maxdig first remain )
                        dq      LIT,-3,ROLL             ; -3 ROLL
                        ; ( remain maxdig first )
                        dq      TWODROP                 ; 2DROP
                        ; ( remain )
                        dq      EXIT

                        DEFASM  "PREP",PUSHPREP,0
                        CHKOVF  1
                        sub     r15,8
                        lea     rax,[rbp-PREPBUF]
                        mov     [r15],rax
                        NEXT

                        DEFASM  "PREP2",PUSHPREP2,0
                        CHKOVF  1
                        sub     r15,8
                        lea     rax,[rbp-PREPBUF2]
                        mov     [r15],rax
                        NEXT

                        ; "zero-run"
                        ; eliminate trailing zeroes at the end of the buffer
                        ; by decrementing addr
                        ; ( start addr -- start addr )
                        DEFCOL  "ZERORUN",ZERORUN,0
                        ; ( start addr )
.prev                   dq      SWAP,TWODUP     ; SWAP 2DUP
                        ; ( addr start addr start )
                        dq      UGTINT,BINNOT   ; U> NOT
                        dq      CONDJUMP,.done  ; ?JUMP[.done]
                        dq      SWAP
                        ; ( start addr )
                        dq      SUBONE          ; 1-
                        dq      DUP,CHARFETCH   ; DUP C@
                        dq      LIT,'0',EQINT   ; '0' =
                        dq      CONDJUMP,.prev  ; ?JUMP[.prev]
                        ; ( start addr )
                        ; finished, increase addr by 1
                        dq      ADDONE          ; 1+
                        dq      EXIT
                        ; ( addr start )
.done                   dq      SWAP,EXIT

                        ; "nine-run"
                        ; Eliminate trailing nines at the end of the buffer
                        ; by decrementing addr.
                        ; What a "nine" is is determined by BASE (=BASE-1).
                        ; On the digit that was not "nine", increment by 1.
                        ; ( start addr -- start addr )
                        DEFCOL  "NINERUN",NINERUN,0
                        dq      PUSHBASE,FETCH  ; BASE @
                        dq      SUBONE          ; 1-
                        dq      DIG2CHR         ; DIG2CHR
                        ; ( start addr nine )
                        dq      LIT,-3,ROLL     ; -3 ROLL
                        ; ( nine start addr )
.prev                   dq      SWAP,TWODUP     ; SWAP 2DUP
                        ; ( nine addr start addr start )
                        dq      UGTINT,BINNOT ; OVER U> NOT
                        dq      CONDJUMP,.done  ; ?JUMP[.done]
                        dq      SWAP            ; SWAP
                        ; ( nine start addr )
                        dq      SUBONE          ; 1-
                        dq      DUP,CHARFETCH   ; DUP C@
                        ; ( nine start addr char )
                        dq      LIT,4,PICK,EQINT  ; 4 PICK =
                        dq      CONDJUMP,.prev  ; ?JUMP[.prev]
                        ; ( nine start addr )
                        dq      DUP,CHARFETCH   ; C@
                        ; ( nine start addr char )
                        dq      LIT,'.',EQINT   ; '.' =
                        dq      CONDJUMP,.prev  ; ?JUMP[.prev]
                        ; ( nine start addr )
                        ; on the character that is not a "nine"
                        ; and not a dot: increment it
                        dq      DUP,CINCR       ; CINCR
                        ; increment pointer to point past that
                        dq      ADDONE          ; 1+
                        ; ( nine start addr )
                        ; get the "nine" on top
.finish                 dq      ROT             ; ROT
                        ; ( start addr nine )
                        ; drop it
                        dq      DROP            ; DROP
                        ; ( start addr )
                        ; done
                        dq      EXIT
                        ; ( nine addr start )
.done                   dq      SWAP            ; SWAP
                        dq      JUMP,.finish    ; JUMP[.finish]

                        ; output mantissa of unified number
                        ; (with at most one leading digit before the decimal
                        ; point)
                        ; ( start limit number maxdig -- length )
                        DEFCOL  "OUTMANT",OUTMANT,0
                        ; ( start limit number maxdig )
                        dq      LIT,-1              ; -1
                        ; ( start limit number maxdig first )
                        dq      LIT,-4,ROLL         ; -4 ROLL
                        ; ( start first limit number maxdig )
                        dq      LIT,-4,ROLL         ; -4 ROLL
                        ; ( start maxdig first limit number )
                        dq      LIT,5,PICK          ; 5 PICK
                        ; ( start maxdig first limit number addr )
                        dq      SWAP                ; SWAP
                        ; ( start maxdig first limit addr number )
                        ; make copy of limit
                        dq      LIT,3,PICK          ; 3 PICK
                        ; ( start maxdig first limit addr number limit )
                        dq      LIT,-6,ROLL         ; -6 ROLL
                        ; ( start limit maxdig first limit addr number )
                        dq      STOREDIGITS         ; DIGITS!
                        ; ( start limit remain )
                        dq      SUBINT              ; -
                        ; ( start addr )
                        ; Now digits are stored, addr points past the end.
                        ; Now we have to check whether we need to do either
                        ; a zero-run or a nine-run (see above).
                        ; if addr equals start, do nothing
                        dq      SWAP,TWODUP         ; SWAP 2DUP
                        ; ( addr start addr start )
                        dq      UGTINT,BINNOT       ; U> NOT
                        dq      CONDJUMP,.stop      ; ?JUMP[.stop]
                        dq      SWAP                ; SWAP
                        ; ( start addr )
                        ; check if the character right before is a '0'
                        dq      DUP,SUBONE,CHARFETCH ; DUP 1- C@
                        ; ( start addr char )
                        dq      DUP,LIT,'0',NEINT   ; DUP '0' <>
                        dq      CONDJUMP,.notzero
                        ; ( start addr char )
                        ; yes: do zero-run
                        dq      DROP,ZERORUN        ; DROP ZERORUN
                        dq      JUMP,.stop2         ; JUMP[.stop]
                        ; ( start addr char )
                        ; see if it's a "nine" (BASE-1)
.notzero                dq      PUSHBASE,FETCH,SUBONE ; BASE @ 1-
                        dq      DIG2CHR             ; DIG2CHR
                        ; ( start addr char nine )
                        dq      NEINT,CONDJUMP,.stop2 ; <> ?JUMP[.stop2]
                        ; ( start addr )
                        ; do nine-run
                        dq      NINERUN             ; NINERUN
                        ; ( start addr )
.stop2                  dq      SWAP                ; SWAP
                        ; ( addr start )
.stop                   dq      SUBINT              ; -
                        ; ( length )
                        dq      EXIT

                        ; count digits before and after optional decimal point
                        ; ( start end -- start end hasdot before after )
                        DEFCOL  "COUNTDIG",COUNTDIG,0
                        dq      OVER                ; OVER
                        ; ( start end ptr )
                        dq      LIT,0,LIT,0,LIT,0   ; 0 0 0
                        ; ( start end ptr hasdot before after )
.next                   dq      LIT,5,ROLL,LIT,5,ROLL ; 5 ROLL 5 ROLL
                        ; ( start hasdot before after end ptr )
                        dq      SWAP,TWODUP,UGEINT  ; SWAP 2DUP U>=
                        dq      CONDJUMP,.end       ; ?JUMP[.end]
                        dq      SWAP
                        ; ( start hasdot before after end ptr )
                        dq      DUP,ADDONE,SWAP     ; DUP +1 SWAP
                        ; ( start hasdot before after end newptr ptr )
                        dq      CHARFETCH       ; DUP C@
                        dq      LIT,'.',NEINT       ; '.' <>
                        dq      CONDJUMP,.notdot    ; JUMP[.notdot]
                        ; dot: set hasdot flag
                        ; ( start hasdot before after end newptr )
                        dq      LIT,-5,ROLL,LIT,-5,ROLL ; -5 ROLL -5 ROLL
                        ; ( start end newptr hasdot before after )
                        dq      ROT                 ; ROT
                        ; ( start end newptr before after hasdot )
                        dq      DROP,LIT,-1         ; DROP -1
                        ; ( start end newptr before after hasdot )
                        dq      LIT,-3,ROLL
                        ; ( start end newptr hasdot before after )
                        dq      JUMP,.next          ; JUMP[.next]
                        ; ( start hasdot before after end newptr )
.notdot                 dq      LIT,-5,ROLL,LIT,-5,ROLL ; -5 ROLL -5 ROLL
                        ; ( start end newptr hasdot before after )
                        dq      LIT,3,PICK          ; 3 PICK
                        dq      CONDJUMP,.hasdot    ; ?JUMP[.hasdot]
                        ; ( start end newptr hasdot before after )
                        ; no dot yet: increase before
                        dq      SWAP,ADDONE,SWAP    ; SWAP 1+ SWAP
                        dq      JUMP,.next          ; JUMP[.next]
                        ; ( start end newptr hasdot before after )
                        ; has dot: increase after
.hasdot                 dq      ADDONE              ; 1+
                        dq      JUMP,.next          ; JUMP[.next]
                        ; ( start hasdot before after ptr end )
.end                    dq      SWAP                ; SWAP
                        ; ( start hasdot before after end ptr )
                        dq      DROP                ; DROP
                        ; ( start hasdot before after end )
                        dq      LIT,-4,ROLL         ; -4 ROLL
                        ; ( start end hasdot before after )
                        dq      EXIT

                        ; call C function
                        ; NOTES:
                        ;   - passing of floating-point arguments
                        ;     in XMM registers is NOT supported
                        ;   - if you do need to pass floating-point arguments
                        ;     put them in a data structure and pass a pointer
                        ;     to them
                        ;   - see abinotes.txt for information about
                        ;     C calling conventions in 64-bit mode
                        ;   - some C functions crash if the stack pointer isn't
                        ;     aligned on 32-byte boundary before the call
                        ;     instruction (the reason is they use aligned
                        ;     memory access instructions like MOVDQA)
                        ;     hence, I align for that instead of just 16 bytes
                        ;     as noted in the ABI documentation.
                        ; ( ... nargs func -- result )
                        ;   nargs - number of regular arguments (ptr,int)
                        ;   func  - address of C function
                        DEFASM  "CALLC",CALLC,0
                        CHKUNF  2
                        ; save stack pointer
                        mov     [rbp-CALLSTKP],rsp
                        ; pop func and nargs
                        mov     rax,[r15]
                        mov     [rbp-CALLADDR],rax
                        mov     rax,[r15+8]
                        mov     [rbp-CALLARGS],rax
                        add     r15,16
                        CHKUNF  rax
                        ; adjust system stack pointer
                        ; must be 32-byte aligned on call
                        xor     rdx,rdx       ; stack args size
                        cmp     rax,6
                        jbe     .lesseqsix    ; are passed in regs
                        mov     rdx,rax       ; rax-6 is stack count
                        shl     rdx,3         ; * 8
                        sub     rsp,rdx       ; reserve on stack
.lesseqsix              sub     rsp,31        ; align to 32-byte boundary
                        and     rsp,~31
                        add     rsp,rdx       ; move up in stack for pushes
                        ; pass args in prescribed registers
                        ; (see abinotes.txt)
                        test    rax,rax
                        jz      .endargs
                        lea     r11,[r15+rax*8]
                        ; 1st parameter: rdi
                        mov     rdi,[r11]
                        sub     r11,8
                        dec     rax
                        jz      .endargs
                        ; 2nd parameter: rsi
                        mov     rsi,[r11]
                        sub     r11,8
                        dec     rax
                        jz      .endargs
                        ; 3rd parameter: rdx
                        mov     rdx,[r11]
                        sub     r11,8
                        dec     rax
                        jz      .endargs
                        ; 4th parameter: rcx
                        mov     rcx,[r11]
                        sub     r11,8
                        dec     rax
                        jz      .endargs
                        ; 5th parameter: r8
                        mov     r8,[r11]
                        sub     r11,8
                        dec     rax
                        jz      .endargs
                        ; 6th parameter: r9
                        mov     r9,[r11]
                        sub     r11,8
                        dec     rax
                        jz      .endargs
                        ; from 7th parameter: pass on stack
.nextarg                mov     r10,[r11]
                        sub     r11,8
                        push    r10
                        dec     rax
                        jz      .endargs
                        jmp     .nextarg
                        ; end of argument list
                        ; adjust parameter stack pointer
.endargs                mov     rax,[rbp-CALLARGS]
                        lea     r15,[r15+rax*8]
                        ; set al to XMM register count
                        ; (always zero here)
                        xor     rax,rax
                        ; call function
                        mov     r10,[rbp-CALLADDR]
                        call    r10
                        ; restore stack pointer
                        mov     rsp,[rbp-CALLSTKP]
                        ; get result
                        CHKOVF  1
                        sub     r15,8
                        mov     [r15],rax
                        ; finished
                        NEXT

                        ; Normally, during compilation, the most recently
                        ; defined word is hidden, so a previous declaration
                        ; of the same word can be referenced.
                        ; However, sometimes you might want NOT to hide the
                        ; word to be able to implement recursion.
                        DEFCOL  "UNHIDE",UNHIDE,F_IMMEDIATE
                        dq      TOLATEST,FETCH      ; >LATEST @
                        ; ( defaddr )
                        ; get namelength/flags byte
                        dq      DUP,LIT,8,ADDINT    ;   DUP 8 +
                        ; ( defaddr addr )
                        dq      DUP,CHARFETCH       ;   DUP C@
                        ; ( defptr addr char )
                        dq      LIT,F_HIDDEN,BINNOT ; [F_HIDDEN] NOT
                        dq      BINAND              ; AND
                        ; ( defptr addr char )
                        dq      SWAP,CHARSTORE      ; SWAP C!
                        ; ( defptr )
                        dq      DROP                ; DROP
                        dq      EXIT

                        ; inverse of UNHIDE: restore F_HIDDEN state
                        DEFCOL  "HIDE",HIDE,F_IMMEDIATE
                        dq      TOLATEST,FETCH      ; >LATEST @
                        ; ( defaddr )
                        ; get namelength/flags byte
                        dq      DUP,LIT,8,ADDINT    ;   DUP 8 +
                        ; ( defaddr addr )
                        dq      DUP,CHARFETCH       ;   DUP C@
                        ; ( defptr addr char )
                        dq      LIT,F_HIDDEN,BINOR  ; [F_HIDDEN] OR
                        ; ( defptr addr char )
                        dq      SWAP,CHARSTORE      ; SWAP C!
                        ; ( defptr )
                        dq      DROP                ; DROP
                        dq      EXIT

                        ; output integral exponent using recursion
                        ; ( limit addr value -- limit addr )
                        DEFCOL  "OUTEXP",OUTEXP,0
                        dq      DUP,PUSHBASE,FETCH,GEINT ; DUP BASE @ >=
                        dq      CONDJUMP,.recurse       ; ?JUMP[.recurse]
                        ; ( limit addr value )
                        ; value is smaller than BASE
.store                  dq      DIG2CHR                 ; DIG2CHR
                        ; ( limit addr char )
                        ; see if there's room in buffer left
                        dq      LIT,-3,ROLL             ; -3 ROLL
                        ; ( char limit addr )
                        dq      SWAP,TWODUP,UGEINT      ; SWAP 2DUP U>=
                        dq      CONDJUMP,.dontstore     ; ?JUMP[.dontstore]
                        ; ( char addr limit )
                        dq      SWAP,ROT                ; SWAP ROT
                        ; ( limit addr char )
                        dq      OVER,CHARSTORE          ; C!
                        ; ( limit addr )
                        dq      ADDONE                  ; 1+
                        ; done
                        dq      EXIT
                        ; ( char addr limit )
.dontstore              dq      SWAP,ROT                ; SWAP ROT
                        ; ( limit addr char )
                        dq      DROP
                        ; ( limit addr )
                        ; finished
                        dq      EXIT
                        ; ( limit addr value )
                        ; value >= BASE, divide and recurse
                        ; create backup copy of value
.recurse                dq      LIT,-3,ROLL             ; -3 ROLL
                        ; ( value limit addr )
                        dq      LIT,3,PICK              ; 3 PICK
                        ; ( value limit addr value )
                        ; divide by BASE
                        dq      PUSHBASE,FETCH,DIVINT   ; BASE @ /
                        ; ( value limit addr value )
                        ; call ourselves, which will eat the value
                        dq      OUTEXP                  ; OUTEXP
                        ; ( value limit addr )
                        ; get the value backup to the front
                        dq      ROT                     ; ROT
                        ; ( limit addr value )
                        ; do a modulo operation with BASE
                        dq      PUSHBASE,FETCH,MODINT   ; BASE @ MOD
                        ; ( limit addr digit )
                        dq      JUMP,.store             ; JUMP[.store]

                        ; Fixes up floating point exponent, and in the
                        ; process, also generates a new representation
                        ; for the number which includes an optional
                        ; exponent field. The input number must be normalized,
                        ; i.e. contain at most one leading digit before the
                        ; optional decimal point. The target buffer must be
                        ; large enough to hold the new representation.
                        ; ( tlimit taddr saddrend saddr hasdot before after
                        ; maxdig exponent sign -- tremain )
                        DEFCOL  "FIXEXPON",FIXEXPON,0
                        ; use sign to add a '-' if necessary
                        dq      BINNOT,CONDJUMP,.nosign     ; NOT ?JUMP[.nosign]
                        ; ( tlimit taddr saddrend saddr hasdot before after
                        ;   maxdig exponent )
                        dq      LIT,9,ROLL,LIT,9,ROLL       ; 9 ROLL 9 ROLL
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   tlimit taddr )
                        ; test whether we can store it
                        dq      SWAP,TWODUP,UGEINT          ; SWAP 2DUP U>=
                        dq      CONDJUMP,.targetfull        ; ?JUMP[.targetfull]
                        ; yes: store
                        dq      SWAP                        ; SWAP
                        dq      STOREMINUS                  ; MINUS!
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   tlimit taddr )
                        ; restore order
                        dq      LIT,-9,ROLL,LIT,-9,ROLL     ; -9 ROLL -9 ROLL
                        ; ( tlimit taddr saddrend saddr hasdot before after
                        ;   maxdig exponent )
                        ; sum before and after
.nosign                 dq      LIT,4,ROLL,LIT,4,ROLL       ; 4 ROLL 4 ROLL
                        ; ( tlimit taddr saddrend saddr hasdot maxdig
                        ;   exponent before after )
                        dq      ADDINT                      ; +
                        ; ( tlimit taddr saddrend saddr hasdot maxdig
                        ;   exponent totdig )
                        dq      SWAP                        ; SWAP
                        ; ( tlimit taddr saddrend saddr hasdot maxdig
                        ;   totdig exponent )
                        ; bring hasdot to front
                        dq      LIT,4,ROLL                  ; 4 ROLL
                        ; ( tlimit taddr saddrend saddr maxdig totdig
                        ;   exponent hasdot )
                        ; drop it (we don't need it here)
                        dq      DROP                        ; DROP
                        ; ( tlimit taddr saddrend saddr maxdig totdig
                        ;   exponent )
                        ; make a copy of tlimit
                        dq      LIT,7,ROLL                  ; 7 ROLL
                        dq      DUP                         ; DUP
                        ; ( taddr saddrend saddr maxdig totdig exponent tlimit
                        ;   tlimit )
                        ; now restore order
                        dq      LIT,-8,ROLL,LIT,-8,ROLL     ; -8 ROLL -8 ROLL
                        ; ( tlimit tlimit taddr saddrend saddr maxdig totdig
                        ;   exponent )
                        ; fix up exponent
                        dq      FIXUPEXP                    ; FIXUPEXP
                        ; ( tlimit tremain exponent )
                        ; check if exponent is zero: don't need it then
                        dq      DUP,EQZEROINT               ; DUP =0
                        dq      CONDJUMP,.noexponent        ; ?JUMP[.noexponent]
                        ; compute a new taddr field from tlimit - tremain
                        dq      LIT,-3,ROLL                 ; -3 ROLL
                        ; ( exponent tlimit tremain )
                        dq      OVER,SWAP,SUBINT            ; OVER SWAP -
                        ; ( exponent tlimit taddr )
                        ; need to write exponent indicator: check if there's
                        ; room in the buffer
                        dq      SWAP,TWODUP,UGEINT       ; SWAP 2DUP U>=
                        dq      CONDJUMP,.bufferfull2    ; ?JUMP[.bufferfull2]
                        ; yes: write it
                        dq      STOREEXPIND                 ; EXPIND!
                        ; ( exponent tlimit taddr )
                        ; restore order
                        dq      LIT,3,ROLL                  ; 3 ROLL
                        ; ( tlimit taddr exponent )
                        ; check exponent again: if negative, store a minus
                        dq      DUP,LTZEROINT,BINNOT        ; DUP <0 NOT
                        dq      CONDJUMP,.notminus          ; ?JUMP[.notminus]
                        ; ( tlimit taddr exponent )
                        ; rotate stack to get exponent to the bottom
                        dq      LIT,-3,ROLL                 ; -3 ROLL
                        ; ( exponent tlimit taddr )
                        ; check if there's room to store the minus
                        dq      SWAP,TWODUP,UGEINT       ; SWAP 2DUP U>=
                        dq      CONDJUMP,.bufferfull2    ; ?JUMP[.bufferfull2]
                        ; store the minus
                        dq      SWAP
                        ; ( exponent tlimit taddr )
                        dq      STOREMINUS              ; MINUS!
                        ; bring the exponent back to the front
                        dq      ROT                     ; ROT
                        ; ( tlimit taddr exponent )
                        ; negate the exponent to make it positive
                        dq      NEGATE                  ; NEG
                        ; ( tlimit taddr exponent )
                        ; output the exponent's value
.notminus               dq      OUTEXP                  ; OUTEXP
                        ; ( tlimit taddr )
                        ; subtract taddr - tlimit to get tremain
                        dq      SWAP,SUBINT             ; SWAP -
                        ; ( tremain )
                        ; done
                        dq      EXIT
                        ; ( exponent taddr tlimit )
                        ; buffer is full, can't write exponent indicator
                        ; recompute tremain
.bufferfull2            dq      SUBINT                      ; -
                        ; ( exponent tremain )
                        ; drop the exponent field
                        dq      SWAP,DROP                   ; SWAP DROP
                        ; ( tremain )
                        ; finished
                        dq      EXIT
                        ; ( tlimit tremain exponent )
                        ; there's no exponent field, finish up
.noexponent             dq      SWAP                        ; SWAP
                        ; ( tlimit exponent tremain )
                        dq      LIT,-3,ROLL                 ; -3 ROLL
                        ; ( tremain tlimit exponent )
                        dq      TWODROP                     ; 2DROP
                        ; ( tremain )
                        dq      EXIT
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   taddr tlimit )
                        ; cannot write leading minus sign, finish up
                        ; compute tremain
.targetfull             dq      SUBINT                      ; -
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   tremain )
                        ; scroll args to leave tremain at the bottom
                        dq      LIT,-8,ROLL                 ; -8 ROLL
                        ; ( tremain saddrend saddr hasdot before after
                        ;   maxdig exponent )
                        ; drop the other fields
                        dq      TWODROP,TWODROP,TWODROP ; 2DROP 2DROP 2DROP
                        dq      DROP
                        ; ( tremain )
                        ; done
                        dq      EXIT

                        ; issues the CPU's FXAM command on the provided
                        ; floating-point value, and returns the resulting status
                        ; bits as an integer with the low 3 bits set to the
                        ; status bits C3, C2 and C0.
                        ;
                        ; The table of result values is as follows:
                        ;
                        ;  dec | C3 | C2 | C0 | description
                        ; -----+----+----+----+--------------------------------
                        ;   0  |  0 |  0 |  0 | Unsupported
                        ;   1  |  0 |  0 |  1 | NaN
                        ;   2  |  0 |  1 |  0 | Normal finite
                        ;   3  |  0 |  1 |  1 | Infinity
                        ;   4  |  1 |  0 |  0 | Zero
                        ;   5  |  1 |  0 |  1 | Empty
                        ;   6  |  1 |  1 |  0 | Denormal
                        ;   7  |  1 |  1 |  1 |
                        ;
                        ; ( number -- result )
                        DEFASM  "FEXAM",FLTEXAM,0
                        CHKUNF  1
                        fld     qword [r15]
                        fxam
                        fstsw   ax          ; get status word
                        ffree   st0
                        fincstp
                        and     ax,0x4500       ; C3 C2 C0
                        shr     ax,8
                        ; - C3 - -  - C2 - C0
                        mov     dl,al
                        and     al,0x01         ; C0
                        ; - - - -  - - - C0
                        mov     cl,dl
                        and     cl,0x04         ; C2
                        shr     cl,1
                        or      al,cl
                        ; - - - -  - - C2 C0
                        mov     cl,dl
                        and     cl,0x40         ; C3
                        shr     cl,4
                        or      al,cl
                        ; - - - -  - C3 C2 C0
                        movzx   rax,ax
                        mov     [r15],rax
                        NEXT

                        ; returns the sign of the provided floating-point number
                        ; TRUE means negative, FALSE means positive
                        ; ( number -- bool )
                        DEFASM  "?FSIGN",FLTSIGN,0
                        CHKUNF  1
                        fld     qword [r15]
                        fxam
                        fstsw   ax          ; get status word
                        ffree   st0
                        fincstp
                        and     ax,0x0200      ; C1
                        shr     ax,9
                        ; - - - -  - - - C1
                        neg     ax
                        movsx   rax,ax
                        mov     [r15],rax
                        NEXT

                        ; checks if floating point number is unsupported
                        ; ( number -- bool )
                        DEFCOL  "?FUNS",FLTISUNS,0
                        dq      FLTEXAM,EQZEROINT       ; FEXAM =0
                        dq      EXIT

                        ; checks if floating point number is not a number
                        ; ( number -- bool )
                        DEFCOL  "?FNAN",FLTISNAN,0
                        dq      FLTEXAM,LIT,1,EQINT     ; FEXAM 1 =
                        dq      EXIT

                        ; checks if floating point number is normal finite
                        ; ( number -- bool )
                        DEFCOL  "?FNORM",FLTISNORM,0
                        dq      FLTEXAM,LIT,2,EQINT     ; FEXAM 2 =
                        dq      EXIT

                        ; checks if floating point number is infinite
                        ; ( number -- bool )
                        DEFCOL  "?FINF",FLTISINF,0
                        dq      FLTEXAM,LIT,3,EQINT     ; FEXAM 3 =
                        dq      EXIT

                        ; checks if floating point number is zero
                        ; ( number -- bool )
                        DEFCOL  "?FZERO",FLTISZERO,0
                        dq      FLTEXAM,LIT,4,EQINT     ; FEXAM 4 =
                        dq      EXIT

                        ; checks if floating point number is empty
                        ; ( number -- bool )
                        DEFCOL  "?FEMP",FLTISEMPTY,0
                        dq      FLTEXAM,LIT,5,EQINT     ; FEXAM 5 =
                        dq      EXIT

                        ; checks if floating point number is denormal
                        ; ( number -- bool )
                        DEFCOL  "?FDEN",FLTISDEN,0
                        dq      FLTEXAM,LIT,6,EQINT     ; FEXAM 6 =
                        dq      EXIT

                        ; extracts significand and exponent from
                        ; given floating-point number, as regular
                        ; base 2 values.
                        ; ( number -- significand exponent )
                        DEFASM  "FEXTRACT",FEXTRACT,0
                        CHKOVF      1
                        fld         qword [r15]
                        sub         r15,8
                        ; execute fxtract
                        fxtract
                        ; st1 - exponent
                        ; st0 - significand
                        fstp        qword [r15+8]
                        fstp        qword [r15]
                        NEXT

                        ; Writes a special string to output if the provided
                        ; floating-point number is a special case, otherwise
                        ; writes just the sign. Returns a boolean TRUE if its a
                        ; finite normal number and the number itself. Returns
                        ; a boolean FALSE otherwise, a number of 0.0
                        ; ( number -- number bool )
                        DEFCOL  "FSPEC.",FSPECDOT,0
                        dq      DUP,FLTSIGN,BINNOT      ; DUP ?FSIGN NOT
                        dq      CONDJUMP,.notneg        ; ?JUMP[.notneg]
                        dq      LIT,.negtext,LIT,1,TYPEOUT ; [.negtext] 1 TYPE
                        dq      FNEGATE
                        dq      JUMP,.notneg            ; JUMP[.notneg]
.negtext                db      "-"
                        align   8
.notneg                 dq      DUP,FLTISNORM,BINNOT    ; DUP ?FNORM NOT
                        dq      CONDJUMP,.notnorm       ; ?JUMP[.notnorm]
                        ; normal number, return TRUE
                        dq      LIT,-1
                        dq      EXIT
.notnorm                dq      DUP,FLTISZERO,BINNOT    ; DUP ?FZERO NOT
                        dq      CONDJUMP,.notzero       ; ?JUMP[.notzero]
                        ; zero, output text
                        dq      LIT,.zertext,LIT,2,TYPEOUT ; [.zertext] 2 TYPE
                        dq      JUMP,.badend            ; JUMP[.badend]
.zertext                db      "0 "
                        align   8
.notzero                dq      DUP,FLTISDEN,BINNOT     ; DUP ?FDEN NOT
                        dq      CONDJUMP,.notden        ; ?JUMP[.notden]
                        ; denormal, output text
                        dq      LIT,.dentext,LIT,4,TYPEOUT ; [.dentext] 4 TYPE
                        dq      JUMP,.badend            ; JUMP[.badend]
.dentext                db      "den "
                        align   8
.notden                 dq      DUP,FLTISINF,BINNOT     ; DUP ?FINF NOT
                        dq      CONDJUMP,.notinf        ; ?JUMP[.notinf]
                        ; infinite, output text
                        dq      LIT,.inftext,LIT,4,TYPEOUT ; [.inftext] 4 TYPE
                        dq      JUMP,.badend            ; JUMP[.badend]
.inftext                db      "inf "
                        align   8
.notinf                 dq      DUP,FLTISNAN,BINNOT     ; DUP ?FNAN NOT
                        dq      CONDJUMP,.notnan        ; ?JUMP[.notnan]
                        ; not a number, output text
                        dq      LIT,.nantext,LIT,4,TYPEOUT ; [.nantext] 4 TYPE
                        dq      JUMP,.badend            ; JUMP[.badend]
.nantext                db      "nan "
                        align   8
.notnan                 dq      DUP,FLTISUNS,BINNOT     ; DUP ?FUNS NOT
                        dq      CONDJUMP,.notuns        ; ?JUMP[.notuns]
                        ; unsupported, output text
                        dq      LIT,.unstext,LIT,4,TYPEOUT ; [.unstext] 4 TYPE
                        dq      JUMP,.badend            ; JUMP[.badend]
.unstext                db      "uns "
                        align   8
.notuns                 dq      DUP,FLTISEMPTY,BINNOT   ; DUP ?FEMP NOT
                        dq      CONDJUMP,.notemp        ; ?JUMP[.notemp]
                        ; empty, output text
                        dq      LIT,.emptext,LIT,4,TYPEOUT ; [.unstext] 4 TYPE
                        dq      JUMP,.badend            ; JUMP[.badend]
.emptext                db      "emp "
                        align   8
.badend:                ; not a finite normal number
.notemp                 dq      DROP,LIT,0.0,LIT,0      ; DROP 0.0 0
                        dq      EXIT

                        ; Print floating-point number using number BASE
                        ; ( number -- )
                        DEFCOL  "F.",FLTDOT,0
                        ; first check the number base (BASE)
                        dq      CHECKBASE               ; CHECKBASE
                        ; classify number and return whether it's a finite
                        ; normal number or a special case. Also outputs the sign
                        ; and negates the number if necessary.
                        dq      FSPECDOT,BINNOT         ; FSPEC. NOT
                        ; ( number bool )
                        dq      CONDJUMP,.notnormal     ; ?JUMP[.notnormal]
                        ; ( number )
                        ; for a finite normal number, the number is returned
                        ; split number into significand and exponent
                        dq      FEXTRACT                ; FEXTRACT
                        ; ( signif2 expon2 )
                        ; compute logb2
                        dq      PUSHBASE,FETCH,I2F      ; BASE @ I2F
                        dq      LIT,2.0,FLOATLOG        ; 2.0 FLOG
                        ; ( signif2 expon2 logb2 )
                        ; multiply with expon2 to get expb2
                        ; (see test_nconv.c for reference)
                        ; expb2 = exp2 * logb2
                        ; however, we need to keep a copy of logb2 for later
                        dq      SWAP                    ; SWAP
                        ; ( signif2 logb2 expon2 )
                        dq      OVER,SWAP               ; OVER SWAP
                        ; ( signif2 logb2 logb2 expon2 )
                        dq      MULFLT                  ; F*
                        ; ( signif2 logb2 expb2 )
                        ; split into integer and floating-point parts
                        ; expb2i = (int) round( expb2 )
                        ; coincidentially, F2I uses FRNDINT to round to integer
                        dq      DUP,F2I                 ; DUP F2I
                        ; ( signif2 logb2 expb2 expb2i )
                        ; expb2f = ( expb2 - expb2i ) / logb2
                        ; however, we need to make copy of expb2i first
                        ; and put it in the back
                        dq      DUP                     ; DUP
                        ; ( signif2 logb2 expb2 expb2i expb2i )
                        dq      ROT                     ; ROT
                        ; ( signif2 logb2 expb2i expb2i expb2 )
                        dq      SWAP                    ; SWAP
                        ; ( signif2 logb2 expb2i expb2 expb2i )
                        dq      I2F,SUBFLT              ; I2F F-
                        ; ( signif2 logb2 expb2i frac )
                        dq      ROT                     ; ROT
                        ; ( signif2 expb2i frac logb2 )
                        dq      DIVFLT                  ; F/
                        ; ( signif2 expb2i expb2f )
                        ; done, now compute the based number
                        ; numb2f = signif2 * pow( 2.0, expb2f )
                        dq      LIT,2.0,SWAP            ; 2.0 SWAP
                        ; ( signif2 expb2i 2.0 expb2f )
                        dq      FPOWER                  ; FPOW
                        ; ( signif2 expb2i expb2p )
                        dq      ROT                     ; ROT
                        ; ( expb2i expb2p signif2 )
                        dq      MULFLT                  ; F*
                        ; ( expb2i numb2f )
                        ; good, now do all the other stuff
                        ; maxdig = (int) round( alog( b, pow( 2, 52 ) ) )
                        dq      PUSHBASE,FETCH,I2F      ; BASE @ I2F
                        ; ( expb2i numb2f basef )
                        dq      LIT,2.0,LIT,52.0,FPOWER ; 2.0 52.0 FPOW
                        ; ( expb2i numb2f basef powf )
                        dq      FLOATLOG,F2I            ; FLOG F2I
                        ; ( expb2i numb2f maxdig )
                        ; cut off one digit at the end
                        ; (for instance, for base 10, this means that instead
                        ; of 16 digits after the decimal point we use only 15)
                        dq      SUBONE                  ; 1-
                        ; prepare for OUTMANT
                        ; we're using the PREP buffer
                        dq      PUSHPREP,DUP,LIT,256,ADDINT ; PREP DUP 256 +
                        ; ( expb2i numb2f maxdig start limit )
                        ; get numb2f to the front
                        dq      LIT,4,ROLL              ; 4 ROLL
                        ; ( expb2i maxdig start limit number )
                        ; get maxdig to the front
                        dq      LIT,4,ROLL              ; 4 ROLL
                        ; ( expb2i start limit number maxdig )
                        ; make a copy of maxdig for later
                        dq      DUP                     ; DUP
                        ; ( expb2i start limit number maxdig maxdig )
                        dq      LIT,-5,ROLL             ; -5 ROLL
                        ; ( expb2i maxdig start limit number maxdig )
                        ; now we're ready for OUTMANT
                        dq      OUTMANT                 ; OUTMANT
                        ; ( expb2i maxdig length )
                        ; count the digits
                        dq      PUSHPREP,DUP            ; PREP DUP
                        ; ( expb2i maxdig length start start )
                        dq      ROT,ADDINT              ; ROT +
                        ; ( expb2i maxdig start addr )
                        dq      COUNTDIG                ; COUNTDIG
                        ; ( expb2i maxdig start addr hasdot before
                        ;   after )
                        ; we'll use the DOT buffer as the output buffer
                        ; since we already output the sign, we don't need
                        ; to remember it, we'll simply pass 0 as the sign
                        ; parameter.
                        ; first, get exp2bi (the exponent) and maxdig to
                        ; the front.
                        dq      LIT,7,ROLL,LIT,7,ROLL   ; 7 ROLL 7 ROLL
                        ; ( start addr hasdot before after expb2i maxdig )
                        ; swap expb2i and maxdig
                        dq      SWAP                    ; SWAP
                        ; ( start addr hasdot before after maxdig expb2i )
                        ; transform start addr into saddr saddrend
                        ; start becomes saddr and addr becomes saddrend
                        dq      LIT,7,ROLL,LIT,7,ROLL   ; 7 ROLL 7 ROLL
                        ; ( hasdot before after maxdig expb2i start addr )
                        ; ( hasdot before after maxdig expb2i saddr saddrend )
                        dq      SWAP
                        ; ( hasdot before after maxdig expb2i saddrend saddr )
                        dq      LIT,-7,ROLL,LIT,-7,ROLL  ; -7 ROLL -7 ROLL
                        ; ( saddrend saddr hasdot before after maxdig expb2i )
                        ; add the "0" (positive) sign
                        dq      LIT,0                   ; 0
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   sign )
                        ; now we need target limit and target address
                        dq      PUSHPREP2,DUP,LIT,256,ADDINT ; PREP2 DUP 256 +
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   sign taddr tlimit )
                        dq      SWAP                    ; SWAP
                        ; ( saddrend saddr hasdot before after maxdig exponent
                        ;   sign tlimit taddr )
                        dq      LIT,-10,ROLL,LIT,-10,ROLL ; -10 ROLL -10 ROLL
                        ; ( tlimit taddr saddrend saddr hasdot before after
                        ; maxdig exponent sign )
                        dq      FIXEXPON                ; FIXEXPON
                        ; ( tremain )
                        ; since tremain is the remaining number of characters
                        ; in the target buffer, and the DOT buffer is 256 bytes
                        ; long, 256-tremain is the length.
                        dq      LIT,256,SWAP,SUBINT     ; 256 SWAP -
                        ; ( length )
                        ; add the base address
                        dq      PUSHPREP2,SWAP          ; DOT SWAP
                        ; ( addr length )
                        ; finally, output it
                        dq      TYPEOUT                 ; TYPE
                        ; output trailing blank
                        dq      LIT,32,EMITCHAR         ; 32 EMIT
                        dq      EXIT

                        ; ( number )
.notnormal              dq      DROP,EXIT               ; DROP

                        section .rodata

                        align   8
fvm_last_sysword        dq      LINKBACK

                        section .note.GNU-stack
