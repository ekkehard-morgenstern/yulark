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
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

// arbitrary logarithm
static double alog( double base, double number ) {
    return log( number ) / log( base );
}

// extern uint64_t nearest( void );
// extern void restore( uint64_t flags );
extern void extract2( double d, double* psig, int16_t* pexp );
extern void extract10( double d, double* psig, int16_t* pexp );
// extern void roundint( double d, int16_t* pint, double* pfrac );

#define LOG102 0.301029995664

static void readln( const char* prompt, char* buf, size_t bufsz ) {
    printf( "%s? ", prompt ); fflush( stdout );
    buf[0] = '\0';
    fgets( buf, bufsz, stdin );
}

int main( int argc, char** argv ) {

    char buf[256];
    double d; int b;
    readln( "Floating-point number", buf, 256 ); 
    if ( sscanf( buf, "%lf", &d ) != 1 ) return EXIT_FAILURE;
    readln( "Desired output base  ", buf, 256 );
    if ( sscanf( buf, "%d", &b ) != 1 || b < 2 || b > 36 ) return EXIT_FAILURE;

    printf( "d = %g, b = %d\n", d, b );

    bool s = signbit(d) ? true : false;
    d = fabs( d );
    if ( d == 0.0 ) {
        printf( "%s0\n", (s?"-":"") );
        return EXIT_SUCCESS;
    } else if ( isnan(d) ) {
        printf( "%snan\n", (s?"-":"") );
        return EXIT_SUCCESS;
    } else if ( isinf(d) ) {
        printf( "%sinf\n", (s?"-":"") );
        return EXIT_SUCCESS;
    } else if ( !isnormal(d) ) {
        printf( "%sdenormal\n", (s?"-":"") );
    }

    double sig10 = 0.0;
    int16_t exp10 = 0;
    extract10( d, &sig10, &exp10 );

    printf( "sig10 = %g, exp10 = %" PRId16 "\n", sig10, exp10 );

    double sig2 = 0.0;
    int16_t exp2 = 0;
    extract2( d, &sig2, &exp2 );
    printf( "sig2 = %g, exp2 = %" PRId16 "\n", sig2, exp2 );

    double t = sig2 * pow( 2.0, exp2 );
    printf( "t = %g\n", t );

    double exp102 = exp2 * LOG102;
    int exp102i = (int) round( exp102 );
    double exp102f = ( exp102 - exp102i ) / LOG102;
    t = sig2 * pow( 2.0, exp102f );
    printf( "t = %g, exp102i = %d\n", t, exp102i );

    double logb2 = alog( b, 2 );
    double expb2 = exp2 * logb2;
    int expb2i = (int) round( expb2 );
    double expb2f = ( expb2 - expb2i ) / logb2;
    t = sig2 * pow( 2.0, expb2f );
    printf( "t = %g, expb2i = %d\n", t, expb2i );

    return EXIT_SUCCESS;
}
