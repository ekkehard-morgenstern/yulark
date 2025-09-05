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

#include "textinfile.hpp"
#include "utilities.hpp"

TextInfile::TextInfile( const std::string& fileName_ )
    : Infile( fileName_ ), inputPos(0) {}

TextInfile::~TextInfile() {}

bool TextInfile::readLine() {
    inputLine.clear();
    do {
        const char* s = ioBuffer.getMemPtr() + inputPos;
        const char* e = ioBuffer.getMemPtr() + ioBuffer.getMemFill();
        const char* p = s;
        // continue reading from buffer
        while ( p < e ) {
            char c = *p;
            if ( c == '\n' ) {
                if ( p > s ) {
                    size_t len = static_cast<size_t>( p - s );
                    autoScaleAppend( inputLine, s, len );
                }
                ++p;
                inputPos = static_cast<int>( p - ioBuffer.getMemPtr() );
                return true;
            }
            ++p;
        }
        // end of buffer
        if ( ioBuffer.getMemFill() < ioBuffer.getMemSize() ) {
            // end of file
            return false;
        }
        // refill buffer
        if ( !ioBuffer.read() ) {
            err = ioBuffer.getLastError();
            return false;
        }
        // continue at beginning of new data
        inputPos = 0;
    } while (true);
}
