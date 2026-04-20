# HW4 教學：CUDA GPU 程式設計

## 目錄
1. [為什麼用 GPU？](#1-為什麼用-gpu)
2. [CUDA 基本概念](#2-cuda-基本概念)
3. [CUDA Memory Hierarchy](#3-cuda-memory-hierarchy)
4. [如何寫第一個 Kernel](#4-如何寫第一個-kernel)
5. [Memory Coalescing](#5-memory-coalescing)
6. [Shared Memory 與 Tiling](#6-shared-memory-與-tiling)
7. [CUDA Mandelbrot 實作思路](#7-cuda-mandelbrot-實作思路)
8. [常見效能問題](#8-常見效能問題)
9. [cudaMalloc / cudaMemcpy / cudaFree](#9-cudamalloc--cudamemcpy--cudafree)
10. [如何 Debug CUDA 程式](#10-如何-debug-cuda-程式)

---

## 1. 為什麼用 GPU？

### GPU vs CPU 架構對比

CPU 和 GPU 的設計哲學完全不同：

| 特性 | CPU | GPU |
|------|-----|-----|
| 設計目標 | 降低單一執行緒延遲 | 最大化平行吞吐量 |
| 核心數 | 少（4~64 核） | 多（數千個 CUDA core） |
| 時脈頻率 | 高（3~5 GHz） | 較低（~2 GHz） |
| Cache | 大（MB 級） | 小（KB 級 per SM） |
| 記憶體頻寬 | 較低（~100 GB/s） | 高（~1 TB/s） |
| 分支預測 | 強（複雜 OOO 執行） | 弱（SIMT 模型） |

### 視覺化比較

```
CPU（大核心設計）：
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│Core 0│ │Core 1│ │Core 2│ │Core 3│  ← 4 個強大核心，各有大 cache
│ ALU  │ │ ALU  │ │ ALU  │ │ ALU  │
│ OOO  │ │ OOO  │ │ OOO  │ │ OOO  │
└──────┘ └──────┘ └──────┘ └──────┘
          大型共享 L3 Cache (MB)

GPU（小核心設計，數量取勝）：
┌─────────────────────────────────────────────────┐
│  SM0  │  SM1  │  SM2  │ ... │  SM79  │  SM80  │  ← 80+ 個 SM
│ 128 cores  128 cores  ...  128 cores           │
│ 每個 SM 有小型 shared memory 和 L1 cache        │
└─────────────────────────────────────────────────┘
    大型 Global Memory（VRAM）連接所有 SM
```

### 什麼情況適合用 GPU？

- **大量相同計算**：同樣的操作要對大量資料執行（如矩陣乘法）
- **資料平行**：不同資料點可以完全獨立計算
- **計算密集**：計算量遠大於記憶體存取量

不適合 GPU 的情況：
- 複雜的分支邏輯（if-else 很多）
- 資料有依賴性（每次計算需要前一次的結果）
- 資料量小（GPU 啟動開銷不划算）

---

## 2. CUDA 基本概念

### Thread, Block, Grid 三層結構

CUDA 採用三層執行結構：

```
Grid（整個 kernel 的執行空間）
├── Block 0       Block 1       Block 2    ...
│   ├── Thread 0  Thread 0      Thread 0
│   ├── Thread 1  Thread 1      Thread 1
│   ├── Thread 2  Thread 2      Thread 2
│   └── ...       ...           ...
└── （Block 之間互相獨立）
```

- **Thread**：最小的執行單元，對應一個 CUDA core
- **Block**：一組 thread，同一 block 的 thread 共享 shared memory，可以同步（`__syncthreads()`）
- **Grid**：所有 block 的集合，構成一個 kernel 的完整執行

### 內建變數

每個 thread 都有一組內建變數，用來知道自己是誰：

```cuda
threadIdx.x   // 在 block 內的 thread 編號（0 ~ blockDim.x - 1）
blockIdx.x    // 在 grid 內的 block 編號（0 ~ gridDim.x - 1）
blockDim.x    // 每個 block 有多少 thread
gridDim.x     // grid 有多少個 block
```

也支援 y、z 維度（2D/3D grid），例如 `threadIdx.y`, `blockIdx.y`。

### 計算全域索引

最常見的模式：計算這個 thread 負責哪個陣列元素：

```cuda
int idx = blockIdx.x * blockDim.x + threadIdx.x;
```

圖示：
```
blockDim.x = 4
Block 0: [T0, T1, T2, T3] → idx = [0, 1, 2, 3]
Block 1: [T0, T1, T2, T3] → idx = [4, 5, 6, 7]
Block 2: [T0, T1, T2, T3] → idx = [8, 9, 10, 11]
```

### 2D 索引（圖像處理常用）

```cuda
// 2D 網格，每個 thread 處理一個像素
int row = blockIdx.y * blockDim.y + threadIdx.y;
int col = blockIdx.x * blockDim.x + threadIdx.x;

if (row < height && col < width) {
    int pixel_idx = row * width + col;
    output[pixel_idx] = process(input[pixel_idx]);
}
```

### Block 大小的選擇

Block 大小（threads per block）通常是 32 的倍數（因為 GPU 以 32 個 thread 為一組執行，稱為 **Warp**）：

常見選擇：
- 1D kernel：128 或 256
- 2D kernel：16×16 = 256 或 32×32 = 1024

每個 block 最多 1024 個 thread（大多數現代 GPU）。

---

## 3. CUDA Memory Hierarchy

理解 GPU 的記憶體層次是優化的關鍵。

### 記憶體類型總覽

```
速度（快→慢）     大小（小→大）      scope
Registers ──────── 幾十個/thread ──── 單一 thread
Shared Memory ─── 數十 KB/SM ──────── 同一 Block 的 threads
L1 Cache ──────── 數十 KB/SM ──────── 同一 SM（自動管理）
L2 Cache ──────── 數 MB ─────────────── 整個 GPU
Global Memory ─── GB 級（VRAM） ────── 整個 GPU + Host 可見
Constant Memory ─ 64 KB ─────────────── 整個 GPU（唯讀，cached）
Texture Memory ─── 唯讀，有 cache ──── 整個 GPU（有特殊存取模式）
```

### Global Memory（最重要但最慢）

- GPU 的主要記憶體（VRAM），容量最大（數 GB）
- 延遲最高（數百個 clock cycles）
- 所有 SM 都可以存取
- `cudaMalloc` 配置的記憶體就在這裡

```cuda
__global__ void kernel(float* global_array) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    global_array[idx] *= 2.0f;  // 存取 global memory（慢）
}
```

### Shared Memory（快，但有限）

- 位於 SM 內部，速度接近 registers
- 同一 block 的所有 thread 共享
- 用 `__shared__` 宣告
- 生命週期：只在 kernel 執行期間存在

```cuda
__global__ void useSharedMem(float* input, float* output, int N) {
    __shared__ float tile[256];  // 256 個 float 的 shared memory

    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) {
        tile[threadIdx.x] = input[idx];  // 從 global 載入到 shared
    }
    __syncthreads();  // 等待所有 thread 都載入完畢

    // 現在可以快速存取 tile[]，不用碰 global memory
    if (idx < N) {
        output[idx] = tile[threadIdx.x] * 2.0f;
    }
}
```

### Registers（最快）

- 每個 thread 私有的暫存器
- kernel 中宣告的 local variable 通常存在 registers
- 數量有限（每個 SM 通常 64K 個 32-bit registers）
- 若 register 不夠用，會 spill 到 local memory（實際上是 global memory，很慢）

```cuda
__global__ void kernel(float* data) {
    float local_val = data[threadIdx.x];  // 存在 register（最快）
    local_val = local_val * local_val + local_val;
    data[threadIdx.x] = local_val;
}
```

### Constant Memory

- 64KB，唯讀，有 cache
- 適合所有 thread 都讀同樣資料（broadcast 效率高）

```cuda
__constant__ float filter[64];  // 在 global scope 宣告

// Host 端寫入
cudaMemcpyToSymbol(filter, host_filter, sizeof(host_filter));

// Kernel 中讀取（自動 cached）
__global__ void applyFilter(float* data) {
    float val = data[threadIdx.x] * filter[threadIdx.x];
    // filter 的存取很快，因為 constant cache
}
```

---

## 4. 如何寫第一個 Kernel

### 函式修飾符

```cuda
__global__ void kernel(...)   // 在 GPU 上執行，由 CPU 呼叫
__device__ float helper(...)  // 在 GPU 上執行，只能由 GPU 呼叫
__host__   void cpuFunc(...)  // 在 CPU 上執行（預設，可省略）
__host__ __device__ float bothFunc(...)  // CPU 和 GPU 都可以呼叫
```

### Kernel Launch 語法

```cuda
kernel<<<gridDim, blockDim>>>(args...);
//      ↑ grid 有幾個 block  ↑ 每個 block 有幾個 thread
```

可以用整數（1D）或 `dim3`（多維）：

```cuda
// 1D
int N = 1024;
int blockSize = 256;
int gridSize = (N + blockSize - 1) / blockSize;  // ceil division
addKernel<<<gridSize, blockSize>>>(a, b, c, N);

// 2D（圖像處理）
dim3 blockDim(16, 16);          // 16×16 = 256 threads per block
dim3 gridDim((W+15)/16, (H+15)/16);  // 足夠覆蓋整個圖像
imageKernel<<<gridDim, blockDim>>>(image, W, H);
```

### 向量加法完整範例

```cuda
#include <cuda_runtime.h>
#include <stdio.h>

// GPU kernel
__global__ void addVectors(float* a, float* b, float* c, int N) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) {  // 邊界檢查很重要！
        c[idx] = a[idx] + b[idx];
    }
}

int main() {
    int N = 1 << 20;  // 1M 個元素
    size_t size = N * sizeof(float);

    // 配置 Host 記憶體
    float *h_a = (float*)malloc(size);
    float *h_b = (float*)malloc(size);
    float *h_c = (float*)malloc(size);

    // 初始化資料
    for (int i = 0; i < N; i++) {
        h_a[i] = 1.0f;
        h_b[i] = 2.0f;
    }

    // 配置 GPU 記憶體
    float *d_a, *d_b, *d_c;
    cudaMalloc(&d_a, size);
    cudaMalloc(&d_b, size);
    cudaMalloc(&d_c, size);

    // 複製資料到 GPU
    cudaMemcpy(d_a, h_a, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, h_b, size, cudaMemcpyHostToDevice);

    // 啟動 kernel
    int blockSize = 256;
    int gridSize = (N + blockSize - 1) / blockSize;
    addVectors<<<gridSize, blockSize>>>(d_a, d_b, d_c, N);

    // 等待 GPU 完成（kernel 是非同步的！）
    cudaDeviceSynchronize();

    // 複製結果回 CPU
    cudaMemcpy(h_c, d_c, size, cudaMemcpyDeviceToHost);

    // 驗證
    printf("c[0] = %f (expected 3.0)\n", h_c[0]);

    // 釋放記憶體
    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_c);
    free(h_a);
    free(h_b);
    free(h_c);

    return 0;
}
```

編譯：
```bash
nvcc -O2 -o vectorAdd vectorAdd.cu
./vectorAdd
```

---

## 5. Memory Coalescing

Memory coalescing 是 CUDA 效能優化中最重要的概念之一。

### 什麼是 Coalescing？

GPU global memory 的存取以 **transaction** 為單位（通常 128 bytes = 32 個 float）。一個 Warp（32 個 thread）同時發出記憶體請求時，如果存取的位址是連續且對齊的，就可以合併成少數幾個 transaction（**coalesced**）；否則需要多個 transaction（**uncoalesced**），效率很差。

### Coalesced vs Uncoalesced

```cuda
// Coalesced（好）：thread i 存取 data[i]，記憶體位址連續
__global__ void coalesced(float* data, int N) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) data[idx] *= 2.0f;  // Thread 0→data[0], Thread 1→data[1], ...
}
// Warp 的 32 個 thread 存取 data[0..31]，一次 transaction 搞定

// Uncoalesced（差）：thread i 存取 data[i * stride]，有間隙
__global__ void strided(float* data, int N, int stride) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) data[idx * stride] *= 2.0f;
}
// stride=32 時：Thread 0→data[0], Thread 1→data[32], Thread 2→data[64]...
// 需要 32 個獨立 transaction，慢 32 倍！
```

### 視覺化

```
Coalesced：
Thread:  0    1    2    3    4    5  ...  31
Address: [0]  [1]  [2]  [3]  [4]  [5] ... [31]
         ←────── 一個 cache line transaction ──────→

Uncoalesced（stride=4）：
Thread:  0     1     2     3     4  ...  31
Address: [0]   [4]   [8]   [12]  [16] ... [124]
         需要多個 transaction，記憶體頻寬大量浪費
```

### 結構體的 Coalescing 問題

```cuda
// AoS（Array of Structures）- 不利於 coalescing
struct Particle {
    float x, y, z;   // 12 bytes
    float vx, vy, vz; // 12 bytes
};
Particle particles[N];

// Thread i 存取 particles[i].x：
// Thread 0: particles[0].x（偏移 0）
// Thread 1: particles[1].x（偏移 12）← 不連續！

// SoA（Structure of Arrays）- 有利於 coalescing
float* px = /* ... */;  // 所有粒子的 x 座標
float* py = /* ... */;  // 所有粒子的 y 座標
// Thread i 存取 px[i]：連續！coalesced！
```

---

## 6. Shared Memory 與 Tiling

Shared memory 是 GPU 效能優化的核心技術，通過「分塊（tiling）」減少對 global memory 的存取。

### Tiling 的概念

以矩陣乘法為例（C = A × B）：

**不用 shared memory 的版本**：計算 C[row][col] 需要讀整行 A 和整列 B，大量 global memory 存取。

```cuda
// 沒有 tiling，每次都從 global memory 讀
__global__ void matmul_naive(float* A, float* B, float* C, int N) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < N && col < N) {
        float sum = 0.0f;
        for (int k = 0; k < N; k++) {
            sum += A[row * N + k] * B[k * N + col];  // 每次都是 global memory！
        }
        C[row * N + col] = sum;
    }
}
```

**用 shared memory tiling 的版本**：

```cuda
#define TILE_SIZE 16

__global__ void matmul_tiled(float* A, float* B, float* C, int N) {
    __shared__ float As[TILE_SIZE][TILE_SIZE];  // shared memory tile for A
    __shared__ float Bs[TILE_SIZE][TILE_SIZE];  // shared memory tile for B

    int row = blockIdx.y * TILE_SIZE + threadIdx.y;
    int col = blockIdx.x * TILE_SIZE + threadIdx.x;
    float sum = 0.0f;

    // 分 N/TILE_SIZE 個 tile 計算
    for (int t = 0; t < N / TILE_SIZE; t++) {
        // 協力載入 tile（每個 thread 載入一個元素）
        As[threadIdx.y][threadIdx.x] = A[row * N + (t * TILE_SIZE + threadIdx.x)];
        Bs[threadIdx.y][threadIdx.x] = B[(t * TILE_SIZE + threadIdx.y) * N + col];

        __syncthreads();  // 確保所有 thread 都載入完畢

        // 用 shared memory 計算這個 tile 的貢獻
        for (int k = 0; k < TILE_SIZE; k++) {
            sum += As[threadIdx.y][k] * Bs[k][threadIdx.x];  // shared memory 快！
        }

        __syncthreads();  // 確保用完 shared memory 後才繼續下一個 tile
    }

    C[row * N + col] = sum;
}
```

**效能改善原因**：
- 每個 tile 的資料從 global memory 載入一次，block 內 TILE_SIZE 個 thread 共用
- 等於把 global memory 存取次數減少了 TILE_SIZE 倍（16 倍！）
- Shared memory 的延遲比 global memory 低 100 倍以上

### `__syncthreads()`

非常重要的同步機制：等待同一 block 內所有 thread 到達這個點。

```cuda
// 正確使用方式：
__shared__ float tile[256];
tile[threadIdx.x] = global_data[idx];  // 各 thread 載入資料
__syncthreads();                        // 確保所有資料都載入
float val = tile[(threadIdx.x + 1) % 256];  // 讀取鄰居的資料（安全）

// 錯誤使用：不能在條件分支中
if (threadIdx.x < 128) {
    __syncthreads();  // 危險！可能造成 deadlock
}
```

---

## 7. CUDA Mandelbrot 實作思路

### 問題映射

Mandelbrot 圖像的每個像素（row, col）對應一個複數 c，彼此**完全獨立**，非常適合 GPU 平行化。

每個 thread 負責一個像素：

```
Thread (0,0) → 像素 (0,0) → 複數 c₀₀
Thread (0,1) → 像素 (0,1) → 複數 c₀₁
...
Thread (i,j) → 像素 (i,j) → 複數 cᵢⱼ
```

### Kernel 設計

```cuda
__global__ void mandelbrot_kernel(int* output, int width, int height,
                                   float xmin, float xmax, float ymin, float ymax,
                                   int max_iter) {
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    int row = blockIdx.y * blockDim.y + threadIdx.y;

    if (col >= width || row >= height) return;

    // 像素座標 → 複數平面座標
    float cx = xmin + col * (xmax - xmin) / width;
    float cy = ymin + row * (ymax - ymin) / height;

    // 計算 Mandelbrot 迭代次數
    float zx = 0.0f, zy = 0.0f;
    int iter = 0;
    while (iter < max_iter && zx*zx + zy*zy < 4.0f) {
        float new_zx = zx*zx - zy*zy + cx;
        zy = 2.0f * zx * zy + cy;
        zx = new_zx;
        iter++;
    }

    output[row * width + col] = iter;
}

// Host 端呼叫
void computeMandelbrot(int* h_output, int W, int H, int max_iter) {
    int* d_output;
    cudaMalloc(&d_output, W * H * sizeof(int));

    dim3 block(16, 16);
    dim3 grid((W + 15) / 16, (H + 15) / 16);
    mandelbrot_kernel<<<grid, block>>>(d_output, W, H,
                                        -2.5f, 1.0f, -1.25f, 1.25f, max_iter);
    cudaDeviceSynchronize();

    cudaMemcpy(h_output, d_output, W * H * sizeof(int), cudaMemcpyDeviceToHost);
    cudaFree(d_output);
}
```

### 多版本優化比較

| 版本 | 優化 | 說明 |
|------|------|------|
| V1 Naive | 無 | 直接計算，基準效能 |
| V2 Coalesced | Memory 存取改善 | 確保 thread 存取連續記憶體 |
| V3 Shared Mem | 如果有共用資料 | Mandelbrot 通常沒太多可共享的 |
| V4 調整 Block 大小 | 改變 blockDim | 實驗找最佳 block size |

---

## 8. 常見效能問題

### Warp Divergence（Warp 分歧）

一個 Warp 的 32 個 thread 必須執行同樣的指令。如果有 `if-else`，不同 thread 走不同路徑，GPU 必須把兩條路都執行，效率減半。

```cuda
// 壞：Warp 內的 thread 走不同路徑
__global__ void badKernel(int* data, int N) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (data[idx] > 0) {
        // 一半 thread 走這條路
        data[idx] = sqrt((float)data[idx]);
    } else {
        // 另一半 thread 走這條路
        data[idx] = -data[idx];
    }
    // 實際上兩條路都執行，慢的那條決定整體時間
}
```

Mandelbrot 的 warp divergence 問題：
- 集合內部的像素：達到 max_iter 才停
- 集合外部的像素：幾次就停
- 同一個 warp 的像素如果有內有外，就會分歧

**解決方向**：把工作量相似的像素分到同一個 block（難），或接受這個 overhead。

### Bank Conflict（記憶體庫衝突）

Shared memory 被分成 32 個 **bank**（對應 warp 大小）。如果同一個 warp 的多個 thread 存取同一個 bank（但不是同一個位址），就會產生序列化存取，效能下降。

```cuda
__shared__ float tile[32][32];

// 無 bank conflict（每個 thread 存取不同 bank）：
float val = tile[threadIdx.y][threadIdx.x];  // threadIdx.x 決定 bank

// 有 bank conflict（stride = 32）：
float val = tile[threadIdx.x][0];  // 所有 thread 存取同一個 column！
// 所有 thread 都在 bank 0，序列化存取！
```

**避免方法**：
- 設計存取模式讓不同 thread 在不同 bank
- 有時可以在 shared memory 加 padding（+1 column）

```cuda
__shared__ float tile[32][33];  // 多一列 padding，避免 bank conflict
```

### Host-Device 資料傳輸瓶頸

PCIe 頻寬（~32 GB/s）遠低於 GPU 記憶體頻寬（~1 TB/s）。頻繁的 CPU↔GPU 資料傳輸是常見的效能瓶頸。

**策略**：
1. **批次傳輸**：一次傳大量資料，不要多次傳小資料
2. **重疊計算與傳輸**：用 CUDA streams 讓 GPU 計算的同時 CPU 準備下一批資料
3. **盡量讓資料留在 GPU**：如果有多個連續的 kernel，不要每次都傳回 CPU

```cuda
// 用 CUDA streams 重疊傳輸與計算
cudaStream_t stream1, stream2;
cudaStreamCreate(&stream1);
cudaStreamCreate(&stream2);

// Stream 1：傳輸 batch 1，計算 batch 0
cudaMemcpyAsync(d_batch1, h_batch1, size, cudaMemcpyHostToDevice, stream1);
kernel<<<grid, block, 0, stream2>>>(d_batch0, result0);

cudaStreamSynchronize(stream1);
cudaStreamSynchronize(stream2);
```

### Occupancy（佔用率）

Occupancy = 實際執行的 warp 數 / SM 最大可執行的 warp 數

高 occupancy 讓 GPU 可以在等待記憶體時切換到其他 warp 執行（隱藏延遲）。

影響 occupancy 的因素：
- Block 大小（太小→ SM 上的 block 數有限制）
- Register 用量（register 越多，每個 SM 能同時執行的 thread 越少）
- Shared memory 用量（shared memory 越多，SM 上能同時執行的 block 越少）

```bash
# 用 nvcc 的 occupancy calculator 或 Nsight 工具分析
nvcc --ptxas-options=-v kernel.cu  # 顯示 register 和 shared memory 用量
```

---

## 9. cudaMalloc / cudaMemcpy / cudaFree

### 基本 API

```cuda
// 配置 GPU 記憶體
cudaError_t cudaMalloc(void** devPtr, size_t size);

// 複製資料
cudaError_t cudaMemcpy(void* dst, const void* src, size_t count,
                        cudaMemcpyKind kind);
// kind 可以是：
//   cudaMemcpyHostToDevice  (CPU → GPU)
//   cudaMemcpyDeviceToHost  (GPU → CPU)
//   cudaMemcpyDeviceToDevice (GPU 內部)

// 釋放 GPU 記憶體
cudaError_t cudaFree(void* devPtr);

// 等待 GPU 完成所有操作
cudaError_t cudaDeviceSynchronize();
```

### 錯誤處理

每個 CUDA API 都回傳 `cudaError_t`，應該要檢查：

```cuda
#define CUDA_CHECK(call) do { \
    cudaError_t err = (call); \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA Error at %s:%d: %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
        exit(EXIT_FAILURE); \
    } \
} while(0)

// 使用方式
CUDA_CHECK(cudaMalloc(&d_data, size));
CUDA_CHECK(cudaMemcpy(d_data, h_data, size, cudaMemcpyHostToDevice));

// Kernel 不直接回傳錯誤，要呼叫後檢查
myKernel<<<grid, block>>>(args);
CUDA_CHECK(cudaGetLastError());     // 檢查 kernel launch 是否成功
CUDA_CHECK(cudaDeviceSynchronize()); // 等待並檢查 kernel 執行
```

### cudaMemset

```cuda
// 把 GPU 記憶體初始化為特定值（類似 C 的 memset）
cudaMemset(d_array, 0, size);  // 清零
```

---

## 10. 如何 Debug CUDA 程式

### 常見錯誤類型

| 錯誤 | 可能原因 |
|------|---------|
| `cudaErrorIllegalAddress` | 存取越界（out-of-bounds）或 null pointer |
| `cudaErrorInvalidValue` | 傳入無效參數（如負數 blockDim） |
| `cudaErrorOutOfMemory` | GPU 記憶體不足 |
| `cudaErrorLaunchFailure` | Kernel 執行失敗（通常是 crash） |

### printf 在 Kernel 中使用

CUDA kernel 可以用 `printf`（但要謹慎，大量輸出會很慢）：

```cuda
__global__ void debugKernel(float* data, int N) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N && idx < 10) {  // 只印前 10 個，避免輸出太多
        printf("Thread %d: data[%d] = %f\n", idx, idx, data[idx]);
    }
}
```

### cuda-memcheck / compute-sanitizer

```bash
# 舊版（CUDA 10 以前）
cuda-memcheck ./program

# 新版（CUDA 11+）
compute-sanitizer ./program
compute-sanitizer --tool memcheck ./program    # 記憶體問題
compute-sanitizer --tool racecheck ./program  # Race condition
compute-sanitizer --tool synccheck ./program  # syncthreads 問題
```

### Nsight Systems / Nsight Compute

用於效能分析：

```bash
# Nsight Systems：系統層級 profiling（CPU+GPU 時間線）
nsys profile ./program

# Nsight Compute：Kernel 層級效能分析
ncu ./program
ncu --metrics l1tex__t_bytes_pipe_lsu_mem_global_op_ld.sum ./program
```

### 常見 Debug 技巧

1. **先在 CPU 上驗證演算法**：用純 CPU 版本確認邏輯正確，再移植到 GPU

2. **逐步擴大規模**：先測試小資料（N=10），確認正確後再測大資料

3. **對照 CPU 結果**：
```cuda
// 計算完後複製回 CPU 並對照
cudaMemcpy(h_gpu_result, d_result, size, cudaMemcpyDeviceToHost);
for (int i = 0; i < N; i++) {
    if (fabs(h_cpu_result[i] - h_gpu_result[i]) > 1e-5f) {
        printf("Mismatch at %d: CPU=%f, GPU=%f\n",
               i, h_cpu_result[i], h_gpu_result[i]);
    }
}
```

4. **確認邊界條件**：kernel 的 `if (idx < N)` 不能少

5. **確認 `__syncthreads()`**：使用 shared memory 後一定要 sync，否則資料可能還沒載入完就被使用

---

## 總結

| 概念 | 關鍵點 |
|------|--------|
| Thread/Block/Grid | 三層結構，計算 global index = blockIdx * blockDim + threadIdx |
| Global Memory | 大但慢，減少存取次數是優化核心 |
| Shared Memory | 快（比 global 快 ~100 倍），同 block 共享，用 tiling 技術 |
| Coalescing | Warp 內連續存取記憶體，大幅提升頻寬利用率 |
| Warp Divergence | 分支讓部分 thread 閒置，盡量讓 warp 內統一執行路徑 |
| cudaMemcpy | 傳輸是瓶頸，盡量批次、重疊、減少次數 |
| 錯誤處理 | 每個 CUDA call 都要檢查回傳值，用 compute-sanitizer 找 bug |

CUDA 程式設計的學習曲線較陡，但掌握了 thread 模型、記憶體層次和 coalescing 三個核心概念後，大部分的優化思路就會變得清晰。
