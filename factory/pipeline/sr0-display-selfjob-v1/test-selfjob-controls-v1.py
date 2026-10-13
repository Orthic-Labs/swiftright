#!/usr/bin/env python3
"""Source controls for interactive self-job envelope; no native execution."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

MAX_SOURCE = 256 * 1024


def read(path: Path) -> str:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_SOURCE:
        raise ValueError("source missing, symlink, or exceeds bound")
    return path.read_text(encoding="utf-8-sig")


def validate(source: str) -> None:
    required = (
        "CreateJob()", "ConfigureJob($job,1073741824)",
        "ReadJobFlags", "AssignProcessToJobObject",
        "ReadActiveProcessCount", "activeReadableBefore", "activeReadableAfter",
        "worker_terminal=1", "sampler_terminal=1", "task_quiescent=1",
        "releaseAllowed", "Release-Lock", "killOnJobClose=$true",
        "-LifecycleProof", "-NoActivate:$NoActivate",
    )
    missing = [token for token in required if token not in source]
    if missing:
        raise ValueError("self-job source missing: " + ",".join(missing))
    forbidden = ("Start-Process", "Stop-Process", "taskkill", "Get-Process | ForEach-Object", "Get-Process * |")
    present = [token for token in forbidden if token.lower() in source.lower()]
    if present:
        raise ValueError("unowned process action present: " + ",".join(present))
    if source.count("ReadActiveProcessCount") < 2:
        raise ValueError("active-count proof is not both pre/post workload")
    admission = source.find("$releaseAllowed=[bool]")
    release = source.rfind("Release-Lock $lockOwner")
    if admission < 0 or release < admission:
        raise ValueError("lock release appears before release admission")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        source = read(args.source)
        validate(source)
        result = {
            "schema": "sr0-display-selfjob-controls-v1",
            "status": "source-admitted",
            "proofs": ["self-job-before-workload", "job-memory-1GiB", "renderer-terminal", "display-sampler-terminal", "active-self-only", "lock-release-gated"],
            "nativeActions": 0,
            "lockActions": 0,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError) as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    print(json.dumps({"status": result["status"], "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
