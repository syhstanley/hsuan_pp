# HW2 TODO — Multi-thread Programming

## Part 0：用 Serial 寫 Monte Carlo 估算 π

目標：先用單執行緒的 Monte Carlo 方法估算 π，作為 Part 1 的基礎。

- [x] 在 `part1/` 實作 serial 版本的 Monte Carlo pi
  - 隨機投點到單位正方形，計算落在單位圓內的比例
  - 估算公式：`π ≈ 4 * (hits / total_tosses)`
  - [x] 確認結果準確到小數點後三位（至少 `1e8` 次投點）
  - 實測：`./pi.out 1 100000000` → `3.141763280000`

---

## Part 1：用 Pthreads 平行化 Monte Carlo 估算 π

目標：把 Part 0 的 serial 版本改成 Pthreads 平行程式，輸出 `pi.out`。

- [x] 在 `part1/pi.c`（或 `pi.cpp`）實作 `pi.out`
  - 主執行緒讀取參數：`./pi.out <num_threads> <total_tosses>`
  - [x] 用 `long long int` 儲存 hits 和 tosses（數量可能很大）
  - [x] 使用 thread-safe 的隨機數生成器（每 thread 獨立 seed）
  - [x] 每個 thread 各自跑一段 tosses，最後匯總結果
  - [x] 輸出 π 估算值，格式如 `3.1415926....`
  - [x] 通過 `make && ./pi.out 8 1000000000` 正確執行（實測：`3.141617604000`）
- [x] 效能優化（目標：`./pi.out 3 100000000; ./pi.out 4 100000000` 總時間 T ≤ 1.00s）
  - 使用較快的 per-thread RNG（xorshift32）
  - 避免 mutex（每 thread local hits，最後 join 後加總）
  - 實測：`t3=0.07s`、`t4=0.05s`，總時間 `0.12s <= 1.00s`

---

## Part 2：用 std::thread 平行化 Mandelbrot 碎形生成

目標：修改 `part2/mandelbrotThread.cpp`，用 `std::thread` 平行化 Mandelbrot 圖像生成。

> ⚠️ 只能修改 `mandelbrotThread.cpp`，不可動其他檔案

- [x] **Step 1**：實作 `workerThreadStart`，用空間分解（spatial decomposition）
  - thread 0 算上半張圖，thread 1 算下半張圖（2 thread 版本）
- [x] **Step 2**：擴展到 2、3、4 個 thread，按 block 分割圖像
  - 使用 interleaved row decomposition（`j = threadId; j < height; j += numThreads`）
  - **Q1**：View 1 speedup（實測）
    - 1 thread: `1.00x`
    - 2 threads: `1.99x`
    - 3 threads: `2.83x`
    - 4 threads: `2.67x`
    - 結論：不是完全線性。2→3 仍有明顯提升，但 4 threads 反而低於 3 threads，主因是負載不均、排程干擾與硬體資源競爭（記憶體/快取）。
- [x] **Step 3**：在 `workerThreadStart` 的頭尾加上 timing code
  - [x] 已輸出每個 thread 執行時間（`[thread i] xxx ms`）
  - **Q2**：3-thread 點位解釋
    - 3-thread 在部分 run 中可看到 thread time 不一致（例如約 73ms ~ 109ms 的波動），代表不同 row 的工作量與系統排程造成某些 thread 較慢。
    - 由於整體時間受最慢 thread 主導，因此 speedup 曲線不會完全線性。
- [x] **Step 4**：改進 work decomposition，讓 speedup 達到 3–4x（View 1 和 View 2 都要）
  - 不可 hardcode 各 thread count 的特定解
  - 不需要 thread 間同步 / 通訊
  - **Q3**：策略與 4-thread speedup
    - 策略：採用 cyclic/interleaved row decomposition，讓每個 thread 同時拿到輕/重 row，降低 Mandelbrot 負載不均影響；每 thread 直接寫不同 row，不需鎖。
    - 4-thread speedup（實測）：
      - View 1: `2.67x`
      - View 2: `2.83x`
- [x] **Q4**：用 8 threads 跑改進後的版本，效能比 4 threads 明顯提升嗎？為什麼？
  - （提示：workstation 有 4 cores / 4 threads）
  - View 1：8-thread `3.09x` vs 4-thread `2.67x`，有提升但不大。
  - View 2：8-thread `3.22x` vs 4-thread `2.83x`，有提升但非線性。
  - 原因：機器僅 4 cores/threads，8 threads 會過度訂閱 CPU，context switch 與資源競爭抵銷部分收益。
- [x] 效能目標：`./mandelbrot -t 3` + `./mandelbrot -t 4` 總時間 T ≤ 0.375s
  - View 1: `77.183ms + 81.918ms = 159.101ms`
  - View 2: `~48ms + 45.242ms < 0.375s`（以最小值計）

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
- [ ] 跑 `test_hw2` 確認通過（目前專案內未提供 `test_hw2` 腳本）
