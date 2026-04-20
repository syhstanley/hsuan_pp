# HW1 教學：SIMD 程式設計

## 目錄
1. [為什麼需要 SIMD？](#1-為什麼需要-simd)
2. [SIMD 基本概念](#2-simd-基本概念)
3. [Intel SSE/AVX 指令集簡介](#3-intel-sseavx-指令集簡介)
4. [Vector Utilization 是什麼？](#4-vector-utilization-是什麼)
5. [Mask 操作](#5-mask-操作)
6. [如何手動向量化](#6-如何手動向量化)
7. [Compiler Auto-Vectorization](#7-compiler-auto-vectorization)
8. [如何用 Assembly 確認向量化](#8-如何用-assembly-確認向量化)
9. [常見陷阱與最佳化技巧](#9-常見陷阱與最佳化技巧)

---

## 1. 為什麼需要 SIMD？

現代 CPU 執行指令的方式，並不是單純「一個指令做一件事」這麼簡單。要榨出更多效能，我們需要了解兩個重要概念：

### Throughput vs Latency

| 概念 | 定義 | 範例 |
|------|------|------|
| **Latency（延遲）** | 一條指令從開始到完成需要幾個 cycle | 浮點乘法：4 cycles |
| **Throughput（吞吐量）** | 每個 cycle 可以「發射」幾條指令 | 若 throughput = 2，代表每 0.5 cycle 可以發一條 |

CPU 有 pipeline，可以同時處理多條指令的不同階段。即便一條乘法需要 4 cycles 才能完成，pipeline 可以在第 1 cycle 就開始下一條乘法，達到更高的吞吐量。

### 為什麼純靠 pipeline 還不夠？

假設你有一個陣列，要對每個元素做平方運算：

```c
for (int i = 0; i < 1000; i++) {
    a[i] = b[i] * b[i];
}
```

就算 pipeline 開很滿，每次還是一次只處理一個元素。如果 CPU 的浮點單元寬度是 256 bits，而一個 float 只有 32 bits，那豈不是浪費了 7/8 的硬體？

**SIMD（Single Instruction, Multiple Data）** 的想法就是：**一條指令同時對多個資料做相同運算**，充分利用 CPU 的寬暫存器。

```
純量運算：   [a0] * [a0] = [r0]        ← 一次處理 1 個
SIMD 運算：  [a0|a1|a2|a3|a4|a5|a6|a7] * 同樣的向量 → 一次處理 8 個
```

理論上 8 倍加速！（實際上受限於記憶體頻寬等因素，但加速效果仍然顯著）

---

## 2. SIMD 基本概念

### Vector Register（向量暫存器）

SIMD 使用特殊的「向量暫存器」，可以同時存放多個數值。你可以把它想成一個裝了多個值的盒子：

```
一個 256-bit 的向量暫存器，可以存：
  - 8 個 float（32-bit × 8 = 256-bit）
  - 4 個 double（64-bit × 4 = 256-bit）
  - 32 個 int8（8-bit × 32 = 256-bit）
```

### Lane（通道）

向量暫存器被切成多個「通道（lane）」，每個通道存一個值，各自獨立運算：

```
YMM0 = [ f0 | f1 | f2 | f3 | f4 | f5 | f6 | f7 ]
         ↑                                    ↑
       lane 0                              lane 7
```

SIMD 指令會對所有 lane **同時**做相同操作，這就是「Single Instruction」的意義。

### Width（寬度）

不同指令集支援不同的向量寬度：
- **SSE**: 128-bit（XMM 暫存器）
- **AVX/AVX2**: 256-bit（YMM 暫存器）
- **AVX-512**: 512-bit（ZMM 暫存器）

---

## 3. Intel SSE/AVX 指令集簡介

Intel 提供了一系列 SIMD 指令集，依照推出時間依序有更大的向量寬度：

| 指令集 | 年份 | 向量寬度 | 暫存器名稱 |
|--------|------|----------|------------|
| SSE    | 1999 | 128-bit  | XMM0~XMM15 |
| SSE2   | 2001 | 128-bit  | XMM0~XMM15 |
| AVX    | 2011 | 256-bit  | YMM0~YMM15 |
| AVX2   | 2013 | 256-bit  | YMM0~YMM15 |
| AVX-512| 2017 | 512-bit  | ZMM0~ZMM31 |

### Intrinsics 命名規則

Intel 提供 C/C++ 的 intrinsic 函式，讓你不用直接寫組語就能使用 SIMD：

```
_mm256_add_ps(a, b)
  ↑     ↑   ↑↑
  |     |   ||── 資料型別：ps = packed single (float), pd = packed double, epi32 = int32...
  |     |   |─── 操作名稱：add, mul, sub, load, store...
  |     └───── 向量寬度：256 = 256-bit
  └─────────── Intel intrinsic 前綴
```

常用的資料型別後綴：
- `ps`：packed single-precision float（float）
- `pd`：packed double-precision float（double）
- `epi32`：packed 32-bit integers
- `epi8`：packed 8-bit integers

### 常用 intrinsics 範例

```c
#include <immintrin.h>  // 引入 AVX 標頭

// 載入 8 個 float 到 YMM 暫存器
__m256 a = _mm256_load_ps(ptr);       // 需要 32-byte 對齊
__m256 b = _mm256_loadu_ps(ptr);      // 不需要對齊（較慢）

// 算術運算
__m256 c = _mm256_add_ps(a, b);       // 8 個 float 同時相加
__m256 d = _mm256_mul_ps(a, b);       // 8 個 float 同時相乘

// 儲存
_mm256_store_ps(ptr, c);              // 需要 32-byte 對齊
_mm256_storeu_ps(ptr, c);             // 不需要對齊

// 比較（回傳 mask）
__m256 mask = _mm256_cmp_ps(a, b, _CMP_GT_OS);  // a > b？
```

---

## 4. Vector Utilization 是什麼？

**Vector Utilization（向量使用率）** 衡量你的 SIMD 運算有多「充實」。

假設你用 AVX2 的 8-wide float 向量，但在某些 lane 上做的是「無效的」或「被 mask 掉的」運算，那麼你的 utilization 就低於 100%。

### 範例：計算 clampedExp

```
result[i] = pow(x[i], y[i]) 但限制在某個最大值
如果 y[i] == 0，結果直接是 1.0
```

在 8 個元素中，假設只有 3 個 `y[i] != 0`，那 5 個 lane 做的計算就是「浪費的」（最終會被 mask 掉），vector utilization 只有 3/8 ≈ 37.5%。

### 為什麼重要？

- 在 HW1 的 Part1 中，你需要計算並回報 vector utilization
- 低 utilization 代表你的資料分佈不適合 SIMD，或者你的 mask 邏輯效率不好
- 優化目標：讓更多 lane 在同一時間做有用的工作

---

## 5. Mask 操作

SIMD 中的「條件執行」不像 scalar 程式可以用 `if-else`。所有 lane 必須同時執行，所以我們用 **mask（遮罩）** 來控制哪些 lane 的結果要被保留。

### 概念

```
lane:     [0] [1] [2] [3] [4] [5] [6] [7]
x:        [1] [2] [3] [4] [5] [6] [7] [8]
y:        [0] [2] [0] [3] [0] [1] [0] [4]
mask(y!=0):[F] [T] [F] [T] [F] [T] [F] [T]  ← F=0x00000000, T=0xFFFFFFFF
result:   [1] [?] [1] [?] [1] [?] [1] [?]   ← mask=F 用 1.0，mask=T 用計算值
```

### 在 Fake SIMD Intrinsics 中

HW1 使用的是一套「假的」SIMD intrinsics，模擬真實行為但方便 debug。以下是 mask 操作的典型模式：

```c
// 產生 mask：哪些位置的 y > 0？
__cs149_mask maskGtZero = _cs149_cmp_gt(y, _cs149_vset_float(0.0f));

// 對 mask 為 true 的 lane 做計算
__cs149_vec_float result;
_cs149_vset_float(result, 1.0f);  // 先全部設為 1.0

// 只對 maskGtZero 為 true 的 lane 執行 pow
_cs149_vlog_float(result, x, maskGtZero);         // log(x)，只在有效 lane
_cs149_vmul_float(result, y, result, maskGtZero); // y * log(x)
_cs149_vexp_float(result, result, maskGtZero);    // exp(y*log(x)) = x^y
```

### 在真實 AVX2 中

```c
__m256 mask = _mm256_cmp_ps(y, _mm256_setzero_ps(), _CMP_GT_OS);

// 用 blendv 選擇：mask=1 用 computed，mask=0 用 default（1.0f）
__m256 one = _mm256_set1_ps(1.0f);
__m256 computed = /* ... 計算 pow(x, y) ... */;
__m256 result = _mm256_blendv_ps(one, computed, mask);
```

---

## 6. 如何手動向量化

以 HW1 的 `clampedExp` 為例，說明如何從純量版本改寫成 SIMD 版本。

### 原始純量版本

```c
void clampedExp(float* values, int* exponents, float* output, int N) {
    for (int i = 0; i < N; i++) {
        float x = values[i];
        int y = exponents[i];
        if (y == 0) {
            output[i] = 1.0f;
        } else {
            float result = powf(x, y);
            output[i] = (result > 9.999999f) ? 9.999999f : result;
        }
    }
}
```

### 向量化步驟

**Step 1：確定向量寬度**

使用 8-wide float（AVX2，256-bit）：

```c
const int VECTOR_WIDTH = 8;
```

**Step 2：處理主迴圈（以 VECTOR_WIDTH 為步進）**

```c
void clampedExpVector(float* values, int* exponents, float* output, int N) {
    // 主迴圈：每次處理 VECTOR_WIDTH 個元素
    int i = 0;
    for (; i + VECTOR_WIDTH <= N; i += VECTOR_WIDTH) {
        __cs149_vec_float x = _cs149_vload_float(values + i);
        __cs149_vec_int   y = _cs149_vload_int(exponents + i);

        // 找出 y == 0 的 lane
        __cs149_mask maskYIsZero = _cs149_cmp_eq(y, _cs149_vset_int(0));
        __cs149_mask maskYNotZero = _cs149_mask_not(maskYIsZero);

        // 初始化結果為 1.0
        __cs149_vec_float result = _cs149_vset_float(1.0f);

        // 對 y != 0 的 lane 計算 x^y（用連乘）
        // ... 依照 HW spec 實作

        // Clamp：超過 9.999999 的截斷
        __cs149_vec_float clampVal = _cs149_vset_float(9.999999f);
        __cs149_mask maskExceed = _cs149_cmp_gt(result, clampVal);
        _cs149_vset_float(result, 9.999999f, maskExceed);

        _cs149_vstore_float(output + i, result);
    }

    // 處理剩餘元素（tail）
    for (; i < N; i++) {
        // 純量處理
    }
}
```

**Step 3：處理 tail**

當 N 不是 VECTOR_WIDTH 的倍數，剩餘的元素用純量或 partial mask 處理。

---

## 7. Compiler Auto-Vectorization

手動向量化費時費力，現代 compiler（GCC、Clang）可以自動幫你向量化。但 compiler 很保守，遇到「不確定是否安全」的情況就不向量化了。

### 為什麼 Compiler 有時候不向量化？

**原因 1：Pointer Aliasing（指標別名問題）**

```c
void add(float* a, float* b, float* c, int N) {
    for (int i = 0; i < N; i++) {
        c[i] = a[i] + b[i];
    }
}
```

Compiler 不確定 `a`、`b`、`c` 是否指向同一塊記憶體。如果 `c == a`，那每次迴圈都會修改到下一次的輸入，這時候向量化就會產生錯誤結果。

**解法：使用 `__restrict` 關鍵字**

```c
void add(float* __restrict a, float* __restrict b, float* __restrict c, int N) {
    for (int i = 0; i < N; i++) {
        c[i] = a[i] + b[i];  // 現在 compiler 知道指標不重疊，可以向量化！
    }
}
```

`__restrict` 是對 compiler 的承諾：「這個指標指向的記憶體不會被其他指標修改。」

**原因 2：記憶體對齊不確定**

```c
void process(float* data, int N) {
    for (int i = 0; i < N; i++) {
        data[i] *= 2.0f;
    }
}
```

`_mm256_load_ps` 要求 32-byte 對齊，否則會 crash。Compiler 若不確定 `data` 是否對齊，可能改用較慢的 `vmovups`（unaligned load）。

**解法：使用 `__builtin_assume_aligned`**

```c
void process(float* data, int N) {
    float* aligned_data = (float*) __builtin_assume_aligned(data, 32);
    for (int i = 0; i < N; i++) {
        aligned_data[i] *= 2.0f;  // compiler 知道對齊，可以用 vmovaps
    }
}
```

**原因 3：浮點數精度要求**

浮點數運算順序不同，結果可能略有差異。Compiler 預設遵守嚴格的 IEEE 754，因此不會任意改變計算順序，這限制了某些向量化機會。

**解法：加上 `-ffast-math` 編譯選項**

```bash
gcc -O2 -ffast-math -mavx2 -o program program.c
```

`-ffast-math` 允許 compiler 重排浮點運算，可能違反嚴格 IEEE 754，但通常在工程應用中結果差異可接受。

> **注意**：`-ffast-math` 會讓 `NaN` 和 `Inf` 的行為變得不可預測，在需要嚴格浮點精度的場合（如金融計算）不應使用。

### 告訴 Compiler 要向量化

使用 pragmas 強制 vectorization：

```c
#pragma GCC ivdep           // 告訴 GCC 忽略 dependency（我保證沒有 aliasing）
for (int i = 0; i < N; i++) {
    c[i] = a[i] + b[i];
}

// Clang 版本
#pragma clang loop vectorize(enable)
for (int i = 0; i < N; i++) {
    // ...
}
```

### 完整範例：觸發 Auto-Vectorization

```c
// 加上這些 hint 讓 compiler 成功向量化
void dotProduct(float* __restrict a, float* __restrict b, float* result, int N) {
    a = (float*) __builtin_assume_aligned(a, 32);
    b = (float*) __builtin_assume_aligned(b, 32);

    float sum = 0.0f;
    for (int i = 0; i < N; i++) {
        sum += a[i] * b[i];
    }
    *result = sum;
}
```

編譯命令：
```bash
gcc -O2 -mavx2 -ffast-math -fopt-info-vec-optimized dotProduct.c
```

`-fopt-info-vec-optimized` 會印出哪些迴圈成功向量化。

---

## 8. 如何用 Assembly 確認向量化

光看 compiler 說「向量化了」還不夠，最可靠的方法是直接看 assembly（組語）。

### 產生 Assembly

```bash
gcc -O2 -mavx2 -S -o output.s program.c
# 或者用 objdump
objdump -d -S program > output.asm
```

或者線上工具：**Compiler Explorer**（https://godbolt.org/）非常好用，可以即時看到編譯結果。

### 關鍵指令識別

| 指令 | 意義 | 是否向量化 |
|------|------|------------|
| `vmovaps` | **Aligned** Packed Single 移動（256-bit） | 是，且資料對齊 |
| `vmovups` | **Unaligned** Packed Single 移動（256-bit） | 是，但資料未對齊 |
| `vaddps`  | Packed Single Add（8 個 float 同時加） | 是 |
| `vmulps`  | Packed Single Multiply（8 個 float 同時乘） | 是 |
| `movss`   | Move Scalar Single（一次只動 1 個 float） | 否，純量 |
| `addss`   | Add Scalar Single | 否，純量 |
| `mulss`   | Multiply Scalar Single | 否，純量 |

### 範例解讀

**未向量化的 assembly：**
```asm
.L3:
    movss   xmm0, DWORD PTR [rsi+rax*4]   ; 載入 1 個 float
    mulss   xmm0, DWORD PTR [rdi+rax*4]   ; 乘以 1 個 float
    addss   xmm1, xmm0                     ; 累加
    inc     rax
    cmp     rax, rdx
    jl      .L3
```

**向量化後的 assembly：**
```asm
.L3:
    vmovaps ymm1, YMMWORD PTR [rsi+rax*4]  ; 載入 8 個 float（對齊）
    vmulps  ymm1, ymm1, YMMWORD PTR [rdi+rax*4]  ; 8 個 float 同時乘
    vaddps  ymm0, ymm0, ymm1               ; 8 個 float 同時加
    add     rax, 8                          ; 步進 8
    cmp     rax, rcx
    jl      .L3
```

看到 `ymm` 暫存器和 `vaddps`/`vmulps` 等指令，就代表成功向量化了！

---

## 9. 常見陷阱與最佳化技巧

### 陷阱 1：記憶體對齊問題

```c
// 危險：可能沒有對齊
float* data = (float*) malloc(N * sizeof(float));

// 安全：指定 32-byte 對齊（AVX2 需要）
float* data = (float*) aligned_alloc(32, N * sizeof(float));

// 或者用 posix_memalign
posix_memalign((void**)&data, 32, N * sizeof(float));
```

### 陷阱 2：Tail 處理

當 N 不是 VECTOR_WIDTH 的倍數，要特別處理剩餘元素：

```c
int i = 0;
// 主迴圈：向量化部分
for (; i + 8 <= N; i += 8) {
    // SIMD 處理
}
// Tail：純量處理剩餘
for (; i < N; i++) {
    // 純量處理
}
```

### 陷阱 3：不必要的型別轉換

在 SIMD 中頻繁轉換 int↔float 會很慢：

```c
// 慢：每次迴圈都做 int→float 轉換
for (int i = 0; i < N; i++) {
    output[i] = (float)exponent[i] * value[i];
}

// 快：先轉換整個陣列，或在向量化時用 _mm256_cvtepi32_ps 一次轉 8 個
```

### 最佳化技巧

1. **資料 layout 要 SIMD-friendly**：
   - Structure of Arrays (SoA) 通常比 Array of Structures (AoS) 更適合 SIMD
   
   ```c
   // AoS（不適合 SIMD）：
   struct Point { float x, y, z; };
   Point points[N];
   
   // SoA（適合 SIMD）：
   float xs[N], ys[N], zs[N];
   ```

2. **迴圈展開（Loop Unrolling）**：
   讓每次迭代做更多工作，減少迴圈控制開銷。Compiler 通常會自動做，也可以手動或用 `#pragma GCC unroll 4`。

3. **Prefetch**：
   提前告訴 CPU 要讀哪些記憶體，讓 cache miss 的代價被隱藏：
   
   ```c
   __builtin_prefetch(&data[i + 64], 0, 0);  // 預載 64 個 float 之後的資料
   ```

4. **Profile 驅動優化**：
   - 先用 `perf stat` 或 `vtune` 確認瓶頸在哪裡
   - 不要盲目最佳化，先量測再改

### 總結

| 技術 | 效果 | 難度 |
|------|------|------|
| 手動 SIMD intrinsics | 最大控制力，效能最好 | 高 |
| `__restrict` + `__builtin_assume_aligned` | 幫 compiler 消除疑慮 | 低 |
| `-ffast-math` | 允許更激進的浮點最佳化 | 低（但要注意副作用） |
| 資料 layout 重排（SoA） | 讓 SIMD 存取更連續 | 中 |

SIMD 是現代高效能運算的基礎工具。雖然手動寫 intrinsics 麻煩，但理解 SIMD 的概念能幫助你寫出「更 compiler-friendly」的程式碼，讓 auto-vectorization 自然發揮效果。
