# CPU 性能监控指南

## 概述

本指南介绍如何在 Ceph RBD 测试期间收集 CPU cycles 和 instructions 性能数据。

## 性能指标说明

### CPU Cycles (CPU 周期数)
- 处理器执行指令所需的时钟周期总数
- 反映 CPU 的工作量
- 单位：cycles

### Instructions (指令数)
- CPU 执行的指令总数
- 反映实际完成的工作量
- 单位：instructions

### IPC (Instructions Per Cycle)
- 每个时钟周期执行的指令数
- 计算公式：IPC = Instructions / Cycles
- 更高的 IPC 表示更高的 CPU 效率

### 其他性能指标
- **cache-references**: 缓存访问次数
- **cache-misses**: 缓存未命中次数
- **branch-instructions**: 分支指令数
- **branch-misses**: 分支预测错误数

## 使用方法

### 方法 1：集成测试脚本（推荐）

运行带性能监控的 RBD 测试：

```bash
cd /data/Projects/cbt
./run_rbd_test_with_perf.sh
```

这会：
1. 在后台启动性能监控
2. 运行 RBD 测试
3. 收集所有节点的性能数据
4. 自动汇总和显示结果

### 方法 2：独立性能监控

只收集性能数据（不运行测试）：

```bash
cd /data/Projects/cbt
./collect_perf_stats.sh [持续时间(秒)] [输出目录] [节点列表]

# 示例：监控 60 秒
./collect_perf_stats.sh 60 ./perf_results "10.103.11.243,10.103.11.244,10.103.11.245"
```

### 方法 3：手动收集

在单个节点上手动收集：

```bash
# 收集 cycles 和 instructions
ssh ceph@10.103.11.243 "sudo perf stat -e cycles,instructions -a sleep 60"

# 收集更多事件
ssh ceph@10.103.11.243 "sudo perf stat -e cycles,instructions,cache-references,cache-misses,branch-instructions,branch-misses -a sleep 60"

# 记录详细数据用于火焰图
ssh ceph@10.103.11.243 "sudo perf record -e cycles -a -g -o /tmp/perf.data sleep 60"
```

## 结果解读

### 输出示例

```
━━━ 节点 10.103.11.243 ━━━
  Cycles:        45,234,567,890
  Instructions:  123,456,789,012
  IPC:           2.729 (Instructions Per Cycle)
  Cache Refs:    5,678,901,234
  Cache Misses:  234,567,890 (4.13%)
```

### 性能分析

**IPC 值参考**：
- `IPC < 1.0`: CPU 效率较低，可能存在大量等待
- `IPC 1.0 - 2.0`: 正常范围
- `IPC 2.0 - 3.0`: 良好的 CPU 利用率
- `IPC > 3.0`: 优秀的 CPU 效率

**Cache Miss Rate 参考**：
- `< 5%`: 优秀
- `5% - 10%`: 良好
- `10% - 20%`: 一般
- `> 20%`: 需要优化

## 高级用法

### 生成火焰图

1. 收集 perf 数据：
```bash
./collect_perf_stats.sh 60 ./perf_results "10.103.11.243"
```

2. 查看详细报告：
```bash
perf report -i ./perf_results/perf_results_*/perf_record_10.103.11.243.data
```

3. 生成火焰图（需要安装 FlameGraph 工具）：
```bash
# 转换 perf 数据
perf script -i ./perf_results/perf_results_*/perf_record_10.103.11.243.data > out.perf

# 生成火焰图（如果安装了 FlameGraph）
./FlameGraph/stackcollapse-perf.pl out.perf > out.folded
./FlameGraph/flamegraph.pl out.folded > flamegraph.svg
```

### 监控特定进程

监控 OSD 进程：

```bash
# 获取 OSD 进程 PID
ssh ceph@10.103.11.243 "pgrep ceph-osd"

# 监控特定 PID
ssh ceph@10.103.11.243 "sudo perf stat -e cycles,instructions -p <PID> sleep 60"
```

### 自定义事件监控

查看可用事件：
```bash
perf list
```

监控自定义事件：
```bash
ssh ceph@10.103.11.243 "sudo perf stat -e cycles,instructions,L1-dcache-load-misses,L1-icache-load-misses,dTLB-load-misses -a sleep 60"
```

## 结果文件说明

测试完成后会生成以下文件：

```
perf_results/
└── perf_results_20260114_103000/
    ├── perf_stat_10.103.11.243.txt      # 节点 243 的统计数据
    ├── perf_stat_10.103.11.244.txt      # 节点 244 的统计数据
    ├── perf_stat_10.103.11.245.txt      # 节点 245 的统计数据
    ├── perf_record_10.103.11.243.data   # 节点 243 的详细记录
    ├── perf_record_10.103.11.244.data   # 节点 244 的详细记录
    └── perf_record_10.103.11.245.data   # 节点 245 的详细记录
```

## 故障排查

### 问题 1: Permission denied

```bash
# 检查 perf 权限
cat /proc/sys/kernel/perf_event_paranoid

# 如果值大于 1，临时降低限制
ssh ceph@10.103.11.243 "sudo sysctl -w kernel.perf_event_paranoid=1"
```

### 问题 2: perf 命令未找到

```bash
# Ubuntu/Debian
sudo apt-get install linux-tools-common linux-tools-$(uname -r)

# CentOS/RHEL
sudo yum install perf
```

### 问题 3: 数据收集不完整

- 确保测试持续时间足够长（至少 30 秒）
- 检查节点的 SSH 连接
- 查看 `/tmp/perf_monitor.log` 获取详细错误

## 性能优化建议

基于收集的数据，可以进行以下优化：

1. **高 Cache Miss Rate (>10%)**
   - 检查数据访问模式
   - 优化数据结构对齐
   - 调整预取策略

2. **低 IPC (<1.5)**
   - 检查是否存在大量 IO 等待
   - 优化分支预测
   - 减少数据依赖

3. **高 Branch Miss Rate**
   - 减少分支数量
   - 使用分支预测友好的代码
   - 优化热点路径

## 参考资料

- [perf 官方文档](https://perf.wiki.kernel.org/)
- [Brendan Gregg 的 perf 示例](http://www.brendangregg.com/perf.html)
- [CPU 性能计数器参考](https://software.intel.com/content/www/us/en/develop/articles/intel-performance-counter-monitor.html)
