#!/bin/bash
# Ceph 全面测试运行脚本
# 支持所有存储类型: RBD, CephFS, RGW, RADOS

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            Ceph 全面性能测试套件                               ║${NC}"
echo -e "${BLUE}║     RBD | CephFS | RGW | RADOS                                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 设置 Python 路径
if [ -f "./cbt_env/bin/python" ]; then
    PYTHON_CMD="./cbt_env/bin/python"
else
    PYTHON_CMD="python3"
fi

# 检查测试是否已完成
check_test_done() {
    local test_name=$1
    local latest_result=$(ls -td results/${test_name}_* 2>/dev/null | head -1 || true)
    if [ -n "$latest_result" ] && [ -d "$latest_result/results" ]; then
        # 提取测试时间
        local test_time=$(basename "$latest_result" | sed "s/${test_name}_//")
        local year=${test_time:0:4}
        local month=${test_time:4:2}
        local day=${test_time:6:2}
        local hour=${test_time:9:2}
        local min=${test_time:11:2}
        echo -e "${GREEN}✓${NC} (${month}-${day} ${hour}:${min})"
        return 0
    fi
    echo ""
    return 0
}

# 检查各项测试状态
mark_librbd=$(check_test_done "rbd_librbd")
mark_krbd=$(check_test_done "rbd_krbd")
mark_nbd=$(check_test_done "rbd_nbd")
mark_cephfs_kernel=$(check_test_done "cephfs_kernel")
mark_cephfs_fuse=$(check_test_done "cephfs_fuse")
mark_rgw=$(check_test_done "rgw_s3")
mark_rados=$(check_test_done "rados_bench")

# 显示测试菜单
echo ""
echo -e "${YELLOW}请选择要运行的测试类型:${NC}"
echo ""
echo -e "${CYAN}━━━ RBD 块存储测试 ━━━${NC}"
echo -e "  1) RBD librbd    - 直接库访问 $mark_librbd"
echo -e "  2) RBD KRBD      - 内核 RBD 模块 $mark_krbd"
echo -e "  3) RBD NBD       - Network Block Device $mark_nbd"
echo "  4) RBD 全部      - 运行所有 RBD 测试"
echo ""
echo -e "${CYAN}━━━ CephFS 文件系统测试 ━━━${NC}"
echo -e "  5) CephFS Kernel - 内核客户端 $mark_cephfs_kernel"
echo -e "  6) CephFS FUSE   - 用户态 FUSE $mark_cephfs_fuse"
echo "  7) CephFS 全部   - 运行所有 CephFS 测试"
echo ""
echo -e "${CYAN}━━━ 对象存储和 RADOS 测试 ━━━${NC}"
echo -e "  8) RGW S3        - S3 对象存储 $mark_rgw"
echo -e "  9) RADOS + perf  - RADOS with CPU cycles 统计 $mark_rados"
echo ""
echo -e "${CYAN}━━━ 综合测试 ━━━${NC}"
echo " 10) 全部测试      - 运行所有可用测试"
echo " 11) 快速对比      - P0 测试 (librbd, KRBD, CephFS-Kernel)"
echo " 12) 完整 perf    - 所有测试 + CPU 性能统计"
echo ""
echo "  0) 退出"
echo ""

read -p "请选择 [0-12]: " choice

# 时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 测试函数
run_test() {
    local test_name=$1
    local config_file=$2
    local desc=$3
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}开始测试: $desc${NC}"
    echo -e "${GREEN}配置文件: $config_file${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}错误: 配置文件不存在: $config_file${NC}"
        return 1
    fi
    
    local archive_dir="./results/${test_name}_${TIMESTAMP}"
    
    if $PYTHON_CMD cbt.py --archive="$archive_dir" "$config_file"; then
        echo -e "${GREEN}✓ 测试完成: $desc${NC}"
        echo -e "${GREEN}  结果目录: $archive_dir${NC}"
        return 0
    else
        echo -e "${RED}✗ 测试失败: $desc${NC}"
        return 1
    fi
}

# 运行测试
case $choice in
    1)
        run_test "rbd_librbd" "rbd_test_243_245_quick.yaml" "RBD librbd 直接访问"
        ;;
    2)
        echo -e "${YELLOW}提示: KRBD 需要先映射 RBD 卷到内核设备${NC}"
        run_test "rbd_krbd" "rbd_krbd_243_245_quick.yaml" "RBD KRBD 内核模块"
        ;;
    3)
        echo -e "${YELLOW}提示: NBD 需要先通过 rbd-nbd 映射设备${NC}"
        run_test "rbd_nbd" "rbd_nbd_243_245_quick.yaml" "RBD NBD 网络块设备"
        ;;
    4)
        echo -e "${BLUE}运行所有 RBD 测试...${NC}"
        run_test "rbd_librbd" "rbd_test_243_245_quick.yaml" "RBD librbd"
        run_test "rbd_krbd" "rbd_krbd_243_245_quick.yaml" "RBD KRBD"
        run_test "rbd_nbd" "rbd_nbd_243_245_quick.yaml" "RBD NBD"
        ;;
    5)
        echo -e "${YELLOW}提示: 需要先配置 CephFS 和 MDS${NC}"
        run_test "cephfs_kernel" "cephfs_kernel_243_245_quick.yaml" "CephFS 内核客户端"
        ;;
    6)
        echo -e "${YELLOW}提示: 需要先配置 CephFS 和 MDS${NC}"
        run_test "cephfs_fuse" "cephfs_fuse_243_245_quick.yaml" "CephFS FUSE"
        ;;
    7)
        echo -e "${BLUE}运行所有 CephFS 测试...${NC}"
        run_test "cephfs_kernel" "cephfs_kernel_243_245_quick.yaml" "CephFS Kernel"
        run_test "cephfs_fuse" "cephfs_fuse_243_245_quick.yaml" "CephFS FUSE"
        ;;
    8)
        echo -e "${YELLOW}提示: 需要先配置 RGW 服务和 S3 用户${NC}"
        run_test "rgw_s3" "rgw_s3_243_245_quick.yaml" "RGW S3 对象存储"
        ;;
    9)
        echo -e "${YELLOW}提示: 此测试将收集 CPU cycles & instructions 数据${NC}"
        run_test "rados_bench" "rados_bench_243_245_quick.yaml" "RADOS + perf 统计"
        ;;
    10)
        echo -e "${BLUE}运行全部测试...${NC}"
        echo -e "${YELLOW}这将花费较长时间（约 30-60 分钟）${NC}"
        read -p "确认继续? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            run_test "rbd_librbd" "rbd_test_243_245_quick.yaml" "RBD librbd"
            run_test "rbd_krbd" "rbd_krbd_243_245_quick.yaml" "RBD KRBD"
            run_test "rbd_nbd" "rbd_nbd_243_245_quick.yaml" "RBD NBD"
            run_test "cephfs_kernel" "cephfs_kernel_243_245_quick.yaml" "CephFS Kernel"
            run_test "cephfs_fuse" "cephfs_fuse_243_245_quick.yaml" "CephFS FUSE"
            run_test "rgw_s3" "rgw_s3_243_245_quick.yaml" "RGW S3"
            run_test "rados_bench" "rados_bench_243_245_quick.yaml" "RADOS Bench + perf"
        fi
        ;;
    11)
        echo -e "${BLUE}运行快速对比测试 (P0)...${NC}"
        run_test "rbd_librbd" "rbd_test_243_245_quick.yaml" "RBD librbd"
        run_test "rbd_krbd" "rbd_krbd_243_245_quick.yaml" "RBD KRBD"
        run_test "cephfs_kernel" "cephfs_kernel_243_245_quick.yaml" "CephFS Kernel"
        ;;
    12)
        echo -e "${BLUE}运行完整性能测试（包含 perf 统计）...${NC}"
        echo -e "${YELLOW}这将花费较长时间（约 40-70 分钟）${NC}"
        read -p "确认继续? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            run_test "rbd_librbd" "rbd_test_243_245_quick.yaml" "RBD librbd"
            run_test "rbd_krbd" "rbd_krbd_243_245_quick.yaml" "RBD KRBD"
            run_test "rbd_nbd" "rbd_nbd_243_245_quick.yaml" "RBD NBD"
            run_test "cephfs_fuse" "cephfs_fuse_243_245_quick.yaml" "CephFS FUSE"
            run_test "rados_bench" "rados_bench_243_245_quick.yaml" "RADOS Bench + perf"
            
            echo -e "\n${CYAN}生成性能报告...${NC}"
            if [ -f "./extract_perf_metrics.sh" ]; then
                ./extract_perf_metrics.sh
            fi
        fi
        ;;
    0)
        echo -e "${YELLOW}退出${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    测试完成                                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${CYAN}结果目录: ./results/${NC}"
echo ""
echo -e "${YELLOW}查看结果:${NC}"
echo "  ls -lh results/"
echo "  cat results/*/00000000/*/output.txt"
echo ""
echo -e "${YELLOW}对比不同测试的性能:${NC}"
echo "  ./compare_test_results.sh"
