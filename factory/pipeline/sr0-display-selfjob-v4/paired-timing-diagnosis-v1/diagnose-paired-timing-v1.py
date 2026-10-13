#!/usr/bin/env python3
"""Bounded report-only Windows/Mac timing diagnosis.

Reads existing analyzer/report JSON only. It never reads raw trees recursively,
rewrites receipts, launches analyzer/native work, or claims parity.
"""
from __future__ import annotations
import argparse, hashlib, json, os
from pathlib import Path

CAP = 4 * 1024 * 1024

def fail(message: str) -> None:
    raise SystemExit(message)

def read_json(path: Path) -> tuple[dict, str, int]:
    if path.is_symlink() or not path.is_file():
        fail(f"report must be regular file: {path}")
    size = path.stat().st_size
    if size > CAP:
        fail(f"report exceeds {CAP} bytes: {path}")
    raw = path.read_bytes()
    try:
        value = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        fail(f"invalid report JSON {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"report must be JSON object: {path}")
    return value, hashlib.sha256(raw).hexdigest(), size

def fresh_json(path: Path, value: dict) -> None:
    if path.exists() or path.is_symlink():
        fail(f"fresh output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temp.open("xb") as stream:
            stream.write((json.dumps(value, indent=2, sort_keys=True) + "\n").encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()

def first_run(report: dict) -> tuple[str, dict]:
    runs = report.get("runs")
    if isinstance(runs, dict):
        if len(runs) != 1:
            fail("Windows strict report must contain exactly one run")
        run_id, run = next(iter(runs.items()))
        if not isinstance(run_id, str) or not isinstance(run, dict):
            fail("Windows strict report run entry is invalid")
        return run_id, run
    if isinstance(runs, list) and len(runs) == 1 and isinstance(runs[0], dict):
        return "r1", runs[0]
    fail("Windows strict report must contain exactly one run")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows-report", required=True)
    ap.add_argument("--mac-report", required=True)
    ap.add_argument("--output", required=True)
    ns = ap.parse_args()
    windows_path = Path(ns.windows_report).resolve()
    mac_path = Path(ns.mac_report).resolve()
    output = Path(ns.output).resolve()
    windows, windows_sha, windows_bytes = read_json(windows_path)
    mac, mac_sha, mac_bytes = read_json(mac_path)
    run_id, run = first_run(windows)
    summary = run.get("summary")
    if not isinstance(summary, dict):
        fail("Windows strict report run summary missing")
    required = ("presents_in_window", "displayed_in_window", "refresh_ms", "visible_ms", "presented_interval_ms", "clock_correlation_ms")
    if any(key not in summary for key in required):
        fail("Windows strict report timing fields incomplete")
    mac_required = ("requiredRuns", "observedRuns", "passedRuns", "status")
    if any(key not in mac for key in mac_required):
        fail("Mac F1 report identity fields incomplete")
    windows_timing = {
        "presentsInWindow": summary["presents_in_window"],
        "displayedInWindow": summary["displayed_in_window"],
        "expectedRows": summary.get("rows"),
        "refreshMs": summary["refresh_ms"],
        "visibleMs": summary["visible_ms"],
        "presentedIntervalMs": summary["presented_interval_ms"],
        "clockCorrelationMs": summary["clock_correlation_ms"],
        "missedVblanks": summary.get("missed_vblanks"),
        "droppedInWindow": summary.get("pm_dropped_in_window"),
        "runId": run_id,
        "invalid": run.get("invalid", []),
    }
    mac_timing = {
        "status": mac["status"],
        "requiredRuns": mac["requiredRuns"],
        "observedRuns": mac["observedRuns"],
        "passedRuns": mac["passedRuns"],
        "timingFieldsPresent": False,
        "hold": "Mac F1 report carries capture identities/qualification, not comparable visible timing percentiles",
    }
    result = {
        "kind": "sr0-display-paired-timing-diagnosis-v1",
        "status": "diagnostic-held",
        "qualificationClaim": False,
        "parityClaim": False,
        "inputs": {
            "windowsReport": {"path": str(windows_path), "bytes": windows_bytes, "sha256": windows_sha},
            "macReport": {"path": str(mac_path), "bytes": mac_bytes, "sha256": mac_sha},
        },
        "windows": {"overall": windows.get("overall"), "timing": windows_timing},
        "mac": mac_timing,
        "comparison": {
            "status": "held",
            "reason": "no-worse-than-Mac comparison requires comparable Mac timing report; existing Mac F1 report has no visible timing percentile fields",
            "thresholdsUnchanged": True,
            "requiredNextInput": "fresh Mac timing report with raw timing refs joined to same case/tuple",
        },
    }
    fresh_json(output, result)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
