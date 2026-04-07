# HW2 TODO — Multi-thread Programming

## Part 0：用 Serial 寫 Monte Carlo 估算 π

目標：先用單執行緒的 Monte Carlo 方法估算 π，作為 Part 1 的基礎。

- [ ] 在 `part1/` 實作 serial 版本的 Monte Carlo pi
  - 隨機投點到單位正方形，計算落在單位圓內的比例
  - 估算公式：`π ≈ 4 * (hits / total_tosses)`
  - 確認結果準確到小數點後三位（至少 `1e8` 次投點）

---

## Part 1：用 Pthreads 平行化 Monte Carlo 估算 π

目標：把 Part 0 的 serial 版本改成 Pthreads 平行程式，輸出 `pi.out`。

- [ ] 在 `part1/pi.c`（或 `pi.cpp`）實作 `pi.out`
  - 主執行緒讀取參數：`./pi.out <num_threads> <total_tosses>`
  - 用 `long long int` 儲存 hits 和 tosses（數量可能很大）
  - 使用 thread-safe 的隨機數生成器（如 `rand_r`）
  - 每個 thread 各自跑一段 tosses，最後匯總結果
  - 輸出 π 估算值，格式如 `3.1415926....`
  - 通過 `make && ./pi.out 8 1000000000` 正確執行
- [ ] 效能優化（目標：`./pi.out 3 100000000; ./pi.out 4 100000000` 總時間 T ≤ 1.00s）
  - 可考慮 SIMD intrinsics 或更快的亂數生成器
  - 避免 false sharing / mutex contention

---

## Part 2：用 std::thread 平行化 Mandelbrot 碎形生成

目標：修改 `part2/mandelbrotThread.cpp`，用 `std::thread` 平行化 Mandelbrot 圖像生成。

> ⚠️ 只能修改 `mandelbrotThread.cpp`，不可動其他檔案

- [ ] **Step 1**：實作 `workerThreadStart`，用空間分解（spatial decomposition）
  - thread 0 算上半張圖，thread 1 算下半張圖（2 thread 版本）
- [ ] **Step 2**：擴展到 2、3、4 個 thread，按 block 分割圖像
  - **Q1**：畫出 View 1 的 speedup vs. thread 數量折線圖，解釋是否為線性加速？為什麼？
- [ ] **Step 3**：在 `workerThreadStart` 的頭尾加上 timing code
  - **Q2**：用每個 thread 的執行時間解釋 speedup 圖的形狀（特別是 3-thread 的數據點）
- [ ] **Step 4**：改進 work decomposition，讓 speedup 達到 3–4x（View 1 和 View 2 都要）
  - 不可 hardcode 各 thread count 的特定解
  - 不需要 thread 間同步 / 通訊
  - **Q3**：說明你的 parallelization 策略，回報 4-thread speedup
- [ ] **Q4**：用 8 threads 跑改進後的版本，效能比 4 threads 明顯提升嗎？為什麼？
  - （提示：workstation 有 4 cores / 4 threads）
- [ ] 效能目標：`./mandelbrot -t 3` + `./mandelbrot -t 4` 總時間 T ≤ 0.375s

---

## 繳交

- [ ] 整理成 `HW2_xxxxxxx.zip`，目錄結構：
  ```
  part1/
    Makefile
    pi.c (或 pi.cpp)
  part2/
    mandelbrotThread.cpp
  url.txt   ← HackMD 報告連結
  ```
- [ ] HackMD 報告開啟「知道連結就可以編輯」權限
- [ ] 跑 `test_hw2` 確認通過
