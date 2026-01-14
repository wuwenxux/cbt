#!/bin/bash
# 收集 CPU cycles 和 instructions 统计信息的脚本
# 在 RBD 测试期间收集性能数据

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 参数
DURATION=${1:-60}  # 测试持续时间（秒）
OUTPUT_DIR=${2:-./perf_results}
NODES=${3:-"10.103.11.243,10.103.11.244,10.103.11.245"}

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CPU 性能数据收集脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "持续时间: ${GREEN}${DURATION}${NC} 秒"
echo -e "输出目录: ${GREEN}${OUTPUT_DIR}${NC}"
echo -e "监控节点: ${GREEN}${NODES}${NC}"
echo ""

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 将节点字符串转换为数组
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

echo -e "${YELLOW}开始收集性能数据...${NC}"

# 在每个节点上启动 perf stat
PIDS=()
for node in "${NODE_ARRAY[@]}"; do
    echo -e "  在节点 ${GREEN}$node${NC} 上启动 perf stat..."
    
    # 在远程节点上运行 perf stat
    ssh ceph@$node "sudo perf stat -e cycles,instructions,cache-references,cache-misses,branch-instructions,branch-misses \
        -a -o /tmp/perf_stat_${node}.txt sleep ${DURATION}" > /dev/null 2>&1 &
    
    PIDS+=($!)
    
    # 同时收集 perf record 数据用于火焰图
    ssh ceph@$node "sudo perf record -e cycles -a -g -o /tmp/perf_record_${node}.data sleep ${DURATION}" > /dev/null 2>&1 &
    
    PIDS+=($!)
done

echo -e "${YELLOW}等待 ${DURATION} 秒收集数据...${NC}"

# 显示进度条
for ((i=1; i<=DURATION; i++)); do
    printf "\r进度: [%-50s] %d%%" $(printf '#%.0s' $(seq 1 $((i*50/DURATION)))) $((i*100/DURATION))
    sleep 1
done
echo ""

# 等待所有后台进程完成
echo -e "${YELLOW}等待所有收集任务完成...${NC}"
for pid in "${PIDS[@]}"; do
    wait $pid 2>/dev/null || true
done

# 从远程节点收集结果
echo -e "${YELLOW}收集结果文件...${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_DIR="$OUTPUT_DIR/perf_results_$TIMESTAMP"
mkdir -p "$RESULT_DIR"

for node in "${NODE_ARRAY[@]}"; do
    echo -e "  从 ${GREEN}$node${NC} 收集数据..."
    
    # 收集 perf stat 结果
    if ssh ceph@$node "test -f /tmp/perf_stat_${node}.txt" 2>/dev/null; then
        scp ceph@$node:/tmp/perf_stat_${node}.txt "$RESULT_DIR/perf_stat_${node}.txt" 2>/dev/null || true
        ssh ceph@$node "sudo rm -f /tmp/perf_stat_${node}.txt" 2>/dev/null || true
    fi
    
    # 收集 perf record 数据
    if ssh ceph@$node "test -f /tmp/perf_record_${node}.data" 2>/dev/null; then
        scp ceph@$node:/tmp/perf_record_${node}.data "$RESULT_DIR/perf_record_${node}.data" 2>/dev/null || true
        ssh ceph@$node "sudo rm -f /tmp/perf_record_${node}.data" 2>/dev/null || true
    fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}数据收集完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "结果保存在: ${BLUE}$RESULT_DIR${NC}"
echo ""

# 解析和显示汇总结果
echo -e "${YELLOW}性能统计汇总:${NC}"
echo ""

for node in "${NODE_ARRAY[@]}"; do
    STAT_FILE="$RESULT_DIR/perf_stat_${node}.txt"
    if [ -f "$STAT_FILE" ]; then
        echo -e "${BLUE}━━━ 节点 $node ━━━${NC}"
        
        # 提取关键指标
        CYCLES=$(grep -E "^\s+[0-9,]+ cycles" "$STAT_FILE" | awk '{print $1}' | tr -d ',')
        INSTRUCTIONS=$(grep -E "^\s+[0-9,]+ instructions" "$STAT_FILE" | awk '{print $1}' | tr -d ',')
        CACHE_REF=$(grep -E "^\s+[0-9,]+ cache-references" "$STAT_FILE" | awk '{print $1}' | tr -d ',')
        CACHE_MISS=$(grep -E "^\s+[0-9,]+ cache-misses" "$STAT_FILE" | awk '{print $1}' | tr -d ',')
        
        if [ -n "$CYCLES" ] && [ -n "$INSTRUCTIONS" ]; then
            IPC=$(echo "scale=3; $INSTRUCTIONS / $CYCLES" | bc)
            echo "  Cycles:        $(printf "%'d" $CYCLES)"
            echo "  Instructions:  $(printf "%'d" $INSTRUCTIONS)"
            echo "  IPC:           $IPC (Instructions Per Cycle)"
            
            if [ -n "$CACHE_REF" ] && [ -n "$CACHE_MISS" ]; then
                CACHE_MISS_RATE=$(echo "scale=2; $CACHE_MISS * 100 / $CACHE_REF" | bc)
                echo "  Cache Refs:    $(printf "%'d" $CACHE_REF)"
                echo "  Cache Misses:  $(printf "%'d" $CACHE_MISS) (${CACHE_MISS_RATE}%)"
            fi
        else
            echo "  (数据不完整，查看原始文件)"
        fi
        echo ""
    fi
done

echo -e "${YELLOW}详细报告:${NC}"
echo "  查看完整统计: cat $RESULT_DIR/perf_stat_*.txt"
echo "  生成火焰图:   perf report -i $RESULT_DIR/perf_record_*.data"
echo ""

exit 0
