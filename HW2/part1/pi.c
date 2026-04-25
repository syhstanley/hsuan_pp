#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdint.h>

typedef struct {
    int thread_id;
    long long int tosses;
    long long int hits;
} ThreadArgs;

static inline uint32_t xorshift32(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

static void *worker(void *arg) {
    ThreadArgs *args = (ThreadArgs *)arg;
    long long int local_hits = 0;

    // Use per-thread seed; avoid zero state for xorshift.
    uint32_t seed = (uint32_t)(0x9e3779b9u ^ (args->thread_id * 0x85ebca6bu));
    if (seed == 0) seed = 1u;

    for (long long int i = 0; i < args->tosses; ++i) {
        // Convert random int to [0,1).
        double x = (double)xorshift32(&seed) / 4294967296.0;
        double y = (double)xorshift32(&seed) / 4294967296.0;
        double dist2 = x * x + y * y;
        if (dist2 <= 1.0) {
            local_hits++;
        }
    }

    args->hits = local_hits;
    return NULL;
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        printf("Usage: %s <num_threads> <total_tosses>\n", argv[0]);
        return 1;
    }

    int num_threads = atoi(argv[1]);
    long long int total_tosses = atoll(argv[2]);
    if (num_threads <= 0 || total_tosses <= 0) {
        fprintf(stderr, "Error: num_threads and total_tosses must be positive.\n");
        return 1;
    }

    pthread_t *threads = (pthread_t *)malloc((size_t)num_threads * sizeof(pthread_t));
    ThreadArgs *args = (ThreadArgs *)malloc((size_t)num_threads * sizeof(ThreadArgs));
    if (!threads || !args) {
        fprintf(stderr, "Error: allocation failed.\n");
        free(threads);
        free(args);
        return 1;
    }

    long long int base = total_tosses / num_threads;
    long long int rem = total_tosses % num_threads;
    for (int t = 0; t < num_threads; ++t) {
        args[t].thread_id = t;
        args[t].tosses = base + (t < rem ? 1 : 0);
        args[t].hits = 0;
        pthread_create(&threads[t], NULL, worker, &args[t]);
    }

    long long int total_hits = 0;
    for (int t = 0; t < num_threads; ++t) {
        pthread_join(threads[t], NULL);
        total_hits += args[t].hits;
    }

    double pi = 4.0 * (double)total_hits / (double)total_tosses;
    printf("%.12f\n", pi);

    free(threads);
    free(args);

    return 0;
}
