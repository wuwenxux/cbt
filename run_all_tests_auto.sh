#!/bin/bash
# 自动运行所有 Ceph 性能测试（带 perf 统计）

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 运行单个测试
run_single_test() {
    local test_name=$1
    local yaml_file=$2
    local description=$3
    
    log_info "开始测试: $description"
    log_info "配置文件: $yaml_file"
    
    # 运行 CBT
    if python3 cbt.py -a /tmp/cbt_archive "$yaml_file"; then
        log_success "$description - 测试完成"
        return 0
    else
        log_error "$description - 测试失败"
        return 1
    fi
}

# 测试列表
declare -A TESTS
TESTS[rbd_librbd]="rbd_test_243_245_quick.yaml|RBD librbd (用户空间库)"
TESTS[rbd_krbd]="rbd_krbd_243_245_quick.yaml|RBD KRBD (内核模块)"
TESTS[rbd_nbd]="rbd_nbd_243_245_quick.yaml|RBD NBD (Network Block Device)"
TESTS[cephfs_fuse]="cephfs_fuse_243_245_quick.yaml|CephFS FUSE (用户态)"
TESTS[rados_bench]="rados_bench_243_245_quick.yaml|RADOS Bench + perf"

# 主程序
main() {
    log_info "========================================="
    log_info "Ceph 全面性能测试 - 自动化运行"
    log_info "========================================="
    
    # 检查是否在 CBT 目录
    if [ ! -f "cbt.py" ]; then
        log_error "错误: 请在 CBT 项目根目录运行此脚本"
        exit 1
    fi
    
    # 统计
    local total=0
    local passed=0
    local failed=0
    
    # 运行所有测试
    for test_key in rbd_librbd rbd_krbd rbd_nbd cephfs_fuse rados_bench; do
        total=$((total + 1))
        
        IFS='|' read -r yaml_file description <<< "${TESTS[$test_key]}"
        
        echo ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "测试 $total/5: $description"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if run_single_test "$test_key" "$yaml_file" "$description"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            log_warning "继续下一个测试..."
        fi
        
        # 测试间隔
        sleep 5
    done
    
    # 总结
    echo ""
    log_info "========================================="
    log_info "测试完成统计"
    log_info "========================================="
    echo -e "总测试数: $total"
    echo -e "${GREEN}通过: $passed${NC}"
    echo -e "${RED}失败: $failed${NC}"
    
    if [ $failed -eq 0 ]; then
        log_success "所有测试通过! ✅"
    else
        log_warning "部分测试失败，请检查日志"
    fi
    
    # 提示生成报告
    echo ""
    log_info "下一步: 运行报告生成脚本"
    log_info "  ./extract_and_update_report.sh"
}

main "$@"
