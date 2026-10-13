#!/usr/bin/env python3
"""Source controls for reviewed v2 self-job envelope; no native execution."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

MAX_SOURCE = 256 * 1024


def read(path: Path) -> str:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_SOURCE:
        raise ValueError("source missing, symlink, or exceeds bound")
    return path.read_text(encoding="utf-8-sig")


def validate(source: str, helper: str) -> None:
    required = (
        "CreateCurrentProcess(1073741824)", "JobMemoryOnlyFlags", "WaitForOnlyCurrent(30000)",
        "RequireOnlyCurrent", "helperSha256", "frozenTaskSha256", "Get-FileHash",
        "WorkloadWin.exe", "kernel_terminal=1", "handle=(?!0)", "worker_terminal=1",
        "sampler_terminal=1", "task_quiescent=1", "Release-Lock", "killOnJobClose=$false",
    )
    missing = [token for token in required if token not in source]
    if missing:
        raise ValueError("v2 source missing: " + ",".join(missing))
    if "CreateCurrentProcess" not in helper or "JobMemoryOnlyFlags = 0x200" not in helper or "CloseHandle" not in helper:
        raise ValueError("reviewed v15 helper pin missing")
    if "Register-ScheduledTask" in source or "Start-ScheduledTask" in source or "Start-Process" in source or "taskkill" in source:
        raise ValueError("workload must be direct child of self-job")
    if source.count("Get-FileHash") < 2:
        raise ValueError("helper & frozen source hashes must both be admitted")
    if source.rfind("Release-Lock $lockOwner") < source.find("$releaseAllowed=[bool]"):
        raise ValueError("lock release precedes proof admission")


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--source", required=True, type=Path); ap.add_argument("--helper", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        source = read(args.source); helper = read(args.helper); validate(source, helper)
        result = {"schema": "sr0-display-selfjob-controls-v2", "status": "source-admitted", "helper": "reviewed-v15-job-memory-only", "proofs": ["exact-source-hashes", "direct-WorkloadWin-source", "self-job-before-workload", "job-memory-1GiB-0x200", "retained-host-kernel-handle", "renderer-terminal", "display-sampler-terminal", "active-self-only", "lock-release-gated"], "nativeActions": 0, "lockActions": 0}
        args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError) as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    print(json.dumps({"status": result["status"], "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0


if __name__ == "__main__": raise SystemExit(main())
