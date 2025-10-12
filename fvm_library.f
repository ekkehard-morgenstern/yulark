\
\   YULARK - a virtual machine written in C++
\   Copyright (C) 2025  Ekkehard Morgenstern
\
\   This program is free software: you can redistribute it and/or modify
\   it under the terms of the GNU General Public License as published by
\   the Free Software Foundation, either version 3 of the License, or
\   (at your option) any later version.
\
\   This program is distributed in the hope that it will be useful,
\   but WITHOUT ANY WARRANTY; without even the implied warranty of
\   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
\   GNU General Public License for more details.
\
\   You should have received a copy of the GNU General Public License
\   along with this program.  If not, see <https://www.gnu.org/licenses/>.
\
\   NOTE: Programs created with YULARK do not fall under this license.
\
\   CONTACT INFO:
\       E-Mail: ekkehard@ekkehardmorgenstern.de
\       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
\             Germany, Europe
\

\ create a variable
: VARIABLE ( -- ) CREATE 0 , ;

\ create a constant with a value from the stack
: CONSTANT ( n -- ) CREATE , DOES> @ ;

\ create an array that can hold n words
: ARRAY ( n -- ) CREATE ALLOT ;

\ define the PAD array (256 bytes, 32 x 8)
32 ARRAY PAD

\ define a string buffer array (256 bytes, 32 x 8)
\ for string handling functions
32 ARRAY STRBUF

\ check character for EOF
( char -- bool )
: ?EOF
    -1 =
;

\ skip one space character in the input
: SKIP1SPC
    INPGETCH
    ( char )
    \ check for space or EOF
    DUP ?EOF OVER ?SPC OR UNLESS
        ( char )
        \ if not: go back one character
        >IN DECR
    THEN
    ( char )
    DROP
;

\ read a string literal from the input, skipping
\ one leading space character
: STRLIT
    \ clear the length counter in the string buffer
    0 STRBUF C!
    \ skip one space
    SKIP1SPC
    \ start loop
    BEGIN
        \ get a character
        INPGETCH
        ( char )
        \ check for EOF and double quote
        DUP -1 <> OVER 34 <> AND
    WHILE
        \ neither EOF nor double quote
        ( char )
        \ fetch length of buffer
        STRBUF C@
        ( char len )
        \ check length, maximum 255 chars allowed
        DUP 255 < IF
            ( char len )
            \ increment length and store
            1+ STRBUF
            ( char len addr )
            2DUP C!
            ( char len strbuf )
            \ sum base address and length and store there
            + C!
        THEN
    REPEAT
    ( char )
    DROP
;

\ get address and length of a counted string
( addr -- addr+1 len )
: COUNT
    ( addr )
    DUP C@
    ( addr len )
    SWAP 1+ SWAP
;

\ output a string literal
\ when compiling, put the string at HERE and generate code to output it
\ compiles to:
\   JUMP <pos> <str> LIT[str] LIT[len] TYPE
\
\ ( -- )
: ." IMMEDIATE
    ?IMMEDIATE UNLESS
        \ read literal into STRBUF
        STRLIT
        \ compile string into the word with output code
        COMPILE JUMP
        0 ,
        \ HERE-8 is the address where to store the jump location
        HERE 8 -
        ( pos )
        \ get buffer address and length
        STRBUF COUNT HERE
        ( pos srcaddr srclen tgtaddr )
        \ allot space
        OVER 7 + 7 NOT AND 8 / ALLOT
        \ copy args to CMOVE
        ( pos srcaddr srclen tgtaddr )
        SWAP
        ( pos srcaddr tgtaddr srclen )
        2DUP SWAP
        ( pos srcaddr tgtaddr srclen srclen tgtaddr )
        5 ROLL
        ( pos tgtaddr srclen srclen tgtaddr srcaddr )
        SWAP
        ( pos tgtaddr srclen srclen srcaddr tgtaddr )
        ROT
        ( pos tgtaddr srclen srcaddr tgtaddr srclen )
        \ copy string over
        CMOVE
        ( pos tgtaddr srclen )
        ROT
        ( tgtaddr srclen pos )
        \ patch the JUMP location to HERE
        HERE SWAP !
        \ compile string address and length
        ( tgtaddr srclen )
        SWAP
        \ ( srclen tgtaddr )
        LITERAL LITERAL
        \ compile TYPE
        COMPILE TYPE
    ELSE
        \ read literal into STRBUF
        STRLIT
        \ output the buffer
        STRBUF COUNT TYPE
    THEN
;

: BANNER
    >INP @ SYSISATTY IF
        ." YULARK FORTH Engine" 10 EMIT
        ." Copyright © 2025  Ekkehard Morgenstern" 10 EMIT
        ." See LICENSE file for license information." 10 EMIT
    THEN
;

BANNER
OKAY
