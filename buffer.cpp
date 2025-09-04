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

#include "buffer.hpp"

#include <cstring>

Buffer::Buffer() {
    memory = new char [ DEFAULT_BUFFER_SIZE ];
    memSize = DEFAULT_BUFFER_SIZE;
    memFill = 0;
}

Buffer::Buffer( const Buffer& src ) {
    if ( src.memSize ) {
        memory = new char [ src.memSize ];
        if ( src.memFill ) {
            std::memcpy( memory, src.memory, src.memFill );
        }
    } else {
        memory = nullptr;
    }
    memSize = src.memSize;
    memFill = src.memFill;
}

Buffer::Buffer( Buffer&& src ) {
    memory = src.memory; src.memory = nullptr;
    memSize = src.memSize; src.memSize = 0;
    memFill = src.memFill; src.memFill = 0;
}

Buffer::~Buffer() {
    if ( memory != nullptr ) {
        delete [] memory; memory = nullptr;
    }
    memSize = memFill = 0;
}

Buffer& Buffer::operator=( const Buffer& src ) {
    if ( src.memFill > memSize ) {
        char* newMem = new char [ src.memSize ];
        std::memcpy( newMem, src.memory, src.memFill );
        delete [] memory; memory = newMem;
        memSize = src.memSize;
        memFill = src.memFill;
    } else {
        if ( src.memFill ) {
            std::memcpy( memory, src.memory, src.memFill );
        }
        memFill = src.memFill;
    }
    return *this;
}

Buffer& Buffer::operator=( Buffer&& src ) {
    memory = src.memory; src.memory = nullptr;
    memSize = src.memSize; src.memSize = 0;
    memFill = src.memFill; src.memFill = 0;
    return *this;
}
