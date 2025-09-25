#include <stdlib.h>
#include <stdio.h>

int main( int argc, char** argv ) {
    printf( "%u %u %u", (unsigned) sizeof(int), (unsigned) sizeof(long), 
        (unsigned) sizeof(long long) );
    return EXIT_SUCCESS;
}

