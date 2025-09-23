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
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <math.h>

extern uint64_t _fpowl( uint64_t a, uint64_t b );

typedef union _wu_t {
    uint64_t    ui;
    double      d;
} wu_t;

static uint64_t getdbl( void ) {
    char buf[256];
    if ( fgets( buf, 256U, stdin ) == NULL ) {
        exit( EXIT_FAILURE );
    }
    double d;
    if ( sscanf( buf, "%lf", &d ) != 1 ) {
        exit( EXIT_FAILURE );
    }
    printf( "%g\n", d );
    wu_t u;
    u.d = d;
    return u.ui;
}

int main( int argc, char** argv ) {

    uint64_t a = getdbl();
    uint64_t b = getdbl();

    printf( "%016" PRIX64 "\n", a );
    printf( "%016" PRIX64 "\n", b );

    uint64_t c = _fpowl( a, b );

    printf( "%016" PRIX64 "\n", c );

    wu_t u;
    u.ui = c;
    printf( "%g\n", u.d );

    u.ui = a; double da = u.d;
    u.ui = b; double db = u.d;
    double dc = pow( da, db );
    printf ("%g^%g = %g\n", da, db, dc );

    return EXIT_SUCCESS;
}
