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

#include "utilities.hpp"

void autoScaleAppend( std::string& buffer, const char* s, size_t len ) {
    size_t cap = buffer.capacity();
    size_t siz = buffer.size();
    size_t rem = cap - siz;
    if ( len > rem ) {
        if ( cap <= SIZE_MAX / 3U ) {
            cap *= 3U;
        }
        rem = cap - siz;
        if ( len > rem ) {
            rem = SIZE_MAX - siz;
            if ( len > rem ) {
                len = rem;
                if ( len == 0U ) {
                    return;
                }
            }
            cap = siz + len;
        }
        buffer.reserve( cap );
    }
    buffer.append( s, len );
}