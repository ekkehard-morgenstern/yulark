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

                        ; rsi - memory block
                        ; rdi - memory size
                        ; rdx - return stack size
                        ; rcx - initial word address
fwm_run                 push    r15
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
                        ret

                        ; terminates every FORTH word written in machine code
fwm_next                mov     r12,[r13]   ; WA := [WP]+
                        add     r13,8
                        mov     rax,[r12]   ; JUMP [WA]
                        jmp     rax

                        ; starts the processing of every FORTH implemented word
fwm_docol               sub     r14,8       ; -[RSP] := WP
                        mov     [r14],r13
                        lea     r13,[r12+8] ; WP := +WA
                        jmp     fwm_next

                        ; terminates any FORTH implemented word
fwm_exit                mov     r13,[r14]   ; WP := [RSP]+
                        add     r14,8
                        jmp     fwm_next
