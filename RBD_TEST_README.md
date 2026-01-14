# RBD 测试配置说明

## 概述

本配置用于在 Ceph 集群 (10.103.11.243, 244, 245) 上运行 RBD (RADOS Block Device) 性能测试。

## 集群配置

- **头节点 (Head Node)**: 10.103.11.243
- **OSD 节点**: 10.103.11.243, 10.103.11.244, 10.103.11.245
- **Monitor 节点**: 
  - 10.103.11.243:6789 (a)
  - 10.103.11.244:6789 (b)
  - 10.103.11.245:6789 (c)
- **客户端**: 10.103.11.243

## 配置文件

### 1. `rbd_test_243_245_quick.yaml` - 快速测试
- **测试时长**: 60秒
- **预热时间**: 5秒
- **卷大小**: 1GB
- **测试模式**: 随机写 (randwrite)
- **IO大小**: 4KB
- **IO深度**: 4
- **并发任务**: 1

**适用场景**: 快速验证集群配置和测试环境

### 2. `rbd_test_243_245.yaml` - 完整测试
- **测试时长**: 120秒
- **预热时间**: 10秒
- **卷大小**: 10GB
- **测试模式**: randread, randwrite, read, write
- **IO大小**: 4KB, 128KB, 1MB
- **IO深度**: 1, 8, 32
- **并发任务**: 1, 4

**适用场景**: 全面的性能基准测试

## 使用方法

### 方式一: 使用运行脚本（推荐）

```bash
./run_rbd_test.sh
```

脚本会自动:
1. 检查集群节点连接
2. 显示 Ceph 集群状态
3. 让你选择测试配置
4. 运行测试并保存结果

### 方式二: 直接运行 CBT

```bash
# 激活虚拟环境
source activate_cbt.sh

# 快速测试
python3 cbt.py --archive=./results/rbd_quick rbd_test_243_245_quick.yaml

# 完整测试
python3 cbt.py --archive=./results/rbd_full rbd_test_243_245.yaml
```

## 前置条件

1. **SSH 访问**: 确保可以无密码 SSH 到所有节点
   ```bash
   ssh ceph@10.103.11.243
   ssh ceph@10.103.11.244
   ssh ceph@10.103.11.245
   ```

2. **Ceph 集群运行正常**:
   ```bash
   ssh ceph@10.103.11.243 "sudo ceph -s"
   ```
   集群状态应该是 HEALTH_OK 或 HEALTH_WARN（可接受）

3. **所需软件已安装**:
   - FIO: `/usr/bin/fio`
   - Ceph 客户端工具: `/usr/bin/rbd`, `/usr/bin/ceph`
   - Python 虚拟环境: `cbt_env`

4. **磁盘空间**:
   - 快速测试: 至少 2GB 可用空间
   - 完整测试: 至少 20GB 可用空间

## 测试输出

测试结果会保存在 `results/` 目录下，包含:
- FIO JSON 输出文件
- IOPS、带宽、延迟日志
- 测试配置副本
- 集群状态快照

## 自定义配置

可以修改 YAML 配置文件来调整测试参数：

```yaml
benchmarks:
  librbdfio:
    time: 300              # 测试时长（秒）
    vol_size: 10240        # 卷大小（MB）
    mode: 'randwrite'      # read, write, randread, randwrite, rw
    iodepth: [8, 16]       # IO深度列表
    numjobs: [1, 4]        # 并发任务数列表
    op_size: [4096, 8192]  # IO大小（字节）
```

## 测试指标

CBT 会收集以下性能指标：
- **IOPS**: 每秒IO操作数
- **带宽**: MB/s
- **延迟**: 平均延迟、P50、P95、P99 延迟
- **CPU使用率**: 客户端和OSD节点
- **网络流量**: 集群间通信

## 故障排查

### 问题1: SSH连接失败
```bash
# 测试SSH连接
ssh -v ceph@10.103.11.243

# 设置SSH密钥
ssh-copy-id ceph@10.103.11.243
```

### 问题2: Ceph命令权限不足
```bash
# 确保用户有sudo权限或在ceph组中
sudo usermod -aG ceph $USER
```

### 问题3: FIO未找到
```bash
# 安装FIO
sudo apt-get install fio  # Ubuntu/Debian
sudo yum install fio      # CentOS/RHEL
```

### 问题4: 存储池已存在
如果测试中断，可能需要手动清理：
```bash
ssh ceph@10.103.11.243 "sudo ceph osd pool delete rbd_test rbd_test --yes-i-really-really-mean-it"
```

## 性能优化建议

1. **网络**: 确保使用万兆网络
2. **磁盘**: 使用SSD或NVMe提高性能
3. **副本数**: 根据需求调整 replication 参数
4. **PG数量**: 根据OSD数量调整 pg_size

## 参考资源

- [CBT 官方文档](https://github.com/ceph/cbt)
- [Ceph RBD 性能调优](https://docs.ceph.com/en/latest/rbd/)
- [FIO 用户指南](https://fio.readthedocs.io/)
