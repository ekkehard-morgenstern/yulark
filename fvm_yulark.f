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
0 YU-RB-RPOS !
0 YU-RB-WPOS !

\ Create variables for the trough to eat tokens from
128 ARRAY YU-TROUGH
0 YU-TROUGH C!
VARIABLE YU-TR-FILL
0 YU-TR-FILL !
1023 CONSTANT YU-TR-SIZE-UPB

\ Variable indicates whether the input channel is a TTY (terminal)
VARIABLE YU-IS-A-TTY
>INP @ SYSISATTY YU-IS-A-TTY !

\ Create regular expression for whitespace
: YU-RE-WHTSPC RE/ ^[ \t\r\n]*/ ;   \ editors might think the \ is a comment

\ Create regular expression for names
: YU-RE-NAME RE/ ^[A-Z_][A-Z0-9_]*/I ;

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
        DUP ?EOF UNLESS
            \ non-EOF character: record in ring buffer
            DUP YU-RB-PUTCH
        THEN
    THEN
;

\ function to fill the trough
: YU-FILL-TROUGH
    YU-TR-FILL @ YU-TR-SIZE-UPB < IF
        BEGIN
            \ read character
            YU-RDCH
            ( char )
            \ test if it's EOF
            DUP ?EOF
            ( char eof )
            \ or if it's a linefeed in TTY mode
            OVER 10 = YU-IS-A-TTY @ AND NOR
            ( char noteof )
            \ get fill state of trough
            YU-TR-FILL @
            ( char noteof fill )
            SWAP
            ( char fill noteof )
            \ check limit
            OVER YU-TR-SIZE-UPB <
            ( char fill noteof noteob )
            AND
        WHILE
            ( char fill )
            \ store character at trough position
            YU-TROUGH + C!
            ( )
            \ increment fill count
            YU-TR-FILL INCR
        REPEAT
        ( char fill )
        SWAP
        ( fill char )
        \ see if last character wasn't a EOF
        DUP ?EOF UNLESS
            \ yes, it wasn't, put it in putback buffer
            YU-PUTBACK !
            ( fill )
        ELSE
            \ nope, it was EOF, not needed
            DROP
            ( fill)
        THEN
        ( fill )
        \ finished, buffer filled, add NUL byte
        0 SWAP
        ( 0 fill )
        YU-TROUGH + C!
        ( )
    THEN
;

\ check if trough is empty
( -- bool )
: ?YU-TROUGH-EMPTY
    YU-TROUGH C@ 0 = IF
        \ yes, attempt to read a character
        YU-RDCH
        ( char )
        DUP ?EOF UNLESS
            \ not EOF: check if it's a linefeed
            ( char )
            DUP 10 = IF
                ( char )
                \ yes, consume
                DROP
            ELSE
                ( char )
                \ no, put back
                YU-PUTBACK !
            THEN
            ( )
            \ refill trough
            YU-FILL-TROUGH
            \ check if it's still empty
            YU-TROUGH C@ 0 =
        ELSE
            \ EOF
            DROP
            TRUE
        THEN
    ELSE
        \ buffer not empty
        FALSE
    THEN
;

\ take a bite from the trough
\ returns newly allocated zero-terminated string, use XFREE to free
( length -- zaddr )
: YU-CHOMP
    \ first, get the size of the trough content
    YU-TROUGH ZSTRLEN
    ( usrlen curlen )
    \ if the requested length is greater, use the current length
    2DUP U> IF
        ( usrlen curlen )
        SWAP DROP
        ( curlen )
    ELSE
        ( usrlen curlen )
        DROP
        ( usrlen )
    THEN
    ( length )
    \ create a copy
    DUP YU-TROUGH SWAP ZSTRCRT
    ( length zaddr )
    SWAP
    ( zaddr length )
    \ shift the remainder of YU-TROUGH down to the beginning
    YU-TROUGH ZSTRLEN
    ( zaddr length total )
    \ add one to total for the terminating NULL
    1+
    \ subtract length (that which has been eaten)
    OVER -
    ( zaddr length remain )
    \ use that to do CMOVE from beyond the end of the copied part
    OVER
    ( zaddr length remain length )
    YU-TROUGH +
    ( zaddr length remain source )
    YU-TROUGH
    ( zaddr length remain source target )
    ROT
    ( zaddr length source target remain )
    CMOVE
    ( zaddr length )
    DROP
    ( zaddr )
;

\ same as YU-CHOMP, but doesn't allocate memory and has no result
( length -- )
: YU-CHUCK
    \ first, get the size of the trough content
    YU-TROUGH ZSTRLEN
    ( usrlen curlen )
    \ if the requested length is greater, use the current length
    2DUP U> IF
        ( usrlen curlen )
        SWAP DROP
        ( curlen )
    ELSE
        ( usrlen curlen )
        DROP
        ( usrlen )
    THEN
    ( length )
    \ shift the remainder of YU-TROUGH down to the beginning
    YU-TROUGH ZSTRLEN
    ( length total )
    \ add one to total for the terminating NULL
    1+
    \ subtract length (that which has been eaten)
    OVER -
    ( length remain )
    \ use that to do CMOVE from beyond the end of the copied part
    OVER
    ( length remain length )
    YU-TROUGH +
    ( length remain source )
    YU-TROUGH
    ( length remain source target )
    ROT
    ( length source target remain )
    CMOVE
    ( length )
    DROP
;

\ skip whitespace
: YU-EAT-WHTSPC
    \ first, see if buffer is empty
    ?YU-TROUGH-EMPTY UNLESS
        \ nope, attempt to match whitespace
        YU-RE-WHTSPC YU-TROUGH DUP ZSTRLEN 1 0 REEXEC
        ( matches )
        DUP 0 <> IF
            DUP 0 CELLS + @
            ( matches so )
            OVER 1 CELLS + @
            ( matches so eo )
            ROT
            ( so eo matches )
            XFREE
            ( so eo )
            SWAP
            ( eo so )
            DROP
            ( length )
            \ bite off that part and discard it
            YU-CHUCK
        ELSE
            ( 0 )
            DROP
        THEN
    THEN
;

\ potentially eat token from trough
\ returns a pointer to a new string (that must later be freed using XFREE)
\ or 0 if token wasn't eaten
( regex -- caddr )
: YU-TROUGH-EAT?
    \ first, eat all leading whitespace in the trough
    YU-EAT-WHTSPC
    ( regex )
    \ attempt to match regex
    YU-TROUGH DUP ZSTRLEN 1 0 REEXEC
    ( matches )
    DUP 0 <> IF
        DUP 0 CELLS + @
        ( matches so )
        OVER 1 CELLS + @
        ( matches so eo )
        ROT
        ( so eo matches )
        XFREE
        ( so eo )
        SWAP
        ( eo so )
        DROP
        ( length )
        \ bite off that part and return it
        YU-CHOMP
        ( zaddr )
    THEN
    \ if there was no match, there'll be 0 on the stack just like we want
    \ in that case.
;

\ read a name and return new NUL-terminated string containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( char -- zaddr )
: YU-EAT-NAME YU-RE-NAME YU-TROUGH-EAT? ;

: YU-BANNER
    >INP @ SYSISATTY IF
        BOLD ." Yulark initialized." REGULAR LF
    THEN
;

YU-BANNER
FREEMSG
OKAY
