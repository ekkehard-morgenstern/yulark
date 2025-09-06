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

#include "infile.hpp"

Infile::Infile( const std::string& fileName_ )
    :   fileName(fileName_), ioBuffer(-1), fd(-1), err(0) {}

Infile::~Infile() {
    close();
}

bool Infile::open() {
    if ( fd != -1 ) {
        return true;
    }
    // attempt to open file
RETRY:
    fd = ::open( fileName.c_str(), O_RDONLY );
    if ( fd == -1 ) {
        if ( errno == EINTR ) {
            // TBD: Signal arrived at process, call poll handler
            goto RETRY;
        }
        err = errno;
        return false;
    }
    ioBuffer.setFd( fd );
    err = 0;
    // attempt to fill the buffer with data
    if ( !ioBuffer.read() ) {
        int lastErr = ioBuffer.getLastError();
        close();
        err = lastErr;
        return false;
    }
    return true;
}

void Infile::close() {
    if ( fd == -1 ) {
        return;
    }
    ioBuffer.setFd( -1 );
    ::close( fd ); fd = -1; err = 0;
}

off_t Infile::getFilePos() const {
    off_t rv = lseek( fd, 0, SEEK_CUR );
    if ( rv == static_cast<off_t>(-1) ) {
        err = errno;
    } else {
        err = 0;
    }
    return rv;
}
