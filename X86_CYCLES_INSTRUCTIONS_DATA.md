# x86 架构 Ceph 存储性能数据 - Cycles & Instructions

**目的**: 为 RISC-V 架构性能预测提供 x86 基准数据

**测试环境**:
- CPU 架构: x86_64
- 内核版本: 6.14.0-37-generic
- Ceph 版本: 19.2.3 (squid)
- 测试时间: 30秒/场景

**⚠️ 重要说明 - 统计范围**:
- **统计节点**: 10.103.11.249 (客户端节点)
- **统计进程**: 
  - FIO 测试进程
  - CephFS FUSE 客户端进程 (ceph-fuse)
  - RBD 用户空间库 (librbd)
- **不包括**: Ceph 服务端进程 (OSD, MON, MDS) 的 CPU 消耗
- **含义**: 这些数据反映的是**客户端处理 I/O 请求的 CPU 开销**

**集群拓扑**:
```
客户端节点 (10.103.11.249) ← perf stat 统计这里
    ↓ 网络请求
服务端节点 (10.103.11.243, 244, 245) ← 未统计
    ├─ MON (监控)
    ├─ OSD (对象存储)
    └─ MDS (元数据服务器，仅 CephFS)
```

---

## 📌 快速理解

**这些数据告诉你什么**:
- 在 x86 客户端上，使用 CephFS 或 RBD 进行 I/O 操作时，客户端 CPU 执行了多少条指令、花费了多少个时钟周期
- 用于预测：如果把客户端换成 RISC-V，客户端 CPU 需要多少指令和周期

**这些数据不包括什么**:
- Ceph 存储服务端 (OSD/MON/MDS) 的 CPU 开销
- 网络传输时间
- 磁盘 I/O 时间

**示例场景**:
```
应用程序 (x86 客户端) 
  ↓ 
CephFS FUSE / RBD librbd ← 这里的 CPU 开销被统计
  ↓ 网络
Ceph 服务端 (OSD 等) ← 这里的 CPU 开销未统计
```

---

## 📊 核心数据表格

### CephFS FUSE 客户端

| 测试场景 | Cycles | Instructions | IPC | 备注 |
|---------|--------|--------------|-----|------|
| 随机写 4K | 2,252,432,968 | 2,016,745,041 | 0.90 | IOPS: 1,820 |
| 随机读 4K | 3,794,756,238 | 3,588,595,581 | 0.95 | IOPS: 1,162 |
| 顺序写 1M | 389,544,602 | 517,644,826 | 1.33 | BW: 7.09 MB/s |

### RBD librbd (用户空间库)

| 测试场景 | Cycles | Instructions | IPC | 备注 |
|---------|--------|--------------|-----|------|
| 随机写 4K | 3,042,960,620 | 2,366,207,550 | 0.78 | IOPS: 504 |
| 随机读 4K | 21,158,558,565 | 15,385,719,738 | 0.73 | IOPS: 3,698 |
| 顺序写 1M | 902,998,137 | 673,147,019 | 0.75 | BW: 12.1 MB/s |

### RBD NBD (块设备映射, 高并发)

| 测试场景 | Cycles | Instructions | IPC | 备注 |
|---------|--------|--------------|-----|------|
| 随机写 4K | 988,835,544 | 744,719,789 | 0.75 | IOPS: 124, numjobs=4, iodepth=32 |
| 随机读 4K | 77,019,449,021 | 68,504,676,411 | 0.89 | IOPS: 55.7k, numjobs=4, iodepth=32 |
| 顺序写 1M | 1,562,251,010 | 1,286,375,237 | 0.82 | BW: 9.9 MB/s, numjobs=2, iodepth=16 |
| 顺序读 1M | 24,665,939,592 | 33,801,888,089 | 1.37 | BW: 2.6 GB/s, numjobs=2, iodepth=16 |

---

## 📈 数据对比（x86 基准）

### 按测试场景对比

| 测试场景 | CephFS Cycles | CephFS Instr | RBD Cycles | RBD Instr | Cycles 比值 | Instr 比值 |
|---------|---------------|--------------|------------|-----------|------------|-----------|
| 随机写 4K | 2,252,432,968 | 2,016,745,041 | 3,042,960,620 | 2,366,207,550 | 1.35x | 1.17x |
| 随机读 4K | 3,794,756,238 | 3,588,595,581 | 21,158,558,565 | 15,385,719,738 | 5.57x | 4.29x |
| 顺序写 1M | 389,544,602 | 517,644,826 | 902,998,137 | 673,147,019 | 2.32x | 1.30x |

**说明**: 
- "比值" = RBD / CephFS
- RBD 随机读的 Cycles 和 Instructions 都明显高于 CephFS

### 按存储类型汇总

| 存储类型 | 平均 Cycles | 平均 Instructions | 平均 IPC | 测试配置 |
|---------|-------------|------------------|---------|---------|
| **CephFS FUSE** | 2,145,577,936 | 2,040,995,149 | 1.06 | numjobs=1, iodepth=4 |
| **RBD librbd** | 8,368,172,441 | 6,141,691,436 | 0.75 | numjobs=1, iodepth=4 |
| **RBD NBD** | 26,059,118,792 | 26,084,414,882 | 0.96 | numjobs=2-4, iodepth=16-32 |

**说明**: RBD NBD 使用高并发配置，Cycles 和 Instructions 数值较大属正常

---

## 🔢 原始数据（用于计算）

### CephFS FUSE - 随机写 4K
```
Cycles:        2,252,432,968
Instructions:  2,016,745,041
IPC:           0.90
测试时长:      30.44s
```

### CephFS FUSE - 随机读 4K
```
Cycles:        3,794,756,238
Instructions:  3,588,595,581
IPC:           0.95
测试时长:      122.93s
```

### CephFS FUSE - 顺序写 1M
```
Cycles:        389,544,602
Instructions:  517,644,826
IPC:           1.33
测试时长:      36.86s
```

### RBD librbd - 随机写 4K
```
Cycles:        3,042,960,620
Instructions:  2,366,207,550
IPC:           0.78
测试时长:      41.72s
```

### RBD librbd - 随机读 4K
```
Cycles:        21,158,558,565
Instructions:  15,385,719,738
IPC:           0.73
测试时长:      31.21s
```

### RBD librbd - 顺序写 1M
```
Cycles:        902,998,137
Instructions:  673,147,019
IPC:           0.75
测试时长:      33.31s
```

### RBD NBD - 随机写 4K (numjobs=4, iodepth=32)
```
Cycles:        988,835,544
Instructions:  744,719,789
IPC:           0.75
测试时长:      71.51s
IOPS:          124
带宽:          507 KB/s
```

### RBD NBD - 随机读 4K (numjobs=4, iodepth=32)
```
Cycles:        77,019,449,021
Instructions:  68,504,676,411
IPC:           0.89
测试时长:      70.31s
IOPS:          55,700
带宽:          217 MB/s
```

### RBD NBD - 顺序写 1M (numjobs=2, iodepth=16)
```
Cycles:        1,562,251,010
Instructions:  1,286,375,237
IPC:           0.82
测试时长:      73.96s
IOPS:          9
带宽:          9.88 MB/s
```

### RBD NBD - 顺序读 1M (numjobs=2, iodepth=16)
```
Cycles:        24,665,939,592
Instructions:  33,801,888,089
IPC:           1.37
测试时长:      70.32s
IOPS:          2,638
带宽:          2.64 GB/s
```

---

## 💡 RISC-V 预测参考

### ⚠️ 预测范围说明

**本数据仅适用于预测**:
- ✅ Ceph **客户端** RISC-V 性能（FIO + ceph-fuse/librbd）
- ✅ 客户端侧的 I/O 处理开销
- ✅ 应用层和文件系统/块设备层的 CPU 消耗

**不包括预测**:
- ❌ Ceph **服务端** RISC-V 性能（OSD, MON, MDS）
- ❌ 网络传输开销
- ❌ 服务端的存储引擎 CPU 消耗

**完整系统预测需要**:
```
总性能 = 客户端开销 + 网络延迟 + 服务端开销
       = (本数据) + (网络测试) + (服务端单独测试)
```

### 架构差异考虑因素

1. **指令集差异**
   - x86: CISC 架构，单指令可完成复杂操作
   - RISC-V: RISC 架构，需要更多指令完成相同操作
   - **预期**: RISC-V 指令数 = x86 指令数 × 1.2~1.5

2. **IPC 差异**
   - x86 测得 IPC: 0.73~1.33
   - RISC-V 预期 IPC: 可能更低或相似（取决于实现）
   - **预期**: RISC-V IPC = x86 IPC × 0.8~1.0

3. **频率差异**
   - x86 测试频率: 未明确（需要查看 CPU 型号）
   - RISC-V 目标频率: 需要根据具体硬件确定
   - **公式**: 实际时间 = Cycles / 频率

### 简化预测公式

```
RISC-V_Instructions ≈ x86_Instructions × 1.2~1.5

RISC-V_Cycles ≈ RISC-V_Instructions / RISC-V_IPC
              ≈ (x86_Instructions × 1.3) / (x86_IPC × 0.9)
              ≈ x86_Cycles × 1.44

执行时间 = RISC-V_Cycles / RISC-V_频率
```

### 预测示例（CephFS 随机写 4K）

假设 RISC-V 参数：
- 指令膨胀系数: 1.3x
- IPC 系数: 0.9x
- CPU 频率: 2 GHz

```
x86 数据:
  Instructions: 2,016,745,041
  Cycles:       2,252,432,968
  IPC:          0.90

RISC-V 预测:
  Instructions: 2,016,745,041 × 1.3 = 2,621,768,553
  预期 IPC:     0.90 × 0.9 = 0.81
  Cycles:       2,621,768,553 / 0.81 = 3,236,257,473
  时间:         3,236,257,473 / 2,000,000,000 = 1.62 秒
```

---

## 📋 数据采集方法

### 测试拓扑

| 组件 | 节点 | 进程 | perf 统计 |
|------|------|------|----------|
| **测试工具** | 10.103.11.243 | FIO | ✅ 统计 |
| **CephFS FUSE** | 10.103.11.243 | ceph-fuse | ✅ 统计 |
| **RBD librbd** | 10.103.11.243 | librbd (FIO 调用) | ✅ 统计 |
| **Ceph MON** | 10.103.11.243/244/245 | ceph-mon | ❌ 未统计 |
| **Ceph OSD** | 10.103.11.243/244/245 | ceph-osd | ❌ 未统计 |
| **Ceph MDS** | 10.103.11.243 | ceph-mds | ❌ 未统计 |

### 采集命令

```bash
# 执行位置: 10.103.11.249 (客户端节点)

# CephFS FUSE 测试
ssh ceph@10.103.11.249 "
    sudo perf stat -e cycles,instructions \
        fio --name=test --directory=/tmp/cephfs_fuse \
        --ioengine=libaio --rw=randwrite --bs=4k \
        --iodepth=4 --runtime=30 --time_based
"

# RBD librbd 测试
ssh ceph@10.103.11.249 "
    sudo perf stat -e cycles,instructions \
        fio --name=test --ioengine=rbd \
        --pool=test_pool --rbdname=test_img \
        --rw=randread --bs=4k --iodepth=4 \
        --runtime=30 --time_based
"

# RBD NBD 测试
ssh ceph@10.103.11.249 "
    sudo perf stat -e cycles,instructions \
        fio --name=test --filename=/dev/nbd0 \
        --ioengine=libaio --rw=randread --bs=4k \
        --iodepth=32 --numjobs=4 --runtime=30 --time_based
"
```

### perf stat 统计内容

**统计对象**: `fio` 进程及其所有子进程和库调用

**包括**:
- FIO 主进程的所有指令和周期
- CephFS FUSE: `ceph-fuse` 守护进程的 I/O 处理
- RBD librbd: `librbd` 库的网络通信和数据处理
- 系统调用 (open, read, write 等)
- 内核态代码执行 (如果有)

**不包括**:
- 其他独立运行的 Ceph 守护进程 (osd, mon, mds)
- 网络协议栈在服务端的处理
- 远程节点 (244, 245) 的任何进程

---

## 📁 完整测试数据位置

- CephFS 详细数据: `./cephfs_perf_results/fuse_20260115_040159/`
- RBD 详细数据: `./rbd_perf_results/librbd_20260115_045343/`
- 完整报告: `./CEPH_STORAGE_COMPLETE_TEST_REPORT.md`

---

**数据收集日期**: 2026-01-15  
**用途**: RISC-V 性能预测基准
