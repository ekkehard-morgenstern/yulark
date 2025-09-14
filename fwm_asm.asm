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

                        global      fwm_run,fwm_next,fwm_docol,fwm_exit,fwm_term

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

                        ; rsi - memory block
                        ; rdi - memory size
                        ; rdx - return stack size
                        ; rcx - initial word address
fwm_run                 enter   0,0
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

                        ; go to NEXT
                        jmp     fwm_next

                        ; terminates the execution of FORTH code
fwm_term                pop     rbx
                        pop     r12
                        pop     r13
                        pop     r14
                        pop     r15
                        leave
                        ret

                        ; terminates every FORTH word written in machine code
fwm_next                mov     r12,[r13]   ; WA := [WP]+
                        add     r13,8
                        mov     rax,[r12]   ; JUMP [WA]
                        jmp     rax

;                       +--------------------+
;                       |       DOCOL        |
;                       +--------------------+
;                       |  link to previous  |
;                       +-----+--------------+
;                       | NLF | NAME ...     |
;                       +--------------------+
;                       | NAME ... PAD 0 0 0 | (optional name/pad bytes)
;                       +--------------------+
;                       |  definition ...    | word-addresses
;                       +--------------------+

                        ; starts the processing of every FORTH implemented word
fwm_docol               sub     r14,8       ; -[RSP] := WP
                        mov     [r14],r13
                        lea     r13,[r12+16] ; WP := WA + 2
                        ; r13 is now at the NLF field
                        ; read name length
                        mov     al,[r13]
                        ; ignore the flags, round up to word boundary
                        and     al,0x1f
                        add     al,7
                        and     al,0xf8
                        ; add to word pointer (r13)
                        movzx   rax,al
                        add     r13,rax
                        ; begin processing word definition
                        jmp     fwm_next

                        ; terminates any FORTH implemented word
fwm_exit                mov     r13,[r14]   ; WP := [RSP]+
                        add     r14,8
                        jmp     fwm_next
