#!/usr/bin/env python3
"""Pure source controls for tuple12 Workload lifecycle controls v4."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
V4 = ROOT / "qualification/tuple12-takeover/workload-controls-v4"
RUN = V4 / "run-workload.ps1"
TASK = V4 / "task-workload.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(run: str, task: str):
    run_needles = (
        "Add-Type -TypeDefinition @'",
        "public static class Sr0Tuple12PresentMonKernel",
        "WaitForSingleObject",
        "GetExitCodeProcess",
        "$pmHandle = $pmProc.Handle",
        "$pmKernelTerminal = [Sr0Tuple12PresentMonKernel]::Terminal",
        "$pmKernelExit -eq $pmDotnetExit",
        "$pmStdoutDone = if ($pmStdout) { $pmStdout.Wait(15000) }",
        "$pmStderrDone = if ($pmStderr) { $pmStderr.Wait(15000) }",
        "stdout_drained=$pmStdoutDone stderr_drained=$pmStderrDone",
        "PresentMon terminal/exit/drain proof missing",
    )
    for needle in run_needles:
        if needle not in run:
            fail("run-positive", needle)
    task_needles = (
        "$samplerTerminalAll = $true",
        "$samplerOut = $sampler.StandardOutput.ReadToEndAsync()",
        "$samplerErr = $sampler.StandardError.ReadToEndAsync()",
        "handle=$samplerHandle",
        "$samplerOutDrained = $samplerOut -and $samplerOut.Wait(15000)",
        "$samplerErrDrained = $samplerErr -and $samplerErr.Wait(15000)",
        "sampler-stdout.txt",
        "sampler-stderr.txt",
        "stream_drains run=$id worker_stdout=",
        "sampler_terminal=$([int]$samplerTerminalAll)",
        "catch { $samplerTerminalAll = $false;",
        "GetExitCodeProcess(h, out code)",
        "($samplerKernelCode -eq $samplerDotnetExit)",
    )
    for needle in task_needles:
        if needle not in task:
            fail("task-positive", needle)
    if task.count("static extern uint GetWindowThreadProcessId") != 1:
        fail("task-positive", "duplicate GetWindowThreadProcessId")
    if "$null = $sampler.StandardOutput.ReadToEndAsync()" in task:
        fail("task-positive", "sampler stdout discarded")


def main():
    run = RUN.read_text(encoding="utf-8")
    task = TASK.read_text(encoding="utf-8")
    positive(run, task)
    mutations = (
        ("sampler-initialized-false", lambda r, t: (r, t.replace("$samplerTerminalAll = $true", "$samplerTerminalAll = $false", 1))),
        ("sampler-stdout-discarded", lambda r, t: (r, t.replace("$samplerOut = $sampler.StandardOutput.ReadToEndAsync()", "$null = $sampler.StandardOutput.ReadToEndAsync()", 1))),
        ("sampler-stderr-not-drained", lambda r, t: (r, t.replace("$samplerErrDrained = $samplerErr -and $samplerErr.Wait(15000)", "$samplerErrDrained = $true", 1))),
        ("pm-kernel-proof-removed", lambda r, t: (r.replace("$pmKernelTerminal = [Sr0Tuple12PresentMonKernel]::Terminal", "$pmKernelTerminal = $true #", 1), t)),
        ("pm-exit-equality-removed", lambda r, t: (r.replace("$pmKernelExit -eq $pmDotnetExit", "$true", 1), t)),
        ("sampler-handle-removed", lambda r, t: (r, t.replace("handle=$samplerHandle", "handle=none"))),
    )
    caught = []
    for label, mutate in mutations:
        try:
            positive(*mutate(run, task))
        except AssertionError:
            caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 workload lifecycle v4 controls: PASS positive + 6 mutation faults")
    print("run_sha256=" + hashlib.sha256(RUN.read_bytes()).hexdigest())
    print("task_sha256=" + hashlib.sha256(TASK.read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
