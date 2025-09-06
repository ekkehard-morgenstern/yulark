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

#include "iobuffer.hpp"

IOBuffer::IOBuffer( int fd_ ) : fd(fd_), err(0) {}

IOBuffer::IOBuffer( const IOBuffer& src )
    :   Buffer( src ), fd( src.fd ), err(0) {}

IOBuffer::IOBuffer( IOBuffer&& src )
    :   Buffer( src ) { fd = src.fd; src.fd = -1; err = 0; }

IOBuffer::~IOBuffer() { fd = -1; err = 0; }

IOBuffer& IOBuffer::operator=( const IOBuffer& src ) {
    Buffer::operator=( src );
    fd = src.fd;
    err = 0;
    return *this;
}

IOBuffer& IOBuffer::operator=( IOBuffer&& src ) {
    Buffer::operator=( src );
    fd = src.fd; src.fd = -1; err = 0;
    return *this;
}

bool IOBuffer::read() {
    if ( memory == nullptr || memSize == 0 ) {
        return false;
    }
    ssize_t rv;
    err = 0;
RETRY:
    rv = ::read( fd, memory, memSize );
    if ( rv == -1 ) {
        if ( errno == EINTR ) {
            // TBD: Signal arrived at process, call poll handler
            goto RETRY;
        }
        err = errno;
        return false;
    }
    memFill = rv;
    return true;
}

bool IOBuffer::write() const {
    if ( memory == nullptr ) {
        return false;
    }
    if ( memFill == 0 ) {
        return true;
    }
    ssize_t rv;
    err = 0;
RETRY:
    rv = ::write( fd, memory, memFill );
    if ( rv == -1 || static_cast<size_t>(rv) < memFill ) {
        if ( rv == -1 && errno == EINTR ) {
            // TBD: Signal arrived at process, call poll handler
            goto RETRY;
        }
        if ( rv == -1 ) {
            err = rv;
        }
        return false;
    }
    return true;
}
