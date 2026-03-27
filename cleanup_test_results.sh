#!/bin/bash
# 清理所有 Ceph 测试结果
# 在重新运行完整测试前使用

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            Ceph 测试结果清理脚本                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 确认操作
echo -e "${YELLOW}警告: 此操作将删除以下内容:${NC}"
echo -e "  - results/ 目录中的所有测试结果"
echo -e "  - rbd_perf_results/ 目录"
echo -e "  - cephfs_perf_results/ 目录"
echo -e "  - rbd_nbd_perf_results/ 目录"
echo -e "  - rados_perf_results/ 目录"
echo -e "  - /tmp/cbt_archive/ 归档"
echo -e "  - 所有节点上的 /tmp/cbt/ 临时目录"
echo ""

read -p "确认要清理所有测试结果吗? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}[1/4] 清理本地测试结果目录...${NC}"

# 清理 results 目录（保留目录本身）
if [ -d "results" ]; then
    echo "  删除 results/* ..."
    rm -rf results/rbd_* results/cephfs_* results/rados_* results/rgw_* 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} results/ 已清理"
else
    echo "  results/ 目录不存在，跳过"
fi

# 清理 perf_results 目录
for dir in rbd_perf_results cephfs_perf_results rbd_nbd_perf_results rados_perf_results; do
    if [ -d "$dir" ]; then
        echo "  删除 $dir/ ..."
        rm -rf "$dir"
        echo -e "  ${GREEN}✓${NC} $dir/ 已删除"
    else
        echo "  $dir/ 不存在，跳过"
    fi
done

echo ""
echo -e "${BLUE}[2/4] 清理归档目录...${NC}"

# 清理归档
if [ -d "/tmp/cbt_archive" ]; then
    echo "  删除 /tmp/cbt_archive/ ..."
    sudo rm -rf /tmp/cbt_archive 2>/dev/null || rm -rf /tmp/cbt_archive
    echo -e "  ${GREEN}✓${NC} /tmp/cbt_archive/ 已删除"
else
    echo "  /tmp/cbt_archive/ 不存在，跳过"
fi

echo ""
echo -e "${BLUE}[3/4] 清理远程节点临时目录...${NC}"

# 清理各节点上的 /tmp/cbt
nodes=(10.103.11.243 10.103.11.244 10.103.11.245 10.103.11.249)

for node in "${nodes[@]}"; do
    echo "  清理 $node:/tmp/cbt ..."
    if ssh -o ConnectTimeout=5 ceph@$node "sudo rm -rf /tmp/cbt/* 2>/dev/null && sudo mkdir -p /tmp/cbt && sudo chown ceph:ceph /tmp/cbt" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $node 已清理"
    else
        echo -e "  ${YELLOW}⚠${NC} $node 清理失败或无法连接"
    fi
done

echo ""
echo -e "${BLUE}[4/4] 清理 RBD NBD 挂载点 (如有)...${NC}"

# 清理 node4 上可能的 NBD 挂载
if ssh -o ConnectTimeout=5 ceph@10.103.11.249 "command -v rbd-nbd" 2>/dev/null; then
    echo "  检查 10.103.11.249 上的 NBD 设备..."
    ssh ceph@10.103.11.249 "
        # 卸载所有 NBD 设备
        for dev in \$(rbd-nbd list-mapped 2>/dev/null | tail -n +2 | awk '{print \$5}'); do
            echo \"  卸载 \$dev\"
            sudo rbd-nbd unmap \$dev 2>/dev/null || true
        done
        
        # 强制卸载可能卡住的挂载点
        sudo umount -f /tmp/cbt/mnt/cbt-rbd-nbd/* 2>/dev/null || true
        sudo rm -rf /tmp/cbt/mnt 2>/dev/null || true
    " 2>/dev/null && echo -e "  ${GREEN}✓${NC} NBD 设备已清理"
else
    echo "  跳过 NBD 清理"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  清理完成!                                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}提示:${NC}"
echo "  现在可以运行 ./run_all_ceph_tests.sh 进行全新测试"
echo ""
