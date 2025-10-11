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
        \ if not: go back one character
        >IN DECR
    THEN
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

\ output a string literal
\ ( -- )
: ."
    \ read literal into STRBUF
    STRLIT
    \ output the buffer
    STRBUF DUP C@
    ( addr len )
    SWAP 1+ SWAP
    ( addr len )
    TYPE
;

." Hello world!"
