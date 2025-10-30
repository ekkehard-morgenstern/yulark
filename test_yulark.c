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
#include <string.h>
#include <stdio.h>

#include <unistd.h>
#include <regex.h>

extern const char fvm_library[];
extern size_t fvm_library_size;

extern const char fvm_yulark[];
extern size_t fvm_yulark_size;

extern void fvm_run( void* mem, size_t siz, size_t rsz,
    const char* lib, size_t szlib );

#define MEMSIZE     1048576U
#define RSTKSIZE    65536U

static char memory[MEMSIZE];

int main( int argc, char** argv ) {

    size_t size = fvm_library_size + fvm_yulark_size;
    char* libs = (char*) malloc( size );
    if ( libs == 0 ) return EXIT_FAILURE;
    memcpy( libs, fvm_library, fvm_library_size );
    memcpy( libs + fvm_library_size, fvm_yulark, fvm_yulark_size );

    fvm_run( memory, MEMSIZE, RSTKSIZE, libs, size );

    free( libs );

    return EXIT_SUCCESS;
}
