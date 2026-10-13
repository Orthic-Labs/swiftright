#!/usr/bin/env python3
"""Pure controls for materialized tuple12 Workload lifecycle/noactivate successor."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT / "qualification/tuple12-takeover/workload-controls-v2"
RUN = V2 / "run-workload.ps1"
TASK = V2 / "task-workload.ps1"
PINS = V2 / "source-pins.json"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(run, task):
    run_needles = (
        "[switch]$LifecycleProof",
        "[switch]$NoActivate",
        "$(if ($LifecycleProof) { ' -LifecycleProof' })$(if ($NoActivate) { ' -NoActivate' })",
        "fresh run root",
        "Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -ErrorAction Stop",
        "Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop",
        "$analysisRc = $LASTEXITCODE",
        "if ($LifecycleProof) { exit $analysisRc }",
    )
    for needle in run_needles:
        if needle not in run:
            fail("run-positive", needle)
    if "`$analysisRc" in run or "`$LifecycleProof" in run:
        fail("run-positive", "literal backtick before PowerShell variable")
    # Force remains only in legacy/default branch; lifecycle registration is fail-closed.
    if "Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -Force" not in run:
        fail("default-branch", "legacy -Force branch disappeared")
    if "if ($LifecycleProof) {" not in run or "} else {" not in run:
        fail("default-branch", "explicit lifecycle/default split missing")

    task_needles = (
        "[switch]$LifecycleProof",
        "BottomNoActivate",
        "WindowPid(hwnd) != pid",
        "GetExitCodeProcess",
        "return code != 259",
        "($kernelCode -eq $dotnetExit)",
        "($samplerKernelCode -eq $samplerDotnetExit)",
        "$proc.WaitForExit(15000)",
        "$sampler.WaitForExit(15000)",
        "$so.Wait(15000)",
        "$se.Wait(15000)",
        "$samplerErr.Wait(15000)",
        "worker_terminal=$([int]$workerTerminalAll)",
        "task_quiescent=$([int]($workerTerminalAll -and $samplerTerminalAll))",
        "window-owner-mismatch",
        "startup_activation=guarded",
    )
    for needle in task_needles:
        if needle not in task:
            fail("task-positive", needle)
    if ".Result" not in task:
        fail("drain-positive", "completed async results absent")
    if "$stdoutText = if ($stdoutDrained)" not in task or "$stderrText = if ($stderrDrained)" not in task:
        fail("drain-positive", "bounded fallback absent")


def main():
    run = RUN.read_text(encoding="utf-8")
    task = TASK.read_text(encoding="utf-8")
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    if hashlib.sha256(RUN.read_bytes()).hexdigest() != pins["overlay_source"]["run_workload_sha256"]:
        fail("pin", "run materialization hash drift")
    if hashlib.sha256(TASK.read_bytes()).hexdigest() != pins["overlay_source"]["task_workload_sha256"]:
        fail("pin", "task materialization hash drift")
    positive(run, task)
    faults = []
    mutations = (
        ("remove-native-terminal", "GetExitCodeProcess"),
        ("remove-still-active-check", "return code != 259"),
        ("remove-dotnet-equality", "($kernelCode -eq $dotnetExit)"),
        ("remove-kill-drain", "$proc.WaitForExit(15000)"),
        ("remove-stream-drain", "$so.Wait(15000)"),
        ("remove-terminal-receipt", "worker_terminal=$([int]$workerTerminalAll)"),
        ("remove-sampler-stream-drain", "$samplerErr.Wait(15000)"),
        ("remove-noactivate-forward", "{ ' -NoActivate' }"),
    )
    for label, needle in mutations:
        mutated = run + "\n" + task
        mutated = mutated.replace(needle, "")
        try:
            positive(mutated, mutated)
        except AssertionError:
            faults.append(label)
    if len(faults) != len(mutations):
        fail("fault-controls", f"caught {faults}")
    print("tuple12 workload lifecycle v2 controls: PASS positive + 8 mutation faults")
    print("run_sha256=" + hashlib.sha256(RUN.read_bytes()).hexdigest())
    print("task_sha256=" + hashlib.sha256(TASK.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
