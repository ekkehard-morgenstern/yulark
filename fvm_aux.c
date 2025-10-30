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
#include <string.h>
#include <stdio.h>

#include <unistd.h>
#include <regex.h>

// debugging function for floating-point
void _dbgfdot( uint64_t data ) {
    char tmp[256];
    union {
        uint64_t uival;
        double   dval;
    } u;
    u.uival = data;
    tmp[0] = '\0';
    snprintf( tmp, 256U, "%g ", u.dval );
    size_t len = strlen(tmp);
    int rv = write( 1, tmp, len );
    if ( rv != (int) len ) {
        fprintf( stderr, "? I/O error\n" );
        exit( EXIT_FAILURE );
    }
}

// system memory management interface
uint64_t _xalloc( uint64_t size ) {
    void* block = malloc( (size_t) size );
    if ( block == 0 ) {
        fprintf( stderr, "? out of memory\n" );
        exit( EXIT_FAILURE );
    }
    union {
        uint64_t uval;
        void*    pval;
    } u;
    u.uval = 0;
    u.pval = block;
    return u.uval;
}
void _xfree( uint64_t ptr ) {
    union {
        uint64_t uval;
        void* pval;
    } u;
    u.uval = ptr;
    free( u.pval );
}

// regular expression subroutines

typedef struct _reinfo_t {
    char*   pattern;
    regex_t regex;
} reinfo_t;

static void* create_reinfo( const char* cpattern ) {
    unsigned char len = cpattern[0];
    const char*   str = &cpattern[1];
    reinfo_t* rei = (reinfo_t*) malloc( sizeof(reinfo_t) );
    if ( rei == 0 ) {
        fprintf( stderr, "? out of memory, size = %zu\n",
            sizeof(reinfo_t) );
        goto ERR1;
    }
    rei->pattern = (char*) malloc( len + 1U );
    if ( rei->pattern == 0 ) {
        fprintf( stderr, "? out of memory, size = %zu\n",
            (size_t)( len + 1U ) );
        goto ERR2;
    }
    if ( len ) memcpy( rei->pattern, str, len );
    rei->pattern[len] = '\0';
    memset( &rei->regex, 0, sizeof(regex_t) );
    int rv = regcomp( &rei->regex, rei->pattern, REG_EXTENDED );
    if ( rv != 0 ) {
        char tmp[512]; tmp[0] = '\0';
        regerror( rv, &rei->regex, tmp, 512U );
        fprintf( stderr, "? failed to compile regex '%s': %s\n",
            rei->pattern, tmp );
        goto ERR3;
    }
    return (void*) rei;

ERR3:   free( rei->pattern );
ERR2:   free( rei );
ERR1:   fflush( stderr );
        return 0;
}

static void delete_reinfo( void* rei0 ) {
    reinfo_t* rei = (reinfo_t*) rei0;
    regfree( &rei->regex );
    memset( &rei->regex, 0, sizeof(regex_t) );
    free( rei->pattern ); rei->pattern = 0;
    free( rei );
}

// regular expression interface
uint64_t _reinit( uint64_t cpattern0 ) {
    union {
        void* p;
        uint64_t ui;
        const char* s;
    } u;
    u.ui = cpattern0;
    const char* cpattern = u.s;
    void* rei0 = create_reinfo( cpattern );
    u.ui = 0;
    u.p = rei0;
    return u.ui;
}

void _refree( uint64_t rei0 ) {
    union {
        void* p;
        uint64_t ui;
    } u;
    u.ui = rei0;
    delete_reinfo( u.p );
}
