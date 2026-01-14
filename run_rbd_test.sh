#!/bin/bash
# RBD 测试运行脚本
# Ceph 集群: 10.103.11.243, 244, 245

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}CBT RBD 测试 - Ceph 集群测试${NC}"
echo -e "${GREEN}集群节点: 10.103.11.243, 244, 245${NC}"
echo -e "${GREEN}================================================${NC}"

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 设置 Python 路径
if [ -f "./cbt_env/bin/python" ]; then
    PYTHON_CMD="./cbt_env/bin/python"
    echo -e "${GREEN}使用虚拟环境 Python: $PYTHON_CMD${NC}"
else
    PYTHON_CMD="python3"
    echo -e "${YELLOW}警告: 使用系统 Python: $PYTHON_CMD${NC}"
fi

# 检查并安装 pdsh
echo -e "\n${YELLOW}检查必需工具...${NC}"
if ! command -v pdsh &> /dev/null; then
    echo -e "${YELLOW}pdsh 未安装，正在安装...${NC}"
    if sudo apt-get install -y pdsh > /dev/null 2>&1; then
        echo -e "${GREEN}pdsh 安装成功${NC}"
    else
        echo -e "${RED}警告: pdsh 安装失败，测试可能失败${NC}"
    fi
else
    echo -e "${GREEN}pdsh 已安装${NC}"
fi

# 检查 SSH 连接
echo -e "\n${YELLOW}步骤 1: 检查集群节点连接...${NC}"
NODES=("10.103.11.243" "10.103.11.244" "10.103.11.245")
for node in "${NODES[@]}"; do
    echo -n "检查 $node ... "
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ceph@$node "echo OK" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}失败${NC}"
        echo -e "${RED}请确保可以 SSH 到 ceph@$node${NC}"
        exit 1
    fi
done

# 检查 Ceph 集群状态
echo -e "\n${YELLOW}步骤 2: 检查 Ceph 集群状态...${NC}"
if ssh ceph@10.103.11.243 "sudo ceph -s" > /tmp/ceph_status.txt 2>&1; then
    cat /tmp/ceph_status.txt
else
    echo -e "${RED}警告: 无法获取 Ceph 集群状态${NC}"
    cat /tmp/ceph_status.txt
fi

# 检查本地 Ceph 配置文件
echo -e "\n${YELLOW}步骤 3: 检查本地 Ceph 配置文件...${NC}"
if [ ! -f "/etc/ceph/ceph.conf" ]; then
    echo -e "${YELLOW}本地未找到 Ceph 配置文件，从远程节点复制...${NC}"
    if scp ceph@10.103.11.243:/etc/ceph/ceph.conf /tmp/ceph.conf 2>/dev/null; then
        sudo mkdir -p /etc/ceph
        sudo cp /tmp/ceph.conf /etc/ceph/ceph.conf
        sudo chmod 644 /etc/ceph/ceph.conf
        echo -e "${GREEN}配置文件已复制${NC}"
    else
        echo -e "${RED}警告: 无法复制配置文件，测试可能失败${NC}"
    fi
fi

if [ ! -f "/etc/ceph/ceph.client.admin.keyring" ]; then
    echo -e "${YELLOW}复制 Ceph 管理员密钥...${NC}"
    if scp ceph@10.103.11.243:/etc/ceph/ceph.client.admin.keyring /tmp/ceph.client.admin.keyring 2>/dev/null; then
        sudo cp /tmp/ceph.client.admin.keyring /etc/ceph/ceph.client.admin.keyring
        sudo chmod 644 /etc/ceph/ceph.client.admin.keyring
        echo -e "${GREEN}密钥文件已复制${NC}"
    else
        echo -e "${YELLOW}警告: 无法复制密钥文件${NC}"
    fi
fi

# 选择测试配置
echo -e "\n${YELLOW}步骤 4: 选择测试配置${NC}"
echo "1) 快速测试 (1分钟, 单一配置)"
echo "2) 完整测试 (2分钟, 多种配置)"
echo "3) 自定义配置文件"
read -p "请选择 [1-3]: " choice

case $choice in
    1)
        CONFIG_FILE="rbd_test_243_245_quick.yaml"
        echo -e "${GREEN}使用快速测试配置${NC}"
        ;;
    2)
        CONFIG_FILE="rbd_test_243_245.yaml"
        echo -e "${GREEN}使用完整测试配置${NC}"
        ;;
    3)
        read -p "请输入配置文件路径: " CONFIG_FILE
        ;;
    *)
        echo -e "${RED}无效选择，使用快速测试配置${NC}"
        CONFIG_FILE="rbd_test_243_245_quick.yaml"
        ;;
esac

# 检查配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件 $CONFIG_FILE 不存在${NC}"
    exit 1
fi

echo -e "${GREEN}配置文件: $CONFIG_FILE${NC}"

# 清理旧的临时文件
echo -e "\n${YELLOW}步骤 5: 清理临时文件...${NC}"
ssh ceph@10.103.11.243 "sudo rm -rf /tmp/cbt" || true

# 运行测试
echo -e "\n${YELLOW}步骤 6: 开始 RBD 测试...${NC}"
echo -e "${YELLOW}这可能需要几分钟时间...${NC}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_DIR="./results/rbd_test_$TIMESTAMP"

echo -e "${GREEN}运行命令: $PYTHON_CMD cbt.py --archive=$ARCHIVE_DIR $CONFIG_FILE${NC}"

if $PYTHON_CMD cbt.py --archive="$ARCHIVE_DIR" "$CONFIG_FILE"; then
    echo -e "\n${GREEN}================================================${NC}"
    echo -e "${GREEN}测试完成！${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}结果保存在: $ARCHIVE_DIR${NC}"
    
    # 显示结果摘要
    if [ -d "$ARCHIVE_DIR" ]; then
        echo -e "\n${YELLOW}结果文件:${NC}"
        ls -lh "$ARCHIVE_DIR"
    fi
else
    echo -e "\n${RED}================================================${NC}"
    echo -e "${RED}测试失败！${NC}"
    echo -e "${RED}================================================${NC}"
    exit 1
fi

echo -e "\n${YELLOW}查看详细结果请检查: $ARCHIVE_DIR${NC}"
