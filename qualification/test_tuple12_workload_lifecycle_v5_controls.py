#!/usr/bin/env python3
"""Pure source controls for tuple12 Workload lifecycle controls v5."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
V5 = ROOT / "qualification/tuple12-takeover/workload-controls-v5"
RUN = V5 / "run-workload.ps1"
TASK = V5 / "task-workload.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(run: str, task: str):
    for needle in (
        "public static class Sr0Tuple12PresentMonKernel",
        "$pmHandle = $pmProc.Handle",
        "$pmKernelTerminal = [Sr0Tuple12PresentMonKernel]::Terminal",
        "$pmDotnetExit = if ($pmProc.HasExited) { [int64]$pmProc.ExitCode }",
        "$pmKernelExitSigned = if ([uint64]$pmKernelExit -gt 2147483647)",
        "$pmStopMode = if ($pmForcedStop) { 'forced-owned' } else { 'natural' }",
        "$pmKernelExitSigned -eq $pmDotnetExit",
        "stop=$pmStopMode",
        "$pmStdoutDone = if ($pmStdout) { $pmStdout.Wait(15000) }",
        "$pmStderrDone = if ($pmStderr) { $pmStderr.Wait(15000) }",
        "stdout_drained=$pmStdoutDone stderr_drained=$pmStderrDone",
        "PresentMon terminal/exit/drain proof missing",
        "-NoActivate",
    ):
        if needle not in run:
            fail("run-positive", needle)
    for needle in (
        "[switch]$NoActivate",
        "--sr0-noactivate",
        "if ($NoActivate -and $psi.Arguments -notmatch",
        "pid run=$id pid=$($proc.Id) handle=$workerHandle",
        "[Inj]::BottomNoActivate",
        "startup_activation=guarded",
        "$samplerOut = $sampler.StandardOutput.ReadToEndAsync()",
        "$samplerErr = $sampler.StandardError.ReadToEndAsync()",
        "handle=$samplerHandle",
        "GetExitCodeProcess(h, out code)",
        "($samplerKernelCode -eq $samplerDotnetExit)",
        "stream_drains run=$id worker_stdout=",
    ):
        if needle not in task:
            fail("task-positive", needle)
    if "$null = $sampler.StandardOutput.ReadToEndAsync()" in task:
        fail("task-positive", "sampler stdout discarded")
    if "[Inj]::Acquire($hwnd" in task and "if ($NoActivate)" not in task:
        fail("task-positive", "noactivate branch missing")
    if task.count("static extern uint GetWindowThreadProcessId") != 1:
        fail("task-positive", "duplicate GetWindowThreadProcessId")


def main():
    run = RUN.read_text(encoding="utf-8")
    task = TASK.read_text(encoding="utf-8")
    positive(run, task)
    mutations = (
        ("unsigned-pm-exit", lambda r, t: (r.replace("$pmKernelExitSigned = if ([uint64]$pmKernelExit -gt 2147483647)", "$pmKernelExitSigned = $pmKernelExit", 1), t)),
        ("forced-stop-unrecorded", lambda r, t: (r.replace("$pmStopMode = if ($pmForcedStop) { 'forced-owned' } else { 'natural' }", "$pmStopMode = 'natural'", 1), t)),
        ("pm-exit-equality-removed", lambda r, t: (r.replace("$pmKernelExitSigned -eq $pmDotnetExit", "$true", 1), t)),
        ("startup-guard-param-removed", lambda r, t: (r, t.replace("[switch]$NoActivate", "[switch]$Unused", 1))),
        ("worker-handle-removed", lambda r, t: (r, t.replace("handle=$workerHandle", "handle=none", 1))),
        ("sampler-handle-removed", lambda r, t: (r, t.replace("handle=$samplerHandle", "handle=none"))),
        ("forwarded-noactivate-removed", lambda r, t: (r.replace("$(if ($NoActivate) { ' -NoActivate' })", "", 1), t)),
    )
    caught=[]
    for label, mutate in mutations:
        try: positive(*mutate(run, task))
        except AssertionError: caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 workload lifecycle v5 controls: PASS positive + 7 mutation faults")
    print("run_sha256=" + hashlib.sha256(RUN.read_bytes()).hexdigest())
    print("task_sha256=" + hashlib.sha256(TASK.read_bytes()).hexdigest())
    print("controls_sha256=" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
