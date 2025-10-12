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

extern const char fvm_library[];
extern size_t fvm_library_size;

extern void fvm_run( void* mem, size_t siz, size_t rsz,
    const char* lib, size_t szlib );

#define MEMSIZE     1048576U
#define RSTKSIZE    65536U

static char memory[MEMSIZE];

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
    write( 1, tmp, strlen(tmp) );
}

int main( int argc, char** argv ) {

    fvm_run( memory, MEMSIZE, RSTKSIZE, fvm_library, fvm_library_size );

    return EXIT_SUCCESS;
}
