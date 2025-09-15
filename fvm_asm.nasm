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

                        ; ebp-0x1e0     OFILE handle
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

                        ; set up DP
                        mov     rbx,rsi

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
                        mov     rax,[r13]
                        add     r13,8
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; basic computations

                        DEFASM  "+",ADDINT,0
                        mov     rax,[r15+8]
                        add     rax,[r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "1+",ADDONE,0
                        inc     qword [r15]
                        NEXT

                        DEFASM  "1-",SUBONE,0
                        dec     qword [r15]
                        NEXT

                        DEFASM  "-",SUBINT,0
                        mov     rax,[r15+8]
                        sub     rax,[r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "*",MULINT,0
                        mov     rax,[r15+8]
                        imul    qword [r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "/",DIVINT,0
                        mov     rax,[r15+8]
                        cqo                     ; sign-extend into rdx
                        idiv    qword [r15]
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "*/",MULDIVINT,0
                        mov     rax,[r15+16]
                        imul    qword [r15+8]
                        idiv    qword [r15]
                        add     r15,16
                        mov     [r15],rax
                        NEXT

                        DEFASM  "/MOD",DIVMODINT,0
                        mov     rax,[r15+8]
                        cqo                     ; sign-extend into rdx
                        idiv    qword [r15]
                        mov     [r15+8],rax
                        mov     [r15],rdx
                        NEXT

                        DEFASM  "MOD",MODINT,0
                        mov     rax,[r15+8]
                        cqo                     ; sign-extend into rdx
                        idiv    qword [r15]
                        add     r15,8
                        mov     [r15],rdx
                        NEXT

                        DEFASM  "<0",LTZEROINT,0
                        mov     rax,[r15]
                        cmp     rax,0
                        setl    al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<=0",LEZEROINT,0
                        mov     rax,[r15]
                        cmp     rax,0
                        setle   al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">0",GTZEROINT,0
                        mov     rax,[r15]
                        cmp     rax,0
                        setg    al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">=0",GEZEROINT,0
                        mov     rax,[r15]
                        cmp     rax,0
                        setge   al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "=0",EQZEROINT,0
                        mov     rax,[r15]
                        cmp     rax,0
                        sete    al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<>0",NEZEROINT,0
                        mov     rax,[r15]
                        cmp     rax,0
                        setne   al
                        movsx   rax,al
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<",LTINT,0
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setl    al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<=",LEINT,0
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setle   al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">",GTINT,0
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setg    al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  ">=",GEINT,0
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setge   al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "=",EQINT,0
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        sete    al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "<>",NEINT,0
                        mov     rax,[r15+8]
                        cmp     rax,[r15]
                        setne   al
                        movsx   rax,al
                        add     r15,8
                        mov     [r15],rax
                        NEXT

                        DEFASM  "@",FETCH,0
                        mov     rax,[r15]
                        mov     rax,[rax]
                        mov     [r15],rax
                        NEXT

                        DEFASM  "!",STORE,0
                        mov     rdx,[r15+8]
                        mov     rax,[r15]
                        mov     [rax],rdx
                        add     r15,16
                        NEXT

                        DEFASM  "CELL",CELL,0
                        mov     rax,8   ; return size of memory cell
                        sub     r15,rax
                        mov     [r15],rax
                        NEXT

                        DEFASM  "CELLS",CELLS,0
                        mov     rax,[r15]   ; compute size of n cells
                        shl     rax,3
                        mov     [r15],rax
                        NEXT

                        ; duplicate word on the stack
                        DEFASM  "DUP",DUP,0
                        mov     rax,[r15]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; swap words on stack
                        DEFASM  "SWAP",SWAP,0
                        mov     rax,[r15]
                        mov     rdx,[r15+8]
                        mov     [r15+8],rax
                        mov     [r15],rdx
                        NEXT

                        ; rotate words on stack
                        DEFASM  "ROT",ROT,0
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
                        mov     rax,[r15+8]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; pick word from stack
                        DEFASM  "PICK",PICK,0
                        mov     rax,[r15]
                        dec     rax
                        mov     rax,[rsp+rax*8]
                        mov     [r15],rax
                        NEXT

                        ; drop
                        DEFASM  "DROP",DROP,0
                        add     r15,8
                        NEXT

                        DEFASM  "FPUINIT",FPUINIT,0
                        finit
                        NEXT

                        DEFASM  "I2F",I2F,0
                        fild    qword [r15]
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F2I",F2I,0
                        fld     qword [r15]
                        frndint
                        fistp   qword [r15]
                        NEXT

                        DEFASM  "F+",ADDFLT,0
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        faddp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F-",SUBFLT,0
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fsubp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F*",MULFLT,0
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fmulp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "F/",DIVFLT,0
                        fld     qword [r15+8]   ; st1
                        fld     qword [r15]     ; st0
                        fdivp
                        add     r15,8
                        fstp    qword [r15]
                        NEXT

                        DEFASM  "FMOD",MODFLT,0
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
.end                    NEXT

                        ; to-latest: returns the address of the LATEST variable
                        DEFASM  ">LATEST",TOLATEST,0
                        lea     rax,[rbp-LATEST]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the next dictionary location
                        DEFASM  "HERE",PUSHHERE,0
                        sub     r15,8
                        mov     [r15],rbx
                        NEXT

                        ; to-in returns the address of the PAD offset
                        DEFASM  ">IN",TOIN,0
                        lea     rax,[rbp-PPOS]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the number of chars in the PAD
                        DEFASM  ">MAX",TOMAX,0
                        lea     rax,[rbp-PFILL]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the file handle for the PAD
                        DEFASM  ">FILE",TOFILE,0
                        lea     rax,[rbp-PFILE]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the file handle for output
                        DEFASM  ">OUT",TOOUT,0
                        lea     rax,[rbp-OFILE]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; returns the address of the PAD buffer
                        DEFASM  "PAD",PUSHPAD,0
                        lea     rax,[rbp-PAD]
                        sub     r15,8
                        mov     [r15],rax
                        NEXT

                        ; converts error code to 0
                        DEFASM  "?ERR0",ERR2ZERO,0
                        mov     rax,[r15]
                        cmp     rax,0
                        jge     .good
                        xor     rax,rax
.good                   mov     [r15],rax
                        NEXT

                        ; read bytes from a system file
                        DEFASM  "SYSREAD",SYSREAD,0
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
                        mov     rsi,[r15+16]    ; file handle
                        mov     rdi,[r15+8]     ; buffer
                        mov     rdx,[r15]       ; count
                        add     r15,16
%define __NR_write      1
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

                        section .rodata

                        align   8
fvm_last_sysword        dq      LINKBACK
