#!/bin/bash
# Ceph 全面测试运行脚本
# 支持所有存储类型: RBD, CephFS, RGW, RADOS

set -e
set -o pipefail

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

# 部署验收测试使用的集群信息
# 说明: CBT 性能测试仍然以各 YAML 配置为准，这里只用于快速验证部署是否完成。
SSH_USER="ceph"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
HEAD_NODE="10.103.11.21"
CLIENT_NODE="10.103.11.249"
MON_NODES=("10.103.11.21" "10.103.11.22" "10.103.11.23")

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
        # 从目录名末尾提取 YYYYMMDD_HHMMSS 时间戳，兼容 rgw_s3_1m_ 等带额外后缀的名称
        local test_time=$(basename "$latest_result" | grep -oE '[0-9]{8}_[0-9]{6}$')
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
mark_deploy=$(check_test_done "deployment_check")

# 显示测试菜单
echo ""
echo -e "${YELLOW}请选择要运行的测试类型:${NC}"
echo ""
echo -e "${CYAN}━━━ 环境验收测试 ━━━${NC}"
echo -e " 13) Ceph 部署验收 - 集群健康与客户端连通性 $mark_deploy"
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
echo -e "  8) RGW S3        - S3 对象存储 (hsbench) $mark_rgw"
echo -e "  9) RADOS         - RADOS Bench $mark_rados"
echo ""
echo -e "${CYAN}━━━ 综合测试 ━━━${NC}"
echo " 10) 全部测试      - 运行所有测试（含指令数）"
echo " 11) 快速对比      - P0 测试 (librbd, KRBD, CephFS-Kernel)"
echo ""
echo -e "${CYAN}━━━ 维护 ━━━${NC}"
echo -e " 12) ${RED}清空测试数据${NC}   - 删除集群上的 pool/image/bucket 及 /tmp/cbt 临时目录"
echo ""
echo "  0) 退出"
echo ""
echo -e "${YELLOW}所有测试均自动采集 perf stat 指令数${NC}"
echo ""

read -p "请选择 [0-12]: " choice

# 时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 测试前自动清理 Ceph 集群数据
# 包括: CBT 测试 pool / CephFS fio 文件 / /tmp/cbt 临时目录
auto_clean_ceph_data() {
    local CLIENT_IP="10.103.11.249"
    local ALL_NODES=(10.103.11.244 10.103.11.245 10.103.11.243 10.103.11.249)

    echo -e "${CYAN}  [auto-clean] 清理残留设备和临时文件...${NC}"

    # 1. 客户端：解挂 /tmp/cbt 下挂载点，unmap 残留的 NBD/KRBD 设备
    #    说明：pool/CephFS 数据由 CBT 自身的 initialize()/teardown() 管理，这里不触碰
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 ceph@${CLIENT_IP} "
        # 解挂 /tmp/cbt 下所有挂载点（逆序，懒卸载）
        grep '/tmp/cbt' /proc/mounts 2>/dev/null | awk '{print \$2}' | sort -r | \
            xargs -r -I{} sudo umount -f -l {} 2>/dev/null || true

        # unmap 所有 rbd-nbd 映射（list-mapped 第 5 列是设备名 /dev/nbdX）
        sudo rbd-nbd list-mapped 2>/dev/null | awk 'NR>1{print \$5}' | \
            xargs -r -I{} sh -c \
              'sudo rbd-nbd unmap --force \"\$1\" 2>/dev/null || sudo rbd-nbd unmap \"\$1\" 2>/dev/null || true' _ {}
        sleep 1
        remaining=\$(sudo rbd-nbd list-mapped 2>/dev/null | grep -c '/dev/nbd' || true)
        [ \"\$remaining\" -gt 0 ] && echo \"  [warn] \$remaining NBD 映射仍未释放\" || true

        # unmap 所有 krbd 设备（rbd showmapped 第 5 列是设备名）
        sudo rbd showmapped 2>/dev/null | awk 'NR>1{print \$5}' | \
            xargs -r -I{} sudo rbd unmap --force {} 2>/dev/null || true
    " 2>/dev/null || true

    # 2. 清空所有节点 /tmp/cbt 本地临时目录，重建为 ceph 用户可写
    for node in "${ALL_NODES[@]}"; do
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ceph@${node} \
            "sudo rm -rf /tmp/cbt && mkdir -p /tmp/cbt && \
             echo '  [auto-clean] cleaned /tmp/cbt on ${node}'" 2>/dev/null || true
    done

    # 3. 清理 perf lock 文件，防止 perf stat 进程泄漏阻塞后续测试
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ceph@${CLIENT_IP} \
        "rm -f /tmp/perf_lock_* /tmp/perf_stat_*.txt 2>/dev/null
         sudo pkill -f 'while \[ -f /tmp/perf_lock' 2>/dev/null || true
         sudo pkill -f 'perf stat.*sleep 999999' 2>/dev/null || true" 2>/dev/null || true

    # 4. 清理本地残留的 perf stat SSH 进程
    pkill -f "ssh.*perf_lock" 2>/dev/null || true
    pkill -f "pdsh.*perf stat" 2>/dev/null || true

    echo -e "${CYAN}  [auto-clean] 完成${NC}"
}

# 基础测试函数（只跑 benchmark，不收集指令数）
# 用于选项 10（全部测试）等不需要 perf 的场景
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

    auto_clean_ceph_data

    # 清空同名旧结果，只保留本次测试数据
    local old_results=$(ls -d ./results/${test_name}_* 2>/dev/null || true)
    if [ -n "$old_results" ]; then
        echo -e "${YELLOW}清空旧结果: $(echo "$old_results" | tr '\n' ' ')${NC}"
        echo "$old_results" | xargs rm -rf
    fi

    local archive_dir="./results/${test_name}_${TIMESTAMP}"

    local rc=0
    if $PYTHON_CMD cbt.py --archive="$archive_dir" "$config_file"; then
        echo -e "${GREEN}✓ 测试完成: $desc${NC}"
        echo -e "${GREEN}  结果目录: $archive_dir${NC}"
    else
        echo -e "${RED}✗ 测试失败: $desc${NC}"
        rc=1
    fi

    # 结果已保存到本地，立即清理远端数据
    auto_clean_ceph_data

    return $rc
}

# perf 测试函数（benchmark + SSH 采集客户端指令数）
# 用于选项 12（完整 perf）
run_test_with_perf() {
    local test_name=$1
    local config_file=$2
    local desc=$3

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}开始测试 [+perf]: $desc${NC}"
    echo -e "${GREEN}配置文件: $config_file${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ ! -f "$config_file" ]; then
        echo -e "${RED}错误: 配置文件不存在: $config_file${NC}"
        return 1
    fi

    auto_clean_ceph_data

    # 清空同名旧结果，只保留本次测试数据
    local old_results=$(ls -d ./results/${test_name}_* 2>/dev/null || true)
    if [ -n "$old_results" ]; then
        echo -e "${YELLOW}清空旧结果: $(echo "$old_results" | tr '\n' ' ')${NC}"
        echo "$old_results" | xargs rm -rf
    fi

    local archive_dir="./results/${test_name}_${TIMESTAMP}"
    local perf_out_dir="./perf_results/${test_name}_${TIMESTAMP}"
    local perf_remote_file="/tmp/perf_stat_${test_name}_${TIMESTAMP}.txt"
    local perf_lock_file="/tmp/perf_lock_${test_name}_${TIMESTAMP}"

    # 清理残留 lock 文件
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        ${SSH_USER}@${CLIENT_NODE} \
        "rm -f ${perf_lock_file} ${perf_remote_file}" 2>/dev/null || true

    # 在客户端前台运行 perf stat（本地后台）
    # 用 lock 文件控制生命周期：删除 lock → 监控脚本自然退出（exit 0）→ perf 写数据
    echo -e "${CYAN}  启动客户端 perf stat 监控 (${CLIENT_NODE})...${NC}"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        ${SSH_USER}@${CLIENT_NODE} \
        "touch ${perf_lock_file}; sudo perf stat -a \
         sh -c 'while [ -f ${perf_lock_file} ]; do sleep 1; done' \
         2>${perf_remote_file}" &
    local perf_ssh_pid=$!
    sleep 2  # 等待 perf stat 完成初始化

    local test_rc=0
    if $PYTHON_CMD cbt.py --archive="$archive_dir" "$config_file"; then
        echo -e "${GREEN}✓ 测试完成: $desc${NC}"
    else
        echo -e "${RED}✗ 测试失败: $desc${NC}"
        test_rc=1
    fi

    # 删除 lock 文件 → 监控脚本自然退出 → perf 写完数据 → SSH 关闭
    echo -e "${CYAN}  停止 perf stat 并取回结果...${NC}"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        ${SSH_USER}@${CLIENT_NODE} \
        "rm -f ${perf_lock_file}" 2>/dev/null || true
    # 等待最多 30s，超时则强制 kill，避免残留进程阻塞后续 pdsh sync
    local wait_count=0
    while kill -0 $perf_ssh_pid 2>/dev/null && [ $wait_count -lt 30 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
    done
    kill -9 $perf_ssh_pid 2>/dev/null || true  # 兜底强制退出

    mkdir -p "$perf_out_dir"
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
           ${SSH_USER}@${CLIENT_NODE} \
           "test -s ${perf_remote_file}" 2>/dev/null; then
        scp -o StrictHostKeyChecking=no \
            ${SSH_USER}@${CLIENT_NODE}:${perf_remote_file} \
            "${perf_out_dir}/perf_stat_client.txt" 2>/dev/null && \
            echo -e "${GREEN}  perf stat → ${perf_out_dir}/perf_stat_client.txt${NC}" || \
            echo -e "${YELLOW}  警告: 无法取回 perf stat 结果${NC}"
        ssh -o StrictHostKeyChecking=no ${SSH_USER}@${CLIENT_NODE} \
            "rm -f ${perf_remote_file}" 2>/dev/null || true
    else
        echo -e "${YELLOW}  警告: 客户端 perf stat 结果文件为空或不存在${NC}"
    fi

    echo -e "${GREEN}  结果目录: $archive_dir${NC}"

    # 结果已取回，立即清理远端数据
    auto_clean_ceph_data

    return $test_rc
}

# 单 case perf 测试函数
# 从 base_yaml 中提取单个 mode × op_size 组合，生成临时 YAML，
# 再启停 perf stat 包裹这一个 case 的 CBT 运行。
# 参数: test_name base_yaml bench_key mode op_size desc
#   bench_key: benchmarks 下的 key，如 rbdfio / fio
#   mode:      randwrite | randread | write | read
#   op_size:   4096 | 1048576
run_case_with_perf() {
    local test_name="$1"
    local base_yaml="$2"
    local bench_key="$3"
    local mode="$4"
    local op_size="$5"
    local desc="$6"

    local size_label
    if [ "$op_size" -ge 1048576 ]; then
        size_label="1m"
    else
        size_label="4k"
    fi
    local full_name="${test_name}_${mode}_${size_label}"
    local tmp_yaml="/tmp/cbt_${full_name}_${TIMESTAMP}.yaml"

    # 生成只含单个 case 的临时 YAML
    $PYTHON_CMD - <<PYEOF
import yaml
with open('$base_yaml') as f:
    cfg = yaml.safe_load(f)
for k, v in list(cfg.get('benchmarks', {}).items()):
    if k == '$bench_key':
        v['mode']    = ['$mode']
        v['op_size'] = [$op_size]
        for list_key in ('iodepth', 'numjobs', 'procs_per_endpoint', 'concurrent_ops'):
            if list_key in v and isinstance(v[list_key], list):
                v[list_key] = [v[list_key][0]]
with open('$tmp_yaml', 'w') as f:
    yaml.dump(cfg, f, allow_unicode=True, default_flow_style=False)
PYEOF

    if [ ! -f "$tmp_yaml" ]; then
        echo -e "${RED}错误: 生成临时 YAML 失败${NC}"
        return 1
    fi

    run_test_with_perf "$full_name" "$tmp_yaml" "$desc"
    local rc=$?
    rm -f "$tmp_yaml"
    return $rc
}

run_deployment_check() {
    local test_name="deployment_check"
    local archive_dir="./results/${test_name}_${TIMESTAMP}"
    local result_dir="${archive_dir}/results"
    local log_file="${result_dir}/deployment_check.log"
    local rc=0

    mkdir -p "$result_dir"

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}开始测试: Ceph 部署完成验收${NC}"
    echo -e "${GREEN}检查项: SSH / MON / OSD / 客户端 Ceph 访问${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    {
        echo "Ceph deployment validation"
        echo "timestamp: $(date '+%F %T')"
        echo "head_node: ${HEAD_NODE}"
        echo "client_node: ${CLIENT_NODE}"
        echo "mon_nodes: ${MON_NODES[*]}"
        echo
    } | tee "$log_file"

    echo -e "${CYAN}[1/5] 检查 head 节点 SSH${NC}" | tee -a "$log_file"
    if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HEAD_NODE}" "hostname && whoami" 2>&1 | tee -a "$log_file"; then
        rc=1
    fi

    echo -e "${CYAN}[2/5] 检查 monitor 节点 SSH${NC}" | tee -a "$log_file"
    for mon in "${MON_NODES[@]}"; do
        if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${mon}" "hostname" 2>&1 | tee -a "$log_file"; then
            rc=1
        fi
    done

    echo -e "${CYAN}[3/5] 检查集群健康状态${NC}" | tee -a "$log_file"
    if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HEAD_NODE}" \
        "sudo ceph -s && echo && sudo ceph health detail && echo && sudo ceph mon stat && echo && sudo ceph osd stat && echo && sudo ceph osd tree" \
        2>&1 | tee -a "$log_file"; then
        rc=1
    fi

    echo -e "${CYAN}[4/5] 检查客户端 Ceph 工具与配置${NC}" | tee -a "$log_file"
    if ! ssh "${SSH_OPTS[@]}" "${SSH_USER}@${CLIENT_NODE}" \
        "hostname && test -f /etc/ceph/ceph.conf && command -v ceph && command -v rbd && command -v fio && sudo ceph -s" \
        2>&1 | tee -a "$log_file"; then
        rc=1
    fi

    echo -e "${CYAN}[5/5] 输出可选的 CephFS 状态${NC}" | tee -a "$log_file"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${HEAD_NODE}" "sudo ceph fs status || true" 2>&1 | tee -a "$log_file"

    if [ "$rc" -eq 0 ]; then
        echo -e "${GREEN}✓ 测试完成: Ceph 部署完成验收${NC}"
        echo -e "${GREEN}  结果目录: ${archive_dir}${NC}"
        return 0
    fi

    echo -e "${RED}✗ 测试失败: Ceph 部署完成验收${NC}"
    echo -e "${RED}  请先修复 SSH / Ceph 配置 / 集群健康问题，再执行性能测试${NC}"
    return 1
}

# 运行测试（所有选项均自动采集 perf stat 指令数）
_gen_report() {
    echo -e "\n${CYAN}生成 JSON + Excel 报告...${NC}"
    $PYTHON_CMD collect_results.py && $PYTHON_CMD json_to_excel.py && \
        echo -e "${GREEN}✓ benchmark_results.xlsx 已生成${NC}"
}

case $choice in
    1)
        run_test_with_perf "rbd_librbd" "rbd_test_243_245.yaml" "RBD librbd"
        _gen_report
        ;;
    2)
        run_test_with_perf "rbd_krbd" "rbd_krbd_243_245_quick.yaml" "RBD KRBD"
        _gen_report
        ;;
    3)
        run_test_with_perf "rbd_nbd" "rbd_nbd_243_245_quick.yaml" "RBD NBD"
        _gen_report
        ;;
    4)
        echo -e "${BLUE}运行所有 RBD 测试（含指令数）...${NC}"
        run_test_with_perf "rbd_librbd" "rbd_test_243_245.yaml"       "RBD librbd"
        run_test_with_perf "rbd_krbd"   "rbd_krbd_243_245_quick.yaml" "RBD KRBD"
        run_test_with_perf "rbd_nbd"    "rbd_nbd_243_245_quick.yaml"  "RBD NBD"
        _gen_report
        ;;
    5)
        run_test_with_perf "cephfs_kernel" "cephfs_kernel_existing_quick.yaml" "CephFS Kernel"
        _gen_report
        ;;
    6)
        run_test_with_perf "cephfs_fuse" "cephfs_fuse_243_245_quick.yaml" "CephFS FUSE"
        _gen_report
        ;;
    7)
        echo -e "${BLUE}运行所有 CephFS 测试（含指令数）...${NC}"
        run_test_with_perf "cephfs_kernel" "cephfs_kernel_existing_quick.yaml" "CephFS Kernel"
        run_test_with_perf "cephfs_fuse"   "cephfs_fuse_243_245_quick.yaml"    "CephFS FUSE"
        _gen_report
        ;;
    8)
        run_test_with_perf "rgw_s3"    "rgw_s3_hsbench_quick.yaml"    "RGW S3 4K"
        run_test_with_perf "rgw_s3_1m" "rgw_s3_1m_hsbench_quick.yaml" "RGW S3 1M"
        _gen_report
        ;;
    9)
        run_test_with_perf "rados_bench" "rados_bench_243_245_quick.yaml" "RADOS Bench"
        _gen_report
        ;;
    10)
        echo -e "${BLUE}运行全部测试（含指令数）...${NC}"
        echo -e "${YELLOW}预计耗时约 60-90 分钟${NC}"
        read -p "确认继续? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            run_test_with_perf "rbd_librbd"    "rbd_test_243_245.yaml"             "RBD librbd"
            run_test_with_perf "rbd_krbd"      "rbd_krbd_243_245_quick.yaml"       "RBD KRBD"
            run_test_with_perf "rbd_nbd"       "rbd_nbd_243_245_quick.yaml"        "RBD NBD"
            run_test_with_perf "cephfs_kernel" "cephfs_kernel_existing_quick.yaml" "CephFS Kernel"
            run_test_with_perf "cephfs_fuse"   "cephfs_fuse_243_245_quick.yaml"    "CephFS FUSE"
            run_test_with_perf "rgw_s3"        "rgw_s3_hsbench_quick.yaml"         "RGW S3 4K (PUT/GET)"
            run_test_with_perf "rgw_s3_1m"     "rgw_s3_1m_hsbench_quick.yaml"      "RGW S3 1M (PUT/GET)"
            run_test_with_perf "rados_bench"   "rados_bench_243_245_quick.yaml"    "RADOS Bench"
            _gen_report
        fi
        ;;
    11)
        echo -e "${BLUE}运行快速对比测试 P0（含指令数）...${NC}"
        run_test_with_perf "rbd_librbd"    "rbd_test_243_245.yaml"             "RBD librbd"
        run_test_with_perf "rbd_krbd"      "rbd_krbd_243_245_quick.yaml"       "RBD KRBD"
        run_test_with_perf "cephfs_kernel" "cephfs_kernel_existing_quick.yaml" "CephFS Kernel"
        _gen_report
        ;;
    12)
        echo -e "${YELLOW}提示: 选项 13 做部署验收${NC}"
        run_deployment_check
        ;;
    13)
        echo -e "${RED}警告: 即将清空 Ceph 集群上的测试运行数据！${NC}"
        echo -e "${YELLOW}包括: CBT 测试 pool、RBD image、RGW 测试用户/bucket、/tmp/cbt 临时目录${NC}"
        read -p "确认清空? (y/n): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            HEAD="10.103.11.244"
            echo -e "${CYAN}[1/4] 删除 CBT 测试 pool...${NC}"
            for pool in krbd_test_pool rbd_test nbd_test rados_test cbt_test; do
                ssh -o StrictHostKeyChecking=no ceph@${HEAD} \
                    "sudo ceph osd pool ls | grep -q '^${pool}$' && \
                     sudo ceph osd pool delete ${pool} ${pool} --yes-i-really-really-mean-it && \
                     echo 'deleted: ${pool}' || echo 'skip: ${pool}'"
            done
            echo -e "${CYAN}[2/4] 删除 RGW 测试用户 cbt...${NC}"
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ceph@${HEAD} \
                "timeout 30 sudo radosgw-admin user rm --uid=cbt --purge-data 2>/dev/null && echo 'deleted: rgw user cbt' || echo 'skip: rgw user cbt'"
            echo -e "${CYAN}[3/4] 清空所有节点 /tmp/cbt 临时目录...${NC}"
            for node in 10.103.11.244 10.103.11.245 10.103.11.243 10.103.11.249; do
                ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ceph@${node} \
                    "sudo rm -rf /tmp/cbt && mkdir -p /tmp/cbt && echo 'cleaned /tmp/cbt on ${node}'" 2>/dev/null || \
                    echo "skip: /tmp/cbt on ${node}"
            done
            echo -e "${CYAN}[4/4] 检查集群状态...${NC}"
            ssh -o StrictHostKeyChecking=no ceph@${HEAD} "sudo ceph -s"
            echo -e "${GREEN}✓ Ceph 测试运行数据已清空${NC}"
        else
            echo -e "${YELLOW}已取消${NC}"
        fi
        exit 0
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
echo "  查看各测试目录下的 perf_stat 与 FIO 输出"
