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

                        global      _fpowl

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

                        section .note.GNU-stack

