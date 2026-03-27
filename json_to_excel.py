#!/usr/bin/env python3
"""
json_to_excel.py  –  Convert benchmark_results.json to an Excel workbook.

Sheets produced:
  1. Benchmark Results  – one row per test case (FIO / rados bench / hsbench)
  2. Perf Stat          – standalone perf stat records
  3. Summary            – pivot-style summary by (test_object, test_action, block_size)

Usage:
    python3 json_to_excel.py [--input benchmark_results.json] [--output benchmark_results.xlsx]
"""

import argparse
import json
import sys
from pathlib import Path

try:
    import openpyxl
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from openpyxl.utils import get_column_letter
except ImportError:
    sys.exit("openpyxl not found – run: pip install openpyxl")


# ---------------------------------------------------------------------------
# Column definitions
# ---------------------------------------------------------------------------

BENCHMARK_COLUMNS = [
    ('test_run_id',         '测试批次',         24),
    ('test_date',           '测试时间',         20),
    ('test_object',         '测试对象',         14),
    ('benchmark_type',      '测试工具',         14),
    ('test_action',         '测试动作',         14),
    ('block_size',          '块大小',           10),
    ('iodepth',             'IO深度',            8),
    ('numjobs',             '并发数',            8),
    ('concurrent_ops',      '并发OPS',           10),
    ('duration_sec',        '测试时长(s)',        10),
    ('ramp_sec',            '预热(s)',            8),
    ('iops',                'IOPS',             12),
    ('bandwidth_mbps',      '带宽(MB/s)',        12),
    ('lat_mean_us',         '平均延迟(μs)',      14),
    ('lat_p50_us',          'P50延迟(μs)',       14),
    ('lat_p99_us',          'P99延迟(μs)',       14),
    ('lat_p999_us',         'P99.9延迟(μs)',     14),
    ('lat_max_us',          '最大延迟(μs)',      14),
    ('perf_cycles',         '指令周期数',        18),
    ('perf_instructions',   '指令数',            18),
    ('perf_ipc',            'IPC',               8),
    ('perf_cache_references',  '缓存引用',       18),
    ('perf_cache_misses',      '缓存缺失',       18),
    ('perf_cache_miss_rate_pct', '缓存缺失率(%)', 14),
    ('perf_branch_instructions', '分支指令',     18),
    ('perf_branch_misses',     '分支预测失败',   14),
    ('perf_elapsed_sec',    'Perf采样时长(s)',   16),
    ('perf__perf_file',     'Perf文件',          30),
    ('case_id',             'Case ID',           14),
]

PERF_COLUMNS = [
    ('perf_run',             '测试批次',          22),
    ('perf_date',            '测试时间',          20),
    ('node_ip',              '节点IP',             16),
    ('started_on',           '开始时间',          28),
    ('elapsed_sec',          '采样时长(s)',        14),
    ('cycles',               '指令周期数',         18),
    ('instructions',         '指令数',             18),
    ('ipc',                  'IPC',                 8),
    ('cache_references',     '缓存引用',           18),
    ('cache_misses',         '缓存缺失',           18),
    ('cache_miss_rate_pct',  '缓存缺失率(%)',      14),
    ('branch_instructions',  '分支指令',           18),
    ('branch_misses',        '分支预测失败',       14),
    ('perf_file',            'Perf文件',           36),
]

SUMMARY_COLUMNS = [
    ('test_object',       '测试对象',    14),
    ('test_action',       '测试动作',    14),
    ('block_size',        '块大小',      10),
    ('benchmark_type',    '测试工具',    14),
    ('count',             '样本数',       8),
    ('avg_iops',          '平均IOPS',    14),
    ('avg_bw_mbps',       '平均带宽(MB/s)', 14),
    ('avg_lat_mean_us',   '平均延迟(μs)',  14),
    ('avg_lat_p99_us',    'P99延迟(μs)',  14),
    ('avg_ipc',           '平均IPC',      10),
    ('avg_instructions',  '平均指令数',   18),
]


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

HEADER_FILL = PatternFill(start_color='1F4E79', end_color='1F4E79', fill_type='solid')
ALT_FILL    = PatternFill(start_color='D6E4F0', end_color='D6E4F0', fill_type='solid')
HEADER_FONT = Font(bold=True, color='FFFFFF', name='Calibri', size=11)
DATA_FONT   = Font(name='Calibri', size=10)
CENTER      = Alignment(horizontal='center', vertical='center', wrap_text=False)
LEFT        = Alignment(horizontal='left',   vertical='center', wrap_text=False)

THIN = Side(style='thin', color='BFBFBF')
THIN_BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def _write_header(ws, columns):
    for col_idx, (_, label, width) in enumerate(columns, 1):
        cell = ws.cell(row=1, column=col_idx, value=label)
        cell.font = HEADER_FONT
        cell.fill = HEADER_FILL
        cell.alignment = CENTER
        cell.border = THIN_BORDER
        ws.column_dimensions[get_column_letter(col_idx)].width = width
    ws.row_dimensions[1].height = 22
    ws.freeze_panes = 'A2'


def _write_row(ws, row_idx, columns, record):
    fill = ALT_FILL if row_idx % 2 == 0 else None
    for col_idx, (key, _, _) in enumerate(columns, 1):
        value = record.get(key)
        cell = ws.cell(row=row_idx, column=col_idx, value=value)
        cell.font = DATA_FONT
        cell.border = THIN_BORDER
        if fill:
            cell.fill = fill
        # Right-align numbers
        if isinstance(value, (int, float)):
            cell.alignment = CENTER
        else:
            cell.alignment = LEFT


# ---------------------------------------------------------------------------
# Sheet builders
# ---------------------------------------------------------------------------

def build_benchmark_sheet(wb, records):
    ws = wb.create_sheet('Benchmark Results')
    _write_header(ws, BENCHMARK_COLUMNS)
    for i, rec in enumerate(records, 2):
        _write_row(ws, i, BENCHMARK_COLUMNS, rec)
    ws.auto_filter.ref = f'A1:{get_column_letter(len(BENCHMARK_COLUMNS))}1'


def build_perf_sheet(wb, records):
    ws = wb.create_sheet('Perf Stat')
    _write_header(ws, PERF_COLUMNS)
    for i, rec in enumerate(records, 2):
        _write_row(ws, i, PERF_COLUMNS, rec)
    ws.auto_filter.ref = f'A1:{get_column_letter(len(PERF_COLUMNS))}1'


def build_summary_sheet(wb, records):
    ws = wb.create_sheet('Summary')

    # Group by (test_object, test_action, block_size, benchmark_type)
    groups = {}
    for r in records:
        key = (
            r.get('test_object', ''),
            r.get('test_action', ''),
            r.get('block_size', ''),
            r.get('benchmark_type', ''),
        )
        groups.setdefault(key, []).append(r)

    def _avg(lst, field):
        vals = [v for v in (r.get(field) for r in lst) if isinstance(v, (int, float))]
        return round(sum(vals) / len(vals), 2) if vals else None

    summary = []
    for (obj, action, bs, btype), rows in sorted(groups.items()):
        summary.append({
            'test_object':    obj,
            'test_action':    action,
            'block_size':     bs,
            'benchmark_type': btype,
            'count':          len(rows),
            'avg_iops':       _avg(rows, 'iops'),
            'avg_bw_mbps':    _avg(rows, 'bandwidth_mbps'),
            'avg_lat_mean_us': _avg(rows, 'lat_mean_us'),
            'avg_lat_p99_us': _avg(rows, 'lat_p99_us'),
            'avg_ipc':        _avg(rows, 'perf_ipc'),
            'avg_instructions': _avg(rows, 'perf_instructions'),
        })

    _write_header(ws, SUMMARY_COLUMNS)
    for i, rec in enumerate(summary, 2):
        _write_row(ws, i, SUMMARY_COLUMNS, rec)
    ws.auto_filter.ref = f'A1:{get_column_letter(len(SUMMARY_COLUMNS))}1'


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Convert benchmark_results.json to Excel')
    parser.add_argument('--input', default='./benchmark_results.json',
                        help='Input JSON file (default: ./benchmark_results.json)')
    parser.add_argument('--output', default='./benchmark_results.xlsx',
                        help='Output Excel file (default: ./benchmark_results.xlsx)')
    args = parser.parse_args()

    json_path = Path(args.input)
    if not json_path.exists():
        sys.exit(f"Input file not found: {json_path}")

    with open(json_path, encoding='utf-8') as f:
        data = json.load(f)

    benchmark_records = data.get('benchmark_results', [])
    perf_records      = data.get('standalone_perf_results', [])

    wb = openpyxl.Workbook()
    # Remove default sheet
    wb.remove(wb.active)

    build_summary_sheet(wb, benchmark_records)
    build_benchmark_sheet(wb, benchmark_records)
    build_perf_sheet(wb, perf_records)

    wb.save(args.output)
    print(f"Excel saved: {args.output}")
    print(f"  Sheet 'Summary':           {len(set((r.get('test_object',''), r.get('test_action',''), r.get('block_size','')) for r in benchmark_records))} groups")
    print(f"  Sheet 'Benchmark Results': {len(benchmark_records)} rows")
    print(f"  Sheet 'Perf Stat':         {len(perf_records)} rows")


if __name__ == '__main__':
    main()
