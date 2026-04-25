#ifndef TEST_H
#define TEST_H

// Run for multiple experiments to reduce measurement error on gettime().
#define I 20000000

#if defined(__clang__)
#define ASSUME(cond) __builtin_assume(cond)
#elif defined(__GNUC__)
#define ASSUME(cond) do { if (!(cond)) __builtin_unreachable(); } while (0)
#else
#define ASSUME(cond) ((void)0)
#endif

#endif
