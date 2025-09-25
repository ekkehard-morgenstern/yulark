#pragma once
#ifndef FORTHVM_HPP
#define FORTHVM_HPP  1

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

#ifndef BUFFER_HPP
#include "buffer.hpp"
#endif

class ForthVM;

typedef union __forthword_t {
    union __forthword_t*    fwp;
    void*                   ptr;
    char*                   str;
    void                  (*cbfn)(ForthVM*);
    int64_t                 ival;
    uint64_t                uval;
    double                  dval;
    size_t                  zval;
} forthword_t;

#define FW_SIZE             (sizeof(forthword_t))
#define FW_SIZEM1           (FW_SIZE-1U)

class ForthVM_Exception : public std::exception {

protected:
    char buf[256];

public:
    inline ForthVM_Exception( const char* text, const forthword_t& fw ) {
        std::snprintf( buf, 256U, "%s: %016" PRIx64, text, fw.zval );
    }

    inline virtual const char* what() const throw() override {
        return buf;
    }
};

extern "C" void fvm_run( void* mem, size_t siz, size_t rsz );

#define FORTHVM_MEMSIZE 131072U     // 128K
#define FVM_RETSTKSIZE  8192U       // 8K

/*
    memory is organized like so:

        +--------------------------------+
        |       dictionary space         |
        .                                .
        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        .                                .
        |     parameter stack space      |
        +--------------------------------+
        |      return stack space        |
        +--------------------------------+

Word definitions look like this:

        +--------------------+
        |  link to previous  |
        +-----+--------------+
        | NLF | NAME ...     |
        +--------------------+
        | NAME ... PAD 0 0 0 | (optional, remainder of name and pad bytes)
        +--------------------+
        |  code-addr / DOCOL |
        +--------------------+
        |  definition ...    | word-addresses
        +--------------------+



*/


class ForthVM : public Buffer {

public:
    // ForthVM();

};

#endif