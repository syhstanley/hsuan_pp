#include "test.h"

void test2(float *__restrict a, float *__restrict b, float *__restrict c, int N)
{
  ASSUME(N == 1024);
  a = (float *)__builtin_assume_aligned(a, 32);
  b = (float *)__builtin_assume_aligned(b, 32);
  c = (float *)__builtin_assume_aligned(c, 32);

  for (int i = 0; i < I; i++)
  {
    for (int j = 0; j < N; j++)
    {
      // Branchless max form is easier for compiler vectorization.
      c[j] = (b[j] > a[j]) ? b[j] : a[j];
    }
  }
}
