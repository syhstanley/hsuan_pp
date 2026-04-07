# HW1 TODO — SIMD Programming

## Part 1：用 Fake SIMD Intrinsics 手動向量化

目標：在 `part1/vectorOP.cpp` 實作 `clampedExpVector`，把 `clampedExpSerial` 向量化。

- [ ] 讀懂 `PPintrin.h` 裡的 fake vector 指令（load/store/mask 操作）
- [ ] 實作 `clampedExpVector`
  - 任意 N 和 VECTOR_WIDTH 都要正確
  - Vector utilization 要 > 60%
  - 通過 `./myexp` 的正確性驗證
- [ ] **Q1-1**：執行 `./myexp -s 10000`，把 VECTOR_WIDTH 改成 2、4、8、16，觀察 utilization 的變化趨勢，解釋為什麼

> **Bonus**：實作 `arraySumVector`，utilization > 80%，時間複雜度 O(N/W + log2(W))

---

## Part 2：讓 Compiler 自動向量化

目標：透過修改程式碼提示 compiler，讓它產生最佳化的向量化 assembly。

- [ ] **2.1** 開啟 auto-vectorization，觀察 `test1` 的 assembly（`VECTORIZE=1`）
- [ ] **2.2** 加上 `__restrict` qualifier，消除 alias 問題，觀察 assembly 變化
- [ ] **2.3** 加上 `__builtin_assume_aligned`，告訴 compiler 資料對齊
- [ ] **2.4** 開啟 AVX2（`AVX2=1`）
  - **Q2-1**：修改程式讓 assembly 出現 `vmovaps`（aligned move）而非 `vmovups`
- [ ] **2.5** 跑三種設定比較效能
  - **Q2-2**：記錄 no-vec / SSE / AVX2 的執行時間，計算加速比，推論 vector register 位元寬度
- [ ] **2.6** 看 `test2.cpp` 和 `test3.cpp` 的向量化行為
  - 對 `test2` 套用 patch（`patch -i ./test2.cpp.patch`），觀察前後 assembly 差異
  - 對 `test3` 加上 `-ffast-math`，觀察 `addsd` → `addpd` 的變化
  - **Q2-3**：解釋為什麼改寫後 compiler 產生完全不同的 assembly
