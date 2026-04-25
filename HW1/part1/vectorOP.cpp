#include "PPintrin.h"

// implementation of absSerial(), but it is vectorized using PP intrinsics
void absVector(float *values, float *output, int N)
{
  __pp_vec_float x;
  __pp_vec_float result;
  __pp_vec_float zero = _pp_vset_float(0.f);
  __pp_mask maskAll, maskIsNegative, maskIsNotNegative;

  //  Note: Take a careful look at this loop indexing.  This example
  //  code is not guaranteed to work when (N % VECTOR_WIDTH) != 0.
  //  Why is that the case?
  for (int i = 0; i < N; i += VECTOR_WIDTH)
  {

    // All ones
    maskAll = _pp_init_ones();

    // All zeros
    maskIsNegative = _pp_init_ones(0);

    // Load vector of values from contiguous memory addresses
    _pp_vload_float(x, values + i, maskAll); // x = values[i];

    // Set mask according to predicate
    _pp_vlt_float(maskIsNegative, x, zero, maskAll); // if (x < 0) {

    // Execute instruction using mask ("if" clause)
    _pp_vsub_float(result, zero, x, maskIsNegative); //   output[i] = -x;

    // Inverse maskIsNegative to generate "else" mask
    maskIsNotNegative = _pp_mask_not(maskIsNegative); // } else {

    // Execute instruction ("else" clause)
    _pp_vload_float(result, values + i, maskIsNotNegative); //   output[i] = x; }

    // Write results back to memory
    _pp_vstore_float(output + i, result, maskAll);
  }
}

void clampedExpVector(float *values, int *exponents, float *output, int N)
{
  __pp_vec_float x;
  __pp_vec_float result;
  __pp_vec_float clampValue = _pp_vset_float(9.999999f);
  __pp_vec_int y;
  __pp_vec_int count;
  __pp_vec_int zeroInt = _pp_vset_int(0);
  __pp_vec_int oneInt = _pp_vset_int(1);
  __pp_mask maskAll, maskCount;

  for (int i = 0; i < N; i += VECTOR_WIDTH)
  {
    int width = (N - i < VECTOR_WIDTH) ? (N - i) : VECTOR_WIDTH;
    maskAll = _pp_init_ones(width);

    _pp_vload_float(x, values + i, maskAll);
    _pp_vload_int(y, exponents + i, maskAll);

    // result starts from 1.0f; lanes with exponent 0 stay 1.0f
    _pp_vset_float(result, 1.f, maskAll);
    _pp_vmove_int(count, y, maskAll);

    _pp_vgt_int(maskCount, count, zeroInt, maskAll);
    while (_pp_cntbits(maskCount) > 0)
    {
      _pp_vmult_float(result, result, x, maskCount);
      _pp_vsub_int(count, count, oneInt, maskCount);
      _pp_vgt_int(maskCount, count, zeroInt, maskAll);
    }

    _pp_vgt_float(maskCount, result, clampValue, maskAll);
    _pp_vmove_float(result, clampValue, maskCount);
    _pp_vstore_float(output + i, result, maskAll);
  }
}

// returns the sum of all elements in values
// You can assume N is a multiple of VECTOR_WIDTH
// You can assume VECTOR_WIDTH is a power of 2
float arraySumVector(float *values, int N)
{
  __pp_vec_float sum = _pp_vset_float(0.f);
  __pp_vec_float x;
  __pp_mask maskAll = _pp_init_ones();

  for (int i = 0; i < N; i += VECTOR_WIDTH)
  {
    _pp_vload_float(x, values + i, maskAll);
    _pp_vadd_float(sum, sum, x, maskAll);
  }

  // Tree-style horizontal reduction in O(log2(VECTOR_WIDTH)).
  for (int width = VECTOR_WIDTH; width > 1; width >>= 1)
  {
    _pp_hadd_float(sum, sum);
    _pp_interleave_float(sum, sum);
  }

  float result = 0.f;
  __pp_mask maskFirst = _pp_init_ones(1);
  _pp_vstore_float(&result, sum, maskFirst);
  return result;
}