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

class ForthVM : public Buffer {

protected:
    forthword_t             psp;    // parameter stack pointer (zval)
    forthword_t             rsp;    // return stack pointer (zval)
    forthword_t             wa;     // word address (zval into buffer)
    forthword_t             wp;     // word pointer (zval into buffer)

    inline void checkPtr( const forthword_t& p ) const {
        if ( p.zval >= memFill / FW_SIZE ) {
            throw ForthVM_Exception( "Bad FORTH pointer", p );
        }
    }

    inline forthword_t& indirect( const forthword_t& p ) {
        checkPtr( p );
        return *(reinterpret_cast<forthword_t*>(memory) + p.zval);
    }

    inline void increment( forthword_t& p ) const {
        p.zval += FW_SIZE;
        checkPtr( p );
    }

    inline void decrement( forthword_t& p ) const {
        p.zval -= FW_SIZE;
        checkPtr( p );
    }

    inline void next() {
        // terminates every FORTH wrote written in machine code
        wa = indirect( wp ); increment( wp ); // WA := [WP]+
        forthword_t tmp = indirect( wa ); tmp.cbfn( this );  // JUMP [WA]
    }

    // callback for NEXT that can be stored inside the VM
    static void next_cb( ForthVM* vm );

    inline void docol() {
        // starts the processing of every FORTH word implemented in FORTH
        decrement( rsp ); indirect( rsp ) = wp;     // -[RSP] := WP
        increment( wa ); wp = wa;   // WP := +WA
        next();
    }

    // callback for DOCOL that can be stored inside the VM
    static void docol_cb( ForthVM* vm );

    inline void exit() {
        // terminates the processing of any FORTH word implemented in FORTH
        wp = indirect( rsp ); increment( rsp );     // WP := [RSP]+
        next();
    }

    // callback for EXIT that can be stored inside the VM
    static void exit_cb( ForthVM* vm );
};

#endif