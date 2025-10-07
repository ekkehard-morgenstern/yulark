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

static int baseddigit( int base, int val ) {
    return val <= 9 ? '0' + val : ( 'A' + ( val - 10 ) );
}

static void storedigit( char* buf, size_t bufsz, size_t* ppos, int base,
    int val ) {
    size_t pos = *ppos;
    if ( base < 2 || base > 36 || val < 0 || val >= base ) {
        fprintf( stderr, "? storedigit: invalid parameter, base=%d, val=%d\n",
            base, val );
        exit( EXIT_FAILURE );
    }
    int ch = baseddigit( base, val );
    if ( pos < bufsz-1U ) buf[pos++] = (char) ch;
    *ppos = pos;
}

static void storedot( char* buf, size_t bufsz, size_t* ppos ) {
    size_t pos = *ppos;
    if ( pos < bufsz-1U ) buf[pos++] = (char) '.';
    *ppos = pos;
}

static void outputmantissa( char* buf, size_t bufsz, size_t* ppos,
    double data, int base, int maxdig ) {
    size_t pos = *ppos;
    bool first = true;
    while ( --maxdig >= 0 ) {
        int dig = (int) fmod( trunc( data ), base );
        // printf( "dig = %d\n", dig );
        storedigit( buf, bufsz, &pos, base, dig );
        if ( first ) { first = false; storedot( buf, bufsz, &pos ); }
        data *= base;
    }
    char nine = (char) baseddigit( base, base-1 );
    if ( pos > 0U && buf[pos-1U] == '0' ) {
        // zero-run
        while ( pos > 0U && buf[pos-1U] == '0' ) --pos;
    } else if ( pos > 0U && buf[pos-1U] == nine ) {
        // nine-run
        while ( pos > 0U && ( buf[pos-1U] == nine || buf[pos-1U] == '.' ) ) {
            --pos;
        }
        if ( pos > 0U ) buf[pos-1U] += 1;
    }
    buf[pos] = '\0';
    *ppos = pos;
}

static void countdigits( const char* buf, size_t endpos,
    bool* phasdot, size_t* pbefore, size_t* pafter ) {
    bool hasdot = false; size_t before = 0, after = 0;
    for ( size_t i=0; i < endpos; ++i ) {
        char c = buf[i];
        if ( !hasdot ) {
            if ( c == '.' ) {
                hasdot = true;
            } else {
                ++before;
            }
        } else {
            ++after;
        }
    }
    *phasdot = hasdot;
    *pbefore = before;
    *pafter  = after;
}

extern void fixupexp( char* target, const char* source, size_t maxdigits,
    size_t total, int16_t* pexp );

static void outexp( char* buf2, size_t bufsz2, size_t* ppos2, int base,
    int val ) {
    size_t pos2 = *ppos2;
    if ( val >= base ) outexp( buf2, bufsz2, &pos2, base, val / base );
    int dig = val % base;
    int chr = baseddigit( base, dig );
    if ( bufsz2-1U ) buf2[pos2++] = (int) chr;
    *ppos2 = pos2;
}

static void fixexponent( char* buf2, size_t bufsz2, size_t* ppos2,
    const char* buf, size_t endpos, bool hasdot, size_t before, size_t after,
    int maxdig, int16_t* pexpb2i, int base, bool sign ) {
    size_t pos2 = *ppos2;
    size_t total = before + after;
    if ( sign ) buf2[pos2++] = '-';
    fixupexp( &buf2[pos2], buf, (size_t) maxdig, total, pexpb2i );
    // output based exponent field
    int16_t exp = *pexpb2i;
    if ( exp == INT16_C(0) ) return; // not necessary
    pos2 = strlen( buf2 );
    if ( base > 10 ) {  // for bases > 10, don't use E, use '
        if ( bufsz2-1U ) buf2[pos2++] = '\'';
    } else {
        if ( bufsz2-1U ) buf2[pos2++] = 'E';
    }
    if ( exp < INT16_C(0) ) {
        if ( bufsz2-1U ) buf2[pos2++] = '-';
        exp = -exp;
    }
    outexp( buf2, bufsz2, &pos2, base, exp );
    buf2[pos2] = '\0';
    *ppos2 = pos2;
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
    printf( "s = %s\n", (s?"true":"false") );
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
    int16_t expb2i = (int16_t) round( expb2 );
    double expb2f = ( expb2 - expb2i ) / logb2;
    t = sig2 * pow( 2.0, expb2f );
    int maxdig = (int) round( alog( b, pow( 2, 52 ) ) );
    printf( "t = %g, expb2i = %" PRId16 ", expb2f = %g, maxdig = %d\n", t,
        expb2i, expb2f, maxdig );

    size_t pos = 0;
    outputmantissa( buf, 256U, &pos, t, b, maxdig );
    printf( "m = '%s'\n", buf );

    bool hasdot = false; size_t before = 0, after = 0;
    countdigits( buf, pos, &hasdot, &before, &after );
    printf( "hasdot = %s, before = %zu, after = %zu\n",
        (hasdot?"true":"false"), before, after );

    char buf2[256]; size_t pos2 = 0;
    fixexponent( buf2, 256, &pos2, buf, pos, hasdot, before, after, maxdig,
        &expb2i, b, s );

    printf( "buf2 = \"%s\"\n", buf2 );



    return EXIT_SUCCESS;
}
