#!/bin/bash
# 检查 RBD 测试环境脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}CBT RBD 测试环境检查${NC}"
echo -e "${BLUE}Ceph 集群: 10.103.11.243, 244, 245${NC}"
echo -e "${BLUE}================================================${NC}"

# 计数器
PASSED=0
FAILED=0
WARNINGS=0

# 节点列表
NODES=("10.103.11.243" "10.103.11.244" "10.103.11.245")
HEAD_NODE="10.103.11.243"
CEPH_USER="ceph"

# 检查函数
check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((WARNINGS++))
}

# 1. 检查配置文件
echo -e "\n${YELLOW}[1/8] 检查配置文件...${NC}"
if [ -f "rbd_test_243_245_quick.yaml" ]; then
    check_pass "快速测试配置文件存在"
else
    check_fail "快速测试配置文件不存在"
fi

if [ -f "rbd_test_243_245.yaml" ]; then
    check_pass "完整测试配置文件存在"
else
    check_fail "完整测试配置文件不存在"
fi

# 2. 检查 Python 环境
echo -e "\n${YELLOW}[2/8] 检查 Python 环境...${NC}"
if [ -d "cbt_env" ]; then
    check_pass "Python 虚拟环境存在"
    if [ -f "cbt_env/bin/python3" ]; then
        PYTHON_VERSION=$(cbt_env/bin/python3 --version 2>&1)
        check_pass "Python 版本: $PYTHON_VERSION"
    fi
else
    check_fail "Python 虚拟环境不存在"
fi

if [ -f "cbt.py" ]; then
    check_pass "CBT 主程序存在"
else
    check_fail "CBT 主程序不存在"
fi

# 3. 检查网络连接
echo -e "\n${YELLOW}[3/8] 检查网络连接...${NC}"
for node in "${NODES[@]}"; do
    echo -n "  检查 $node ... "
    if ping -c 1 -W 2 "$node" > /dev/null 2>&1; then
        check_pass "可以 ping 通 $node"
    else
        check_fail "无法 ping 通 $node"
    fi
done

# 4. 检查 SSH 连接
echo -e "\n${YELLOW}[4/8] 检查 SSH 连接...${NC}"
for node in "${NODES[@]}"; do
    echo -n "  检查 SSH $CEPH_USER@$node ... "
    if timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 -o BatchMode=yes "$CEPH_USER@$node" "echo OK" > /dev/null 2>&1; then
        check_pass "可以 SSH 到 $CEPH_USER@$node"
    else
        check_fail "无法 SSH 到 $CEPH_USER@$node (需要配置无密码登录)"
    fi
done

# 5. 检查 Ceph 集群状态
echo -e "\n${YELLOW}[5/8] 检查 Ceph 集群状态...${NC}"
if ssh -o StrictHostKeyChecking=no "$CEPH_USER@$HEAD_NODE" "sudo ceph -s" > /tmp/ceph_status.txt 2>&1; then
    check_pass "成功连接到 Ceph 集群"
    
    # 检查集群健康状态
    if grep -q "HEALTH_OK" /tmp/ceph_status.txt; then
        check_pass "Ceph 集群健康状态: HEALTH_OK"
    elif grep -q "HEALTH_WARN" /tmp/ceph_status.txt; then
        check_warn "Ceph 集群健康状态: HEALTH_WARN"
        echo -e "${YELLOW}  详细信息:${NC}"
        cat /tmp/ceph_status.txt | head -20
    else
        check_fail "Ceph 集群健康状态异常"
        cat /tmp/ceph_status.txt | head -20
    fi
    
    # 检查 OSD
    OSD_COUNT=$(grep -oP "osd: \K[0-9]+" /tmp/ceph_status.txt | head -1)
    if [ -n "$OSD_COUNT" ] && [ "$OSD_COUNT" -gt 0 ]; then
        check_pass "OSD 数量: $OSD_COUNT"
    else
        check_fail "没有检测到 OSD"
    fi
    
    # 检查 MON
    MON_COUNT=$(grep -oP "mon: \K[0-9]+" /tmp/ceph_status.txt | head -1)
    if [ -n "$MON_COUNT" ] && [ "$MON_COUNT" -ge 3 ]; then
        check_pass "Monitor 数量: $MON_COUNT"
    else
        check_warn "Monitor 数量不足 3: $MON_COUNT"
    fi
else
    check_fail "无法连接到 Ceph 集群"
    cat /tmp/ceph_status.txt
fi

# 6. 检查所需软件
echo -e "\n${YELLOW}[6/8] 检查所需软件...${NC}"
for node in "${NODES[@]}"; do
    echo -e "\n  节点 $node:"
    
    # 检查 FIO
    if ssh -o StrictHostKeyChecking=no "$CEPH_USER@$node" "which fio" > /dev/null 2>&1; then
        FIO_VERSION=$(ssh "$CEPH_USER@$node" "fio --version" 2>&1)
        check_pass "FIO 已安装: $FIO_VERSION"
    else
        check_fail "FIO 未安装"
    fi
    
    # 检查 RBD
    if ssh -o StrictHostKeyChecking=no "$CEPH_USER@$node" "which rbd" > /dev/null 2>&1; then
        check_pass "RBD 工具已安装"
    else
        check_fail "RBD 工具未安装"
    fi
    
    # 检查 Ceph 命令
    if ssh -o StrictHostKeyChecking=no "$CEPH_USER@$node" "which ceph" > /dev/null 2>&1; then
        check_pass "Ceph 命令行工具已安装"
    else
        check_fail "Ceph 命令行工具未安装"
    fi
done

# 7. 检查磁盘空间
echo -e "\n${YELLOW}[7/8] 检查磁盘空间...${NC}"
for node in "${NODES[@]}"; do
    echo -e "\n  节点 $node:"
    DISK_INFO=$(ssh -o StrictHostKeyChecking=no "$CEPH_USER@$node" "df -h / | tail -1" 2>/dev/null)
    if [ -n "$DISK_INFO" ]; then
        AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
        USED_PCT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
        echo -e "    可用空间: ${GREEN}$AVAIL${NC}"
        if [ "$USED_PCT" -lt 80 ]; then
            check_pass "磁盘空间充足 (已使用 $USED_PCT%)"
        else
            check_warn "磁盘空间不足 (已使用 $USED_PCT%)"
        fi
    else
        check_warn "无法获取磁盘信息"
    fi
    
    # 检查 /tmp 空间
    TMP_INFO=$(ssh -o StrictHostKeyChecking=no "$CEPH_USER@$node" "df -h /tmp | tail -1" 2>/dev/null)
    if [ -n "$TMP_INFO" ]; then
        TMP_AVAIL=$(echo "$TMP_INFO" | awk '{print $4}')
        echo -e "    /tmp 可用: ${GREEN}$TMP_AVAIL${NC}"
    fi
done

# 8. 检查 Ceph 配置文件
echo -e "\n${YELLOW}[8/8] 检查 Ceph 配置文件...${NC}"
if ssh -o StrictHostKeyChecking=no "$CEPH_USER@$HEAD_NODE" "test -f /etc/ceph/ceph.conf" > /dev/null 2>&1; then
    check_pass "Ceph 配置文件存在: /etc/ceph/ceph.conf"
else
    check_fail "Ceph 配置文件不存在: /etc/ceph/ceph.conf"
fi

if ssh -o StrictHostKeyChecking=no "$CEPH_USER@$HEAD_NODE" "test -f /etc/ceph/ceph.client.admin.keyring" > /dev/null 2>&1; then
    check_pass "Ceph 管理员密钥存在"
else
    check_warn "Ceph 管理员密钥不存在或无权限访问"
fi

# 总结
echo -e "\n${BLUE}================================================${NC}"
echo -e "${BLUE}检查结果总结${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${YELLOW}警告: $WARNINGS${NC}"
echo -e "${RED}失败: $FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ 环境检查通过！可以运行 RBD 测试。${NC}"
    echo -e "${GREEN}运行命令: ./run_rbd_test.sh${NC}"
    exit 0
elif [ $FAILED -le 3 ]; then
    echo -e "\n${YELLOW}⚠ 发现一些问题，但可能仍可运行测试。${NC}"
    echo -e "${YELLOW}请检查上述失败项目。${NC}"
    exit 1
else
    echo -e "\n${RED}✗ 环境检查失败！请修复上述问题后再运行测试。${NC}"
    exit 2
fi
