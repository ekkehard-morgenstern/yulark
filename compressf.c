/*
*   YULARK - a virtual machine written in C++
*   Copyright (C) 2025  Ekkehard Morgenstern
*
*   This program is free software: you can redistribute it and/or modify
*   it under the terms of the GNU General Public License as published by
*   the Free Software Foundation, either version 3 of the License, or
*   (at your option) any later version.
*
*   This program is distributed in the hope that it will be useful,
*   but WITHOUT ANY WARRANTY; without even the implied warranty of
*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*   GNU General Public License for more details.
*
*   You should have received a copy of the GNU General Public License
*   along with this program.  If not, see <https://www.gnu.org/licenses/>.
*
*   NOTE: Programs created with YULARK do not fall under this license.
*
*   CONTACT INFO:
*       E-Mail: ekkehard@ekkehardmorgenstern.de
*       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
*             Germany, Europe
*/
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>

static bool isspc( int c ) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\0';
}

static bool quote = false;

static int rdch0( void ) {
    int c = fgetc( stdin );
    if ( c == EOF ) return c;
    if ( c == '"' ) quote = !quote;
    if ( !quote && c == '(' ) {
        do { c = fgetc( stdin ); } while ( c != ')' && c != EOF );
        return ' ';
    }
    if ( !quote && c == '\\' ) {
        do { c = fgetc( stdin ); } while ( c != '\n' && c != EOF );
        if ( c == '\n' ) ungetc( c, stdin );
        return ' ';
    } else if ( c == '\\' ) {
        do {
            c = fgetc( stdin );
            if ( c == '"' ) quote = !quote;
        } while ( c != '\n' && c != EOF );
        if ( c == '\n' ) ungetc( c, stdin );
        return ' ';
    }
    return c;
}

static int rdch1( void ) {
    int c = rdch0();
    if ( !quote && isspc(c) ) {
        do {
            c = rdch0();
        } while ( isspc(c) );
        if ( c != EOF ) ungetc( c, stdin );
        return ' ';
    }
    return c;
}

int main( int argc, char** argv ) {
    for (;;) {
        int c = rdch1();
        if ( c == EOF ) break;
        fputc( c, stdout );
    }
    return EXIT_SUCCESS;
}