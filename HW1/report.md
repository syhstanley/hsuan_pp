# HW1 報告 — SIMD Programming

## 執行摘要

- 已成功編譯並執行 `part1`，完成 `VECTOR_WIDTH=2/4/8/16` 的實測。
- 已修正 `part2` 在此環境（gcc）無法編譯的問題，並成功產生 assembly。
- `part2` 的 AVX2 binary 在本機執行會觸發 `Illegal instruction`（CPU 不支援 AVX2 指令執行），因此 AVX2 只做 assembly 觀察，不做 runtime 測速。

---

## 1) 完成的程式碼（含實際修正）

### Part 1：`part1/vectorOP.cpp`

#### (a) `clampedExpVector`（已完成）

```cpp
for (int i = 0; i < N; i += VECTOR_WIDTH)
{
  int width = (N - i < VECTOR_WIDTH) ? (N - i) : VECTOR_WIDTH;
  maskAll = _pp_init_ones(width);

  _pp_vload_float(x, values + i, maskAll);
  _pp_vload_int(y, exponents + i, maskAll);
  _pp_vset_float(result, 1.f, maskAll);
  _pp_vmove_int(count, y, maskAll);

  _pp_vgt_int(maskCount, count, zeroInt, maskAll);
  while (_pp_cntbits(maskCount) > 0) {
    _pp_vmult_float(result, result, x, maskCount);
    _pp_vsub_int(count, count, oneInt, maskCount);
    _pp_vgt_int(maskCount, count, zeroInt, maskAll);
  }

  _pp_vgt_float(maskCount, result, clampValue, maskAll);
  _pp_vmove_float(result, clampValue, maskCount);
  _pp_vstore_float(output + i, result, maskAll);
}
```

#### (b) `arraySumVector`（bonus，已完成）

```cpp
for (int i = 0; i < N; i += VECTOR_WIDTH) {
  _pp_vload_float(x, values + i, maskAll);
  _pp_vadd_float(sum, sum, x, maskAll);
}

for (int width = VECTOR_WIDTH; width > 1; width >>= 1) {
  _pp_hadd_float(sum, sum);
  _pp_interleave_float(sum, sum);
}
```

### Part 2：為了可執行/可觀察而修正

#### (a) 修正 `Makefile` 的 compiler 與 flags（clang -> gcc 可用）

```make
CC ?= gcc

ifeq ($(VECTORIZE),1)
    CFLAGS += -ftree-vectorize -fopt-info-vec-optimized -fopt-info-vec-missed
else
    CFLAGS += -fno-tree-vectorize
endif
```

#### (b) 修正 `__builtin_assume` 相容性（gcc 不支援）

```c
// part2/test.h
#if defined(__clang__)
#define ASSUME(cond) __builtin_assume(cond)
#elif defined(__GNUC__)
#define ASSUME(cond) do { if (!(cond)) __builtin_unreachable(); } while (0)
#else
#define ASSUME(cond) ((void)0)
#endif
```

並把 `test1.c/test2.c/test3.c` 的：

```c
__builtin_assume(N == 1024);
```

改成：

```c
ASSUME(N == 1024);
```

#### (c) 保留 `restrict + assume_aligned` 與 branchless max

```c
void test2(float *__restrict a, float *__restrict b, float *__restrict c, int N)
{
  ASSUME(N == 1024);
  a = (float *)__builtin_assume_aligned(a, 32);
  b = (float *)__builtin_assume_aligned(b, 32);
  c = (float *)__builtin_assume_aligned(c, 32);
  c[j] = (b[j] > a[j]) ? b[j] : a[j];
}
```

#### (d) 修正 benchmark 被最佳化掉的問題（`part2/main.c`）

```c
volatile double sink = 0.0;
...
case 1:
  test1(values1, values2, output, N);
  for (int k = 0; k < N; k += 64) sink += output[k];
  break;
...
printf("sink=%f\n", sink);
```

---

## 2) 實測觀察

### Q1-1：`./myexp -s 10000`，`VECTOR_WIDTH = 2/4/8/16`

### 實測結果（ClampedExp utilization）

| VECTOR_WIDTH | Vector Utilization |
|---|---:|
| 2 | 87.9% |
| 4 | 82.7% |
| 8 | 80.0% |
| 16 | 78.8% |

### 趨勢與解釋

- 本次結果呈現明顯遞減：向量越寬，utilization 越低。
- 原因是 `clampedExp` 內部使用 mask-driven 迴圈；不同 lane 的 exponent 工作量不同，寬向量更容易出現 lane 間不平衡，造成 idle lanes。
- 另外 tail（不足一個完整向量）也會在寬向量下帶來額外浪費。

### 補充：ArraySum utilization

- W=2: 100.0%
- W=4: 100.0%
- W=8: 100.0%
- W=16: 99.9%

符合此題 reduction 型態高度規律、mask 浪費極低的預期。

---

## 3) Part 2 assembly 與效能觀察

### Q2-1：`vmovaps` / 對齊載入

- 在 `test2.vec.s` 可觀察到：
  - `movaps (%rcx,%rax), %xmm0`
  - `movaps %xmm0, (%rdx,%rax)`
- 並且搭配 `maxps`：
  - `maxps (%rdi,%rax), %xmm0`

代表 `__restrict + __builtin_assume_aligned` 讓編譯器採用對齊向量存取與向量 max 指令。

### Q2-2：no-vec / SSE / AVX2 測速

> 由於 `test1` 迴圈可被高度化簡，此處使用 `test3`（double reduction）觀察時間更有代表性。

| 模式 | 指令寬度 | `./test_auto_vectorize -t 3` 時間 | Speedup vs no-vec |
|---|---|---:|---:|
| no-vec (`make`) | scalar/no-tree-vectorize | 7.454926 sec | 1.00x |
| vectorize (`make VECTORIZE=1`) | SSE-like 128-bit | 7.454920 sec | 1.00x |
| AVX2 (`make VECTORIZE=1 AVX2=1`) | 256-bit | 無法執行（Illegal instruction） | N/A |

說明：
- 本機 CPU 無法執行 AVX2 binary，因此無法給 AVX2 runtime speedup。
- 但可透過 assembly 驗證 AVX2 生成（見下一節）。

### Q2-3：`test3` 在 `-ffast-math` 下的變化（`addsd -> vaddpd`）

- `VECTORIZE=1`（非 fast-math）時，在 `test3.vec.s` 看到 `addsd`（scalar double add）。
- `VECTORIZE=1 AVX2=1 FASTMATH=1 ASSEMBLE=1` 時，在 `test3.vec.avx2.fmath.s` 看到：
  - `vmovapd`
  - `vaddpd`

這說明 `-ffast-math` 放寬浮點嚴格語意後，編譯器更容易把 reduction 改寫成 packed vector 版本。

---

## 4) 本次實際執行指令

### Part 1

- `make clean && make`
- 依序改 `part1/def.h` 的 `VECTOR_WIDTH` 為 2/4/8/16
- 每次執行：`./myexp -s 10000`

### Part 2

- `make cleanall && make`
- `./test_auto_vectorize -t 3`
- `make cleanall && make VECTORIZE=1`
- `./test_auto_vectorize -t 3`
- `make cleanall && make VECTORIZE=1 ASSEMBLE=1`
- `make cleanall && make VECTORIZE=1 AVX2=1 FASTMATH=1 ASSEMBLE=1`


