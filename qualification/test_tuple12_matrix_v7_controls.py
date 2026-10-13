#!/usr/bin/env python3
"""Source controls for bounded tuple12 matrix runner v7.

This file performs no PowerShell, native, GUI, lock, network, or process action.
Root runs headless-controls.ps1 separately after Dell parser review.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/matrix-controls-v7"
RUNNER = SRC / "run-matrix-v7.ps1"
HEADLESS = SRC / "headless-controls.ps1"


def require(text: str, *needles: str) -> None:
    for needle in needles:
        if needle not in text:
            raise AssertionError(f"missing control: {needle}")


def check_runner(src: str) -> None:
    require(
        src,
        "kind='sr0-tuple12-matrix-run-v7'",
        "[ValidateRange(30,300)][int]$CoordinatorTimeoutSeconds = 300",
        "[ValidateRange(1048576,67108864)][int64]$CoordinatorStreamCapBytes = 8388608",
        "[ValidateRange(134217728,4294967296)][int64]$CoordinatorRssCapBytes = 2147483648",
        "WaitForSingleObject($handle,1000)",
        "$originalHandle",
        "$proc.WorkingSet64",
        "$peakRss",
        "$rssSamples",
        "CoordinatorStreamCapBytes",
        "CoordinatorRssCapBytes",
        "if ($timedOut -or $outputExceeded -or $rssExceeded)",
        "$proc.Kill()",
        "terminateAttempted",
        "terminateSucceeded",
        "streamsDrained",
        "if ($coordInfo.timedOut -or $coordInfo.outputExceeded -or $coordInfo.rssExceeded)",
        "$abortRemaining = $true",
        "if ($abortRemaining) { break }",
        "Read-BoundedText",
        "[IO.FileMode]::CreateNew",
        "targetedDelivery=$true",
        "noActivate=$true",
    )
    if "WaitForExit()" in src:
        raise AssertionError("unbounded coordinator WaitForExit remains")
    for forbidden in ("Remove-Item", "Copy-Item", "Stop-Process", "Get-Process", "Stop-ScheduledTask"):
        if forbidden in src:
            raise AssertionError(f"forbidden global/destructive control: {forbidden}")


def check_headless(src: str) -> None:
    require(
        src,
        "Invoke-OwnedChild",
        "CreateNoWindow = $true",
        "$handle = $proc.Handle",
        "WaitForSingleObject($handle,1000)",
        "GetExitCodeProcess($handle",
        "CopyToAsync",
        "$outTask.Wait(5000)",
        "$errTask.Wait(5000)",
        "$proc.Kill()",
        "expectedTimeout",
        "timeout-fault",
        "originalHandleRetained",
        "[IO.FileMode]::CreateNew",
        "gui=$false",
        "desktopLock=$false",
        "nativeInput=$false",
    )
    for forbidden in ("Start-Process", "Remove-Item", "Copy-Item", "Get-Process", "Stop-Process", "SendKeys", "SendInput"):
        if forbidden in src:
            raise AssertionError(f"forbidden headless control: {forbidden}")


def positive(runner: str, headless: str) -> None:
    check_runner(runner)
    check_headless(headless)


def main() -> int:
    runner = RUNNER.read_text(encoding="utf-8")
    headless = HEADLESS.read_text(encoding="utf-8")
    positive(runner, headless)
    faults = (
        ("unbounded-wait", lambda s: s.replace("WaitForSingleObject($handle,1000)", "WaitForExit()", 1)),
        ("drop-rss", lambda s: s.replace("$proc.WorkingSet64", "$proc.PrivateMemorySize64", 1)),
        ("drop-kill", lambda s: s.replace("$proc.Kill()", "$null", 1)),
        ("drop-abort", lambda s: s.replace("$abortRemaining = $true", "$abortRemaining = $false", 2)),
        ("wrong-kind", lambda s: s.replace("kind='sr0-tuple12-matrix-run-v7'", "kind='sr0-tuple12-matrix-run-v6'", 1)),
    )
    caught = []
    for label, mutate in faults:
        try:
            check_runner(mutate(runner))
        except AssertionError:
            caught.append(label)
    if len(caught) != len(faults):
        raise AssertionError(f"fault controls caught {caught}")
    print("tuple12 matrix v7 controls: PASS positive + 5 mutation faults; Dell headless controls prepared")
    print("runner_sha256=" + hashlib.sha256(RUNNER.read_bytes()).hexdigest())
    print("headless_sha256=" + hashlib.sha256(HEADLESS.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
