#!/usr/bin/env python3
"""
Generate a simple summary report (CSV/Markdown) from CBT radosbench results.

This script is intentionally lightweight and only depends on the Python stdlib.

It scans a CBT archive directory created by:
  cbt.py --archive <archive_dir> <yaml>

And aggregates per-run metrics from either:
  - write/json_output.<proc>.<host>  (preferred; produced by CBT parsing)
  - write/output.<proc>.<host> or write/output.<proc> (fallback; raw rados bench output)

Example:
  python3 tools/radosbench_report.py --archive /tmp/cbt_archive/2025-12-18_152648 --csv /tmp/radosbench.csv --md /tmp/radosbench.md
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


@dataclass
class RadosBenchRow:
    archive: str
    iteration: str
    run_id: str
    phase: str  # write / prefill / seq / rand...
    host: str
    proc: str
    op_size: str
    concurrent_ops: str
    total_time_run_s: str
    total_ops: str
    bandwidth_mb_s: str
    avg_iops: str
    stddev_iops: str
    avg_latency_s: str
    stddev_latency_s: str
    max_latency_s: str
    min_latency_s: str


def _parse_key_value_summary(text: str) -> Dict[str, str]:
    """
    Parse the tail summary of `rados bench` output into a dict.
    We accept either:
      - "key: value" lines
      - mixed log lines above; we only start collecting after "Total time run"
    """
    lines = text.splitlines()
    start = 0
    for idx, line in enumerate(lines):
        if "Total time run" in line:
            start = idx
            break
    summary: Dict[str, str] = {}
    for line in lines[start:]:
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        summary[key.strip()] = val.strip()
    return summary


def _read_json_file(path: Path) -> Optional[Dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
        return None
    except Exception:
        return None


def _read_summary_from_run_dir(phase_dir: Path, proc: str, host: str) -> Tuple[Optional[Dict[str, str]], Optional[str]]:
    """
    Return (summary_dict, source_path_str)
    """
    # Preferred: parsed json output
    json_candidates = [
        phase_dir / f"json_output.{proc}.{host}",
        phase_dir / f"json_output.{proc}",
    ]
    for p in json_candidates:
        if p.exists() and p.stat().st_size > 0:
            jd = _read_json_file(p)
            if jd is not None:
                # CBT stores string values already; cast to str just in case
                return ({k: str(v) for k, v in jd.items()}, str(p))

    # Fallback: raw output file(s)
    out_candidates = [
        phase_dir / f"output.{proc}.{host}",
        phase_dir / f"output.{proc}",
    ]
    for p in out_candidates:
        if p.exists() and p.stat().st_size > 0:
            summary = _parse_key_value_summary(p.read_text(encoding="utf-8", errors="ignore"))
            return (summary, str(p))

    return (None, None)


_RE_OP_SIZE = re.compile(r"op_size-(\d+)")
_RE_CONC = re.compile(r"concurrent_ops-(\d+)")


def _extract_params_from_path(phase_dir: Path) -> Tuple[str, str]:
    """
    Extract op_size / concurrent_ops from .../op_size-00004096/concurrent_ops-00000016/<phase>
    """
    s = str(phase_dir)
    op = _RE_OP_SIZE.search(s)
    co = _RE_CONC.search(s)
    op_size = op.group(1) if op else ""
    concurrent_ops = co.group(1) if co else ""
    # normalize zero-padded values
    op_size = str(int(op_size)) if op_size else ""
    concurrent_ops = str(int(concurrent_ops)) if concurrent_ops else ""
    return op_size, concurrent_ops


def _iter_phase_dirs(archive_dir: Path) -> Iterable[Tuple[str, str, str, Path]]:
    """
    Yield (iteration, run_id, phase, phase_dir_path)
    """
    results_root = archive_dir / "results"
    if not results_root.exists():
        return
    for iter_dir in sorted(results_root.glob("[0-9]" * 8)):
        if not iter_dir.is_dir():
            continue
        iteration = iter_dir.name
        for run_dir in sorted(iter_dir.glob("id-*")):
            if not run_dir.is_dir():
                continue
            run_id = run_dir.name
            # radosbench stores phase subdirs like write/, prefill/, seq/, rand/
            for phase_dir in sorted(run_dir.glob("*")):
                if not phase_dir.is_dir():
                    continue
                phase = phase_dir.name
                # only keep likely phases (avoid logs/other)
                if phase in ("write", "prefill", "seq", "rand", "randread", "randwrite", "read", "write_only"):
                    yield iteration, run_id, phase, phase_dir
                # also accept any directory that contains json_output.* or output.*
                else:
                    if list(phase_dir.glob("json_output.*")) or list(phase_dir.glob("output.*")):
                        yield iteration, run_id, phase, phase_dir


def build_rows(archive_dir: Path, host: str = "", proc: str = "0") -> List[RadosBenchRow]:
    rows: List[RadosBenchRow] = []
    for iteration, run_id, phase, phase_dir in _iter_phase_dirs(archive_dir):
        # if host is not provided, try to infer it from existing filenames
        inferred_hosts: List[str] = []
        if not host:
            for p in phase_dir.glob(f"json_output.{proc}.*"):
                inferred_hosts.append(p.name.split(".", 2)[2])
            for p in phase_dir.glob(f"output.{proc}.*"):
                inferred_hosts.append(p.name.split(".", 2)[2])
            inferred_hosts = sorted(set(inferred_hosts))
        hosts = [host] if host else (inferred_hosts or [""])

        op_size, concurrent_ops = _extract_params_from_path(phase_dir)

        for h in hosts:
            summary, _src = _read_summary_from_run_dir(phase_dir, proc=proc, host=h)
            if not summary:
                continue

            total_ops = (
                summary.get("Total writes made")
                or summary.get("Total reads made")
                or summary.get("Total operations")
                or ""
            )
            rows.append(
                RadosBenchRow(
                    archive=str(archive_dir),
                    iteration=iteration,
                    run_id=run_id,
                    phase=phase,
                    host=h,
                    proc=proc,
                    op_size=op_size,
                    concurrent_ops=concurrent_ops,
                    total_time_run_s=summary.get("Total time run", ""),
                    total_ops=total_ops,
                    bandwidth_mb_s=summary.get("Bandwidth (MB/sec)", summary.get("Bandwidth", "")),
                    avg_iops=summary.get("Average IOPS", ""),
                    stddev_iops=summary.get("Stddev IOPS", ""),
                    avg_latency_s=summary.get("Average Latency(s)", summary.get("Average Latency", "")),
                    stddev_latency_s=summary.get("Stddev Latency(s)", ""),
                    max_latency_s=summary.get("Max latency(s)", ""),
                    min_latency_s=summary.get("Min latency(s)", ""),
                )
            )
    return rows


def write_csv(rows: List[RadosBenchRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for r in rows:
            writer.writerow(asdict(r))


def write_markdown(rows: List[RadosBenchRow], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    headers = [
        "iteration",
        "run_id",
        "phase",
        "op_size",
        "concurrent_ops",
        "host",
        "avg_iops",
        "bandwidth_mb_s",
        "avg_latency_s",
        "total_ops",
    ]
    lines: List[str] = []
    lines.append("|" + "|".join(headers) + "|")
    lines.append("|" + "|".join([":---"] * len(headers)) + "|")
    for r in rows:
        d = asdict(r)
        lines.append("|" + "|".join(str(d.get(h, "")) for h in headers) + "|")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description="Aggregate CBT radosbench results into a simple CSV/Markdown report.")
    ap.add_argument("--archive", required=True, help="CBT archive directory (the one passed to cbt.py --archive)")
    ap.add_argument("--host", default="", help="Optional host IP/name suffix used in output filenames (default: auto-detect)")
    ap.add_argument("--proc", default="0", help="Process index to report (default: 0)")
    ap.add_argument("--csv", default="", help="Write CSV summary to this file")
    ap.add_argument("--md", default="", help="Write Markdown summary table to this file")
    args = ap.parse_args()

    archive_dir = Path(args.archive).expanduser().resolve()
    rows = build_rows(archive_dir, host=args.host, proc=str(args.proc))
    if not rows:
        print(f"No radosbench results found under {archive_dir}")
        return 2

    # deterministic ordering
    rows.sort(key=lambda r: (r.iteration, r.run_id, r.phase, int(r.op_size or "0"), int(r.concurrent_ops or "0"), r.host, int(r.proc)))

    if args.csv:
        write_csv(rows, Path(args.csv))
        print(f"Wrote CSV report: {args.csv}")
    if args.md:
        write_markdown(rows, Path(args.md))
        print(f"Wrote Markdown report: {args.md}")

    # default: print a tiny summary
    if not args.csv and not args.md:
        print(f"Found {len(rows)} result rows under {archive_dir}")
        for r in rows[:10]:
            print(r)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())


