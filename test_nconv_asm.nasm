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

                        global      nearest,restore,extract2,extract10,roundint

                        ; switch FPU to round-to-nearest mode
                        ; return previous mode
                        ; rax - result
nearest                 xor         rax,rax
                        push        rax
                        fclex
                        fstcw       word [rsp]
                        mov         dx,word [rsp]   ; dx ctrl backup
                        mov         ax,dx
                        and         ax,0xf0c0
                        or          ax,0x033f   ; xcpt off, hi prec, rnd2n
                        mov         [rsp],ax
                        fldcw       word [rsp]
                        mov         [rsp],dx   ; safekeep ctrl backup
                        pop         rax
                        ret

                        ; restore FPU settings to previous value
                        ; rax - settings
restore                 push        rax
                        fldcw       word [rsp]  ; control word
                        pop         rax
                        ret

                        ; rdi - significand (double*)
                        ; rsi - exponent (int16_t*)
                        ; xmm0 - number
                        ; first, move parameter onto FPU stack
extract2                sub         rsp,8
                        movq        qword [rsp],xmm0
                        fld         qword [rsp]
                        add         rsp,8
                        ; execute fxtract
                        fxtract
                        ; st1 - exponent
                        ; st0 - significand
                        fstp        qword [rdi]
                        fistp       word [rsi]
                        ret

                        ; rdi - significand (double*)
                        ; rsi - exponent (int16_t*)
                        ; xmm0 - number
                        ; first, move parameter onto FPU stack
                        ; (algorithm taken from my other project "AsmBASIC",
                        ; module toknum.nasm, function detok_wrnum())
extract10               sub         rsp,8
                        movq        qword [rsp],xmm0
                        fld         qword [rsp]
                        add         rsp,8
                        ; execute fxtract
                        fxtract
                        ; st1 - exponent
                        ; st0 - significand
                        fxch
                        ; st1 - significand
                        ; st0 - exponent
                        fldlg2      ; log10(2)
                        fmulp
                        ; st1 - significand
                        ; st0 - exponent * log10(2)
                        fld         st0
                        ; st2 - significand
                        ; st1 - exponent * log10(2)
                        ; st0 - exponent * log10(2)
                        frndint
                        ; st2 - significand
                        ; st1 - exponent * log10(2)
                        ; st0 - rndint(exponent*log10(2))
                        fist        word [rsi]
                        fsubp
                        ; st1 - significand
                        ; st0 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       (fraction)
                        fldlg2      ; log10(2)
                        fdivp
                        ; st1 - significand
                        ; st0 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       / log10(2)
                        fld1
                        ; st2 - significand
                        ; st1 - (exponent*log10(2)-rndint(exponent*log10(2))) 
                        ;       / log10(2)
                        ; st0 - 1
                        fld         st1     ; save int part for scale
                        ; st3 - significand
                        ; st2 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       / log10(2)
                        ; st1 - 1
                        ; st0 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       / log10(2)
.loop_prem              fprem               ; n=fmod(exp2,1)
                        fstsw       ax
                        test        ax,0x0400
                        jnz         .loop_prem
                        ; st3 - significand
                        ; st2 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       / log10(2)
                        ; st1 - 1
                        ; st0 - fmod((exponent*log10(2)-rndint(exponent *
                        ;       log10(2)))/log10(2), 1)
                        f2xm1               ; (2^n-1)+1
                        faddp
                        ; st2 - significand
                        ; st1 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       / log10(2)
                        ; st0 - (2^fmod((exponent*log10(2)-rndint(exponent * 
                        ;       log10(2)))/log10(2),1)-1)
                        ;       +1
                        fscale
                        ; st2 - significand
                        ; st1 - (exponent*log10(2)-rndint(exponent*log10(2)))
                        ;       / log10(2)
                        ; st0 - fscale((2^fmod((exponent*log10(2)-rndint(
                        ;       exponent*log10(2)))/log10(2),1)-1)+1, trunc0(
                        ;       (exponent*log10(2)-rndint(exponent*log10(2))) 
                        ;       / log10(2))) => 2^((exponent*log10(2)-rndint(
                        ;       exponent*log10(2)))/log10(2))
                        fstp        st1
                        ; st1 - significand
                        ; st0 - 2^((exponent*log10(2)-rndint(exponent*log10(2)
                        ;       ))/log10(2))
                        fmulp
                        ; st0 - significand * 2^((exponent*log10(2)-rndint( 
                        ;       exponent*log10(2)))/log10(2))
                        fstp        qword [rdi]
                        ret

                        ; xmm0 - double
                        ; rdi - int16_t* pint
                        ; rsi - double* pfrac
roundint                sub         rsp,8
                        movq        qword [rsp],xmm0
                        fld         qword [rsp]
                        fld         st0
                        frndint
                        fist        word [rdi]    ; integer part
                        fsubp
                        fstp        qword [rsi]   ; fraction part
                        add         rsp,8
                        ret
                        
                        section     .note.GNU-stack

