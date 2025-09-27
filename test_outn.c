#include <stdlib.h>
#include <stdio.h>

static void printc( int c ) {
    fputc( c, stdout );
    fflush( stdout );
}

static void printu( unsigned val ) {
    if ( val >= 10U ) printu( val / 10U );
    printc( '0' + ( val % 10U ) );
}

static void printi( int val ) {
    if ( val < 0 ) { printc( '-' ); val = -val; }
    printu( val );
}

int main( int argc, char** argv ) {

    char buf[100]; buf[0] = '\0';
    fgets( buf, 100, stdin );
    int val = atoi(buf);
    printi( val );

    return 0;
}

