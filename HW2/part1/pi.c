#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

// TODO: Implement parallel Monte Carlo PI estimation using Pthreads
// Usage: ./pi.out <num_threads> <total_tosses>
// Output: estimated PI value (accurate to 3 decimal places with >= 1e8 tosses)

int main(int argc, char* argv[]) {
    if (argc != 3) {
        printf("Usage: %s <num_threads> <total_tosses>\n", argv[0]);
        return 1;
    }

    // TODO: implement

    return 0;
}
