# HW2 Report — Multi-thread Programming

## 環境與執行方式

- 專案路徑：`/home/stanley/hsuan_pp/HW2`
- Part 1 編譯執行：
  - `cd part1`
  - `make`
  - `./pi.out <num_threads> <total_tosses>`
- Part 2 編譯執行：
  - `cd part2`
  - `make`
  - `./mandelbrot -t <num_threads> -v <view>`

---

## Part 0 / Part 1：Monte Carlo PI（Pthreads）

## 實作內容

- 檔案：`part1/pi.c`
- 參數格式：`./pi.out <num_threads> <total_tosses>`
- 使用 `long long int` 儲存 tosses/hits。
- 每個 thread 使用自己的 RNG state（xorshift32），避免共享狀態造成 race condition。
- 每個 thread 計算 local hits，主執行緒 `pthread_join` 後做加總，不使用 mutex，降低同步開銷。

核心做法：

```c
for (long long int i = 0; i < args->tosses; ++i) {
    double x = (double)xorshift32(&seed) / 4294967296.0;
    double y = (double)xorshift32(&seed) / 4294967296.0;
    double dist2 = x * x + y * y;
    if (dist2 <= 1.0) local_hits++;
}
```

## 正確性

- `./pi.out 1 100000000`  
  輸出：`3.141763280000`
- `./pi.out 8 1000000000`  
  輸出：`3.141617604000`

可達到小數點後三位正確度需求。

## 效能（Part 1 指標）

- 測試命令：
  - `/usr/bin/time -f "t3=%e" ./pi.out 3 100000000`
  - `/usr/bin/time -f "t4=%e" ./pi.out 4 100000000`
- 實測：
  - `t3 = 0.07s`
  - `t4 = 0.05s`
  - 總時間 `T = 0.12s <= 1.00s`（達標）

---

## Part 2：Mandelbrot（std::thread）

## 實作內容

- 檔案：`part2/mandelbrotThread.cpp`（僅修改此檔）
- 每個 thread 計算自己負責的 row。
- 採用 **interleaved row decomposition**：
  - thread `t` 計算 `j = t, t + numThreads, t + 2*numThreads, ...`
- 在 `workerThreadStart` 頭尾加入 timing（每個 thread 印出執行毫秒數）。

核心分工：

```cpp
for (int j = args->threadId; j < (int)args->height; j += args->numThreads) {
    float y = args->y0 + j * dy;
    int rowBase = j * args->width;
    for (int i = 0; i < (int)args->width; ++i) {
        float x = args->x0 + i * dx;
        args->output[rowBase + i] = mandel(x, y, args->maxIterations);
    }
}
```

---

## Q1：View 1 speedup vs thread 數量

View 1 (`-v 1`) 實測 speedup：

| Threads | Speedup |
|---:|---:|
| 1 | 1.00x |
| 2 | 1.99x |
| 3 | 2.83x |
| 4 | 2.67x |

觀察：
- 1->2 幾乎線性。
- 3 threads 提升明顯。
- 4 threads 未比 3 threads 更快，顯示非理想線性加速（受負載不均與系統資源競爭影響）。

---

## Q2：用每個 thread 時間解釋曲線形狀（特別是 3-thread）

從 per-thread timing 可見：
- 在 3-thread 測試中，不同 thread 的時間有落差（例如可見約 `73ms` 到 `109ms` 的區間）。
- Mandelbrot 各 row 計算量不均，某些 row 接近集合邊界，迭代次數高，導致某些 thread 負載較重。
- 整體執行時間由最慢 thread 決定，因此 speedup 曲線會偏離線性。

---

## Q3：平行化策略與 4-thread speedup

策略：
- 使用 interleaved/cyclic row decomposition，而非連續 block。
- 目的：讓每個 thread 同時分到輕重不一的 row，降低 load imbalance。
- 每個 thread 寫不同 row，無共享寫入衝突，不需要鎖。

4-thread speedup（實測）：
- View 1：`2.67x`
- View 2：`2.83x`

---

## Q4：8 threads 是否明顯優於 4 threads？

實測：
- View 1：4T `2.67x` -> 8T `3.09x`
- View 2：4T `2.83x` -> 8T `3.22x`

結論：
- 有提升，但不明顯，且遠非線性翻倍。
- 原因是機器僅 4 cores/4 threads，8 threads 會過度訂閱 CPU，造成 context switch 與資源競爭，抵銷部分平行收益。

---

## 效能目標檢查

目標：`./mandelbrot -t 3` + `./mandelbrot -t 4` 總時間 `T <= 0.375s`

- View 1 實測 thread 版本最小時間：
  - `-t 3`: `77.183 ms`
  - `-t 4`: `81.918 ms`
  - 合計：`159.101 ms = 0.159101s <= 0.375s`（達標）

---

## 總結

- Part 1（Pthreads Monte Carlo PI）完成且達標：
  - 正確性 OK（1e8 / 1e9 tosses）
  - 效能門檻明顯達標
- Part 2（std::thread Mandelbrot）完成：
  - 有正確 speedup 與完整 Q1~Q4 分析
  - Interleaved 分工改善負載平衡，但受硬體核心數限制，8 threads 提升有限
