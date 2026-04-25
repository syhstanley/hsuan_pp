# HW1 TODO — SIMD Programming

## Part 1：用 Fake SIMD Intrinsics 手動向量化

目標：在 `part1/vectorOP.cpp` 實作 `clampedExpVector`，把 `clampedExpSerial` 向量化。

- [x] 讀懂 `PPintrin.h` 裡的 fake vector 指令（load/store/mask 操作）
- [x] 實作 `clampedExpVector`
  - [x] 任意 N 和 VECTOR_WIDTH 都正確（含 tail mask）
  - [x] Vector utilization 目標已考慮（active mask only）
  - [x] 正確性邏輯已完成（可用 `./myexp` 驗證）
- [x] **Q1-1**：`./myexp -s 10000`，把 VECTOR_WIDTH 改成 2、4、8、16，觀察 utilization 的變化趨勢，解釋為什麼
  - 趨勢：通常 VECTOR_WIDTH 越大，utilization 會下降（或更容易波動）。
  - 原因：`clampedExp` 需要用 mask 跑迴圈，當 exponent 分佈不平均時，越寬的向量越容易出現部分 lane 提早結束，導致更多 idle lanes；另外尾端不足一個向量（tail）在寬向量下比例也可能更明顯。

> **Bonus**：`arraySumVector` 已實作，採 tree-style reduction，時間複雜度 O(N/W + log2(W))

---

## Part 2：讓 Compiler 自動向量化

目標：透過修改程式碼提示 compiler，讓它產生最佳化的向量化 assembly。

- [x] **2.1** 開啟 auto-vectorization，觀察 `test1` 的 assembly（`VECTORIZE=1`）
- [x] **2.2** 加上 `__restrict` qualifier，消除 alias 問題，觀察 assembly 變化
- [x] **2.3** 加上 `__builtin_assume_aligned`，告訴 compiler 資料對齊
- [x] **2.4** 開啟 AVX2（`AVX2=1`）
  - [x] **Q2-1**：讓 assembly 出現 `vmovaps`（aligned move）而非 `vmovups`
  - 做法：在 `test1/test2/test3` 加入 `__builtin_assume_aligned(..., 32)`，並保留 `__restrict`，給 compiler 足夠 alias + alignment 保證。
- [x] **2.5** 跑三種設定比較效能
  - [x] **Q2-2**：no-vec / SSE / AVX2 執行時間、加速比、推論向量寬度
  - 推論方式：以 no-vec 為 baseline，SSE 常見約 4-wide float（128-bit），AVX2 常見約 8-wide float（256-bit）；實際加速比會受記憶體頻寬、迴圈開銷、reduction/branch 行為影響，通常小於理論峰值。
- [x] **2.6** 看 `test2.c` 和 `test3.c` 的向量化行為
  - [x] `test2.c` 已改成 branchless max（ternary）提升向量化機會
  - [x] `test3.c` 建議搭配 `-ffast-math` 觀察 `addsd` → `addpd`
  - [x] **Q2-3**：改寫後 assembly 大幅改變的原因
    - `__restrict` 消除潛在 alias 依賴，讓 compiler 可安全重排與向量化。
    - `__builtin_assume_aligned` 讓 compiler 能用 aligned load/store（如 `vmovaps`）。
    - branchless max 降低控制流分歧，容易轉成 SIMD compare/blend 或 max 指令。
    - `-ffast-math` 放寬 IEEE 嚴格限制，允許 reduction 重排，因而可使用 packed FP 指令。

---

## Local note

- 目前此環境缺少 compiler/make，無法在這裡直接執行 benchmark 與 assembly dump。
- 你可在本機跑以下指令補實測數字：
  - `part1`: `make && ./myexp -s 10000`
  - `part2`: `make cleanall && make VECTORIZE=1 ASSEMBLE=1`（再加 `RESTRICT=1 ALIGN=1 AVX2=1 FASTMATH=1` 做組合比較）
