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

: retest1 RE/ [a-z]+/I ;
: prtmat
    DUP IF
        ( match )
        0
        ( match offs )
        BEGIN
            2DUP 2 * CELLS +
            ( match offs addr )
            DUP @ .
            CELL + @ .
            ( match offs )
            1+
            DUP 3 >=
        UNTIL
        DROP
        ( match )
        XFREE
    ELSE
        DROP
        ." no match"
    THEN
    10 EMIT
;

retest1 S" foo bar" 3 0 REEXEC prtmat
retest1 S" fOo bAr" 3 0 REEXEC prtmat
retest1 S" fOobbAr" 3 0 REEXEC prtmat
