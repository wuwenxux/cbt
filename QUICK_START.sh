#!/bin/bash
# RBD 测试快速启动指南

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║              CBT RBD 测试 - 快速启动指南                       ║
║        Ceph 集群: 10.103.11.243, 244, 245                     ║
╚════════════════════════════════════════════════════════════════╝

📋 准备工作
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 确保可以 SSH 到所有节点（无密码登录）:
   ssh ceph@10.103.11.243
   ssh ceph@10.103.11.244
   ssh ceph@10.103.11.245

2. 确保 Ceph 集群运行正常:
   ssh ceph@10.103.11.243 "sudo ceph -s"

3. 安装所需软件:
   - FIO (fio)
   - Ceph 客户端工具 (rbd, ceph)
   - Python 3 虚拟环境 (cbt_env)


🔍 第一步：检查环境
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

运行环境检查脚本：
    ./check_rbd_env.sh

这将检查：
  ✓ 配置文件
  ✓ Python 环境
  ✓ 网络连接
  ✓ SSH 访问
  ✓ Ceph 集群状态
  ✓ 所需软件
  ✓ 磁盘空间
  ✓ Ceph 配置


🚀 第二步：运行测试
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

方式一：使用自动化脚本（推荐）
    ./run_rbd_test.sh

方式二：手动运行
    # 激活虚拟环境
    source activate_cbt.sh

    # 快速测试（1分钟）
    python3 cbt.py --archive=./results/quick rbd_test_243_245_quick.yaml

    # 完整测试（2分钟，多配置）
    python3 cbt.py --archive=./results/full rbd_test_243_245.yaml


📊 第三步：查看结果
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

测试结果保存在 results/ 目录：
    ls -lh results/

查看详细信息：
    cat results/rbd_test_*/00000000/*/output.txt


📝 配置文件说明
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. rbd_test_243_245_quick.yaml
   - 快速测试（60秒）
   - 单一配置（4K随机写）
   - 用于快速验证环境

2. rbd_test_243_245.yaml
   - 完整测试（120秒）
   - 多种配置组合
   - 测试 4K/128K/1M IO大小
   - 测试读/写/随机读/随机写
   - 测试不同 IO深度和并发数


🔧 故障排查
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

问题1: SSH 连接失败
    # 设置 SSH 密钥
    ssh-copy-id ceph@10.103.11.243
    ssh-copy-id ceph@10.103.11.244
    ssh-copy-id ceph@10.103.11.245

问题2: 权限不足
    # 添加用户到 ceph 组
    ssh ceph@10.103.11.243 "sudo usermod -aG ceph \$USER"

问题3: FIO 未安装
    # Ubuntu/Debian
    sudo apt-get install fio
    # CentOS/RHEL
    sudo yum install fio

问题4: 存储池已存在
    # 清理存储池
    ssh ceph@10.103.11.243 "sudo ceph osd pool delete rbd_test rbd_test --yes-i-really-really-mean-it"


📚 更多信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

详细文档: RBD_TEST_README.md
CBT 官网: https://github.com/ceph/cbt
Ceph 文档: https://docs.ceph.com/


💡 提示
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- 首次运行建议使用快速测试验证环境
- 确保集群有足够的可用空间（至少 20GB）
- 测试期间避免在集群上运行其他负载
- 保留测试结果以便后续分析和对比

EOF
