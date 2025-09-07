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

#include "keyword.hpp"

const KeywordDef Keyword::keywordDefs[] = {
    { nullptr, 0 }
};

std::map<std::string,int> Keyword::mapKeywordToId;
std::map<int,std::string> Keyword::mapIdToKeyword;
bool Keyword::initialized = false;

void Keyword::initialize() {
    int i;
    for ( i=0; keywordDefs[i].name; ++i ) {
        const char* name = keywordDefs[i].name;
        int         id   = keywordDefs[i].id;
        mapKeywordToId.insert(
            std::pair<std::string,int>(
                std::string(name), id
            )
        );
        mapIdToKeyword.insert(
            std::pair<int,std::string>(
                id, std::string(name)
            )
        );
    }
}

void Keyword::autoInit() {
    if ( !initialized ) {
        initialized = true;
        initialize();
    }
}

bool Keyword::findIdByName( const std::string& inpName, int& outId ) {
    autoInit();
    auto iter = mapKeywordToId.find( inpName );
    if ( iter == mapKeywordToId.end() ) {
        return false;
    }
    outId = iter->second;
    return true;
}

bool Keyword::findNameById( int inpId, std::string& outName ) {
    autoInit();
    auto iter = mapIdToKeyword.find( inpId );
    if ( iter == mapIdToKeyword.end() ) {
        return false;
    }
    outName = iter->second;
    return true;
}
