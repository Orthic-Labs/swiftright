#!/usr/bin/env python3
"""Pure controls for tuple12 workload v8 source successors.

No native launch, file mutation, network, or receipt claim is performed.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
RUNNER = ROOT / "tuple12-takeover/workload-controls-v8/run-workload.ps1"
ANALYZER = ROOT / "tuple12-takeover/workload-analysis-v2/analyze_workload.py"
TASK = ROOT / "tuple12-takeover/workload-controls-v8/task-workload.ps1"


def main() -> int:
    runner = RUNNER.read_text(encoding="utf-8")
    analyzer = ANALYZER.read_text(encoding="utf-8")
    task = TASK.read_text(encoding="utf-8")
    failures: list[str] = []

    pid_re = re.compile(r"pid run=(\S+) pid=(\d+)(?: handle=[1-9]\d*)? start_utc=\S+ qpc_start=(\d+)")
    if not pid_re.search("pid run=r1 pid=7 handle=9 start_utc=2026-01-01T00:00:00Z qpc_start=10"):
        failures.append("v7 handle-bearing pid line is not accepted")
    if not pid_re.search("pid run=r1 pid=7 start_utc=2026-01-01T00:00:00Z qpc_start=10"):
        failures.append("legacy pid line is not accepted")
    if pid_re.search("pid run=r1 pid=7 handle=0 start_utc=x qpc_start=10"):
        failures.append("zero handle mutation unexpectedly accepted")
    if "presentmon.console.txt" not in runner or "WriteAllText" not in runner:
        failures.append("joined PresentMon console receipt write missing")
    if "--incremental \"$Base\\incremental.json\"" not in runner:
        failures.append("explicit Base incremental receipt binding missing")
    if "configuration" not in analyzer or "release" not in analyzer:
        failures.append("release configuration gate missing")
    if "incremental_check" not in analyzer:
        failures.append("incremental gate missing")
    if "-NoActivate" not in runner or "NoActivate" not in task:
        failures.append("NoActivate path missing")
    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        return 1
    print("PASS v8 source controls: handle PID join, console receipt, incremental binding, release/incremental gates, NoActivate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
