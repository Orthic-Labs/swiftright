#!/usr/bin/env python3
"""Source checks only; root runs PowerShell, compiler, & matrix on Dell."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/matrix-controls-v8"
RUNNER = SRC / "run-matrix-v8.ps1"
HEADLESS = SRC / "headless-controls.ps1"


def require(text: str, *needles: str) -> None:
    for needle in needles:
        if needle not in text:
            raise AssertionError(f"missing control: {needle}")


def check_runner(src: str) -> None:
    require(src,
            "kind='sr0-tuple12-matrix-run-v8'", "Add-Type -Path $helperPath", "..\\workload-incremental-v6\\shared\\Sr0OwnedJobProcess.cs",
            "CreateSuspended(", "AssignProcessToJobObject", "ResumeThread($thread,$process)",
            "ConfigureJob($job,1073741824)", "WaitForSingleObject($process,1000)",
            "ReadActiveProcessCount($job", "cleanupZero=$cleanupZero", "activeProcesses=$active", "originalHandleRetained",
            "CopyToAsync", "CoordinatorStreamCapBytes", "CoordinatorRssCapBytes",
            "CoordinatorTimeoutSeconds = 1200", "TotalMatrixTimeoutSeconds = 10800",
            "effectiveDeadline", "TotalMatrixTimeoutSeconds-$matrixWatch.Elapsed.TotalSeconds",
            "WorkingSet64", "$peakRss", "rssExceeded", "TerminateJobObject($job",
            "TerminateProcess($process", "targetedDelivery=$true", "noActivate=$true",
            "jobMemoryBytes=1073741824", "rawStdout", "rawStderr",
            "Wait-LockFree", "lockReleased=$false", "scheduled-native-cleanup-proof",
            "if($null -ne $result){return $result}", "$result.cleanupZero=$cleanupZero",
            "[IO.FileMode]::CreateNew")
    if src.count("ReadActiveProcessCount($job") < 2:
        raise AssertionError("active-process proof must be read before & after cleanup")
    if "cleanupZero=$cleanupZero;timedOut" not in src:
        raise AssertionError("cleanup result must retain actual cleanupZero value")
    for bad in ("Start-Process", "ProcessStartInfo", "proc.Kill", "Get-Process", "Stop-Process", "Remove-Item", "Copy-Item", "WaitForExit()"):
        if bad in src:
            raise AssertionError(f"forbidden control: {bad}")


def check_headless(src: str) -> None:
    require(src, "Invoke-OwnedChild", "CreateSuspended(", "AssignProcessToJobObject", "ResumeThread($thread,$process)", "..\\workload-incremental-v6\\shared\\Sr0OwnedJobProcess.cs",
            "ConfigureJob($job,1073741824)", "CopyToAsync", "ReadActiveProcessCount", "cleanupZero",
            "timeout-fault", "originalHandleRetained=$true", "gui=$false", "desktopLock=$false", "nativeInput=$false")
    for bad in ("Start-Process", "ProcessStartInfo", "Remove-Item", "Copy-Item", "Get-Process", "Stop-Process", "SendInput"):
        if bad in src:
            raise AssertionError(f"forbidden headless control: {bad}")


def main() -> int:
    runner = RUNNER.read_text(encoding="utf-8")
    headless = HEADLESS.read_text(encoding="utf-8")
    check_runner(runner); check_headless(headless)
    faults = (
        ("drop-helper", lambda s: s.replace("Add-Type -Path $helperPath", "# helper omitted", 1)),
        ("drop-assignment", lambda s: s.replace("AssignProcessToJobObject($job,$process)", "$true", 1)),
        ("drop-active-proof", lambda s: s.replace("ReadActiveProcessCount($job,[ref]$active)", "$false")),
        ("drop-total-deadline", lambda s: s.replace("TotalMatrixTimeoutSeconds = 10800", "TotalMatrixTimeoutSeconds = 0", 1)),
        ("drop-cleanup", lambda s: s.replace("cleanupZero=$cleanupZero", "cleanupZero=$true", 1)),
        ("wrong-kind", lambda s: s.replace("matrix-run-v8", "matrix-run-v7", 1)),
        ("unbounded-wait", lambda s: s.replace("WaitForSingleObject($process,1000)", "WaitForExit()", 1)),
    )
    caught = []
    for label, mutate in faults:
        try:
            check_runner(mutate(runner))
        except AssertionError:
            caught.append(label)
    if len(caught) != len(faults):
        raise AssertionError(f"fault controls caught {caught}")
    print("tuple12 matrix v8 controls: PASS source guards + 7 mutation faults; no runtime launched")
    print("runner_sha256=" + hashlib.sha256(RUNNER.read_bytes()).hexdigest())
    print("headless_sha256=" + hashlib.sha256(HEADLESS.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
