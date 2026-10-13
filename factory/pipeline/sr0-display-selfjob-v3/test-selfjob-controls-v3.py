#!/usr/bin/env python3
"""Source controls for reviewed v3 self-job envelope; no native execution."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

MAX_SOURCE = 256 * 1024


def read(path: Path) -> str:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_SOURCE:
        raise ValueError("source missing, symlink, or exceeds bound")
    return path.read_text(encoding="utf-8-sig")


def validate(source: str, helper: str, frozen: str) -> None:
    required = (
        "CreateCurrentProcess(1073741824)", "JobMemoryOnlyFlags", "WaitForOnlyCurrent(30000)",
        "RequireOnlyCurrent", "helperSha256", "frozenTaskSha256", "Get-FileHash",
        "WorkloadWin.exe", "kernel_terminal=1", "kernel_exit_raw=", "kernel_exit=", "dotnet_exit=",
        "sampler_kernel_terminal=1", "sampler_kernel_exit_raw=", "sampler_kernel_exit=", "sampler_dotnet_exit=",
        "stdout_drained=", "stderr_drained=", "stream_drains run=", "worker_stdout=1", "worker_stderr=1", "worker_terminal=1", "sampler_terminal=1", "task_quiescent=1",
        "runs_valid=$Runs of $Runs", "replace \"`r\",''", "Release-Lock", "killOnJobClose=$false",
    )
    missing = [token for token in required if token not in source]
    if missing:
        raise ValueError("v3 source missing: " + ",".join(missing))
    if "CreateCurrentProcess" not in helper or "JobMemoryOnlyFlags = 0x200" not in helper or "CloseHandle" not in helper:
        raise ValueError("reviewed v15 helper pin missing")
    if "Register-ScheduledTask" in source or "Start-ScheduledTask" in source or "Start-Process" in source or "taskkill" in source:
        raise ValueError("workload must be direct child of self-job")
    frozen_tokens = (
        "System.Diagnostics.ProcessStartInfo", "[System.Diagnostics.Process]::Start", "WorkloadWin.exe",
        "pid_exit run=", "handle=$workerHandle", "kernel_terminal=", "kernel_exit_raw=", "kernel_exit=", "dotnet_exit=",
        "resources run=", "sampler_kernel_terminal=", "sampler_kernel_exit_raw=", "sampler_kernel_exit=",
        "sampler_dotnet_exit=", "stdout_drained=", "stderr_drained=", "stream_drains run=", "worker_stdout=1", "worker_stderr=1", "worker_terminal=", "sampler_terminal=",
        "task_quiescent=", "finished=$(Get-Date -Format o) runs_valid=$okRuns of $Runs",
    )
    absent = [token for token in frozen_tokens if token not in frozen]
    if absent:
        raise ValueError("frozen v8 receipt contract missing: " + ",".join(absent))
    if "Register-ScheduledTask" in frozen or "Start-ScheduledTask" in frozen or "Start-Process" in frozen:
        raise ValueError("frozen task must launch direct WorkloadWin child")
    if source.count("Get-FileHash") < 2:
        raise ValueError("helper & frozen source hashes must both be admitted")
    if source.rfind("Release-Lock $lockOwner") < source.find("$releaseAllowed=[bool]"):
        raise ValueError("lock release precedes proof admission")


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--source", required=True, type=Path); ap.add_argument("--helper", required=True, type=Path); ap.add_argument("--frozen-task", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        source = read(args.source); helper = read(args.helper); frozen = read(args.frozen_task); validate(source, helper, frozen)
        result = {"schema": "sr0-display-selfjob-controls-v3", "status": "source-admitted", "helper": "reviewed-v15-job-memory-only", "proofs": ["exact-source-hashes", "direct-WorkloadWin-source", "self-job-before-workload", "job-memory-1GiB-0x200", "retained-host-kernel-handle", "renderer-terminal", "display-sampler-terminal", "active-self-only", "lock-release-gated"], "nativeActions": 0, "lockActions": 0}
        args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, ValueError) as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    print(json.dumps({"status": result["status"], "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0


if __name__ == "__main__": raise SystemExit(main())
