#pragma once
#ifndef BUFFER_HPP
#define BUFFER_HPP  1

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

#include <cstddef>

#define DEFAULT_BUFFER_SIZE 16384U

class Buffer {

protected:
    char*   memory;
    size_t  memSize;
    size_t  memFill;

public:
    Buffer();
    Buffer( const Buffer& src );
    Buffer( Buffer&& src );

    virtual ~Buffer();

    inline char* getMemPtr() const { return memory; }
    inline size_t getMemSize() const { return memSize; }
    inline size_t getMemFill() const { return memFill; }

    Buffer& operator=( const Buffer& src );
    Buffer& operator=( Buffer&& src );

};

#endif