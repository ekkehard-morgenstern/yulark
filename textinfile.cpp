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
    : Infile( fileName_ ), inputPos(0), inputLineNumber(1) {}

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
                ++p;
                size_t len = static_cast<size_t>( p - s );
                autoScaleAppend( inputLine, s, len );
                inputPos = static_cast<int>( p - ioBuffer.getMemPtr() );
                ++inputLineNumber;
                return true;
            }
            ++p;
        }
        // end of buffer
        if ( p > s ) {
            size_t len = static_cast<size_t>( p - s );
            autoScaleAppend( inputLine, s, len );
            inputPos = static_cast<int>( p - ioBuffer.getMemPtr() );
        }
        if ( ioBuffer.getMemFill() < ioBuffer.getMemSize() ) {
            // end of file
            return !inputLine.empty();
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

off_t TextInfile::getFilePos() const {
    return Infile::getFilePos() + static_cast<off_t>(inputPos);
}