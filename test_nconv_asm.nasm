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
                        global      fixupexp

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
                        
                        ; fix up exponent (also generates new output)
                        ; (algorithm taken from my other project "AsmBASIC",
                        ; module toknum.nasm, function detok_wrnum())
                        ;   rdi - pointer to target buffer (char*)
                        ;   rsi - pointer to source buffer (const char*)
                        ;   rdx - maximum number of digits
                        ;   rcx - total number of digits
                        ;   r8  - pointer to exponent (int16_t*)
                        ; get exponent shift
fixupexp                mov         ax,[r8]
                        mov         r9,rdx      ; save maximum number of digits
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
                        mov         [r8],ax ; store new exponent
                        ; dx contains the number of zeros before
                        ; the actual digits, the first one being
                        ; the one before the decimal point.
                        mov         al,'0'
                        stosb
                        mov         al,'.'
                        stosb
                        mov         al,'0'
.leadzero               dec         dl
                        jz          .endlead
                        stosb
                        jmp         .leadzero
                        ; now output the remaining digits
.endlead                movzx       rcx,cx
.endlead2               lodsb
                        cmp         al,'.'
                        je          .endlead2
                        stosb
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
                        mov         [r8],ax ; store new exponent
                        ; dx contains the number of digits
                        ; either fetched from after the decimal point
                        ; or added as zeroes to the end
                        movzx       rcx,cx
                        ; first, copy the leading digits straight over
.fetchloop              lodsb
                        cmp         al,'.'
                        je          .gotdp
                        cmp         al,'0'
                        je          .skipfetch
                        stosb
.skipfetch              loop        .fetchloop
                        ; finished before reaching a decimal point
                        ; now add dx zeroes
                        movzx       rcx,dx
                        test        rcx,rcx
                        jz          .shiftdone
                        mov         al,'0'
                        rep         stosb
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
                        rep         movsb
                        ; write decimal point then remaining digits
.skipcopy               xchg        cx,dx
                        movzx       rcx,cx
                        test        rcx,rcx
                        jz          .shiftdone
                        mov         al,'.'
                        stosb
                        rep         movsb
                        jmp         .shiftdone
                        ; integral number (no fraction intended)
                        ; dx > cx, fillcnt = dx - cx
.fillzero               sub         dx,cx
                        ; copy remaining digits
                        movzx       rcx,cx
                        rep         movsb
                        ; then fill with zeroes
                        movzx       rcx,dx
                        mov         al,'0'
                        rep         stosb
                        jmp         .shiftdone
                        ; no shift: copy result over
.noshift                inc         rcx     ; increase b/c of dot
.copy                   lodsb
                        cmp         al,0
                        je          .copydone
                        stosb
                        loop        .copy
                        ; if the last character written was a '.', delete it
.copydone               cmp         byte [rdi-1],'.'
                        jne         .shiftdone
                        mov         byte [rdi-1],0
                        ; after shifting the number around, examine exponent
                        ; (not done in this implementation, see C code)
.shiftdone              nop
                        ; now, finally, write terminating NUL byte
.complete               xor         al,al
                        stosb
                        ret

                        section     .note.GNU-stack

