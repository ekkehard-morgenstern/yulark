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

#include "textinfile.cpp"
#include "infile.cpp"
#include "iobuffer.cpp"
#include "buffer.cpp"
#include "utilities.cpp"

#include <exception>
#include <iostream>
#include <cstdlib>

int main( int argc, char** argv ) {

    try {
        if ( argc < 2 ) {
            std::cerr << "Usage: " << argv[0] << " <infile>" << std::endl;
            return EXIT_FAILURE;
        }
        TextInfile file( argv[1] );
        if ( !file.open() ) {
            std::cerr << "failed to open file" << std::endl;
            std::cerr << "error " << file.getLastError() << std::endl;
            return EXIT_FAILURE;
        }
        while ( file.readLine() ) {
            std::cout << file.getLine();
        }
    } catch ( const std::exception& xcpt ) {
        std::cerr << "exception: " << xcpt.what() << std::endl;
        return EXIT_FAILURE;
    } catch ( ... ) {
        std::cerr << "unhandled exception" << std::endl;
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}