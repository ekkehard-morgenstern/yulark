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

#define MIN_MAXBUFFERSIZE   65535U

static size_t maxBufferSize = SIZE_MAX;

void setMaxBufferSize( size_t size ) {
    if ( size < MIN_MAXBUFFERSIZE ) {
        size = MIN_MAXBUFFERSIZE;
    }
    maxBufferSize = size;
}

/**
 * Auto-scales string buffer to receive the text to be appended.
 * The buffer's capacity is multiplied by 3 each time it is to be resized,
 * except when that wouldn't be sufficient to satisfy the request.
 * The maximum buffer size is SIZE_MAX, which can be a very large value.
 * So this sacrifices stability at the expense of being able to load files
 * with very large lines, for instance. On Linux, the OOM killer will autokill
 * a process that consumes too much memory, so be careful.
 * If the memory size would exceed SIZE_MAX, the input to be appended
 * is truncated as needed.
 * EDIT: I made the size maximum configurable.
 */
void autoScaleAppend( std::string& buffer, const char* s, size_t len ) {
    size_t cap = buffer.capacity();
    size_t siz = buffer.size();
    size_t rem = cap - siz;
    if ( len > rem ) {
        if ( cap <= maxBufferSize / 3U ) {
            cap *= 3U;
        } else {
            cap = maxBufferSize;
        }
        rem = cap - siz;
        if ( len > rem ) {
            rem = maxBufferSize - siz;
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
