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

enum {
    KW_AGAIN = 1, KW_ARRAY, KW_ASSOC, KW_BREAK, KW_CALL, KW_CASE, KW_CLASS,
    KW_COMMAND, KW_CONST, KW_CONTINUE, KW_DATABASE, KW_DEFAULT, KW_DEFINE,
    KW_DELETE, KW_DESTROY, KW_DOWNTO, KW_DYNAMIC, KW_ELSE, KW_END, KW_ENDIF,
    KW_ENUM, KW_EVER, KW_EXPORT, KW_EXTENDS, KW_FOR, KW_FOREVER, KW_FROM,
    KW_FN_FROM_JSON, KW_FUNCTION, KW_GOSUB, KW_GOTO, KW_FN_HTTP, KW_IF,
    KW_IFDEF, KW_IFNDEF, KW_IMPLEMENTS, KW_IMPORT, KW_IN, KW_INCLUDE, KW_INIT,
    KW_FN_INSERT, KW_LET, KW_NEW, KW_PROPERTY, KW_REPEAT, KW_RESULT, KW_RETURN,
    KW_SELECT, KW_STATUS, KW_STEP, KW_SWITCH, KW_TO, KW_FN_TO_JSON, KW_UNTIL,
    KW_UPDATE, KW_VERBATIM, KW_WEND, KW_WHILE
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
