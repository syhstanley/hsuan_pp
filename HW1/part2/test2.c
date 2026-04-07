#include "test.h"

void test2(float *a, float *b, float *c, int N)
{
  __builtin_assume(N == 1024);

  for (int i = 0; i < I; i++)
  {
    for (int j = 0; j < N; j++)
    {
      /* max() */
      if (b[j] > a[j]) c[j] = b[j];
      else c[j] = a[j];
    }
  }
}
