# HW3 教學：OpenMP 平行程式設計

## 目錄
1. [共享記憶體平行化的挑戰](#1-共享記憶體平行化的挑戰)
2. [OpenMP 簡介](#2-openmp-簡介)
3. [常用 Pragma 指令](#3-常用-pragma-指令)
4. [False Sharing 在 OpenMP 的影響](#4-false-sharing-在-openmp-的影響)
5. [圖演算法的平行化挑戰](#5-圖演算法的平行化挑戰)
6. [PageRank 演算法介紹與平行化](#6-pagerank-演算法介紹與平行化)
7. [Conjugate Gradient（CG）方法](#7-conjugate-gradientcg-方法)
8. [OpenMP 效能分析重點](#8-openmp-效能分析重點)

---

## 1. 共享記憶體平行化的挑戰

在 HW2 中，我們用 Pthreads 和 std::thread 手動管理執行緒。這很強大，但也很繁瑣：需要手動建立 thread、傳遞參數、處理同步。

共享記憶體平行化主要面臨以下挑戰：

### Race Condition（資料競爭）
多個 thread 同時讀寫同一記憶體，可能產生不正確的結果。

### Overhead（額外開銷）
- Thread 建立和銷毀的成本
- 同步機制（mutex、barrier）的成本
- 通訊（cache coherence）的成本

### Load Imbalance（負載不均）
有些 thread 工作多，有些工作少，快的 thread 必須等慢的完成。

### 複雜度
手動管理 thread 的程式碼又長又難 debug。

**OpenMP 的目標**：用簡單的「指令（pragma）」告訴編譯器「這個迴圈可以平行化」，編譯器自動幫你管理 thread，大幅降低程式設計難度。

---

## 2. OpenMP 簡介

OpenMP 是一套針對共享記憶體多處理器的平行程式設計標準，支援 C、C++ 和 Fortran。

### 基本概念

- 用 `#pragma omp` 指令告訴編譯器平行化策略
- 不改變程式邏輯，程式在不支援 OpenMP 的環境中仍能正確執行（pragma 會被忽略）
- 採用 **Fork-Join 模型**：

```
主執行緒 ──────►────[fork]────────────►────[join]──────────►──►
                     /    \                  \   /
                  Thread1  Thread2  ...  Thread3 Thread4
                  （平行執行區域）
```

### 編譯與執行

```bash
# 編譯（加上 -fopenmp）
g++ -O2 -fopenmp -o program program.cpp

# 設定執行緒數（環境變數）
export OMP_NUM_THREADS=4
./program

# 或直接在程式碼中設定
#include <omp.h>
omp_set_num_threads(4);
```

### 最簡單的範例

```cpp
#include <omp.h>
#include <stdio.h>

int main() {
    #pragma omp parallel
    {
        int id = omp_get_thread_num();
        int total = omp_get_num_threads();
        printf("Hello from thread %d of %d\n", id, total);
    }
    return 0;
}
```

`#pragma omp parallel` 會建立一個「平行區域（parallel region）」，所有可用的 thread 都會執行大括號內的程式碼。

---

## 3. 常用 Pragma 指令

### `#pragma omp parallel for`

最常用的指令：平行化 for 迴圈。

```cpp
int sum = 0;
int data[1000];

// 每個 thread 負責部分迭代
#pragma omp parallel for
for (int i = 0; i < 1000; i++) {
    data[i] = i * i;  // 各 thread 寫不同位置，安全
}
```

注意：這裡每個 `data[i]` 彼此獨立，所以安全。如果是累加 `sum`，就需要用 reduction。

### Schedule 子句

控制迴圈迭代如何分配給各 thread：

```cpp
// static：靜態分塊（預設）
// 迭代 0~249 給 Thread 0，250~499 給 Thread 1，依此類推
#pragma omp parallel for schedule(static)
for (int i = 0; i < 1000; i++) { ... }

// static, chunk_size：靜態分塊，指定塊大小
// Thread 0 取 0~9, 40~49, 80~89,...
// Thread 1 取 10~19, 50~59,...
#pragma omp parallel for schedule(static, 10)
for (int i = 0; i < 1000; i++) { ... }

// dynamic：動態分配，空閒 thread 取下一個 chunk
// 適合工作量不均的情況（如 Mandelbrot）
#pragma omp parallel for schedule(dynamic, 10)
for (int i = 0; i < 1000; i++) { ... }

// guided：類似 dynamic，但 chunk 大小逐漸縮小
// 開始分大塊，快結束時分小塊（減少最後的 imbalance）
#pragma omp parallel for schedule(guided)
for (int i = 0; i < 1000; i++) { ... }
```

| schedule | 適用場景 | overhead |
|----------|---------|---------|
| static   | 工作量均等 | 最低 |
| dynamic  | 工作量差異大 | 中（需要動態協調） |
| guided   | 介於兩者之間 | 中 |

### `#pragma omp reduction`

安全地在多個 thread 間累加（或其他操作）：

```cpp
double sum = 0.0;
double data[1000] = { /* ... */ };

// 每個 thread 有自己的 local sum，最後自動合併
#pragma omp parallel for reduction(+:sum)
for (int i = 0; i < 1000; i++) {
    sum += data[i];
}

// 支援的運算：+, *, -, &, |, ^, &&, ||, max, min
double max_val = 0.0;
#pragma omp parallel for reduction(max:max_val)
for (int i = 0; i < 1000; i++) {
    if (data[i] > max_val) max_val = data[i];
}
```

Reduction 的原理：
1. 每個 thread 建立一個 local 副本，初始化為 identity value（加法是 0，乘法是 1）
2. 各 thread 各自計算
3. 最後 OpenMP 把所有 thread 的 local 副本合併到原始變數

### `#pragma omp critical`

讓只有一個 thread 能進入的臨界區：

```cpp
int count = 0;

#pragma omp parallel for
for (int i = 0; i < N; i++) {
    if (someCondition(i)) {
        #pragma omp critical
        {
            count++;  // 同一時間只有一個 thread 執行這裡
        }
    }
}
```

`critical` 比 reduction 靈活，但效能較差（有 lock 開銷）。

### `#pragma omp atomic`

比 critical 更輕量，但只支援簡單的原子操作：

```cpp
#pragma omp parallel for
for (int i = 0; i < N; i++) {
    #pragma omp atomic
    count++;  // 原子遞增

    #pragma omp atomic
    sum += data[i];  // 原子加法
}
```

`atomic` 通常使用 CPU 的原子指令（如 x86 的 `lock add`），比 `critical` 快，但只能用於簡單的讀-修改-寫操作。

### `#pragma omp barrier`

讓所有 thread 在此等待，直到全部到達：

```cpp
#pragma omp parallel
{
    int id = omp_get_thread_num();

    // Phase 1：所有 thread 各自計算
    computePhase1(id);

    #pragma omp barrier  // 等待所有 thread 完成 Phase 1

    // Phase 2：需要 Phase 1 的全部結果
    computePhase2(id);
}
```

`#pragma omp parallel for` 結尾自動有 implicit barrier（所有 thread 都完成迴圈才繼續）。

### 變數範圍控制

在 OpenMP parallel 區域內，需要指定變數是共享還是私有：

```cpp
int shared_var = 0;
int i;

#pragma omp parallel for private(i) shared(shared_var)
for (i = 0; i < N; i++) {
    // i 是 private（每個 thread 有自己的 i）
    // shared_var 是 shared（所有 thread 共用，要小心 race condition）
}

// 預設：在 parallel for 中，loop variable 是 private，其他是 shared
// 可以用 default(none) 強制明確指定所有變數
```

### 完整範例：平行計算 π（Reduction）

```cpp
#include <omp.h>
#include <stdio.h>

int main() {
    long N = 1000000000L;
    double step = 1.0 / N;
    double sum = 0.0;

    #pragma omp parallel for reduction(+:sum) schedule(static)
    for (long i = 0; i < N; i++) {
        double x = (i + 0.5) * step;
        sum += 4.0 / (1.0 + x * x);
    }

    double pi = step * sum;
    printf("π ≈ %.10f\n", pi);
    return 0;
}
```

---

## 4. False Sharing 在 OpenMP 的影響

OpenMP 的 thread 共享相同的記憶體空間，因此也會有 false sharing 問題。

### 典型錯誤：陣列累加

```cpp
// 危險！每個 thread 寫 partial_sums[id]，但可能在同一 cache line
double partial_sums[MAX_THREADS];

#pragma omp parallel
{
    int id = omp_get_thread_num();
    partial_sums[id] = 0.0;

    #pragma omp for
    for (int i = 0; i < N; i++) {
        partial_sums[id] += data[i];
    }
}
// 即使每個 thread 寫不同位置，如果在同一個 cache line，效能會很差！
```

### 解決方法

**方法 1：用 reduction（最好）**

```cpp
double sum = 0.0;
#pragma omp parallel for reduction(+:sum)
for (int i = 0; i < N; i++) {
    sum += data[i];
}
```

**方法 2：使用 padding**

```cpp
#define CACHE_LINE 64
struct alignas(CACHE_LINE) PaddedDouble {
    double value;
    char pad[CACHE_LINE - sizeof(double)];
};
PaddedDouble partial_sums[MAX_THREADS];
```

**方法 3：使用 local variable**

```cpp
#pragma omp parallel
{
    double local_sum = 0.0;  // 每個 thread 的 local variable，在 stack 上，不同 thread 位址不同
    #pragma omp for
    for (int i = 0; i < N; i++) {
        local_sum += data[i];
    }
    #pragma omp atomic
    global_sum += local_sum;  // 最後才合併
}
```

---

## 5. 圖演算法的平行化挑戰

圖演算法（Graph Algorithm）的平行化比陣列計算難得多，因為圖的結構是不規則的（irregular），很難均衡分配工作。

### 圖的基本概念

```
頂點（Vertex/Node）：圖中的節點
邊（Edge）：連接兩個頂點
度數（Degree）：一個頂點連接的邊數
```

圖的常見儲存格式：
- **Adjacency Matrix**：N×N 矩陣，記憶體大但查詢快
- **CSR（Compressed Sparse Row）**：稀疏圖的標準格式，記憶體效率高

```
CSR 格式：
  offsets[]:  [0, 2, 5, 6, 8]   ← 每個頂點的邊的起始位置
  neighbors[]: [1, 3, 0, 2, 3, 1, 0, 2]  ← 鄰居列表

  頂點 0 的鄰居：neighbors[0..1] = {1, 3}
  頂點 1 的鄰居：neighbors[2..4] = {0, 2, 3}
```

### BFS（廣度優先搜尋）的 Frontier 概念

BFS 從 source 頂點出發，一層一層地探索圖：

```
Level 0：{source}
Level 1：source 的所有鄰居
Level 2：Level 1 中頂點的所有未訪問鄰居
...
```

每一層叫做一個 **frontier**：

```c
// 序列版 BFS
queue<int> frontier;
frontier.push(source);
bool visited[N] = {false};
visited[source] = true;

while (!frontier.empty()) {
    int v = frontier.front();
    frontier.pop();

    for (int u : neighbors[v]) {
        if (!visited[u]) {
            visited[u] = true;
            frontier.push(u);
        }
    }
}
```

### Top-Down BFS vs Bottom-Up BFS

**Top-Down（從 frontier 往外找）**：
- 對 frontier 中的每個頂點，檢查它的鄰居
- 適合 frontier 小的時候（BFS 早期）
- 問題：frontier 大時，要處理大量頂點，overhead 高

**Bottom-Up（從未訪問頂點找 frontier）**：
- 對所有未訪問頂點，檢查是否有鄰居在 frontier
- 適合 frontier 大的時候（BFS 中期）
- 問題：frontier 小時，會掃描大量不必要的頂點

**Direction-Optimizing BFS（兩者結合）**：
- 根據 frontier 大小動態切換
- 在許多 graph 上效能更好

### 平行化 BFS 的挑戰

1. **Load Imbalance**：不同頂點的度數（鄰居數）差異很大，高度數頂點的工作量遠大於低度數頂點。

2. **寫入衝突**：多個 thread 可能同時嘗試將同一個頂點加入 frontier。

```cpp
// 平行 BFS（Top-Down），用 atomic 避免衝突
#pragma omp parallel for schedule(dynamic, 64)
for (int vi = 0; vi < frontier_size; vi++) {
    int v = frontier[vi];
    for (int j = offsets[v]; j < offsets[v+1]; j++) {
        int u = neighbors[j];
        int expected = -1;
        // atomic compare and swap：只有一個 thread 能成功
        if (__atomic_compare_exchange_n(&distance[u], &expected, dist+1,
                                         false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
            next_frontier[next_size++] = u;  // 注意：next_size 也需要 atomic！
        }
    }
}
```

---

## 6. PageRank 演算法介紹與平行化

### 什麼是 PageRank？

Google 最早用來對網頁排名的演算法。核心思想：
- 被很多頁面鏈接的頁面，重要性高
- 被重要頁面鏈接的頁面，重要性也高

### 數學公式

```
PR(v) = (1-d)/N + d * Σ PR(u)/OutDegree(u)
         ↑                ↑
    隨機跳轉機率      來自所有鏈到 v 的頁面 u
```

- `d`：阻尼因子（damping factor），通常取 0.85
- `N`：總頁面數
- `OutDegree(u)`：頁面 u 的出鏈數

### 迭代計算

PageRank 通過迭代計算，直到收斂：

```
1. 初始化：PR(v) = 1/N（所有頁面等重要）
2. 每次迭代，根據公式更新所有頂點的 PR 值
3. 重複直到 PR 值變化量小於閾值（convergence）
```

```c
// 序列版 PageRank
void pagerank(Graph* g, double* pr, double d, int max_iter) {
    int N = g->num_vertices;
    double* new_pr = malloc(N * sizeof(double));

    for (int iter = 0; iter < max_iter; iter++) {
        // 初始化（考慮 dangling nodes：出度為 0 的頂點）
        double dangling_sum = 0.0;
        for (int v = 0; v < N; v++) {
            if (g->out_degree[v] == 0) {
                dangling_sum += pr[v];
            }
            new_pr[v] = (1.0 - d) / N + d * dangling_sum / N;
        }

        // 分配 PR 給鄰居
        for (int u = 0; u < N; u++) {
            double contrib = d * pr[u] / g->out_degree[u];
            for (int j = g->offsets[u]; j < g->offsets[u+1]; j++) {
                int v = g->neighbors[j];
                new_pr[v] += contrib;
            }
        }

        // 交換 pr 和 new_pr
        memcpy(pr, new_pr, N * sizeof(double));
    }
    free(new_pr);
}
```

### OpenMP 平行化 PageRank

**主要平行化點**：

```cpp
void pagerank_parallel(Graph* g, double* pr, double d, int max_iter) {
    int N = g->num_vertices;
    double* new_pr = new double[N];

    for (int iter = 0; iter < max_iter; iter++) {
        // 1. 計算 dangling sum（可平行化）
        double dangling_sum = 0.0;
        #pragma omp parallel for reduction(+:dangling_sum)
        for (int v = 0; v < N; v++) {
            if (g->out_degree[v] == 0) {
                dangling_sum += pr[v];
            }
        }

        // 2. 初始化 new_pr（可平行化）
        double base = (1.0 - d) / N + d * dangling_sum / N;
        #pragma omp parallel for
        for (int v = 0; v < N; v++) {
            new_pr[v] = base;
        }

        // 3. 累加貢獻（有寫入衝突！需要 atomic 或 pull-based 方式）
        // Pull-based：由目標頂點去拉取來源的貢獻（避免 write conflict）
        #pragma omp parallel for schedule(dynamic, 64)
        for (int v = 0; v < N; v++) {
            // 對所有指向 v 的邊（in-edges）
            for (int j = g->in_offsets[v]; j < g->in_offsets[v+1]; j++) {
                int u = g->in_neighbors[j];
                new_pr[v] += d * pr[u] / g->out_degree[u];
            }
        }

        // 4. 交換
        std::swap(pr, new_pr);
    }
    delete[] new_pr;
}
```

**Pull-based vs Push-based**：
- **Push-based**：每個頂點 u 把貢獻 push 給鄰居 → 寫入不同目標，需要 atomic
- **Pull-based**：每個頂點 v 從鄰居 pull 貢獻 → 每個 thread 只寫自己的 v，不衝突

Pull-based 在 OpenMP 中通常更有效率，因為不需要 atomic 操作。

---

## 7. Conjugate Gradient（CG）方法

### 用途：解線性方程組

CG 方法用來解大型稀疏線性方程組 **Ax = b**，其中 A 是對稱正定矩陣（SPD）。

在科學計算中很常見：
- 有限元素法（FEM）
- 圖像重建
- 機器學習（linear regression, kernel methods）

### 為什麼不用 Gaussian Elimination？

高斯消去法的複雜度是 O(N³)，對大型稀疏矩陣（N 可能是百萬以上）根本無法使用。
CG 方法的複雜度是 O(k × nnz)，其中 k 是迭代次數（通常遠小於 N），nnz 是非零元素數。

### CG 演算法

```
輸入：A（稀疏矩陣），b（右側向量），x₀（初始猜測，通常是零向量）
輸出：x（近似解，使得 Ax ≈ b）

初始化：
  r₀ = b - A × x₀      （殘差，residual）
  p₀ = r₀              （搜尋方向）

每次迭代 k = 0, 1, 2, ...:
  αₖ = (rₖᵀrₖ) / (pₖᵀApₖ)    （步長）
  xₖ₊₁ = xₖ + αₖpₖ             （更新解）
  rₖ₊₁ = rₖ - αₖApₖ            （更新殘差）
  βₖ = (rₖ₊₁ᵀrₖ₊₁) / (rₖᵀrₖ)  （共軛係數）
  pₖ₊₁ = rₖ₊₁ + βₖpₖ           （更新搜尋方向）

直到 ||rₖ|| 夠小為止
```

### 主要操作分析

CG 每次迭代的主要操作：

| 操作 | 名稱 | 複雜度 |
|------|------|--------|
| `A × p`  | SpMV（稀疏矩陣-向量乘法） | O(nnz) |
| `rᵀr`    | Dot product | O(N) |
| `x + αp` | AXPY（向量加法） | O(N) |

**SpMV 是瓶頸**，也是最值得平行化的部分。

### 用 OpenMP 平行化 CG

```cpp
// SpMV：y = A * x，CSR 格式
void spmv(int N, int* offsets, int* cols, double* vals, double* x, double* y) {
    #pragma omp parallel for schedule(dynamic, 32)
    for (int row = 0; row < N; row++) {
        double sum = 0.0;
        for (int j = offsets[row]; j < offsets[row+1]; j++) {
            sum += vals[j] * x[cols[j]];
        }
        y[row] = sum;
    }
}

// Dot product：返回 a ⋅ b
double dot(int N, double* a, double* b) {
    double result = 0.0;
    #pragma omp parallel for reduction(+:result)
    for (int i = 0; i < N; i++) {
        result += a[i] * b[i];
    }
    return result;
}

// AXPY：y = alpha * x + y
void axpy(int N, double alpha, double* x, double* y) {
    #pragma omp parallel for
    for (int i = 0; i < N; i++) {
        y[i] += alpha * x[i];
    }
}
```

SpMV 的 load imbalance 問題：每一行的非零元素數（nnz per row）可能差異很大，所以用 `schedule(dynamic)` 比 `static` 更均衡。

### CG 完整實作（含 OpenMP）

```cpp
void conjugate_gradient(int N, int* offsets, int* cols, double* vals,
                         double* b, double* x, int max_iter, double tol) {
    double* r = new double[N];
    double* p = new double[N];
    double* Ap = new double[N];

    // 初始化：r = b - A*x, p = r
    spmv(N, offsets, cols, vals, x, Ap);  // Ap = A*x
    #pragma omp parallel for
    for (int i = 0; i < N; i++) {
        r[i] = b[i] - Ap[i];
        p[i] = r[i];
    }

    double r_dot = dot(N, r, r);

    for (int iter = 0; iter < max_iter && sqrt(r_dot) > tol; iter++) {
        spmv(N, offsets, cols, vals, p, Ap);  // Ap = A*p
        double pAp = dot(N, p, Ap);
        double alpha = r_dot / pAp;

        axpy(N, alpha, p, x);     // x = x + alpha*p
        axpy(N, -alpha, Ap, r);   // r = r - alpha*Ap

        double r_dot_new = dot(N, r, r);
        double beta = r_dot_new / r_dot;
        r_dot = r_dot_new;

        // p = r + beta*p
        #pragma omp parallel for
        for (int i = 0; i < N; i++) {
            p[i] = r[i] + beta * p[i];
        }
    }

    delete[] r;
    delete[] p;
    delete[] Ap;
}
```

---

## 8. OpenMP 效能分析重點

### 測量時間

```cpp
#include <omp.h>

double start = omp_get_wtime();  // 取得當前時間（秒）
// ... 你的程式碼 ...
double end = omp_get_wtime();
printf("Time: %.4f seconds\n", end - start);
```

### 常見效能問題與解決方案

| 問題 | 症狀 | 解決方案 |
|------|------|---------|
| Load imbalance | 某些 thread 很快結束，其他很慢 | 改用 dynamic schedule |
| False sharing | 加了 OpenMP 反而更慢 | 用 reduction 或 padding |
| Over-synchronization | 到處用 critical/atomic | 盡量用 reduction，減少鎖的範圍 |
| Thread creation overhead | parallel region 太短 | 合併多個小 parallel region |
| Serial bottleneck | 加速比遠低於核心數 | 找出 serial 部分，考慮是否能平行化 |

### 調整 Schedule

實驗不同 schedule 對效能的影響：

```bash
# 用環境變數動態調整 schedule（不用重新編譯）
OMP_SCHEDULE="dynamic,16" ./program
OMP_SCHEDULE="static" ./program
OMP_SCHEDULE="guided" ./program
```

### 分析工具

```bash
# 用 perf 看效能
perf stat -e cache-misses,cache-references ./program

# 用 valgrind 的 cachegrind
valgrind --tool=cachegrind ./program

# Intel VTune（如果有的話）
vtune -collect hotspots ./program
```

### Scalability Test（可擴展性測試）

測試不同 thread 數的效能：

```bash
for T in 1 2 4 8 16; do
    echo -n "Threads=$T: "
    OMP_NUM_THREADS=$T time ./program 2>&1 | grep real
done
```

並計算 Speedup 和 Efficiency，畫出 scalability curve。理想情況是 Speedup 隨 thread 數線性增長，Efficiency 維持在 80% 以上。

### 重點總結

```
OpenMP 最佳實踐：
1. 用 reduction 取代手動 atomic 累加
2. 用 schedule(dynamic) 處理工作量不均的迴圈
3. 避免在 parallel region 內做 I/O 或記憶體配置
4. 臨界區（critical）要盡量小、盡量少
5. 用 omp_get_wtime() 精確測量效能
6. 先確保 serial 版本正確，再加 OpenMP
7. 用 default(none) 強制明確指定變數範圍，避免意外共享
```
