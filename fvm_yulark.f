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

\ Create variable to hold address of YU-EXPR definition (defined later).
\ After assignment using " 'CFA YU-EXPR YU-EXPR-CFA ! ", the variable (or
\ rather, its value) can be evaluated at runtime using " YU-EXPR-CFA RUNCODE ".
\ Thus, you cannot call a definition using the variable until its value has
\ been defined (which should be obvious).
VARIABLE YU-EXPR-CFA

\ Create variable to hold a single putback character, and set it to -1
VARIABLE YU-PUTBACK
    -1 YU-PUTBACK !

\ Create variable to hold a line number (initially zero)
VARIABLE YU-LINE#

\ Create variable for name/identifier buffering and initialize it
32 ARRAY YU-NAMEBUF
0 YU-NAMEBUF C!

\ Create variables for ring buffer and initialize them
8 ARRAY YU-RINGBUF
VARIABLE YU-RB-RPOS
VARIABLE YU-RB-WPOS

\ Function to add a character to YU-NAMEBUF
\ ( char -- )
: YU-NAME-ADDCH
    DUP -1 <> IF
        ( char )
        \ get name length
        YU-NAMEBUF C@
        DUP 255 < IF
            1+
            ( char namelen )
            YU-NAMEBUF
            ( char namelen namebuf )
            \ write length field
            2DUP C!
            ( char namelen namebuf )
            \ write character
            + C!
            ( )
        ELSE
            ( char namelen )
            2DROP
        THEN
    ELSE
        ( char )
        DROP
    THEN
;

\ Utility functions for ring buffer:
\ Place a character into the ring buffer
( char -- )
: YU-RB-PUTCH
    DUP -1 <> IF
        ( char )
        \ store character at current write position
        YU-RINGBUF YU-RB-WPOS @ + C!
        ( )
        \ increment write position
        YU-RB-WPOS DUP @ 1+ 63 AND SWAP !
        \ if write position equals read position, increment that too
        YU-RB-WPOS @ YU-RB-RPOS @ = IF
            YU-RB-RPOS DUP @ 1+ 63 AND SWAP !
        THEN
    ELSE
        ( char )
        DROP
    THEN
;

\ Utility functions for ring buffer:
\ Retrieve a character from the ring buffer
( char -- )
: YU-RB-GETCH
    \ if the read position equals the write position, return -1
    YU-RB-RPOS @ YU-RB-WPOS @ = IF
        -1
    ELSE
        \ otherwise, fetch the character at the read position
        YU-RINGBUF YU-RB-RPOS @ + C@
        ( char )
        \ increment read position
        YU-RB-RPOS DUP @ 1+ 63 AND SWAP !
        ( char )
    THEN
;

\ Utility functions for ring buffer:
\ Print the ring buffer content
: YU-RB-PRINT
    BEGIN
        \ get a character from the buffer
        YU-RB-GETCH
        ( char )
        \ check if character is -1
        DUP -1 <>
    WHILE
        \ not -1: emit character
        ( char )
        EMIT
        ( )
    REPEAT
    \ -1: stop output
    ( -1 )
    DROP
;

\ Define YU-RDCH, which reads a character from the input.
\ If there's a putback character, that is returned first.
\ If an EOF has been encountered, -1 is returned.
\ ( -- char )
: YU-RDCH
    YU-PUTBACK @
    DUP -1 <> IF
        ( putback-char )
        \ restore putback state to -1
        -1 YU-PUTBACK !
        \ return character that has been retrieved before
        ( putback-char )
    ELSE
        ( -1 )
        DROP
        \ read character from input stream
        INPGETCH
        ( char-or-eof )
        DUP 10 = IF
            \ line feed: increment line number
            YU-LINE# INCR
        THEN
        DUP -1 <> IF
            \ non-EOF character: record in ring buffer
            DUP YU-RB-PUTCH
        THEN
    THEN
;

\ test if a character is the character of a name
( char -- bool )
: YU-NAME-CHR?
    \ A .. Z
    DUP 65 >= OVER 90 <= AND
    ( char bool )
    \ a .. z
    OVER 97 >= 3 PICK 122 <= AND
    ( char bool bool )
    3 PICK 48 >= 4 PICK 57 <= AND
    ( char bool bool bool )
    4 PICK 95 =
    ( char bool bool bool bool )
    OR OR OR
    ( char bool )
    SWAP DROP
    ( bool )
;

\ test if a character is the first character of a name
( char -- bool )
: YU-NAME-FCHR?
    YU-NAME-CHR?
;

\ read a name beginning with the supplied character
\ returns 0 0 if the character is not a name character
( char -- addr len )
: YU-NAME-READ
    DUP YU-NAME-FCHR? IF
        \ clear name length
        0 YU-NAMEBUF C!
        BEGIN
            ( char )
            \ put character
            YU-NAME-ADDCH
            ( )
            \ get next character
            YU-RDCH
            ( char )
            \ check if it's -1 or not a name character
            DUP -1 = OVER YU-NAME-CHR? NOT OR
        UNTIL
        ( char )
        \ if it's not -1, put it back
        DUP -1 <> IF
            ( char )
            YU-PUTBACK !
        ELSE
            ( char )
            DROP
        THEN
        ( )
        YU-NAMEBUF COUNT
        ( addr len )
    ELSE
        ( char )
        DROP
        0 0
    THEN
;


: YU-BANNER
    >INP @ SYSISATTY IF
        BOLD ." Yulark initialized." REGULAR LF
    THEN
;

YU-BANNER
FREEMSG
OKAY
