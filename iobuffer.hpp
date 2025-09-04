#pragma once
#ifndef IOBUFFER_HPP
#define IOBUFFER_HPP

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

class IOBuffer : public Buffer {

protected:
    int fd;
    mutable int err;

public:
    IOBuffer( int fd_ );
    IOBuffer( const IOBuffer& src );
    IOBuffer( IOBuffer&& src );

    virtual ~IOBuffer();

    IOBuffer& operator=( const IOBuffer& src );
    IOBuffer& operator=( IOBuffer&& src );

    bool read();
    bool write() const;

    inline int getLastError() const { return err; }
    inline int getFd() const { return fd; }
    inline void setFd( int fd_ ) { fd = fd_; }

};


#endif