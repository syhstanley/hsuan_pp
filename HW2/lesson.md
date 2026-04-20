# HW2 教學：多執行緒程式設計

## 目錄
1. [為什麼需要多執行緒？](#1-為什麼需要多執行緒)
2. [Process vs Thread](#2-process-vs-thread)
3. [Pthreads 基礎](#3-pthreads-基礎)
4. [False Sharing](#4-false-sharing)
5. [std::thread 基礎（C++11）](#5-stdthread-基礎c11)
6. [Work Decomposition 策略](#6-work-decomposition-策略)
7. [Speedup 與 Amdahl's Law](#7-speedup-與-amdahls-law)
8. [Mandelbrot 平行化：為什麼有 Load Imbalance？](#8-mandelbrot-平行化為什麼有-load-imbalance)

---

## 1. 為什麼需要多執行緒？

現代 CPU 幾乎都有多個「核心（Core）」。一個四核 CPU 同時最多可以執行 4 段程式碼。如果你的程式只用單一執行緒，就只用了 1/4 的硬體。

### 多核時代的挑戰

過去 CPU 越做越快，靠的是提高時脈（clock frequency）。大約在 2004 年之後，因為散熱和功耗的限制，時脈提升遇到了瓶頸。製造商改為在同一顆晶片上放更多核心：

```
2005：雙核 → 2010：四核 → 2020：十六核（消費級）→ 2024：二十四核+
```

這代表**軟體要靠多執行緒才能真正利用硬體**。

### 適合平行化的問題

不是所有問題都能平行化，最適合的是：
- 大量獨立計算（Monte Carlo 模擬、圖像處理）
- 資料可以分割、各自計算後再合併（Map-Reduce 模式）

---

## 2. Process vs Thread

| 特性 | Process（行程） | Thread（執行緒） |
|------|-----------------|-----------------|
| 記憶體空間 | 各自獨立 | 共享同一個 Process 的記憶體 |
| 建立開銷 | 大（fork、複製 page table） | 小 |
| 通訊方式 | IPC（pipe、socket、共享記憶體） | 直接讀寫共享變數 |
| 安全性 | 高（崩潰不影響其他 process） | 低（一個 thread 崩潰可能影響全部） |
| 適用場景 | 多個獨立服務 | 平行計算同一任務 |

### 視覺化

```
Process A                    Process B
┌─────────────────────┐     ┌─────────────────────┐
│ Code                │     │ Code                │
│ Stack (thread 1)    │     │ Stack               │
│ Stack (thread 2)    │     │                     │
│ Stack (thread 3)    │     │                     │
│ Heap (共享)         │     │ Heap (獨立)         │
│ Globals (共享)      │     │ Globals (獨立)      │
└─────────────────────┘     └─────────────────────┘
```

同一個 Process 內的 threads 共享 heap 和 global variables，這讓通訊很方便，但也引入了同步問題。

---

## 3. Pthreads 基礎

POSIX Threads（pthreads）是 Linux/Unix 系統的標準多執行緒 API，用 C 語言撰寫。

### 建立和等待執行緒

```c
#include <pthread.h>

// Thread function 的型別必須是：void* func(void* arg)
void* threadFunc(void* arg) {
    int id = *(int*)arg;
    printf("Hello from thread %d\n", id);
    return NULL;
}

int main() {
    pthread_t threads[4];
    int ids[4] = {0, 1, 2, 3};

    // 建立 4 個 thread
    for (int i = 0; i < 4; i++) {
        pthread_create(&threads[i], NULL, threadFunc, &ids[i]);
        //             ↑ handle   ↑ attr  ↑ func     ↑ arg
    }

    // 等待所有 thread 完成
    for (int i = 0; i < 4; i++) {
        pthread_join(threads[i], NULL);
        //           ↑ handle   ↑ return value（可以是 NULL 表示不關心）
    }

    printf("All threads done!\n");
    return 0;
}
```

編譯時要加上 `-lpthread`：
```bash
gcc -O2 -lpthread -o program program.c
```

### 傳遞多個參數給 Thread

`pthread_create` 的 arg 只有一個，要傳多個參數，可以包成 struct：

```c
typedef struct {
    int thread_id;
    int num_threads;
    double* data;
    int N;
    double result;   // 用來回傳結果
} ThreadArgs;

void* worker(void* arg) {
    ThreadArgs* args = (ThreadArgs*) arg;
    int id = args->thread_id;
    int n  = args->num_threads;

    // 計算這個 thread 負責的範圍
    int start = id * (args->N / n);
    int end   = (id == n-1) ? args->N : start + args->N / n;

    double local_sum = 0.0;
    for (int i = start; i < end; i++) {
        local_sum += args->data[i];
    }
    args->result = local_sum;
    return NULL;
}
```

### Race Condition（競態條件）

當多個 thread 同時存取並修改同一個變數，而且結果取決於「誰先執行」，就叫做 race condition。這是多執行緒 bug 的最大來源。

```c
// 危險！Race condition
int counter = 0;

void* increment(void* arg) {
    for (int i = 0; i < 100000; i++) {
        counter++;  // 這不是原子操作！
    }
    return NULL;
}
```

`counter++` 在機器層面是三個步驟：
1. 讀取 counter 的值到暫存器
2. 暫存器的值 +1
3. 把暫存器的值寫回 counter

兩個 thread 可能同時讀到相同的值，各自 +1，然後都寫回同樣的值，結果 counter 只加了 1 而不是 2。最終結果是不可預測的。

### Mutex：保護共享資源

**Mutex（互斥鎖）** 確保同一時間只有一個 thread 可以進入「臨界區（critical section）」：

```c
#include <pthread.h>

int counter = 0;
pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

void* increment(void* arg) {
    for (int i = 0; i < 100000; i++) {
        pthread_mutex_lock(&lock);    // 上鎖，若已鎖住則等待
        counter++;                     // 臨界區（Critical Section）
        pthread_mutex_unlock(&lock);  // 解鎖
    }
    return NULL;
}
```

使用 mutex 要注意：
- **Lock 和 Unlock 必須配對**，否則會死鎖（deadlock）
- **臨界區要盡量短**，避免其他 thread 等太久
- mutex 本身有開銷，高頻率鎖定/解鎖會嚴重降低效能

### thread-safe 亂數：`rand_r`

標準的 `rand()` 是 **not thread-safe**！它使用全域的 seed 狀態，多個 thread 同時呼叫會造成 race condition（或給出錯誤結果）。

```c
// 危險：多個 thread 共用全域 seed
int r = rand();

// 安全：每個 thread 有自己的 seed
unsigned int seed = thread_id * 1234 + 5678;  // 每個 thread 用不同 seed
int r = rand_r(&seed);
```

`rand_r` 把 seed 存在呼叫者提供的記憶體裡，所以每個 thread 有獨立的 seed，不會互相干擾。

### Pthreads Monte Carlo π 範例

Monte Carlo 方法估算 π：在 1×1 的正方形內隨機撒點，落在四分之一圓內的比例 ≈ π/4。

```c
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define NUM_THREADS 4
#define TOTAL_POINTS 10000000

typedef struct {
    int thread_id;
    long num_points;
    long count_in_circle;
} ThreadArgs;

void* monteCarlo(void* arg) {
    ThreadArgs* args = (ThreadArgs*) arg;
    unsigned int seed = args->thread_id * 12345 + 67890;
    long count = 0;

    for (long i = 0; i < args->num_points; i++) {
        double x = (double)rand_r(&seed) / RAND_MAX;
        double y = (double)rand_r(&seed) / RAND_MAX;
        if (x*x + y*y <= 1.0) {
            count++;
        }
    }
    args->count_in_circle = count;
    return NULL;
}

int main() {
    pthread_t threads[NUM_THREADS];
    ThreadArgs args[NUM_THREADS];

    for (int i = 0; i < NUM_THREADS; i++) {
        args[i].thread_id = i;
        args[i].num_points = TOTAL_POINTS / NUM_THREADS;
        args[i].count_in_circle = 0;
        pthread_create(&threads[i], NULL, monteCarlo, &args[i]);
    }

    long total_in_circle = 0;
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
        total_in_circle += args[i].count_in_circle;
    }

    double pi = 4.0 * total_in_circle / TOTAL_POINTS;
    printf("π ≈ %f\n", pi);
    return 0;
}
```

注意：每個 thread 把結果存在各自的 `args[i].count_in_circle`，最後 main thread 加總，**不需要 mutex**，因為沒有共享寫入。

---

## 4. False Sharing

False sharing 是多執行緒效能的隱形殺手，理解它非常重要。

### Cache Line 基礎

CPU 不是一個 byte 一個 byte 存取記憶體的，而是以「Cache Line」為單位（通常是 64 bytes）。當你讀一個變數，整個 64 bytes 都會載入 cache。

```
記憶體：[  a[0]  |  a[1]  |  a[2]  |  a[3]  | ... ]
                 ←── 64 bytes（一個 cache line）───→
```

### False Sharing 的問題

```c
// 假設 4 個 thread 各自更新自己的 result
double results[4];  // 這 4 個 double 共 32 bytes，可能在同一個 cache line！

// Thread 0 更新 results[0]
// Thread 1 更新 results[1]
// ...
```

當 Thread 0 寫入 `results[0]`，整個 cache line 被標記為「dirty」，其他核心的 cache 就失效了。即便 Thread 1 只是要存取 `results[1]`（完全不同的資料），它的 cache 也失效，必須重新從記憶體或其他核心取得，這叫做 **False Sharing**——它們其實沒有共享資料，但因為在同一個 cache line 而互相干擾。

### 解決方法：Padding

```c
// 每個 result 之間插入 padding，確保在不同 cache line
#define CACHE_LINE_SIZE 64

typedef struct {
    double value;
    char padding[CACHE_LINE_SIZE - sizeof(double)];  // 填滿一個 cache line
} PaddedDouble;

PaddedDouble results[4];  // 現在每個 result 在獨立的 cache line！

// Thread 0 寫 results[0].value，完全不影響 results[1]
```

或者用對齊屬性：

```c
typedef struct __attribute__((aligned(64))) {
    double value;
} AlignedDouble;

AlignedDouble results[4];
```

---

## 5. std::thread 基礎（C++11）

C++11 引入了 `std::thread`，讓多執行緒程式更現代化、更安全。

### 基本用法

```cpp
#include <thread>
#include <iostream>

void worker(int id) {
    std::cout << "Hello from thread " << id << std::endl;
}

int main() {
    std::thread t1(worker, 0);  // 傳入 function 和 argument
    std::thread t2(worker, 1);

    t1.join();  // 等待 t1 完成
    t2.join();  // 等待 t2 完成

    return 0;
}
```

編譯：
```bash
g++ -std=c++11 -O2 -pthread -o program program.cpp
```

### 使用 Lambda

Lambda（匿名函式）讓程式碼更簡潔，且可以用 capture 取得外部變數：

```cpp
#include <thread>
#include <vector>

int main() {
    int N = 1000;
    std::vector<double> data(N);
    std::vector<double> results(4, 0.0);
    int num_threads = 4;

    std::vector<std::thread> threads;
    for (int t = 0; t < num_threads; t++) {
        threads.emplace_back([&, t]() {
            // [&] capture 所有外部變數 by reference
            // [t] 注意：t 要用值 capture，否則迴圈結束後 t 的值會不對
            int start = t * (N / num_threads);
            int end = (t == num_threads - 1) ? N : start + N / num_threads;
            double sum = 0.0;
            for (int i = start; i < end; i++) {
                sum += data[i];
            }
            results[t] = sum;  // 不同 thread 寫不同位置，不需要 mutex
        });
    }

    for (auto& th : threads) {
        th.join();
    }

    double total = 0.0;
    for (double r : results) total += r;
    return 0;
}
```

> **Lambda capture 注意事項**：
> - `[=]`：值 capture（複製），安全但可能有額外開銷
> - `[&]`：reference capture，要確保 lambda 執行期間外部變數仍然有效
> - `[&, t]`：其他 by reference，`t` by value（迴圈計數器必須 by value！）

### std::mutex 與 std::lock_guard

```cpp
#include <mutex>

std::mutex mtx;
int counter = 0;

void increment() {
    std::lock_guard<std::mutex> guard(mtx);  // RAII：自動 lock/unlock
    counter++;
}  // guard 離開 scope，自動解鎖
```

`lock_guard` 比 pthreads 的 lock/unlock 更安全，因為它用 RAII 保證即使發生例外也會解鎖。

---

## 6. Work Decomposition 策略

如何把工作分配給各個 thread，是平行化的核心問題。

### Static Block Decomposition（靜態分塊）

最直觀的方法：把陣列切成 T 塊，每個 thread 負責一塊。

```
N = 16, T = 4：
Thread 0: [0,  1,  2,  3]
Thread 1: [4,  5,  6,  7]
Thread 2: [8,  9, 10, 11]
Thread 3: [12, 13, 14, 15]
```

```c
int chunk = N / num_threads;
int start = thread_id * chunk;
int end = (thread_id == num_threads - 1) ? N : start + chunk;
```

**優點**：簡單、記憶體存取連續（對 cache 友善）
**缺點**：若不同位置的工作量不同，容易造成 load imbalance

### Interleaved / Cyclic Decomposition（交錯分配）

每個 thread 以 T 為步進，交錯取元素：

```
N = 16, T = 4：
Thread 0: [0,  4,  8, 12]
Thread 1: [1,  5,  9, 13]
Thread 2: [2,  6, 10, 14]
Thread 3: [3,  7, 11, 15]
```

```c
for (int i = thread_id; i < N; i += num_threads) {
    // 處理 index i
}
```

**優點**：當工作量不均時（如 Mandelbrot），交錯分配讓每個 thread 的負載更均衡
**缺點**：記憶體存取不連續（stride 為 T），可能造成 cache miss

### 圖示比較

想像 Mandelbrot 集合：中間的像素計算量大（需要很多迭代），邊緣的計算量小。

```
計算量視覺化（數字越大越重）：
1 1 3 5 5 3 1 1 1
1 2 5 9 9 5 2 1 1
1 3 9 ∞ ∞ 9 3 1 1
1 2 5 9 9 5 2 1 1
1 1 3 5 5 3 1 1 1
```

**Block decomposition**（Thread 0 負責上半部）：
```
Thread 0: 1 1 3 5 5 3 1 1 = 20（輕）
Thread 1: 1 2 5 9 9 5 2 1 = 34
Thread 2: 1 3 9 ∞ ∞ 9 3 1 = 很重！
Thread 3: 1 2 5 9 9 5 2 1 = 34
```
Thread 2 要等 Thread 0, 1, 3 都結束才能開始新工作，浪費時間。

**Interleaved decomposition**（Thread 0 取第 0, 4 行）：
```
Thread 0: 1 1 3 5 5 3 1 1 + 1 2 5 9 9 5 2 1 = 54
Thread 1: 1 2 5 9 9 5 2 1 + 1 3 9 ∞ ∞ 9 3 1 = 差不多
Thread 2: 1 3 9 ∞ ∞ 9 3 1 + ... = 均衡
Thread 3: ... 
```
每個 thread 都有「一些重的和一些輕的」，負載更均衡。

---

## 7. Speedup 與 Amdahl's Law

### Speedup 定義

```
Speedup(T) = 單執行緒時間 / T 個執行緒時間
           = T_serial / T_parallel(T)
```

理想情況下，4 個 thread 應該有 4 倍加速（linear speedup），但實際上因為：
- 程式有無法平行化的部分（serial fraction）
- 同步開銷（mutex、barrier）
- 記憶體頻寬限制
- Cache 效應（false sharing）

實際加速通常低於線性。

### Amdahl's Law

如果程式有一部分 `s`（0 到 1 之間）是 sequential（無法平行化），那麼：

```
最大 Speedup(T) = 1 / (s + (1-s)/T)
```

當 T → ∞（無限多個 thread）：

```
最大 Speedup = 1 / s
```

### 範例

假設程式有 5% 是 sequential（s = 0.05），可平行部分是 95%：

| 執行緒數 T | 理論最大加速 |
|-----------|-------------|
| 2         | 1.90×       |
| 4         | 3.48×       |
| 8         | 5.93×       |
| 16        | 9.14×       |
| 32        | 12.31×      |
| ∞         | 20×         |

即使有無限多個處理器，加速也被限制在 20 倍！這說明**降低 serial fraction 比增加處理器更重要**。

### 效率（Efficiency）

```
Efficiency(T) = Speedup(T) / T
```

Efficiency = 1 代表完美線性加速，實際上總是小於 1。如果 efficiency 很低，代表很多時間花在等待和同步上，不值得用那麼多 thread。

---

## 8. Mandelbrot 平行化：為什麼有 Load Imbalance？

### Mandelbrot 集合

Mandelbrot 集合是一個數學集合，判斷複數 c 是否屬於這個集合的方法：

```
z₀ = 0
zₙ₊₁ = zₙ² + c
```

如果這個序列不發散（|z| 不超過 2），則 c 屬於 Mandelbrot 集合。

程式實作時，我們計算每個像素（對應一個複數 c）需要多少次迭代才發散，上限是 `MAX_ITER`。

```c
int mandelbrot(double cx, double cy, int max_iter) {
    double zx = 0.0, zy = 0.0;
    int iter = 0;
    while (iter < max_iter && zx*zx + zy*zy < 4.0) {
        double new_zx = zx*zx - zy*zy + cx;
        zy = 2*zx*zy + cy;
        zx = new_zx;
        iter++;
    }
    return iter;
}
```

### 為什麼有 Load Imbalance？

Mandelbrot 集合的邊界周圍，數列需要很多次迭代才能判斷是否發散（接近 `MAX_ITER`）。集合內部和外部的點則很快就能判斷。

因此：
- 集合邊界的像素：計算量大（接近 `MAX_ITER` 次迭代）
- 集合外部的像素：計算量小（幾次迭代就發散）

如果用 Block decomposition，負責邊界的 thread 會比其他 thread 慢很多，其他 thread 閒置等待，造成 load imbalance。

### 解決方案比較

| 方法 | 說明 | 效果 |
|------|------|------|
| Block decomposition | 每個 thread 負責連續的行 | 差（邊界集中在特定行） |
| Interleaved decomposition | 行數交錯分配 | 好（輕重行均衡分配） |
| Dynamic scheduling | 動態分配行，空閒的 thread 取下一行 | 最好（完全均衡），但有 overhead |

### 效能測量建議

```bash
# 用 time 指令測量執行時間
time ./mandelbrot 1        # 1 個 thread
time ./mandelbrot 2        # 2 個 thread
time ./mandelbrot 4        # 4 個 thread

# 計算 Speedup
python3 -c "print('Speedup 4x:', T1 / T4)"
```

也可以用 `perf stat` 獲得更詳細的效能資訊：

```bash
perf stat ./mandelbrot 4
```

### 完整 Speedup 分析範例

執行實驗，填寫表格：

| 執行緒數 | 執行時間(s) | Speedup | Efficiency |
|---------|------------|---------|------------|
| 1       | 8.0        | 1.0×    | 100%       |
| 2       | 4.2        | 1.9×    | 95%        |
| 4       | 2.3        | 3.5×    | 87.5%      |
| 8       | 1.4        | 5.7×    | 71%        |
| 16      | 1.1        | 7.3×    | 45%        |

觀察：執行緒數越多，效率越低。這是因為：
1. Amdahl's Law 的限制（serial fraction）
2. 同步開銷增加
3. 超過實體核心數後，context switch 增加

---

## 總結

| 概念 | 重點 |
|------|------|
| Race condition | 多個 thread 同時寫同一記憶體，結果不可預測 |
| Mutex | 保護臨界區，一次只讓一個 thread 進入 |
| rand_r | Thread-safe 亂數，每個 thread 有獨立 seed |
| False sharing | 不同 thread 修改同一 cache line，導致效能下降 |
| Block decomposition | 簡單，但可能 load imbalance |
| Interleaved decomposition | 更均衡，適合 Mandelbrot 這類工作量不均的問題 |
| Amdahl's Law | Serial 部分決定平行化的極限加速比 |

多執行緒程式設計的難點在於：**正確性**（避免 race condition）和**效能**（減少同步開銷、均衡負載）往往是矛盾的。好的設計需要在兩者之間取得平衡。
