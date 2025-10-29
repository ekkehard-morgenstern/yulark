\
\   YULARK - a virtual machine written in C++
\   Copyright (C) 2025  Ekkehard Morgenstern
\
\   This program is free software: you can redistribute it and/or modify
\   it under the terms of the GNU General Public License as published by
\   the Free Software Foundation, either version 3 of the License, or
\   (at your option) any later version.
\
\   This program is distributed in the hope that it will be useful,
\   but WITHOUT ANY WARRANTY; without even the implied warranty of
\   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
\   GNU General Public License for more details.
\
\   You should have received a copy of the GNU General Public License
\   along with this program.  If not, see <https://www.gnu.org/licenses/>.
\
\   NOTE: Programs created with YULARK do not fall under this license.
\
\   CONTACT INFO:
\       E-Mail: ekkehard@ekkehardmorgenstern.de
\       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
\             Germany, Europe
\

\ create a variable
: VARIABLE ( -- ) CREATE 0 , ;

\ create a constant with a value from the stack
: CONSTANT ( n -- ) CREATE , DOES> @ ;

\ create an array that can hold n words
: ARRAY ( n -- ) CREATE ALLOT ;

\ define the PAD array (256 bytes, 32 x 8)
32 ARRAY PAD

\ define a string buffer array (256 bytes, 32 x 8)
\ for string handling functions
32 ARRAY STRBUF

\ define ANSI control sequence argument counter
VARIABLE CSAC

\ define ANSI control sequence argument array
8 ARRAY CSAA

\ define screen attribute combinations
64 ARRAY ATTRARY

\ check character for EOF
( char -- bool )
: ?EOF
    -1 =
;

\ skip one space character in the input
: SKIP1SPC
    INPGETCH
    ( char )
    \ check for space or EOF
    DUP ?EOF OVER ?SPC OR UNLESS
        ( char )
        \ if not: go back one character
        >IN DECR
    THEN
    ( char )
    DROP
;

\ store a string character
( char -- )
: SC!
    \ fetch length of buffer
    STRBUF C@
    ( char len )
    \ check length, maximum 255 chars allowed
    DUP 255 < IF
        ( char len )
        \ increment length and store
        1+ STRBUF
        ( char len addr )
        2DUP C!
        ( char len strbuf )
        \ sum base address and length and store there
        + C!
    ELSE
        ( char len )
        2DROP
    THEN
;

\ read a string literal from the input, skipping
\ one leading space character
: STRLIT
    \ clear the length counter in the string buffer
    0 STRBUF C!
    \ skip one space
    SKIP1SPC
    \ start loop
    BEGIN
        \ get a character
        INPGETCH
        ( char )
        \ check for EOF and double quote
        DUP -1 <> OVER 34 <> AND
    WHILE
        \ neither EOF nor double quote
        ( char )
        \ store character
        SC!
    REPEAT
    \ EOF or double quote
    ( char )
    DROP
;

\ get address and length of a counted string
( addr -- addr+1 len )
: COUNT
    ( addr )
    DUP C@
    ( addr len )
    SWAP 1+ SWAP
;

\ output a string literal
\ when compiling, put the string at HERE and generate code to output it
\ compiles to:
\   JUMP <pos> <str> LIT[str] LIT[len] TYPE
\
\ ( -- )
: ." IMMEDIATE \ " \ (terminating quote is for compressor)
    ?IMMEDIATE UNLESS
        \ read literal into STRBUF
        STRLIT
        \ compile string into the word with output code
        COMPILE JUMP
        0 ,
        \ HERE-8 is the address where to store the jump location
        HERE 8 -
        ( pos )
        \ get buffer address and length
        STRBUF COUNT HERE
        ( pos srcaddr srclen tgtaddr )
        \ allot space
        OVER 7 + 7 NOT AND 8 / ALLOT
        \ copy args to CMOVE
        ( pos srcaddr srclen tgtaddr )
        SWAP
        ( pos srcaddr tgtaddr srclen )
        2DUP SWAP
        ( pos srcaddr tgtaddr srclen srclen tgtaddr )
        5 ROLL
        ( pos tgtaddr srclen srclen tgtaddr srcaddr )
        SWAP
        ( pos tgtaddr srclen srclen srcaddr tgtaddr )
        ROT
        ( pos tgtaddr srclen srcaddr tgtaddr srclen )
        \ copy string over
        CMOVE
        ( pos tgtaddr srclen )
        ROT
        ( tgtaddr srclen pos )
        \ patch the JUMP location to HERE
        HERE SWAP !
        \ compile string address and length
        ( tgtaddr srclen )
        SWAP
        \ ( srclen tgtaddr )
        LITERAL LITERAL
        \ compile TYPE
        COMPILE TYPE
    ELSE
        \ read literal into STRBUF
        STRLIT
        \ output the buffer
        STRBUF COUNT TYPE
    THEN
;

\ quote a string literal
\ when compiling, put the string at HERE and generate code to output address
\ and length fields
\ compiles to:
\   JUMP <pos> <str> LIT[str] LIT[len]
\
\ ( -- addr len )
: S" IMMEDIATE \ " \ (terminating quote is for compressor)
    ?IMMEDIATE UNLESS
        \ read literal into STRBUF
        STRLIT
        \ compile string into the word with output code
        COMPILE JUMP
        0 ,
        \ HERE-8 is the address where to store the jump location
        HERE 8 -
        ( pos )
        \ get buffer address and length
        STRBUF COUNT HERE
        ( pos srcaddr srclen tgtaddr )
        \ allot space
        OVER 7 + 7 NOT AND 8 / ALLOT
        \ copy args to CMOVE
        ( pos srcaddr srclen tgtaddr )
        SWAP
        ( pos srcaddr tgtaddr srclen )
        2DUP SWAP
        ( pos srcaddr tgtaddr srclen srclen tgtaddr )
        5 ROLL
        ( pos tgtaddr srclen srclen tgtaddr srcaddr )
        SWAP
        ( pos tgtaddr srclen srclen srcaddr tgtaddr )
        ROT
        ( pos tgtaddr srclen srcaddr tgtaddr srclen )
        \ copy string over
        CMOVE
        ( pos tgtaddr srclen )
        ROT
        ( tgtaddr srclen pos )
        \ patch the JUMP location to HERE
        HERE SWAP !
        \ compile string address and length
        ( tgtaddr srclen )
        SWAP
        \ ( srclen tgtaddr )
        LITERAL LITERAL
    ELSE
        \ read literal into STRBUF
        STRLIT
        \ output buffer info
        STRBUF COUNT
    THEN
;

\ quote a counted string literal
\ when compiling, put the string at HERE and generate code to output address
\ compiles to:
\   JUMP <pos> <str> LIT[str]
\
\ ( -- addr )
: C" IMMEDIATE \ " \ (terminating quote is for compressor)
    ?IMMEDIATE UNLESS
        \ read literal into STRBUF
        STRLIT
        \ compile string into the word with output code
        COMPILE JUMP
        0 ,
        \ HERE-8 is the address where to store the jump location
        HERE 8 -
        ( pos )
        \ get buffer address (at count byte) and length+1
        STRBUF DUP C@ 1+
        ( pos srcaddr srclen )
        HERE
        ( pos srcaddr srclen tgtaddr )
        \ allot space
        OVER 7 + 7 NOT AND 8 / ALLOT
        \ copy args to CMOVE
        ( pos srcaddr srclen tgtaddr )
        SWAP
        ( pos srcaddr tgtaddr srclen )
        2DUP SWAP
        ( pos srcaddr tgtaddr srclen srclen tgtaddr )
        5 ROLL
        ( pos tgtaddr srclen srclen tgtaddr srcaddr )
        SWAP
        ( pos tgtaddr srclen srclen srcaddr tgtaddr )
        ROT
        ( pos tgtaddr srclen srcaddr tgtaddr srclen )
        \ copy string over
        CMOVE
        ( pos tgtaddr srclen )
        ROT
        ( tgtaddr srclen pos )
        \ patch the JUMP location to HERE
        HERE SWAP !
        \ compile string address and length
        ( tgtaddr srclen )
        SWAP
        \ ( srclen tgtaddr )
        \ only generate code to push address, length not needed
        LITERAL DROP
    ELSE
        \ read literal into STRBUF
        STRLIT
        \ output buffer info
        STRBUF
    THEN
;

: LF 10 EMIT ;

: SHOW_W
."   15. Disclaimer of Warranty." LF
." " LF
."   THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY" LF
." APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT" LF
." HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM 'AS IS' WITHOUT WARRANTY" LF
." OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO," LF
." THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR" LF
." PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM" LF
." IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF" LF
." ALL NECESSARY SERVICING, REPAIR OR CORRECTION." LF
." " LF
."   16. Limitation of Liability." LF
." " LF
."   IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING" LF
." WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS" LF
." THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY" LF
." GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE" LF
." USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF" LF
." DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD" LF
." PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS)," LF
." EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF" LF
." SUCH DAMAGES." LF
." " LF
."   17. Interpretation of Sections 15 and 16." LF
." " LF
."   If the disclaimer of warranty and limitation of liability provided" LF
." above cannot be given local legal effect according to their terms," LF
." reviewing courts shall apply local law that most closely approximates" LF
." an absolute waiver of all civil liability in connection with the" LF
;

: SHOW_C
."                      GNU GENERAL PUBLIC LICENSE" LF
."                        Version 3, 29 June 2007" LF
." " LF
."  Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>" LF
."  Everyone is permitted to copy and distribute verbatim copies" LF
."  of this license document, but changing it is not allowed." LF
." " LF
."                             Preamble" LF
." " LF
."   The GNU General Public License is a free, copyleft license for" LF
." software and other kinds of works." LF
." " LF
."   The licenses for most software and other practical works are designed" LF
." to take away your freedom to share and change the works.  By contrast," LF
." the GNU General Public License is intended to guarantee your freedom to" LF
." share and change all versions of a program--to make sure it remains free" LF
." software for all its users.  We, the Free Software Foundation, use the" LF
." GNU General Public License for most of our software; it applies also to" LF
." any other work released this way by its authors.  You can apply it to" LF
." your programs, too." LF
." " LF
."   When we speak of free software, we are referring to freedom, not" LF
." price.  Our General Public Licenses are designed to make sure that you" LF
." have the freedom to distribute copies of free software (and charge for" LF
." them if you wish), that you receive source code or can get it if you" LF
." want it, that you can change the software or use pieces of it in new" LF
." free programs, and that you know you can do these things." LF
." " LF
."   To protect your rights, we need to prevent others from denying you" LF
." these rights or asking you to surrender the rights.  Therefore, you have" LF
." certain responsibilities if you distribute copies of the software, or if" LF
." you modify it: responsibilities to respect the freedom of others." LF
." " LF
."   For example, if you distribute copies of such a program, whether" LF
." gratis or for a fee, you must pass on to the recipients the same" LF
." freedoms that you received.  You must make sure that they, too, receive" LF
." or can get the source code.  And you must show them these terms so they" LF
." know their rights." LF
." " LF
."   Developers that use the GNU GPL protect your rights with two steps:" LF
." (1) assert copyright on the software, and (2) offer you this License" LF
." giving you legal permission to copy, distribute and/or modify it." LF
." " LF
."   For the developers' and authors' protection, the GPL clearly explains" LF
." that there is no warranty for this free software.  For both users' and" LF
." authors' sake, the GPL requires that modified versions be marked as" LF
." changed, so that their problems will not be attributed erroneously to" LF
." authors of previous versions." LF
." " LF
."   Some devices are designed to deny users access to install or run" LF
." modified versions of the software inside them, although the manufacturer" LF
." can do so.  This is fundamentally incompatible with the aim of" LF
." protecting users' freedom to change the software.  The systematic" LF
." pattern of such abuse occurs in the area of products for individuals to" LF
." use, which is precisely where it is most unacceptable.  Therefore, we" LF
." have designed this version of the GPL to prohibit the practice for those" LF
." products.  If such problems arise substantially in other domains, we" LF
." stand ready to extend this provision to those domains in future versions" LF
." of the GPL, as needed to protect the freedom of users." LF
." " LF
."   Finally, every program is threatened constantly by software patents." LF
." States should not allow patents to restrict development and use of" LF
." software on general-purpose computers, but in those that do, we wish to" LF
." avoid the special danger that patents applied to a free program could" LF
." make it effectively proprietary.  To prevent this, the GPL assures that" LF
." patents cannot be used to render the program non-free." LF
." " LF
."   The precise terms and conditions for copying, distribution and" LF
." modification follow." LF
." " LF
."                        TERMS AND CONDITIONS" LF
." " LF
."   0. Definitions." LF
." " LF
."   'This License' refers to version 3 of the GNU General Public License." LF
." " LF
."   'Copyright' also means copyright-like laws that apply to other kinds of" LF
." works, such as semiconductor masks." LF
." " LF
."   'The Program' refers to any copyrightable work licensed under this" LF
." License.  Each licensee is addressed as 'you'.  'Licensees' and" LF
." 'recipients' may be individuals or organizations." LF
." " LF
."   To 'modify' a work means to copy from or adapt all or part of the work" LF
." in a fashion requiring copyright permission, other than the making of an" LF
." exact copy.  The resulting work is called a 'modified version' of the" LF
." earlier work or a work 'based on' the earlier work." LF
." " LF
."   A 'covered work' means either the unmodified Program or a work based" LF
." on the Program." LF
." " LF
."   To 'propagate' a work means to do anything with it that, without" LF
." permission, would make you directly or secondarily liable for" LF
." infringement under applicable copyright law, except executing it on a" LF
." computer or modifying a private copy.  Propagation includes copying," LF
." distribution (with or without modification), making available to the" LF
." public, and in some countries other activities as well." LF
." " LF
."   To 'convey' a work means any kind of propagation that enables other" LF
." parties to make or receive copies.  Mere interaction with a user through" LF
." a computer network, with no transfer of a copy, is not conveying." LF
." " LF
."   An interactive user interface displays 'Appropriate Legal Notices'" LF
." to the extent that it includes a convenient and prominently visible" LF
." feature that (1) displays an appropriate copyright notice, and (2)" LF
." tells the user that there is no warranty for the work (except to the" LF
." extent that warranties are provided), that licensees may convey the" LF
." work under this License, and how to view a copy of this License.  If" LF
." the interface presents a list of user commands or options, such as a" LF
." menu, a prominent item in the list meets this criterion." LF
." " LF
."   1. Source Code." LF
." " LF
."   The 'source code' for a work means the preferred form of the work" LF
." for making modifications to it.  'Object code' means any non-source" LF
." form of a work." LF
." " LF
."   A 'Standard Interface' means an interface that either is an official" LF
." standard defined by a recognized standards body, or, in the case of" LF
." interfaces specified for a particular programming language, one that" LF
." is widely used among developers working in that language." LF
." " LF
."   The 'System Libraries' of an executable work include anything, other" LF
." than the work as a whole, that (a) is included in the normal form of" LF
." packaging a Major Component, but which is not part of that Major" LF
." Component, and (b) serves only to enable use of the work with that" LF
." Major Component, or to implement a Standard Interface for which an" LF
." implementation is available to the public in source code form.  A" LF
." 'Major Component', in this context, means a major essential component" LF
." (kernel, window system, and so on) of the specific operating system" LF
." (if any) on which the executable work runs, or a compiler used to" LF
." produce the work, or an object code interpreter used to run it." LF
." " LF
."   The 'Corresponding Source' for a work in object code form means all" LF
." the source code needed to generate, install, and (for an executable" LF
." work) run the object code and to modify the work, including scripts to" LF
." control those activities.  However, it does not include the work's" LF
." System Libraries, or general-purpose tools or generally available free" LF
." programs which are used unmodified in performing those activities but" LF
." which are not part of the work.  For example, Corresponding Source" LF
." includes interface definition files associated with source files for" LF
." the work, and the source code for shared libraries and dynamically" LF
." linked subprograms that the work is specifically designed to require," LF
." such as by intimate data communication or control flow between those" LF
." subprograms and other parts of the work." LF
." " LF
."   The Corresponding Source need not include anything that users" LF
." can regenerate automatically from other parts of the Corresponding" LF
." Source." LF
." " LF
."   The Corresponding Source for a work in source code form is that" LF
." same work." LF
." " LF
."   2. Basic Permissions." LF
." " LF
."   All rights granted under this License are granted for the term of" LF
." copyright on the Program, and are irrevocable provided the stated" LF
." conditions are met.  This License explicitly affirms your unlimited" LF
." permission to run the unmodified Program.  The output from running a" LF
." covered work is covered by this License only if the output, given its" LF
." content, constitutes a covered work.  This License acknowledges your" LF
." rights of fair use or other equivalent, as provided by copyright law." LF
." " LF
."   You may make, run and propagate covered works that you do not" LF
." convey, without conditions so long as your license otherwise remains" LF
." in force.  You may convey covered works to others for the sole purpose" LF
." of having them make modifications exclusively for you, or provide you" LF
." with facilities for running those works, provided that you comply with" LF
." the terms of this License in conveying all material for which you do" LF
." not control copyright.  Those thus making or running the covered works" LF
." for you must do so exclusively on your behalf, under your direction" LF
." and control, on terms that prohibit them from making any copies of" LF
." your copyrighted material outside their relationship with you." LF
." " LF
."   Conveying under any other circumstances is permitted solely under" LF
." the conditions stated below.  Sublicensing is not allowed; section 10" LF
." makes it unnecessary." LF
." " LF
."   3. Protecting Users' Legal Rights From Anti-Circumvention Law." LF
." " LF
."   No covered work shall be deemed part of an effective technological" LF
." measure under any applicable law fulfilling obligations under article" LF
." 11 of the WIPO copyright treaty adopted on 20 December 1996, or" LF
." similar laws prohibiting or restricting circumvention of such" LF
." measures." LF
." " LF
."   When you convey a covered work, you waive any legal power to forbid" LF
." circumvention of technological measures to the extent such circumvention" LF
." is effected by exercising rights under this License with respect to" LF
." the covered work, and you disclaim any intention to limit operation or" LF
." modification of the work as a means of enforcing, against the work's" LF
." users, your or third parties' legal rights to forbid circumvention of" LF
." technological measures." LF
." " LF
."   4. Conveying Verbatim Copies." LF
." " LF
."   You may convey verbatim copies of the Program's source code as you" LF
." receive it, in any medium, provided that you conspicuously and" LF
." appropriately publish on each copy an appropriate copyright notice;" LF
." keep intact all notices stating that this License and any" LF
." non-permissive terms added in accord with section 7 apply to the code;" LF
." keep intact all notices of the absence of any warranty; and give all" LF
." recipients a copy of this License along with the Program." LF
." " LF
."   You may charge any price or no price for each copy that you convey," LF
." and you may offer support or warranty protection for a fee." LF
." " LF
."   5. Conveying Modified Source Versions." LF
." " LF
."   You may convey a work based on the Program, or the modifications to" LF
." produce it from the Program, in the form of source code under the" LF
." terms of section 4, provided that you also meet all of these conditions:" LF
." " LF
."     a) The work must carry prominent notices stating that you modified" LF
."     it, and giving a relevant date." LF
." " LF
."     b) The work must carry prominent notices stating that it is" LF
."     released under this License and any conditions added under section" LF
."     7.  This requirement modifies the requirement in section 4 to" LF
."     'keep intact all notices'." LF
." " LF
."     c) You must license the entire work, as a whole, under this" LF
."     License to anyone who comes into possession of a copy.  This" LF
."     License will therefore apply, along with any applicable section 7" LF
."     additional terms, to the whole of the work, and all its parts," LF
."     regardless of how they are packaged.  This License gives no" LF
."     permission to license the work in any other way, but it does not" LF
."     invalidate such permission if you have separately received it." LF
." " LF
."     d) If the work has interactive user interfaces, each must display" LF
."     Appropriate Legal Notices; however, if the Program has interactive" LF
."     interfaces that do not display Appropriate Legal Notices, your" LF
."     work need not make them do so." LF
." " LF
."   A compilation of a covered work with other separate and independent" LF
." works, which are not by their nature extensions of the covered work," LF
." and which are not combined with it such as to form a larger program," LF
." in or on a volume of a storage or distribution medium, is called an" LF
." 'aggregate' if the compilation and its resulting copyright are not" LF
." used to limit the access or legal rights of the compilation's users" LF
." beyond what the individual works permit.  Inclusion of a covered work" LF
." in an aggregate does not cause this License to apply to the other" LF
." parts of the aggregate." LF
." " LF
."   6. Conveying Non-Source Forms." LF
." " LF
."   You may convey a covered work in object code form under the terms" LF
." of sections 4 and 5, provided that you also convey the" LF
." machine-readable Corresponding Source under the terms of this License," LF
." in one of these ways:" LF
." " LF
."     a) Convey the object code in, or embodied in, a physical product" LF
."     (including a physical distribution medium), accompanied by the" LF
."     Corresponding Source fixed on a durable physical medium" LF
."     customarily used for software interchange." LF
." " LF
."     b) Convey the object code in, or embodied in, a physical product" LF
."     (including a physical distribution medium), accompanied by a" LF
."     written offer, valid for at least three years and valid for as" LF
."     long as you offer spare parts or customer support for that product" LF
."     model, to give anyone who possesses the object code either (1) a" LF
."     copy of the Corresponding Source for all the software in the" LF
."     product that is covered by this License, on a durable physical" LF
."     medium customarily used for software interchange, for a price no" LF
."     more than your reasonable cost of physically performing this" LF
."     conveying of source, or (2) access to copy the" LF
."     Corresponding Source from a network server at no charge." LF
." " LF
."     c) Convey individual copies of the object code with a copy of the" LF
."     written offer to provide the Corresponding Source.  This" LF
."     alternative is allowed only occasionally and noncommercially, and" LF
."     only if you received the object code with such an offer, in accord" LF
."     with subsection 6b." LF
." " LF
."     d) Convey the object code by offering access from a designated" LF
."     place (gratis or for a charge), and offer equivalent access to the" LF
."     Corresponding Source in the same way through the same place at no" LF
."     further charge.  You need not require recipients to copy the" LF
."     Corresponding Source along with the object code.  If the place to" LF
."     copy the object code is a network server, the Corresponding Source" LF
."     may be on a different server (operated by you or a third party)" LF
."     that supports equivalent copying facilities, provided you maintain" LF
."     clear directions next to the object code saying where to find the" LF
."     Corresponding Source.  Regardless of what server hosts the" LF
."     Corresponding Source, you remain obligated to ensure that it is" LF
."     available for as long as needed to satisfy these requirements." LF
." " LF
."     e) Convey the object code using peer-to-peer transmission, provided" LF
."     you inform other peers where the object code and Corresponding" LF
."     Source of the work are being offered to the general public at no" LF
."     charge under subsection 6d." LF
." " LF
."   A separable portion of the object code, whose source code is excluded" LF
." from the Corresponding Source as a System Library, need not be" LF
." included in conveying the object code work." LF
." " LF
."   A 'User Product' is either (1) a 'consumer product', which means any" LF
." tangible personal property which is normally used for personal, family," LF
." or household purposes, or (2) anything designed or sold for incorporation" LF
." into a dwelling.  In determining whether a product is a consumer product," LF
." doubtful cases shall be resolved in favor of coverage.  For a particular" LF
." product received by a particular user, 'normally used' refers to a" LF
." typical or common use of that class of product, regardless of the status" LF
." of the particular user or of the way in which the particular user" LF
." actually uses, or expects or is expected to use, the product.  A product" LF
." is a consumer product regardless of whether the product has substantial" LF
." commercial, industrial or non-consumer uses, unless such uses represent" LF
." the only significant mode of use of the product." LF
." " LF
."   'Installation Information' for a User Product means any methods," LF
." procedures, authorization keys, or other information required to install" LF
." and execute modified versions of a covered work in that User Product from" LF
." a modified version of its Corresponding Source.  The information must" LF
." suffice to ensure that the continued functioning of the modified object" LF
." code is in no case prevented or interfered with solely because" LF
." modification has been made." LF
." " LF
."   If you convey an object code work under this section in, or with, or" LF
." specifically for use in, a User Product, and the conveying occurs as" LF
." part of a transaction in which the right of possession and use of the" LF
." User Product is transferred to the recipient in perpetuity or for a" LF
." fixed term (regardless of how the transaction is characterized), the" LF
." Corresponding Source conveyed under this section must be accompanied" LF
." by the Installation Information.  But this requirement does not apply" LF
." if neither you nor any third party retains the ability to install" LF
." modified object code on the User Product (for example, the work has" LF
." been installed in ROM)." LF
." " LF
."   The requirement to provide Installation Information does not include a" LF
." requirement to continue to provide support service, warranty, or updates" LF
." for a work that has been modified or installed by the recipient, or for" LF
." the User Product in which it has been modified or installed.  Access to a" LF
." network may be denied when the modification itself materially and" LF
." adversely affects the operation of the network or violates the rules and" LF
." protocols for communication across the network." LF
." " LF
."   Corresponding Source conveyed, and Installation Information provided," LF
." in accord with this section must be in a format that is publicly" LF
." documented (and with an implementation available to the public in" LF
." source code form), and must require no special password or key for" LF
." unpacking, reading or copying." LF
." " LF
."   7. Additional Terms." LF
." " LF
."   'Additional permissions' are terms that supplement the terms of this" LF
." License by making exceptions from one or more of its conditions." LF
." Additional permissions that are applicable to the entire Program shall" LF
." be treated as though they were included in this License, to the extent" LF
." that they are valid under applicable law.  If additional permissions" LF
." apply only to part of the Program, that part may be used separately" LF
." under those permissions, but the entire Program remains governed by" LF
." this License without regard to the additional permissions." LF
." " LF
."   When you convey a copy of a covered work, you may at your option" LF
." remove any additional permissions from that copy, or from any part of" LF
." it.  (Additional permissions may be written to require their own" LF
." removal in certain cases when you modify the work.)  You may place" LF
." additional permissions on material, added by you to a covered work," LF
." for which you have or can give appropriate copyright permission." LF
." " LF
."   Notwithstanding any other provision of this License, for material you" LF
." add to a covered work, you may (if authorized by the copyright holders of" LF
." that material) supplement the terms of this License with terms:" LF
." " LF
."     a) Disclaiming warranty or limiting liability differently from the" LF
."     terms of sections 15 and 16 of this License; or" LF
." " LF
."     b) Requiring preservation of specified reasonable legal notices or" LF
."     author attributions in that material or in the Appropriate Legal" LF
."     Notices displayed by works containing it; or" LF
." " LF
."     c) Prohibiting misrepresentation of the origin of that material, or" LF
."     requiring that modified versions of such material be marked in" LF
."     reasonable ways as different from the original version; or" LF
." " LF
."     d) Limiting the use for publicity purposes of names of licensors or" LF
."     authors of the material; or" LF
." " LF
."     e) Declining to grant rights under trademark law for use of some" LF
."     trade names, trademarks, or service marks; or" LF
." " LF
."     f) Requiring indemnification of licensors and authors of that" LF
."     material by anyone who conveys the material (or modified versions of" LF
."     it) with contractual assumptions of liability to the recipient, for" LF
."     any liability that these contractual assumptions directly impose on" LF
."     those licensors and authors." LF
." " LF
."   All other non-permissive additional terms are considered 'further" LF
." restrictions' within the meaning of section 10.  If the Program as you" LF
." received it, or any part of it, contains a notice stating that it is" LF
." governed by this License along with a term that is a further" LF
." restriction, you may remove that term.  If a license document contains" LF
." a further restriction but permits relicensing or conveying under this" LF
." License, you may add to a covered work material governed by the terms" LF
." of that license document, provided that the further restriction does" LF
." not survive such relicensing or conveying." LF
." " LF
."   If you add terms to a covered work in accord with this section, you" LF
." must place, in the relevant source files, a statement of the" LF
." additional terms that apply to those files, or a notice indicating" LF
." where to find the applicable terms." LF
." " LF
."   Additional terms, permissive or non-permissive, may be stated in the" LF
." form of a separately written license, or stated as exceptions;" LF
." the above requirements apply either way." LF
." " LF
."   8. Termination." LF
." " LF
."   You may not propagate or modify a covered work except as expressly" LF
." provided under this License.  Any attempt otherwise to propagate or" LF
." modify it is void, and will automatically terminate your rights under" LF
." this License (including any patent licenses granted under the third" LF
." paragraph of section 11)." LF
." " LF
."   However, if you cease all violation of this License, then your" LF
." license from a particular copyright holder is reinstated (a)" LF
." provisionally, unless and until the copyright holder explicitly and" LF
." finally terminates your license, and (b) permanently, if the copyright" LF
." holder fails to notify you of the violation by some reasonable means" LF
." prior to 60 days after the cessation." LF
." " LF
."   Moreover, your license from a particular copyright holder is" LF
." reinstated permanently if the copyright holder notifies you of the" LF
." violation by some reasonable means, this is the first time you have" LF
." received notice of violation of this License (for any work) from that" LF
." copyright holder, and you cure the violation prior to 30 days after" LF
." your receipt of the notice." LF
." " LF
."   Termination of your rights under this section does not terminate the" LF
." licenses of parties who have received copies or rights from you under" LF
." this License.  If your rights have been terminated and not permanently" LF
." reinstated, you do not qualify to receive new licenses for the same" LF
." material under section 10." LF
." " LF
."   9. Acceptance Not Required for Having Copies." LF
." " LF
."   You are not required to accept this License in order to receive or" LF
." run a copy of the Program.  Ancillary propagation of a covered work" LF
." occurring solely as a consequence of using peer-to-peer transmission" LF
." to receive a copy likewise does not require acceptance.  However," LF
." nothing other than this License grants you permission to propagate or" LF
." modify any covered work.  These actions infringe copyright if you do" LF
." not accept this License.  Therefore, by modifying or propagating a" LF
." covered work, you indicate your acceptance of this License to do so." LF
." " LF
."   10. Automatic Licensing of Downstream Recipients." LF
." " LF
."   Each time you convey a covered work, the recipient automatically" LF
." receives a license from the original licensors, to run, modify and" LF
." propagate that work, subject to this License.  You are not responsible" LF
." for enforcing compliance by third parties with this License." LF
." " LF
."   An 'entity transaction' is a transaction transferring control of an" LF
." organization, or substantially all assets of one, or subdividing an" LF
." organization, or merging organizations.  If propagation of a covered" LF
." work results from an entity transaction, each party to that" LF
." transaction who receives a copy of the work also receives whatever" LF
." licenses to the work the party's predecessor in interest had or could" LF
." give under the previous paragraph, plus a right to possession of the" LF
." Corresponding Source of the work from the predecessor in interest, if" LF
." the predecessor has it or can get it with reasonable efforts." LF
." " LF
."   You may not impose any further restrictions on the exercise of the" LF
." rights granted or affirmed under this License.  For example, you may" LF
." not impose a license fee, royalty, or other charge for exercise of" LF
." rights granted under this License, and you may not initiate litigation" LF
." (including a cross-claim or counterclaim in a lawsuit) alleging that" LF
." any patent claim is infringed by making, using, selling, offering for" LF
." sale, or importing the Program or any portion of it." LF
." " LF
."   11. Patents." LF
." " LF
."   A 'contributor' is a copyright holder who authorizes use under this" LF
." License of the Program or a work on which the Program is based.  The" LF
." work thus licensed is called the contributor's 'contributor version'." LF
." " LF
."   A contributor's 'essential patent claims' are all patent claims" LF
." owned or controlled by the contributor, whether already acquired or" LF
." hereafter acquired, that would be infringed by some manner, permitted" LF
." by this License, of making, using, or selling its contributor version," LF
." but do not include claims that would be infringed only as a" LF
." consequence of further modification of the contributor version.  For" LF
." purposes of this definition, 'control' includes the right to grant" LF
." patent sublicenses in a manner consistent with the requirements of" LF
." this License." LF
." " LF
."   Each contributor grants you a non-exclusive, worldwide, royalty-free" LF
." patent license under the contributor's essential patent claims, to" LF
." make, use, sell, offer for sale, import and otherwise run, modify and" LF
." propagate the contents of its contributor version." LF
." " LF
."   In the following three paragraphs, a 'patent license' is any express" LF
." agreement or commitment, however denominated, not to enforce a patent" LF
." (such as an express permission to practice a patent or covenant not to" LF
." sue for patent infringement).  To 'grant' such a patent license to a" LF
." party means to make such an agreement or commitment not to enforce a" LF
." patent against the party." LF
." " LF
."   If you convey a covered work, knowingly relying on a patent license," LF
." and the Corresponding Source of the work is not available for anyone" LF
." to copy, free of charge and under the terms of this License, through a" LF
." publicly available network server or other readily accessible means," LF
." then you must either (1) cause the Corresponding Source to be so" LF
." available, or (2) arrange to deprive yourself of the benefit of the" LF
." patent license for this particular work, or (3) arrange, in a manner" LF
." consistent with the requirements of this License, to extend the patent" LF
." license to downstream recipients.  'Knowingly relying' means you have" LF
." actual knowledge that, but for the patent license, your conveying the" LF
." covered work in a country, or your recipient's use of the covered work" LF
." in a country, would infringe one or more identifiable patents in that" LF
." country that you have reason to believe are valid." LF
." " LF
."   If, pursuant to or in connection with a single transaction or" LF
." arrangement, you convey, or propagate by procuring conveyance of, a" LF
." covered work, and grant a patent license to some of the parties" LF
." receiving the covered work authorizing them to use, propagate, modify" LF
." or convey a specific copy of the covered work, then the patent license" LF
." you grant is automatically extended to all recipients of the covered" LF
." work and works based on it." LF
." " LF
."   A patent license is 'discriminatory' if it does not include within" LF
." the scope of its coverage, prohibits the exercise of, or is" LF
." conditioned on the non-exercise of one or more of the rights that are" LF
." specifically granted under this License.  You may not convey a covered" LF
." work if you are a party to an arrangement with a third party that is" LF
." in the business of distributing software, under which you make payment" LF
." to the third party based on the extent of your activity of conveying" LF
." the work, and under which the third party grants, to any of the" LF
." parties who would receive the covered work from you, a discriminatory" LF
." patent license (a) in connection with copies of the covered work" LF
." conveyed by you (or copies made from those copies), or (b) primarily" LF
." for and in connection with specific products or compilations that" LF
." contain the covered work, unless you entered into that arrangement," LF
." or that patent license was granted, prior to 28 March 2007." LF
." " LF
."   Nothing in this License shall be construed as excluding or limiting" LF
." any implied license or other defenses to infringement that may" LF
." otherwise be available to you under applicable patent law." LF
." " LF
."   12. No Surrender of Others' Freedom." LF
." " LF
."   If conditions are imposed on you (whether by court order, agreement or" LF
." otherwise) that contradict the conditions of this License, they do not" LF
." excuse you from the conditions of this License.  If you cannot convey a" LF
." covered work so as to satisfy simultaneously your obligations under this" LF
." License and any other pertinent obligations, then as a consequence you may" LF
." not convey it at all.  For example, if you agree to terms that obligate you" LF
." to collect a royalty for further conveying from those to whom you convey" LF
." the Program, the only way you could satisfy both those terms and this" LF
." License would be to refrain entirely from conveying the Program." LF
." " LF
."   13. Use with the GNU Affero General Public License." LF
." " LF
."   Notwithstanding any other provision of this License, you have" LF
." permission to link or combine any covered work with a work licensed" LF
." under version 3 of the GNU Affero General Public License into a single" LF
." combined work, and to convey the resulting work.  The terms of this" LF
." License will continue to apply to the part which is the covered work," LF
." but the special requirements of the GNU Affero General Public License," LF
." section 13, concerning interaction through a network will apply to the" LF
." combination as such." LF
." " LF
."   14. Revised Versions of this License." LF
." " LF
."   The Free Software Foundation may publish revised and/or new versions of" LF
." the GNU General Public License from time to time.  Such new versions will" LF
." be similar in spirit to the present version, but may differ in detail to" LF
." address new problems or concerns." LF
." " LF
."   Each version is given a distinguishing version number.  If the" LF
." Program specifies that a certain numbered version of the GNU General" LF
." Public License 'or any later version' applies to it, you have the" LF
." option of following the terms and conditions either of that numbered" LF
." version or of any later version published by the Free Software" LF
." Foundation.  If the Program does not specify a version number of the" LF
." GNU General Public License, you may choose any version ever published" LF
." by the Free Software Foundation." LF
." " LF
."   If the Program specifies that a proxy can decide which future" LF
." versions of the GNU General Public License can be used, that proxy's" LF
." public statement of acceptance of a version permanently authorizes you" LF
." to choose that version for the Program." LF
." " LF
."   Later license versions may give you additional or different" LF
." permissions.  However, no additional obligations are imposed on any" LF
." author or copyright holder as a result of your choosing to follow a" LF
." later version." LF
." " LF
;

\ output word list in ascending order (requires recursion)
\ ( defptr -- )
: WORDSR
    UNHIDE
    DUP <>0 IF
        ( defptr )
        \ get pointer to previous definition and call recursively
        DUP @ WORDSR
        ( defptr )
        8 +
        ( namefld )
        DUP C@ 31 AND
        ( namefld length )
        SWAP 1+ SWAP
        TYPE 32 EMIT
    ELSE
        DROP
    THEN
;

\ output word list in ascending order (requires recursion)
: WORDS
    >LATEST @
    ( defptr )
    WORDSR
    10 EMIT
;

\ output integer content of address
( addr -- )
: ? @ . ;

\ output unsigned integer content of address
( addr -- )
: U? @ U. ;

\ output floating-point content of address
( addr -- )
: F? @ F. ;

\ duplicate n if it is non-zero
( n -- n [n] )
: ?DUP DUP IF DUP THEN ;

\ output ANSI control sequence introducer
: CSI
    27 EMIT ." ["
    \ clear argument counter
    0 CSAC !
;

\ add control sequence argument
( n -- )
: CSA
    \ store argument only if it is non-zero
    \ and if argument count < 8
    CSAC DUP @ 8 <
    ( n csac bool )
    3 PICK <>0 AND IF
        ( n csac )
        SWAP
        ( csac n )
        \ store argument in array
        OVER @ CELLS CSAA + !
        ( csac )
        \ increment argument counter
        INCR
        ( )
    ELSE
        ( n csac )
        2DROP
    THEN
;

\ emit control sequence arguments
: EMITCSAA
    CSAC @ DUP IF
        ( cnt )
        \ count is non-zero
        0
        \ index is 0
        ( cnt inx )
        \ clear DOT buffer
        0 DOT C!
        BEGIN
            ( cnt inx )
            DUP CELLS CSAA + @
            ( cnt inx val )
            \ output value into DOT buffer
            U>DOT
            ( cnt inx )
            \ increment index
            1+
            \ check if limit has been reached
            2DUP SWAP
            ( cnt inx inx cnt )
            <
        WHILE
            ( cnt inx )
            \ yes, there's more, output semicolon into DOT buffer
            59 >DOT
            \ continue
        REPEAT
        ( cnt inx )
        2DROP
        \ print DOT buffer
        PRINTDOT
    ELSE
        ( cnt )
        DROP
    THEN
;

\ output set graphic rendition ANSI sequence
: SGR
    EMITCSAA
    ." m"
;

\ convert index to foreground color code
( n -- n )
: FGCOL
    15 AND
    DUP 8 < IF
        ( n )
        30 +
    ELSE
        ( n )
        8 -
        90 +
    THEN
;

\ convert index to background color code
( n -- n )
: BGCOL
    15 AND
    DUP 8 < IF
        ( n )
        40 +
    ELSE
        ( n )
        8 -
        100 +
    THEN
;

\ convert index to 256 color index
( n -- n )
: COL256
    255 AND
;

\ set foreground color only
\ NOTE that whether a color is honored is device-dependent
( n -- )
: PEN
    CSI
    FGCOL
    CSA
    SGR
;

\ set foreground color only (256 colors)
\ NOTE that whether a color is honored is device-dependent
( n -- )
: PEN256
    CSI
    38 CSA 5 CSA
    COL256 CSA
    SGR
;

\ set background color only
\ NOTE that whether a color is honored is device-dependent
( n -- )
: PAPER
    CSI
    BGCOL
    CSA
    SGR
;

\ set background color only (256 colors)
\ NOTE that whether a color is honored is device-dependent
( n -- )
: PAPER256
    CSI
    48 CSA 5 CSA
    COL256 CSA
    SGR
;

\ set video mode only
( n -- )
: MODE
    CSI
    10 MOD
    CSA
    SGR
;

\ shorthands
: REGULAR 0 MODE ;
: BOLD 1 MODE ;
: FAINT 2 MODE ;
: ITALIC 3 MODE ;
: UNDERLINE 4 MODE ;
: SLOWBLINK 5 MODE ;
: RAPIDBLINK 6 MODE ;
: REVERSE 7 MODE ;
: CONCEALED 8 MODE ;
: CROSSEDOUT 9 MODE ;

\ clear video mode only
( n -- )
: MODEOFF
    CSI
    10 MOD 20 +
    CSA
    SGR
;

\ shorthands
\ NOTE: BOLDOFF acts as DOUBLEUNDERLINE on some terminals
: BOLDOFF 1 MODEOFF ;
: DOUBLEUNDERLINE 1 MODEOFF ;
: FAINTOFF 2 MODEOFF ;
: ITALICOFF 3 MODEOFF ;
: UNDERLINEOFF 4 MODEOFF ;
: BLINKOFF 5 MODEOFF ;
: REVERSEOFF 7 MODEOFF ;
: CROSSEDOUTOFF 9 MODEOFF ;
: CONCEALEDOFF 8 MODEOFF ;

\ color shorthands
\ color names are merely suggestions and depend on the terminal emulator
0 CONSTANT BLACK
1 CONSTANT RED
2 CONSTANT GREEN
3 CONSTANT YELLOW
4 CONSTANT BLUE
5 CONSTANT MAGENTA
6 CONSTANT CYAN
7 CONSTANT WHITE
8 CONSTANT GRAY
9 CONSTANT BRIGHTRED
10 CONSTANT BRIGHTGREEN
11 CONSTANT BRIGHTYELLOW
12 CONSTANT BRIGHTBLUE
13 CONSTANT BRIGHTMAGENTA
14 CONSTANT BRIGHTCYAN
15 CONSTANT BRIGHTWHITE

\ shortcut for PAPER PEN
\ NOTE that whether a color is honored is device-dependent
( paper pen -- )
: COLOR
    CSI
    FGCOL CSA
    BGCOL CSA
    SGR
;

\ shortcut for PAPER256 PEN256
\ NOTE that whether a color is honored is device-dependent
( paper pen -- )
: COLOR256
    PEN256
    PAPER256
;

\ set an entry in the screen attribute table
\ NOTE that whether a color is honored is device-dependent
( index mode foreground background -- )
: ATTRDEF
    ( index mode foreground background )
    ROT
    ( index foreground background mode )
    10 UMOD 256 * ROT
    ( index background mode foreground )
    15 AND 16 * ROT
    ( index mode foreground background )
    15 AND
    \ combine into attribute
    + +
    ( index attr )
    SWAP
    ( attr index )
    63 AND
    CELLS ATTRARY + !
;

\ set an entry in the screen attribute table (256 colors)
\ NOTE that whether a color is honored is device-dependent
( index mode foreground background -- )
: ATTRDEF256
    ( index mode foreground background )
    ROT
    ( index foreground background mode )
    10 UMOD 65536 * ROT
    ( index background mode foreground )
    255 AND 256 * ROT
    ( index mode foreground background )
    255 AND
    \ combine into attribute
    + +
    ( index attr )
    SWAP
    ( attr index )
    63 AND
    CELLS ATTRARY + !
;

\ recall an entry from the screen attribute table
\ NOTE that whether a color is honored is device-dependent
( n -- )
: ATTR
    63 AND CELLS ATTRARY + @
    CSI
    ( attr )
    DUP 256 / 10 UMOD CSA
    ( attr )
    DUP 16 / FGCOL CSA
    ( attr )
    BGCOL CSA
    ( )
    SGR
;

\ recall an entry from the screen attribute table (256 colors)
\ NOTE that whether a color is honored is device-dependent
( n -- )
: ATTR256
    63 AND CELLS ATTRARY + @
    ( attr )
    DUP 65536 / 10 UMOD MODE
    ( attr )
    DUP 256 / PEN256
    ( attr )
    PAPER256
    ( )
;

\ home cursor
( y x -- )
: HOME
    CSI
    SWAP CSA CSA
    EMITCSAA
    ." H"
;

\ alias LOCATE (same as HOME)
( y x -- )
: LOCATE HOME ;

\ junk: clear part or all of screen
( mode -- )
: JUNK
    CSI
    CSA
    EMITCSAA
    ." J"
;

\ shorthand
: CLS 1 1 HOME 2 JUNK ;

\ kill: clear part or all of line
( mode -- )
: KILL
    CSI
    CSA
    EMITCSAA
    ." K"
;

\ scroll: >0 up, <0 down
( n -- )
: SCROLL
    DUP >=0 IF
        ( n )
        CSI CSA EMITCSAA ." S"
    ELSE
        ( n )
        CSI NEG CSA EMITCSAA ." T"
    THEN
;

\ dump init text line
: DUMPINITL
    0
    ( inx )
    \ length will be 87 bytes
    87 STRBUF C!
    \ 87th byte will be LF
    10 STRBUF 87 + C!
    \ start loop
    BEGIN
        ( inx )
        \ store blank
        32 OVER STRBUF 1+ + C!
        ( inx )
        \ loop until line is full
        1+ DUP 86 >=
    UNTIL
    ( inx )
    DROP
;

\ set address field in dump line
( addr -- )
: DUMPADDR
    16
    ( addr inx )
    BEGIN
        SWAP
        ( inx addr )
        \ divide current address by 16
        16 U/MOD
        ( inx result remainder )
        \ convert remainder to character
        DIG2CHR
        ( inx result char )
        \ store character in line buffer
        3 PICK STRBUF + C!
        ( inx result )
        SWAP
        ( addr inx )
        1- DUP 1 <
    UNTIL
    ( addr inx )
    2DROP
;

\ dump hex byte
( addr inx -- )
: DUMPHEXB
    ( addr inx )
    15 AND
    \ compute buffer position
    DUP 8 < IF
        \ 19 + inx * 3
        DUP 3 * 19 +
        ( addr inx pos )
    ELSE
        \ 44 + ( inx - 8 ) * 3
        DUP 8 - 3 * 44 +
        ( addr inx pos )
    THEN
    ( addr inx pos )
    -3 ROLL
    ( pos addr inx )
    \ get data byte
    + C@
    ( pos byte )
    \ divide by 16
    16 U/MOD
    ( pos result remainder )
    DIG2CHR
    ( pos result char )
    \ store at pos + 1
    3 PICK 1+ STRBUF + C!
    ( pos result )
    DIG2CHR
    \ store at pos
    SWAP STRBUF + C!
    ( )
;

\ dump ascii byte
( addr inx -- )
: DUMPASCB
    ( addr inx )
    15 AND
    \ compute buffer position
    DUP 8 < IF
        \ 69 + inx
        DUP 69 +
        ( addr inx pos )
    ELSE
        \ 78 + ( inx - 8 )
        DUP 8 - 78 +
        ( addr inx pos )
    THEN
    ( addr inx pos )
    -3 ROLL
    ( pos addr inx )
    \ get data byte
    + C@
    ( pos byte )
    \ check if in printable range
    DUP 32 U>=
    ( pos byte bool )
    OVER 127 U<
    ( pos byte bool bool )
    AND UNLESS
        ( pos byte )
        \ if not, generate dot (46)
        DROP 46
    THEN
    ( pos byte )
    \ store at position
    SWAP STRBUF + C!
    ( )
;

\ dump byte as hex and ascii
( addr inx -- )
: DUMPBYTE
    2DUP DUMPHEXB DUMPASCB
;

\ dump bytes as hex and ascii
\ len will be limited to 16
( addr len -- )
: DUMPBYTES
    2 PICK 0
    ( addr len addr inx )
    BEGIN
        2DUP DUMPBYTE
        ( addr len addr inx )
        1+ DUP 4 PICK >=
        ( addr len addr inx bool )
        OVER 16 >=
        ( addr len addr inx bool bool )
        OR
    UNTIL
    ( addr len addr inx )
    2DROP 2DROP
;

\ display hex dump of memory area
\ format:
\ 0000000000111111111122222222223333333333444444444455555555556666
\ 0123456789012345678901234567890123456789012345678901234567890123
\  6666667777777777888888
\  4567890123456789012345
\  AAAAAAAAAAAAAAAA  DD DD DD DD DD DD DD DD  DD DD DD DD DD DD DD
\   DD  ........ ........
( addr len -- )
: DUMP
    BEGIN
        \ prepare line buffer
        ( addr len )
        DUMPINITL
        ( addr len )
        OVER DUMPADDR
        ( addr len )
        2DUP DUMPBYTES
        \ print line
        STRBUF COUNT TYPE
        \ advance to next line
        ( addr len )
        16 - SWAP 16 + SWAP
        ( addr len )
        DUP <=0
    UNTIL
    2DROP
;

: BANNER
    >INP @ SYSISATTY IF
        BOLD ." YULARK FORTH Engine" REGULAR LF
        ." Copyright © 2025  Ekkehard Morgenstern" LF
        ." This program comes with ABSOLUTELY NO WARRANTY; for details type 'SHOW_W'." LF
        ." This is free software, and you are welcome to redistribute it under certain conditions; type 'SHOW_C' for details." LF
    THEN
;

: FREEMSG
    >INP @ SYSISATTY IF
        BOLD 32 EMIT ?FREEDSP . ." bytes free in dictionary space." REGULAR LF
    THEN
;

\ store a regular expression character
( char -- )
: REC!
    SC!
;

( -- true )
: TRUE -1 ;

( -- false )
: FALSE 0 ;

\ handle a regular expression character
\ can be regular character or backslash escaped character
\ returns bool TRUE for continue and FALSE for stop
( char -- bool )
: RECHR
    DUP 92 = IF
        DROP
        INPGETCH
        ( char )
        \ if it's not EOF, store the 2-character sequence
        DUP -1 <> IF
            ( char )
            \ store backslash
            92 REC!
            ( char )
            \ store character
            REC!
            \ leave TRUE
            TRUE
        ELSE
            \ EOF, leave FALSE
            FALSE
        THEN
    ELSE
        \ not escape character: store if it's not EOF or slash
        ( char )
        DUP -1 <> OVER 47 <> AND IF
            ( char )
            \ store character
            REC!
            \ leave TRUE
            TRUE
        ELSE
            \ EOF or slash, leave FALSE
            FALSE
        THEN
    THEN
;

\ read a regular expression literal from the input, skipping
\ one leading space character
: RELIT
    \ clear the length counter in the string buffer
    0 STRBUF C!
    \ skip one space
    SKIP1SPC
    \ start loop
    BEGIN
        \ get a character
        INPGETCH
        ( char )
        \ handle it
        RECHR
        ( bool )
        \ will have TRUE for continue, FALSE for stop
        NOT
    UNTIL
;

BANNER
FREEMSG
OKAY
