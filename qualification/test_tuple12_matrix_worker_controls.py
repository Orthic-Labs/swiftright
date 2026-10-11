#!/usr/bin/env python3
"""Pure source controls for matrix worker-v3 failure cleanup.

No PowerShell, process, task, filesystem output, or remote host is used.
"""
from pathlib import Path


WORKER = Path(__file__).parents[1] / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-matrix-v1/worker-v3.ps1"


def require(text: str, needles: tuple[str, ...]) -> bool:
    return all(needle in text for needle in needles)


def main() -> int:
    text = WORKER.read_text(encoding="utf-8")
    positive = (
        "[string]::IsNullOrWhiteSpace($rawPath)",
        "$proof.pathObservation.blank",
        "[IO.Path]::GetFullPath($rawPath)",
        "$driverProc.WaitForExit(30000)",
        "$childProc.WaitForExit(30000)",
        "$stdoutTask.GetAwaiter().GetResult()",
        "Kernel-Terminal $driverHandle",
        "Kernel-Terminal $childHandle",
        "[IO.FileMode]::CreateNew",
    )
    if not require(text, positive):
        print("WORKER_CONTROLS_FAIL positive")
        return 1
    faults = {
        "blank-path-retry-removed": ("if ([string]::IsNullOrWhiteSpace($rawPath))", "if ($false)"),
        "driver-cleanup-removed": ("$driverProc.WaitForExit(30000)", "$driverProc.WaitForExit(1)"),
        "child-cleanup-removed": ("$childProc.WaitForExit(30000)", "$childProc.WaitForExit(1)"),
        "stream-drain-removed": ("$stdoutTask.GetAwaiter().GetResult()", "$stdoutTask.GetAwaiter().GetResultX()"),
        "kernel-proof-removed": ("Kernel-Terminal $childHandle", "Kernel-Terminal $removedHandle"),
    }
    for name, (old, replacement) in faults.items():
        mutated = text.replace(old, replacement)
        if require(mutated, positive):
            print(f"WORKER_CONTROLS_FAIL {name}")
            return 1
        print(f"WORKER_CONTROLS_PASS {name}")
    print(f"WORKER_CONTROLS_PASS positive={len(positive)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
