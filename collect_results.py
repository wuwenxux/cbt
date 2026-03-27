#!/usr/bin/env python3
"""
collect_results.py  –  Collect Ceph benchmark results into JSON for Excel export.

Usage:
    python3 collect_results.py [options]

Options:
    --results-dir   Path to CBT archive root  (default: ./results)
    --perf-dir      Path to standalone perf_results dir  (default: ./perf_results)
    --output        Output JSON file  (default: ./benchmark_results.json)

Output JSON schema:
  {
    "generated_at": "...",
    "benchmark_results": [ <row>, ... ],
    "standalone_perf_results": [ <perf_row>, ... ]
  }

Each benchmark row (for fio / radosbench / hsbench) has:
    test_run_id, test_date, test_object, benchmark_type,
    test_action, block_size, iodepth, numjobs / concurrent_ops,
    duration_sec, iops, bandwidth_mbps,
    lat_mean_us, lat_p50_us, lat_p99_us, lat_p999_us,
    perf_cycles, perf_instructions, perf_ipc,
    perf_cache_references, perf_cache_misses, perf_cache_miss_rate_pct,
    perf_branch_instructions, perf_branch_misses, perf_elapsed_sec
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML not found – run: pip install pyyaml")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ts_from_dirname(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name)
    if m:
        try:
            return datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S').isoformat()
        except ValueError:
            pass
    return None


def _test_object_from_archive(archive_name: str, benchmarks: dict) -> str:
    n = archive_name.lower()
    if 'librbd' in n:
        return 'RBD librbd'
    if 'krbd' in n:
        return 'RBD KRBD'
    if 'nbd' in n:
        return 'RBD NBD'
    if 'cephfs' in n and 'fuse' in n:
        return 'CephFS FUSE'
    if 'cephfs' in n:
        return 'CephFS Kernel'
    if 'rados' in n:
        return 'RADOS'
    if 'rgw' in n or 's3' in n:
        return 'RGW S3'
    # Fall back to benchmark key
    for k in benchmarks:
        if 'librbd' in k:
            return 'RBD librbd'
        if 'rbd' in k or 'krbd' in k:
            return 'RBD KRBD'
        if 'rados' in k:
            return 'RADOS'
        if 'hsbench' in k or 's3' in k or 'rgw' in k:
            return 'RGW S3'
        if 'cephfs' in k or 'fio' in k:
            return 'CephFS Kernel'
    return 'Unknown'


# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------

def parse_fio_output(path: str) -> dict:
    """Extract metrics from FIO output file (contains JSON embedded in plain text)."""
    try:
        with open(path) as f:
            raw = f.read()
        # Find the JSON block: first '{' … last '}'
        start = raw.find('{')
        end = raw.rfind('}') + 1
        if start < 0 or end <= 0:
            return {}
        data = json.loads(raw[start:end])
    except Exception as e:
        return {'_error': str(e)}

    jobs = data.get('jobs', [])
    if not jobs:
        return {}
    job = jobs[0]

    opts = data.get('global options', {})
    mode = opts.get('rw', '')

    # Pick direction
    if 'read' in mode:
        direction = 'read'
    elif 'write' in mode or 'trim' in mode:
        direction = 'write'
    else:
        direction = 'read' if job.get('read', {}).get('iops', 0) > 0 else 'write'

    io = job.get(direction, {})
    lat_ns = io.get('lat_ns', {})
    clat_ns = io.get('clat_ns', {})
    pct = clat_ns.get('percentile', {})

    bw_kib = io.get('bw', 0)
    return {
        'iops': round(io.get('iops', 0), 1),
        'bandwidth_mbps': round(bw_kib / 1024, 2),
        'lat_mean_us': round(lat_ns.get('mean', 0) / 1000, 2),
        'lat_p50_us': round(pct.get('50.000000', 0) / 1000, 2),
        'lat_p99_us': round(pct.get('99.000000', 0) / 1000, 2),
        'lat_p999_us': round(pct.get('99.900000', 0) / 1000, 2),
    }


def parse_rados_json(path: str) -> dict:
    """Parse the compact JSON produced by rados bench."""
    try:
        with open(path) as f:
            data = json.loads(f.read())
    except Exception as e:
        return {'_error': str(e)}

    ops_key = 'Total writes made' if 'Total writes made' in data else 'Total reads made'
    return {
        'iops': round(float(data.get('Average IOPS', 0)), 1),
        'bandwidth_mbps': float(data.get('Bandwidth (MB/sec)', 0)),
        'lat_mean_us': round(float(data.get('Average Latency(s)', 0)) * 1e6, 2),
        'lat_max_us': round(float(data.get('Max latency(s)', 0)) * 1e6, 2),
        'lat_min_us': round(float(data.get('Min latency(s)', 0)) * 1e6, 2),
        'total_ops': int(float(data.get(ops_key, 0))),
        'total_time_s': float(data.get('Total time run', 0)),
    }


def parse_perf_stat(path: str) -> dict:
    """Parse a `perf stat` output file."""
    result = {}
    try:
        with open(path) as f:
            raw = f.read()
    except Exception as e:
        return {'_error': str(e)}

    counters = {
        'cycles': r'([\d,]+)\s+cycles',
        'instructions': r'([\d,]+)\s+instructions',
        'cache_references': r'([\d,]+)\s+cache-references',
        'cache_misses': r'([\d,]+)\s+cache-misses',
        'branch_instructions': r'([\d,]+)\s+branch-instructions',
        'branch_misses': r'([\d,]+)\s+branch-misses',
    }
    for key, pat in counters.items():
        m = re.search(pat, raw)
        if m:
            result[key] = int(m.group(1).replace(',', ''))

    m = re.search(r'#\s+([\d.]+)\s+insn per cycle', raw)
    if m:
        result['ipc'] = float(m.group(1))
    elif result.get('instructions') and result.get('cycles'):
        result['ipc'] = round(result['instructions'] / result['cycles'], 4)

    m = re.search(r'#\s+([\d.]+)%\s+of all cache refs', raw)
    if m:
        result['cache_miss_rate_pct'] = float(m.group(1))

    m = re.search(r'([\d.]+)\s+seconds time elapsed', raw)
    if m:
        result['elapsed_sec'] = float(m.group(1))

    m = re.search(r'# started on (.+)', raw)
    if m:
        result['started_on'] = m.group(1).strip()

    return result


# ---------------------------------------------------------------------------
# Per-archive processors
# ---------------------------------------------------------------------------

def _find_perf_in_casedir(case_dir: Path) -> dict:
    perf_subdir = case_dir / 'perf'
    if perf_subdir.is_dir():
        for pf in sorted(perf_subdir.glob('perf_stat.*')):
            data = parse_perf_stat(str(pf))
            if data and '_error' not in data:
                data['_perf_file'] = str(pf)
                return data
    return {}


def _prefix_perf(d: dict) -> dict:
    return {f'perf_{k}': v for k, v in d.items()}


def _bytes_to_size_str(b) -> str:
    b = int(b)
    if b >= 1024 * 1024:
        return f"{b // (1024*1024)}M"
    if b >= 1024:
        return f"{b // 1024}K"
    return f"{b}B"


def process_fio_case(case_dir: Path, bm: dict, base: dict) -> list:
    perf = _prefix_perf(_find_perf_in_casedir(case_dir))
    records = []
    for out in sorted(case_dir.glob('output.0.*')):
        metrics = parse_fio_output(str(out))
        if not metrics or '_error' in metrics:
            continue
        op_size_b = bm.get('op_size', 0)
        row = {
            **base,
            'test_action': bm.get('mode', bm.get('rw', '')),
            'block_size': _bytes_to_size_str(op_size_b) if op_size_b else bm.get('size', '?'),
            'iodepth': bm.get('iodepth'),
            'numjobs': bm.get('numjobs', bm.get('procs_per_endpoint', 1)),
            'concurrent_ops': None,
            'duration_sec': bm.get('time'),
            'ramp_sec': bm.get('ramp'),
            **metrics,
            **perf,
        }
        records.append(row)
    return records


def process_radosbench_case(case_dir: Path, bm: dict, base: dict, clients: list) -> list:
    perf = _prefix_perf(_find_perf_in_casedir(case_dir))
    records = []
    for op in ('write', 'seq'):
        op_path = case_dir / op
        if not op_path.is_dir():
            continue
        json_files = sorted(op_path.glob('json_output.0.*'))
        if not json_files:
            continue
        metrics = parse_rados_json(str(json_files[0]))
        if not metrics or '_error' in metrics:
            continue
        op_size_b = bm.get('op_size', 0)
        row = {
            **base,
            'test_action': op,
            'block_size': _bytes_to_size_str(op_size_b) if op_size_b else '?',
            'iodepth': None,
            'numjobs': None,
            'concurrent_ops': bm.get('concurrent_ops'),
            'duration_sec': bm.get('time'),
            'ramp_sec': None,
            **metrics,
            **perf,
        }
        records.append(row)
    return records


def process_hsbench_case(case_dir: Path, bm: dict, base: dict) -> list:
    perf = _prefix_perf(_find_perf_in_casedir(case_dir))
    records = []
    for out in sorted(case_dir.glob('output.0.*')):
        try:
            with open(out) as f:
                raw_out = f.read()
        except Exception:
            raw_out = ''

        # Try to parse hsbench tabular output for IOPS / bandwidth
        iops = None
        bw_mbps = None
        # hsbench prints lines like: "Mode ... Ops/sec ... MB/s ..."
        for line in raw_out.splitlines():
            cols = line.split()
            # Look for numeric Ops/sec column
            if len(cols) >= 3:
                try:
                    iops = float(cols[1])
                    bw_mbps = float(cols[2]) if len(cols) > 2 else None
                    break
                except ValueError:
                    pass

        row = {
            **base,
            'test_action': bm.get('modes', ''),
            'block_size': bm.get('size', '?'),
            'iodepth': None,
            'numjobs': bm.get('threads'),
            'concurrent_ops': None,
            'duration_sec': bm.get('duration'),
            'ramp_sec': None,
            'buckets': bm.get('buckets'),
            'objects': bm.get('objects'),
            'iops': iops,
            'bandwidth_mbps': bw_mbps,
            'lat_mean_us': None,
            'lat_p50_us': None,
            'lat_p99_us': None,
            'lat_p999_us': None,
            'hsbench_raw_output': raw_out[:3000],
            **perf,
        }
        records.append(row)
    # If no output files found, still create one empty row
    if not records:
        row = {
            **base,
            'test_action': bm.get('modes', ''),
            'block_size': bm.get('size', '?'),
            'iodepth': None,
            'numjobs': bm.get('threads'),
            'concurrent_ops': None,
            'duration_sec': bm.get('duration'),
            'ramp_sec': None,
            'buckets': bm.get('buckets'),
            'objects': bm.get('objects'),
            'iops': None, 'bandwidth_mbps': None,
            'lat_mean_us': None, 'lat_p50_us': None,
            'lat_p99_us': None, 'lat_p999_us': None,
            'hsbench_raw_output': None,
            **perf,
        }
        records.append(row)
    return records


# ---------------------------------------------------------------------------
# Main collection logic
# ---------------------------------------------------------------------------

def _load_run_perf(perf_dir: str, archive_name: str) -> dict:
    """Load the per-run perf stat file from perf_results/<archive_name>/.

    Returns a dict with prefixed keys (perf_cycles, perf_instructions, …)
    or an empty dict when no matching file is found.
    """
    perf_path = Path(perf_dir) / archive_name
    if not perf_path.is_dir():
        return {}
    # Accept perf_stat_client.txt or any perf_stat_*.txt in the directory
    for candidate in sorted(perf_path.glob('perf_stat_*.txt')):
        data = parse_perf_stat(str(candidate))
        if data and '_error' not in data and data.get('instructions'):
            data['_perf_file'] = str(candidate)
            return _prefix_perf(data)
    return {}


def collect(results_dir: str, perf_dir: str, output_file: str):
    results_path = Path(results_dir)
    benchmark_records = []

    for archive_dir in sorted(results_path.iterdir()):
        if not archive_dir.is_dir():
            continue

        cbt_config_path = archive_dir / 'results' / 'cbt_config.yaml'
        if not cbt_config_path.exists():
            continue

        with open(cbt_config_path) as f:
            cbt_config = yaml.safe_load(f) or {}

        archive_name = archive_dir.name
        benchmarks = cbt_config.get('benchmarks', {})
        cluster = cbt_config.get('cluster', {})
        clients = cluster.get('clients', [])

        test_object = _test_object_from_archive(archive_name, benchmarks)
        test_date = _ts_from_dirname(archive_name)

        # Per-run perf data (from SSH-collected perf_results/<archive_name>/)
        run_perf = _load_run_perf(perf_dir, archive_name)

        iter_dir = archive_dir / 'results' / '00000000'
        if not iter_dir.is_dir():
            continue

        for case_dir in sorted(iter_dir.iterdir()):
            if not case_dir.is_dir() or not case_dir.name.startswith('id-'):
                continue

            bm_config_path = case_dir / 'benchmark_config.yaml'
            if not bm_config_path.exists():
                continue

            with open(bm_config_path) as f:
                bm_config = yaml.safe_load(f) or {}

            bm = bm_config.get('cluster', {})
            benchmark_type = bm.get('benchmark', list(benchmarks.keys())[0] if benchmarks else 'unknown')

            base = {
                'test_run_id': archive_name,
                'test_date': test_date,
                'test_object': test_object,
                'benchmark_type': benchmark_type,
                'case_id': case_dir.name,
            }

            # Prefer in-case perf files; fall back to the per-run perf file
            case_perf = _prefix_perf(_find_perf_in_casedir(case_dir))
            merged_perf = run_perf if not case_perf else case_perf

            if benchmark_type in ('librbdfio', 'rbdfio', 'kvmrbdfio'):
                records = process_fio_case(case_dir, bm, base)
                for r in records:
                    r.update({k: v for k, v in merged_perf.items() if k not in r or r[k] is None})
                benchmark_records.extend(records)

            elif benchmark_type == 'fio':
                # fio 可用于 CephFS、NBD 等多种场景，根据 test_object 区分
                if 'CephFS' in test_object:
                    base['benchmark_type'] = 'fio_cephfs'
                elif 'NBD' in test_object:
                    base['benchmark_type'] = 'fio_nbd'
                else:
                    base['benchmark_type'] = f'fio_{test_object.lower().replace(" ", "_")}'
                records = process_fio_case(case_dir, bm, base)
                for r in records:
                    r.update({k: v for k, v in merged_perf.items() if k not in r or r[k] is None})
                benchmark_records.extend(records)

            elif benchmark_type == 'radosbench':
                records = process_radosbench_case(case_dir, bm, base, clients)
                for r in records:
                    r.update({k: v for k, v in merged_perf.items() if k not in r or r[k] is None})
                benchmark_records.extend(records)

            elif benchmark_type == 'hsbench':
                records = process_hsbench_case(case_dir, bm, base)
                for r in records:
                    r.update({k: v for k, v in merged_perf.items() if k not in r or r[k] is None})
                benchmark_records.extend(records)

    # Standalone perf_results directory
    standalone_perf = []
    perf_path = Path(perf_dir)
    if perf_path.is_dir():
        for run_dir in sorted(perf_path.iterdir()):
            if not run_dir.is_dir():
                continue
            run_name = run_dir.name
            run_date = _ts_from_dirname(run_name)
            for pf in sorted(run_dir.glob('perf_stat_*.txt')):
                node_ip = pf.stem.replace('perf_stat_', '')
                data = parse_perf_stat(str(pf))
                standalone_perf.append({
                    'perf_run': run_name,
                    'perf_date': run_date,
                    'node_ip': node_ip,
                    'perf_file': str(pf),
                    **data,
                })

    output_data = {
        'generated_at': datetime.now().isoformat(),
        'summary': {
            'total_benchmark_records': len(benchmark_records),
            'total_standalone_perf_records': len(standalone_perf),
            'archives_scanned': str(results_dir),
        },
        'benchmark_results': benchmark_records,
        'standalone_perf_results': standalone_perf,
    }

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(output_data, f, indent=2, ensure_ascii=False, default=str)

    print(f"Collected {len(benchmark_records)} benchmark records")
    print(f"Collected {len(standalone_perf)} standalone perf stat records")
    print(f"Output: {output_file}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Collect Ceph benchmark results into a single JSON file for Excel export')
    parser.add_argument('--results-dir', default='./results',
                        help='CBT archive root directory (default: ./results)')
    parser.add_argument('--perf-dir', default='./perf_results',
                        help='Standalone perf_results directory (default: ./perf_results)')
    parser.add_argument('--output', default='./benchmark_results.json',
                        help='Output JSON file path (default: ./benchmark_results.json)')
    args = parser.parse_args()

    collect(args.results_dir, args.perf_dir, args.output)
