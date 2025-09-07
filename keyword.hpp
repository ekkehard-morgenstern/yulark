#pragma once
#ifndef KEYWORD_HPP
#define KEYWORD_HPP 1

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

#ifndef TYPES_HPP
#include "types.hpp"
#endif

struct KeywordDef {
    const char* const name;
    int               id;
};

class Keyword {

    static const KeywordDef             keywordDefs[];
    static std::map<std::string,int>    mapKeywordToId;
    static std::map<int,std::string>    mapIdToKeyword;
    static bool                         initialized;

    static void initialize();

protected:
    static void autoInit();

public:
    static bool findIdByName( const std::string& inpName, int& outId );
    static bool findNameById( int inpId, std::string& outName );




};

#endif
