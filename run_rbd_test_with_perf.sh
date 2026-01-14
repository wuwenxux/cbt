#!/bin/bash
# RBD 测试运行脚本（带性能监控）
# Ceph 集群: 10.103.11.243, 244, 245

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}CBT RBD 测试 + 性能监控${NC}"
echo -e "${BLUE}集群节点: 10.103.11.243, 244, 245${NC}"
echo -e "${BLUE}================================================${NC}"

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

# 选择测试配置
echo -e "\n${YELLOW}选择测试配置:${NC}"
echo "1) 快速测试 (1分钟, 单一配置) + 性能监控"
echo "2) 完整测试 (2分钟, 多种配置) + 性能监控"
read -p "请选择 [1-2]: " choice

case $choice in
    1)
        CONFIG_FILE="rbd_test_243_245_quick.yaml"
        TEST_DURATION=65  # 60秒测试 + 5秒预热
        echo -e "${GREEN}使用快速测试配置${NC}"
        ;;
    2)
        CONFIG_FILE="rbd_test_243_245.yaml"
        TEST_DURATION=130  # 120秒测试 + 10秒预热
        echo -e "${GREEN}使用完整测试配置${NC}"
        ;;
    *)
        echo -e "${RED}无效选择，使用快速测试配置${NC}"
        CONFIG_FILE="rbd_test_243_245_quick.yaml"
        TEST_DURATION=65
        ;;
esac

# 检查配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}错误: 配置文件 $CONFIG_FILE 不存在${NC}"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_DIR="./results/rbd_test_perf_$TIMESTAMP"
PERF_DIR="./perf_results"

echo -e "\n${YELLOW}准备启动测试...${NC}"
echo -e "测试持续时间: ${GREEN}${TEST_DURATION}${NC} 秒"
echo -e "结果目录: ${GREEN}$ARCHIVE_DIR${NC}"
echo -e "性能数据目录: ${GREEN}$PERF_DIR${NC}"

# 在后台启动性能监控
echo -e "\n${YELLOW}[1/2] 启动性能监控（后台）...${NC}"
./collect_perf_stats.sh $TEST_DURATION $PERF_DIR "10.103.11.243,10.103.11.244,10.103.11.245" > /tmp/perf_monitor.log 2>&1 &
PERF_PID=$!
echo -e "${GREEN}性能监控进程 PID: $PERF_PID${NC}"

# 等待2秒确保性能监控已启动
sleep 2

# 运行 RBD 测试
echo -e "\n${YELLOW}[2/2] 运行 RBD 测试...${NC}"
echo -e "${GREEN}运行命令: $PYTHON_CMD cbt.py --archive=$ARCHIVE_DIR $CONFIG_FILE${NC}"
echo ""

if $PYTHON_CMD cbt.py --archive="$ARCHIVE_DIR" "$CONFIG_FILE"; then
    TEST_SUCCESS=true
else
    TEST_SUCCESS=false
fi

# 等待性能监控完成
echo -e "\n${YELLOW}等待性能监控完成...${NC}"
wait $PERF_PID 2>/dev/null || true

if [ "$TEST_SUCCESS" = true ]; then
    echo -e "\n${GREEN}================================================${NC}"
    echo -e "${GREEN}测试和性能监控完成！${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}测试结果: $ARCHIVE_DIR${NC}"
    echo -e "${GREEN}性能数据: $PERF_DIR${NC}"
    
    # 显示性能监控日志
    if [ -f "/tmp/perf_monitor.log" ]; then
        echo -e "\n${YELLOW}性能监控摘要:${NC}"
        tail -30 /tmp/perf_monitor.log
    fi
    
    # 显示结果摘要
    if [ -d "$ARCHIVE_DIR" ]; then
        echo -e "\n${YELLOW}测试结果文件:${NC}"
        ls -lh "$ARCHIVE_DIR" 2>/dev/null || true
    fi
else
    echo -e "\n${RED}================================================${NC}"
    echo -e "${RED}测试失败！${NC}"
    echo -e "${RED}================================================${NC}"
    
    # 仍然显示性能数据（如果有）
    if [ -f "/tmp/perf_monitor.log" ]; then
        echo -e "\n${YELLOW}性能监控日志:${NC}"
        cat /tmp/perf_monitor.log
    fi
    
    exit 1
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}查看详细结果:${NC}"
echo -e "${BLUE}========================================${NC}"
echo "• 测试结果: ls -R $ARCHIVE_DIR"
echo "• 性能统计: cat $PERF_DIR/perf_results_*/perf_stat_*.txt"
echo "• 生成火焰图: perf report -i $PERF_DIR/perf_results_*/perf_record_*.data"
echo ""
