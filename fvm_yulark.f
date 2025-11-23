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
\ identifier := /[A-Z_][A-Z0-9_]*/i .
: YU-RE-IDENT RE/ ^[A-Z_][A-Z0-9_]*/I ;

\ Create regular expression for decimal numbers
\ dec-n := /[0-9]+(\.[0-9]+)?(E[+-]?[0-9]+)?/i .
: YU-RE-DEC RE/ ^[0-9]+(\.[0-9]+)?(E[+-]?[0-9]+)?/I ;

\ Create regular expression for octal numbers
\ oct-n := /@[0-7]+(\.[0-7]+)?(E[+-]?[0-7]+)?/i .
: YU-RE-OCT RE/ ^@[0-7]+(\.[0-7]+)?(E[+-]?[0-7]+)?/I ;

\ Create regular expression for binary numbers
\ bin-n := /\%[0-1]+(\.[0-1]+)?(E[+-]?[0-1]+)?/i .
: YU-RE-BIN RE/ ^\%[0-1]+(\.[0-1]+)?(E[+-]?[0-1]+)?/I ;

\ Create regular expression for hexadecimal numbers
\ hex-n := /\$[0-9A-F]+(\.[0-9A-F]+)?('[+-]?[0-9A-F]+)?/i .
: YU-RE-HEX RE/ ^\$[0-9A-F]+(\.[0-9A-F]+)?('[+-]?[0-9A-F]+)?/I ;

\ Create regular expression for numbers with specifed base
\ base-n := /#[0-9]+#[0-9A-Z]+(\.[0-9A-Z]+)?([E'][+-]?[0-9A-Z]+)?/i .
: YU-RE-BASE RE/ ^#[0-9]+#[0-9A-Z]+(\.[0-9A-Z]+)?([E'][+-]?[0-9A-Z]+)?/I ;

\ Create regular expression for double quoted string constants
\ str-seq1 := /"([^"\\]|\\(x[0-9a-fA-F]{1,2}|b[0-1]{1,8}|[0-7]{1,3}|[abetrn]|[\\"']))*"/ .
: YU-RE-STRSEQ1 RE/ ^"([^"\\]|\\(x[0-9a-fA-F]{1,2}|b[0-1]{1,8}|[0-7]{1,3}|[abetrn]|[\\"']))*"/ ;

\ Create regular expression for single quoted string constants
\ str-seq2 := /'([^'\\]|\\(x[0-9a-fA-F]{1,2}|b[0-1]{1,8}|[0-7]{1,3}|[abetrn]|[\\"']))*'/ .
: YU-RE-STRSEQ2 RE/ ^'([^'\\]|\\(x[0-9a-fA-F]{1,2}|b[0-1]{1,8}|[0-7]{1,3}|[abetrn]|[\\"']))*'/ ; \ " \ for compressor

\ Allocate N cells.
( size -- memptr )
: YU-CELLS-ALLOC CELLS XALLOC ;

\ Allocate AST (abstract syntax tree) node
\ Each node contains the following fields:
\
\   +-------------------------+
\   |       node type         |
\   +-------------------------+
\   |   node-specific data    |
\   +-------------------------+
\   |    number of branches   |
\   +-------------------------+
\   | allocated number of br. |
\   +-------------------------+
\   |   pointer to branches   |
\   +-------------------------+
\
0 CELLS CONSTANT YU-ASTN-TYPE
1 CELLS CONSTANT YU-ASTN-DATA
2 CELLS CONSTANT YU-ASTN-NUM-BR
3 CELLS CONSTANT YU-ASTN-ALO-BR
4 CELLS CONSTANT YU-ASTN-PTR-BR

: YU-ASTN-ALLOC 5 YU-CELLS-ALLOC ;

( type data -- node )
: YU-ASTN-CREATE
    YU-ASTN-ALLOC
    ( type data node )
    3 PICK 2 PICK YU-ASTN-TYPE + !
    2 PICK 2 PICK YU-ASTN-DATA + !
    0 OVER YU-ASTN-NUM-BR + !
    0 OVER YU-ASTN-ALO-BR + !
    0 OVER YU-ASTN-PTR-BR + !
    -3 ROLL
    ( node type data )
    2DROP
    ( data )
;

( data -- )
: YU-ASTN-DELETE
    \ allow recursion
    UNHIDE
    \ check pointer
    DUP <>0 IF
        ( data )
        DUP YU-ASTN-NUM-BR + @ DUP 0 U> IF
            BEGIN
                ( data numbr )
                \ decrement and store branch count
                1- OVER YU-ASTN-NUM-BR + OVER SWAP !
                ( data numbr )
                \ load branch address
                OVER YU-ASTN-PTR-BR + @ OVER CELLS +
                ( data numbr brptr )
                DUP @
                ( data numbr brptr braddr )
                \ free branch by using recursion
                YU-ASTN-DELETE
                ( data numbr brptr )
                \ set branch pointer to 0
                0 SWAP !
                ( data numbr )
                \ loop until count equals 0
                DUP =0
            UNTIL
            ( data numbr )
            \ free the branch pointer
            OVER YU-ASTN-PTR-BR + @ XFREE
            \ store 0 in it
            OVER YU-ASTN-PTR-BR + 0 SWAP !
            ( data numbr )
        THEN
        ( data numbr )
        DROP
        XFREE
    THEN
;

\ add branch to AST
( astn br -- )
: YU-ASTN-ADDBR
    \ check if number of branches is equal or greater than number of allocated
    \ branches
    OVER YU-ASTN-NUM-BR + @
    ( astn br numbr )
    2 PICK YU-ASTN-ALO-BR + @
    ( astn br numbr alloc )
    2DUP >= IF
        \ number of branches is equal or greater than number of allocated
        \ branches: increase number of allocated branches
        \ if it was 0, make it 10
        ( astn br numbr alloc )
        DUP =0 IF
            DROP 10
        ELSE
            2 *
        THEN
        \ get the branch pointer then reallocate it to new size
        4 PICK YU-ASTN-PTR-BR + @
        OVER CELLS XREALLOC
        ( astn br numbr alloc newptr )
        5 PICK YU-ASTN-PTR-BR + !
        ( astn br numbr alloc )
        \ save new allocation size
        4 PICK YU-ASTN-ALO-BR + !
        ( astn br numbr )
    ELSE
        ( astn br numbr alloc )
        \ no, number of allocated branches not needed here
        DROP
        ( astn br numbr )
    THEN
    ( astn br numbr )
    \ store the branch at the current branch index (number of branches)
    2DUP 5 PICK YU-ASTN-PTR-BR + @ SWAP CELLS + !
    ( astn br numbr )
    \ increment number of branches
    1+ 3 PICK YU-ASTN-NUM-BR + !
    ( astn br )
    2DROP
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
    YU-TROUGH C@ =0 IF
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
            YU-TROUGH C@ =0
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
    YU-TR-FILL @
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
    YU-TR-FILL @
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
    \ subtract length from fill counter
    YU-TR-FILL @ SWAP - YU-TR-FILL !
    ( zaddr )
;

\ same as YU-CHOMP, but doesn't allocate memory and has no result
( length -- )
: YU-CHUCK
    \ first, get the size of the trough content
    YU-TR-FILL @
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
    YU-TR-FILL @
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
    \ subtract length from fill counter
    YU-TR-FILL @ SWAP - YU-TR-FILL !
;

\ skip whitespace
: YU-EAT-WHTSPC
    \ first, see if buffer is empty
    ?YU-TROUGH-EMPTY UNLESS
        \ nope, attempt to match whitespace
        YU-RE-WHTSPC YU-TROUGH YU-TR-FILL @ 1 0 REEXEC
        ( matches )
        DUP <>0 IF
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
    YU-TROUGH YU-TR-FILL @ 1 0 REEXEC
    ( matches )
    DUP <>0 IF
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

\ eat an identifier and return new NUL-terminated string containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-IDENT YU-RE-IDENT YU-TROUGH-EAT? ;

\ eat a decimal number and return new NUL-terminated string containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-DEC YU-RE-DEC YU-TROUGH-EAT? ;

\ eat an octal number and return new NUL-terminated string containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-OCT YU-RE-OCT YU-TROUGH-EAT? ;

\ eat a binary number and return new NUL-terminated string containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-BIN YU-RE-BIN YU-TROUGH-EAT? ;

\ eat a hexadecimal number and return new NUL-terminated string containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-HEX YU-RE-HEX YU-TROUGH-EAT? ;

\ eat a number with specified base and return new NUL-terminated string
\ containing it
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-BASE YU-RE-BASE YU-TROUGH-EAT? ;

\ eat any kind of number
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
\ number := hex-n | bin-n | oct-n | dec-n | base-n .
( -- zaddr )
: YU-EAT-NUM
    YU-EAT-HEX DUP UNLESS
        DROP
        YU-EAT-BIN DUP UNLESS
            DROP
            YU-EAT-OCT DUP UNLESS
                DROP
                YU-EAT-DEC DUP UNLESS
                    DROP
                    YU-EAT-BASE
                THEN
            THEN
        THEN
    THEN
;

\ eat a double-quoted string sequence
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-STRSEQ1 YU-RE-STRSEQ1 YU-TROUGH-EAT? ;

\ eat a single-quoted string sequence
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
( -- zaddr )
: YU-EAT-STRSEQ2 YU-RE-STRSEQ2 YU-TROUGH-EAT? ;

\ eat any kind of string sequence
\ if there's no match, 0 is returned.
\ if there's a match, the resulting string must be freed with XFREE after use.
\ string := str-seq1 | str-seq2 .
( -- zaddr )
: YU-EAT-STR
    YU-EAT-STRSEQ1 DUP UNLESS
        DROP
        YU-EAT-STRSEQ2
    THEN
;

\ concept for identifier hash tables:
\       cooked-ident -> ( origname, prefix )
\       ( origname, prefix ) -> cooked-ident
\ cooked-ident layout:
\       USR-scope-name
\ for instance:
\       USR-CLS-33 -> ( 'MyClass', 'CLS' )
\ these cooked identifiers can then be used in YULARK FORTH code.
( ... )

: YU-BANNER
    YU-IS-A-TTY @ IF
        BOLD ." Yulark initialized." REGULAR LF
    THEN
;

YU-BANNER
FREEMSG
OKAY
