#pragma once
#ifndef INFILE_HPP
#define INFILE_HPP  1

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

#ifndef IOBUFFER_HPP
#include "iobuffer.hpp"
#endif

class Infile {

    Infile( const Infile& ) = delete;
    Infile( Infile&& ) = delete;

    Infile& operator=( const Infile& ) = delete;
    Infile& operator=( Infile&& ) = delete;

protected:
    std::string     fileName;
    IOBuffer        ioBuffer;
    int             fd;
    mutable int     err;

public:
    Infile( const std::string& fileName_ );
    virtual ~Infile();

    inline int getFd() const { return fd; }
    inline int getLastError() const { return err; }

    bool open();
    void close();

    virtual off_t getFilePos() const;
};


#endif
