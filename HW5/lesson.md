# HW5 教學：MPI 分散式記憶體平行程式設計

## 目錄
1. [分散式記憶體 vs 共享記憶體](#1-分散式記憶體-vs-共享記憶體)
2. [MPI 基本概念](#2-mpi-基本概念)
3. [MPI 程式結構](#3-mpi-程式結構)
4. [Point-to-Point 通訊](#4-point-to-point-通訊)
5. [Collective Operations](#5-collective-operations)
6. [Tree-based Reduction vs Linear Reduction](#6-tree-based-reduction-vs-linear-reduction)
7. [One-sided Communication（RMA）](#7-one-sided-communicationrma)
8. [MPI + Monte Carlo π 的各種實作方式](#8-mpi--monte-carlo-π-的各種實作方式)
9. [Deadlock 常見原因](#9-deadlock-常見原因)
10. [如何用 mpirun 跑程式](#10-如何用-mpirun-跑程式)

---

## 1. 分散式記憶體 vs 共享記憶體

### 回顧：共享記憶體（HW2, HW3）

在之前的作業中，我們用 Pthreads、std::thread、OpenMP 等工具，讓多個執行緒在**同一台機器**上協同工作。這些執行緒共享同一塊記憶體，可以直接讀寫對方的資料。

```
共享記憶體架構（Symmetric Multiprocessing, SMP）：

  Thread 0  Thread 1  Thread 2  Thread 3
      \         |         |         /
       \        |         |        /
        ↓       ↓         ↓       ↓
     ┌─────────────────────────────┐
     │         共享記憶體           │
     │  （所有 thread 都可以存取）   │
     └─────────────────────────────┘
```

**優點**：通訊方便（直接讀寫共享變數）
**缺點**：規模受限於單機核心數，記憶體也受限

### 分散式記憶體（Distributed Memory）

MPI 的目標是讓多台機器（稱為 **節點 node**）協同計算，每台機器有**各自獨立的記憶體**：

```
分散式記憶體架構（Distributed Memory）：

  Node 0          Node 1          Node 2          Node 3
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ Memory  │    │ Memory  │    │ Memory  │    │ Memory  │
│ Process │    │ Process │    │ Process │    │ Process │
└────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘
     └──────────────┴──────────────┴──────────────┘
                    網路（Interconnect）
                  （InfiniBand, Ethernet, ...）
```

**優點**：可以擴展到數千台機器（HPC 叢集）
**缺點**：通訊需要明確的訊息傳遞，程式設計更複雜

### 哪個更快？

不一定。對於超大規模的問題：
- 共享記憶體受限於單機（記憶體容量、核心數）
- 分散式記憶體可以水平擴展，但網路通訊延遲高

現代的 HPC 程式通常**兩者結合**：節點之間用 MPI，節點內部用 OpenMP。

---

## 2. MPI 基本概念

### Rank（排名）

MPI 用 **rank** 識別每個 process（類似 thread id）：
- 每個 MPI process 有一個唯一的 rank（0 到 N-1）
- Rank 0 通常是「主控 process」，負責 I/O 和協調

### Communicator（通訊子）

Communicator 定義了一組可以互相通訊的 process。最常用的是：
- `MPI_COMM_WORLD`：包含所有 process 的預設 communicator

你也可以建立子集的 communicator，但本課程主要用 `MPI_COMM_WORLD`。

### World（世界）

`MPI_COMM_WORLD` 代表整個 MPI「世界」，包含所有參與計算的 process。

```
mpirun -n 4 ./program 啟動後：

MPI_COMM_WORLD:
┌───────────────────────────────────┐
│  Rank 0  Rank 1  Rank 2  Rank 3  │
└───────────────────────────────────┘
```

### MPI 的執行模型

MPI 採用 **SPMD（Single Program, Multiple Data）** 模型：
- **每個 process 執行同一份程式**
- 但根據自己的 rank 決定做什麼工作

```c
// 所有 process 都執行這段程式碼
int rank, size;
MPI_Comm_rank(MPI_COMM_WORLD, &rank);
MPI_Comm_size(MPI_COMM_WORLD, &size);

if (rank == 0) {
    // 只有 rank 0 做這件事（主控者）
    printf("I am the master!\n");
} else {
    // rank 1, 2, 3, ... 做這件事（工作者）
    printf("I am worker %d!\n", rank);
}
```

---

## 3. MPI 程式結構

### 必要的初始化與結束

每個 MPI 程式的固定框架：

```c
#include <mpi.h>
#include <stdio.h>

int main(int argc, char* argv[]) {
    // 1. 初始化 MPI 環境（必須第一個呼叫）
    MPI_Init(&argc, &argv);

    // 2. 取得這個 process 的 rank
    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    // 3. 取得總 process 數
    int size;
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    // ─── 你的程式邏輯 ─────────────────────
    printf("Hello from process %d of %d\n", rank, size);
    // ───────────────────────────────────────

    // 4. 結束 MPI 環境（必須最後呼叫）
    MPI_Finalize();
    return 0;
}
```

編譯與執行：
```bash
# 用 mpicc 編譯（包裝了 gcc）
mpicc -O2 -o hello hello.c

# 用 mpirun 執行（-n 指定 process 數）
mpirun -n 4 ./hello
```

### 常用的 MPI 函式

```c
MPI_Init(&argc, &argv)               // 初始化
MPI_Finalize()                       // 結束
MPI_Comm_rank(comm, &rank)           // 取得自己的 rank
MPI_Comm_size(comm, &size)           // 取得 communicator 的 process 數
MPI_Wtime()                          // 取得時間（類似 omp_get_wtime）
MPI_Barrier(comm)                    // 全域同步（所有 process 都到這裡才繼續）
```

---

## 4. Point-to-Point 通訊

點對點通訊：一個 process 傳訊息給另一個 process。

### Blocking 通訊：MPI_Send / MPI_Recv

```c
// 傳送
int MPI_Send(
    void* buf,         // 要傳送的資料的起始位址
    int count,         // 資料元素數量
    MPI_Datatype type, // 資料型別
    int dest,          // 目標 process 的 rank
    int tag,           // 訊息標籤（用來區分不同類型的訊息）
    MPI_Comm comm      // communicator
);

// 接收
int MPI_Recv(
    void* buf,         // 接收緩衝區
    int count,         // 最大接收元素數
    MPI_Datatype type, // 資料型別
    int source,        // 來源 rank（或 MPI_ANY_SOURCE）
    int tag,           // 訊息標籤（或 MPI_ANY_TAG）
    MPI_Comm comm,
    MPI_Status* status // 接收結果資訊（可用 MPI_STATUS_IGNORE）
);
```

### 常用 MPI 資料型別

| C 型別 | MPI 型別 |
|--------|---------|
| `int` | `MPI_INT` |
| `long` | `MPI_LONG` |
| `float` | `MPI_FLOAT` |
| `double` | `MPI_DOUBLE` |
| `char` | `MPI_CHAR` |

### 範例：Process 0 和 Process 1 互相傳訊息

```c
int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);
    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    if (rank == 0) {
        int data = 42;
        MPI_Send(&data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);  // 傳給 rank 1
        printf("Rank 0 sent %d to rank 1\n", data);
    } else if (rank == 1) {
        int data;
        MPI_Recv(&data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        printf("Rank 1 received %d from rank 0\n", data);
    }

    MPI_Finalize();
    return 0;
}
```

### 傳送陣列

```c
// 傳送整個陣列
double data[1000];
if (rank == 0) {
    // 填充資料
    for (int i = 0; i < 1000; i++) data[i] = i * 0.1;
    MPI_Send(data, 1000, MPI_DOUBLE, 1, 0, MPI_COMM_WORLD);
} else if (rank == 1) {
    MPI_Recv(data, 1000, MPI_DOUBLE, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
}
```

### Non-blocking 通訊：MPI_Isend / MPI_Irecv

Blocking 的 `MPI_Send` 可能需要等待接收方 ready 才返回（取決於訊息大小和 MPI 實作），這會造成等待浪費。Non-blocking 版本立即返回，讓 process 可以繼續做其他事：

```c
MPI_Request req;
MPI_Status status;

// Non-blocking 傳送：立即返回
MPI_Isend(&data, count, MPI_DOUBLE, dest, tag, MPI_COMM_WORLD, &req);

// 做一些其他工作...
doSomethingUseful();

// 等待通訊完成（必須呼叫，否則 buf 可能還沒傳完就被修改）
MPI_Wait(&req, &status);
```

```c
// Non-blocking 接收
MPI_Request recv_req;
MPI_Irecv(&buffer, count, MPI_DOUBLE, src, tag, MPI_COMM_WORLD, &recv_req);

// 做一些計算...
compute();

// 確認接收完成後才使用 buffer
MPI_Wait(&recv_req, MPI_STATUS_IGNORE);
use(buffer);
```

### 等待多個請求

```c
MPI_Request requests[4];
MPI_Isend(..., &requests[0]);
MPI_Isend(..., &requests[1]);
MPI_Irecv(..., &requests[2]);
MPI_Irecv(..., &requests[3]);

// 等待全部完成
MPI_Waitall(4, requests, MPI_STATUSES_IGNORE);
```

---

## 5. Collective Operations

集體操作（Collective Operations）：communicator 內**所有 process 都必須呼叫**的操作，是 MPI 最強大的工具。

### MPI_Bcast（廣播）

從一個 process（root）廣播資料到所有 process：

```
Before:
  Rank 0: [42]
  Rank 1: [??]
  Rank 2: [??]
  Rank 3: [??]

After MPI_Bcast(root=0):
  Rank 0: [42]
  Rank 1: [42]
  Rank 2: [42]
  Rank 3: [42]
```

```c
int value;
if (rank == 0) {
    value = 42;  // root 準備資料
}
// 所有 process 都呼叫 MPI_Bcast，root=0 的資料被廣播給其他人
MPI_Bcast(&value, 1, MPI_INT, 0, MPI_COMM_WORLD);
// 現在所有 process 的 value 都是 42
```

### MPI_Reduce（歸約）

收集所有 process 的資料，做某種運算後把結果給 root：

```
Before:
  Rank 0: local_sum = 10
  Rank 1: local_sum = 20
  Rank 2: local_sum = 30
  Rank 3: local_sum = 40

After MPI_Reduce(op=MPI_SUM, root=0):
  Rank 0: total_sum = 100   ← 只有 root 得到結果
  Rank 1: (undefined)
  Rank 2: (undefined)
  Rank 3: (undefined)
```

```c
double local_sum = /* 這個 process 計算的結果 */;
double total_sum;

MPI_Reduce(
    &local_sum,      // 送出的資料（sendbuf）
    &total_sum,      // 接收結果的緩衝區（recvbuf，只有 root 有效）
    1,               // 元素數量
    MPI_DOUBLE,      // 資料型別
    MPI_SUM,         // 操作（MPI_SUM, MPI_MAX, MPI_MIN, MPI_PROD, ...）
    0,               // root rank
    MPI_COMM_WORLD
);

if (rank == 0) {
    printf("Total sum = %f\n", total_sum);
}
```

### MPI_Allreduce（全體歸約）

和 `MPI_Reduce` 一樣，但結果給**所有** process，不只給 root：

```c
double local_val = /* ... */;
double global_max;

// 所有 process 都能得到最大值
MPI_Allreduce(&local_val, &global_max, 1, MPI_DOUBLE, MPI_MAX, MPI_COMM_WORLD);
// 現在所有 process 都有 global_max
```

### MPI_Gather（收集）

每個 process 提供一份資料，root 把所有人的資料收集起來（按 rank 順序拼接）：

```
Before:
  Rank 0: local = [10, 11]
  Rank 1: local = [20, 21]
  Rank 2: local = [30, 31]
  Rank 3: local = [40, 41]

After MPI_Gather(root=0):
  Rank 0: gathered = [10, 11, 20, 21, 30, 31, 40, 41]
```

```c
int local_data[2] = {rank*10, rank*10+1};
int* gathered = NULL;

if (rank == 0) {
    gathered = malloc(size * 2 * sizeof(int));  // root 配置接收緩衝區
}

MPI_Gather(
    local_data, 2, MPI_INT,   // 每個 process 送出 2 個 int
    gathered,   2, MPI_INT,   // root 每次接收 2 個 int
    0, MPI_COMM_WORLD
);

if (rank == 0) {
    // gathered[] 現在有所有 process 的資料
    for (int i = 0; i < size * 2; i++) {
        printf("%d ", gathered[i]);
    }
    free(gathered);
}
```

### MPI_Scatter（分發）

`MPI_Gather` 的反向操作：root 把資料切分後分發給各 process：

```
Before:
  Rank 0: all_data = [10, 11, 20, 21, 30, 31, 40, 41]

After MPI_Scatter(root=0):
  Rank 0: local = [10, 11]
  Rank 1: local = [20, 21]
  Rank 2: local = [30, 31]
  Rank 3: local = [40, 41]
```

```c
int* all_data = NULL;
if (rank == 0) {
    all_data = malloc(size * 2 * sizeof(int));
    for (int i = 0; i < size * 2; i++) all_data[i] = (i/2)*10 + i%2;
}

int local_data[2];
MPI_Scatter(
    all_data,   2, MPI_INT,   // root 送出（每人 2 個）
    local_data, 2, MPI_INT,   // 各 process 接收
    0, MPI_COMM_WORLD
);
```

### Collective 操作摘要

| 操作 | 說明 | 誰有結果 |
|------|------|---------|
| `MPI_Bcast` | Root 廣播資料 | 全部 |
| `MPI_Reduce` | 收集並計算，給 root | 只有 root |
| `MPI_Allreduce` | 收集並計算，給全部 | 全部 |
| `MPI_Gather` | 收集各 process 的資料到 root | 只有 root |
| `MPI_Allgather` | 收集各 process 的資料到全部 | 全部 |
| `MPI_Scatter` | Root 分發資料給各 process | 各自收到自己的部分 |

---

## 6. Tree-based Reduction vs Linear Reduction

為什麼 `MPI_Reduce` 比你自己用 `MPI_Send/Recv` 實作快？

### Linear Reduction（線性歸約）

最直覺的實作：所有 worker 把結果傳給 rank 0，rank 0 一個一個加：

```
Step 1: Rank 1 → Rank 0 (send local_sum)
Step 2: Rank 2 → Rank 0 (send local_sum)
Step 3: Rank 3 → Rank 0 (send local_sum)
...
Step N-1: Rank N-1 → Rank 0

Rank 0 最後把 N-1 個值加總
```

**問題**：Rank 0 必須依序處理每個訊息，總時間 = O(N) 通訊步驟。

### Tree-based Reduction（樹狀歸約）

把 reduction 組織成一棵二元樹：

```
4 個 process 的 Tree Reduce：

Round 1（Step 1）：
  Rank 1 → Rank 0：Rank 0 加上 Rank 1 的值
  Rank 3 → Rank 2：Rank 2 加上 Rank 3 的值

Round 2（Step 2）：
  Rank 2 → Rank 0：Rank 0 加上（Rank 2 + Rank 3）的值

完成！Rank 0 有全部的總和
```

**優點**：並行度更高，總時間 = O(log N) 步驟，遠快於 O(N)。

| 方法 | 通訊步驟 | 8 processes | 1024 processes |
|------|---------|------------|----------------|
| Linear | O(N) | 7 步 | 1023 步 |
| Tree | O(log₂N) | 3 步 | 10 步 |

`MPI_Reduce` 通常就是用 tree-based 演算法實作的，所以你應該盡量用 collective operations 而不是自己用 point-to-point 實作。

---

## 7. One-sided Communication（RMA）

One-sided communication（單側通訊）是 MPI-2 引入的進階功能，讓一個 process 可以**直接讀寫另一個 process 的記憶體**，不需要對方配合（發出 MPI_Recv）。

### 概念

傳統的 two-sided（雙側）通訊：
```
Sender: MPI_Send(...)   ← 需要雙方配合
Receiver: MPI_Recv(...)
```

One-sided（單側）通訊：
```
Process A: MPI_Put(data → Process B的記憶體)  ← B 不需要做任何事
Process A: MPI_Get(Process B的記憶體 → local)  ← B 不需要做任何事
```

### Window（視窗）

要使用 RMA，先建立一個「視窗（window）」，讓其他 process 可以存取這塊記憶體：

```c
double* win_data;
MPI_Win win;

// 配置一塊記憶體並建立 window
MPI_Win_allocate(
    size * sizeof(double),  // 每個 process 貢獻的記憶體大小
    sizeof(double),         // displacement unit
    MPI_INFO_NULL,
    MPI_COMM_WORLD,
    &win_data,              // 指向這個 process 的 window 記憶體
    &win
);
```

或者用現有的記憶體建立 window：

```c
double local_buf[100];
MPI_Win win;
MPI_Win_create(
    local_buf,              // 這個 process 貢獻的記憶體
    100 * sizeof(double),   // 大小（bytes）
    sizeof(double),         // displacement unit
    MPI_INFO_NULL,
    MPI_COMM_WORLD,
    &win
);
```

### MPI_Put 和 MPI_Get

```c
// MPI_Put：把本地資料寫到遠端記憶體
MPI_Put(
    &local_data,    // 本地資料的位址
    1,              // 資料量
    MPI_DOUBLE,     // 資料型別
    target_rank,    // 目標 process 的 rank
    0,              // 目標 process window 內的偏移量
    1,              // 目標資料量
    MPI_DOUBLE,     // 目標資料型別
    win             // window
);

// MPI_Get：從遠端記憶體讀資料到本地
MPI_Get(
    &local_buf,     // 本地接收緩衝區
    1,
    MPI_DOUBLE,
    source_rank,    // 來源 process 的 rank
    0,              // 來源 window 內的偏移量
    1,
    MPI_DOUBLE,
    win
);
```

### MPI_Win_fence（圍欄同步）

RMA 操作需要同步機制，確保所有 Put/Get 都完成：

```c
MPI_Win_fence(0, win);  // 開始 RMA epoch（同步點）

// 在這裡做 MPI_Put, MPI_Get 操作

MPI_Win_fence(0, win);  // 結束 RMA epoch（確保所有操作完成）
```

`MPI_Win_fence` 是一個集體操作，所有 process 都要呼叫，類似 `MPI_Barrier`，但專用於 RMA。

### 完整 RMA 範例

```c
// 用 RMA 讓所有 process 收集彼此的 local_value
int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    double* window_mem;
    MPI_Win win;

    // 每個 process 的 window 大小：size 個 double（存放所有人的值）
    MPI_Win_allocate(size * sizeof(double), sizeof(double),
                     MPI_INFO_NULL, MPI_COMM_WORLD, &window_mem, &win);

    // 初始化自己的 window 記憶體
    for (int i = 0; i < size; i++) window_mem[i] = 0.0;

    double my_value = rank * 1.5;  // 每個 process 的本地值

    MPI_Win_fence(0, win);  // 開始 epoch

    // 每個 process 把自己的值寫到所有 process 的 window
    for (int target = 0; target < size; target++) {
        MPI_Put(&my_value, 1, MPI_DOUBLE,
                target, rank, 1, MPI_DOUBLE, win);
        // 把 my_value 寫到 target process 的 window[rank]
    }

    MPI_Win_fence(0, win);  // 結束 epoch，確保所有 Put 完成

    // 現在 window_mem[i] = process i 的值
    printf("Rank %d: values = ", rank);
    for (int i = 0; i < size; i++) printf("%.1f ", window_mem[i]);
    printf("\n");

    MPI_Win_free(&win);
    MPI_Finalize();
    return 0;
}
```

---

## 8. MPI + Monte Carlo π 的各種實作方式

Monte Carlo 估算 π 是 MPI 入門的經典問題，可以用多種通訊模式實作。

### 問題回顧

在 1×1 正方形內隨機撒 N 個點，落在四分之一圓內的比例 ≈ π/4。

每個 process 隨機撒 N/size 個點，計算局部命中數，最後合併結果。

### 方式一：使用 MPI_Reduce

最簡潔的版本：

```c
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    long total_points = 10000000L;
    long local_points = total_points / size;

    // 用 rank 當 seed，確保不同 process 有不同亂數
    unsigned int seed = rank * 12345 + 67890;
    long local_count = 0;

    for (long i = 0; i < local_points; i++) {
        double x = (double)rand_r(&seed) / RAND_MAX;
        double y = (double)rand_r(&seed) / RAND_MAX;
        if (x*x + y*y <= 1.0) local_count++;
    }

    // 所有 process 的 local_count 加總到 rank 0 的 global_count
    long global_count;
    MPI_Reduce(&local_count, &global_count, 1, MPI_LONG, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        double pi = 4.0 * global_count / total_points;
        printf("π ≈ %.6f\n", pi);
    }

    MPI_Finalize();
    return 0;
}
```

### 方式二：使用 Blocking Send/Recv（線性收集）

Worker 把結果傳給 rank 0，rank 0 逐一接收：

```c
if (rank == 0) {
    long global_count = local_count;
    for (int i = 1; i < size; i++) {
        long recv_count;
        MPI_Recv(&recv_count, 1, MPI_LONG, i, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        global_count += recv_count;
    }
    double pi = 4.0 * global_count / total_points;
    printf("π ≈ %.6f\n", pi);
} else {
    MPI_Send(&local_count, 1, MPI_LONG, 0, 0, MPI_COMM_WORLD);
}
```

### 方式三：使用 Non-blocking Send/Recv

Rank 0 先發出所有 Irecv，同時 workers 計算完後 Isend：

```c
if (rank == 0) {
    long recv_counts[MAX_SIZE];
    MPI_Request reqs[MAX_SIZE];

    // 先發出所有接收請求
    for (int i = 1; i < size; i++) {
        MPI_Irecv(&recv_counts[i], 1, MPI_LONG, i, 0, MPI_COMM_WORLD, &reqs[i]);
    }

    // 等待所有接收完成
    for (int i = 1; i < size; i++) {
        MPI_Wait(&reqs[i], MPI_STATUS_IGNORE);
    }

    long global_count = local_count;
    for (int i = 1; i < size; i++) global_count += recv_counts[i];
    printf("π ≈ %.6f\n", 4.0 * global_count / total_points);
} else {
    MPI_Request req;
    MPI_Isend(&local_count, 1, MPI_LONG, 0, 0, MPI_COMM_WORLD, &req);
    MPI_Wait(&req, MPI_STATUS_IGNORE);
}
```

### 方式四：手動 Tree Reduction

展示 tree-based 的實作原理（通常不需要手動實作，MPI_Reduce 自動做了）：

```c
// Tree reduction：步驟 log₂(size)
long value = local_count;
for (int step = 1; step < size; step *= 2) {
    if (rank % (2 * step) == 0) {
        // 我是這一輪的接收者
        if (rank + step < size) {
            long recv_val;
            MPI_Recv(&recv_val, 1, MPI_LONG, rank + step, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
            value += recv_val;
        }
    } else if (rank % step == 0) {
        // 我是這一輪的傳送者
        MPI_Send(&value, 1, MPI_LONG, rank - step, 0, MPI_COMM_WORLD);
        break;  // 送出後退出（不再參與後續 round）
    }
}

if (rank == 0) {
    printf("π ≈ %.6f\n", 4.0 * value / total_points);
}
```

### 方式五：MPI_Gather 收集所有結果

```c
long all_counts[MAX_SIZE];
MPI_Gather(&local_count, 1, MPI_LONG,
           all_counts,   1, MPI_LONG, 0, MPI_COMM_WORLD);

if (rank == 0) {
    long global_count = 0;
    for (int i = 0; i < size; i++) global_count += all_counts[i];
    printf("π ≈ %.6f\n", 4.0 * global_count / total_points);
}
```

### 方式比較

| 方法 | 通訊步驟 | 程式複雜度 | 適用場景 |
|------|---------|-----------|---------|
| MPI_Reduce | O(log N) 內部 | 最簡單 | 推薦，通常最快 |
| Blocking Send/Recv | O(N) | 簡單 | 學習用 |
| Non-blocking | O(N)，可重疊 | 中等 | 可與計算重疊 |
| Tree（手動） | O(log N) | 複雜 | 理解 Reduce 原理 |
| Gather | 類似 Reduce | 簡單 | 需要所有資料時 |

---

## 9. Deadlock 常見原因

Deadlock 是 MPI 程式設計中最常見的 bug，程式會永遠卡住不動。

### 原因一：Send/Recv 配對錯誤

```c
// 危險！所有 process 都先 Send，沒有人先 Recv
// MPI_Send 可能會等到有人接收才返回（取決於訊息大小和 MPI 實作）
if (rank == 0) {
    MPI_Send(&data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);  // 等 rank 1 recv
    MPI_Recv(&data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
} else if (rank == 1) {
    MPI_Send(&data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD);  // 等 rank 0 recv
    MPI_Recv(&data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
}
// Rank 0 等 rank 1 接收，rank 1 等 rank 0 接收 → 死鎖！
```

**解法一**：讓一方先 Recv：
```c
if (rank == 0) {
    MPI_Send(&data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);
    MPI_Recv(&data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
} else if (rank == 1) {
    MPI_Recv(&data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);  // 先 Recv
    MPI_Send(&data, 1, MPI_INT, 0, 0, MPI_COMM_WORLD);
}
```

**解法二**：用 MPI_Sendrecv（安全地同時傳送和接收）：
```c
MPI_Sendrecv(
    &send_data, 1, MPI_INT, dest,   tag,
    &recv_data, 1, MPI_INT, source, tag,
    MPI_COMM_WORLD, MPI_STATUS_IGNORE
);
```

**解法三**：用 Non-blocking 通訊：
```c
MPI_Request reqs[2];
MPI_Isend(&send_data, 1, MPI_INT, dest,   tag, MPI_COMM_WORLD, &reqs[0]);
MPI_Irecv(&recv_data, 1, MPI_INT, source, tag, MPI_COMM_WORLD, &reqs[1]);
MPI_Waitall(2, reqs, MPI_STATUSES_IGNORE);  // 兩個同時進行，不死鎖
```

### 原因二：Collective 操作不是所有 process 都呼叫

```c
// 危險！只有部分 process 呼叫 MPI_Barrier
if (rank == 0) {
    MPI_Barrier(MPI_COMM_WORLD);  // rank 0 呼叫了
}
// rank 1, 2, 3 沒有呼叫 MPI_Barrier → 死鎖！
```

**規則**：Collective operations（MPI_Bcast, MPI_Reduce, MPI_Barrier 等）必須被 communicator 內**所有** process 呼叫，順序也要一致。

### 原因三：Tag 不匹配

```c
// Rank 0 傳 tag=0，rank 1 等 tag=1 → 永遠等不到
if (rank == 0) MPI_Send(&data, 1, MPI_INT, 1, 0, MPI_COMM_WORLD);
if (rank == 1) MPI_Recv(&data, 1, MPI_INT, 0, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
//                                                 ↑ tag=1，但 rank 0 傳的是 tag=0
```

**解法**：仔細對照 Send 和 Recv 的 tag 和 source/dest，或用 `MPI_ANY_TAG` / `MPI_ANY_SOURCE`。

---

## 10. 如何用 mpirun 跑程式

### 基本用法

```bash
# 編譯
mpicc -O2 -o myprogram myprogram.c
# 或 C++
mpicxx -O2 -std=c++11 -o myprogram myprogram.cpp

# 執行（在本機上啟動 4 個 process）
mpirun -n 4 ./myprogram
# 或
mpiexec -n 4 ./myprogram
```

### 在多台機器上執行

```bash
# 指定機器列表（machinefile）
mpirun -n 8 --hostfile machines.txt ./myprogram

# machines.txt 的格式：
# node01 slots=4   ← node01 上跑 4 個 process
# node02 slots=4   ← node02 上跑 4 個 process
```

### 常用選項

```bash
# 指定每個 process 綁定到特定 CPU（提高效能）
mpirun -n 4 --bind-to core ./myprogram

# 顯示 process 的排列方式
mpirun -n 4 --report-bindings ./myprogram

# 設定環境變數給所有 process
mpirun -n 4 -x MY_VAR=value ./myprogram

# 傳入命令列參數
mpirun -n 4 ./myprogram 1000000 100
```

### OpenMPI vs MPICH

兩個常見的 MPI 實作：

| | OpenMPI | MPICH |
|-|---------|-------|
| 編譯命令 | `mpicc`, `mpicxx` | `mpicc`, `mpicxx` |
| 執行命令 | `mpirun` | `mpirun` 或 `mpiexec` |
| 查詢版本 | `mpirun --version` | `mpirun --version` |
| 特色 | 功能豐富，支援多種網路 | 輕量，相容性好 |

查詢你使用的是哪個：
```bash
mpicc --version
# 或
ompi_info | head  # OpenMPI 有這個指令
```

### 測量 MPI 程式效能

```bash
# 簡單計時
time mpirun -n 4 ./myprogram

# 用程式內部計時（更精確）
# 程式碼中：
double start = MPI_Wtime();
// ... 計算 ...
double elapsed = MPI_Wtime() - start;

// 取所有 process 中最慢的（代表整體完成時間）
double max_elapsed;
MPI_Reduce(&elapsed, &max_elapsed, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
if (rank == 0) printf("Total time: %f seconds\n", max_elapsed);
```

### 在 NYCU CSCC 叢集上執行（如果有的話）

```bash
# 用 SLURM 提交 job
sbatch job.sh

# job.sh 範例：
#!/bin/bash
#SBATCH --nodes=2          # 使用 2 個 node
#SBATCH --ntasks-per-node=4 # 每個 node 4 個 process
#SBATCH --time=00:05:00    # 最長執行時間

module load openmpi/4.0
mpirun -n 8 ./myprogram
```

---

## 總結

| 概念 | 關鍵點 |
|------|--------|
| 分散式記憶體 | 每個 process 有獨立記憶體，必須明確通訊 |
| Rank / Communicator | rank 識別 process 身份，MPI_COMM_WORLD 包含所有人 |
| MPI_Send / MPI_Recv | Blocking P2P 通訊，要注意配對順序 |
| MPI_Isend / MPI_Irecv | Non-blocking，可以重疊計算與通訊 |
| MPI_Reduce / MPI_Allreduce | 集體歸約，底層用 tree-based 演算法，效率高 |
| MPI_Bcast / Gather / Scatter | 常見的資料分發/收集模式 |
| RMA (MPI_Put / MPI_Get) | 單側存取遠端記憶體，適合不規則通訊模式 |
| Deadlock | Send/Recv 沒有配對、collective 沒全員呼叫 |
| mpirun | `-n` 指定 process 數，`--hostfile` 指定機器 |

MPI 是 HPC（High Performance Computing）的核心工具，掌握了本課的概念後，你就具備了設計和分析分散式平行程式的基礎能力，可以進一步探索 MPI+OpenMP 混合程式設計、MPI IO，甚至更現代的分散式框架。
