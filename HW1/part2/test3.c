#include "test.h"

double test3(double *a, int N) {
  ASSUME(N == 1024);
  a = (double *)__builtin_assume_aligned(a, 32);

  double b = 0;
  for (int i=0; i<I; i++) {
    for (int j=0; j<N; j++) {
      b += a[j];
    }
  }
  return b;
}
