#!/usr/bin/env python3
"""Source-only controls for root display launch packet."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parent
ENVELOPE = ROOT / "run-display-root-launch-v1.ps1"
SCHEDULER = ROOT / "schedule-root-launch-v1.ps1"
PINS = ROOT / "source-pins.json"


def need(ok, msg):
    if not ok:
        raise AssertionError(msg)


def ordered(s, *parts):
    pos = [s.index(x) for x in parts]
    need(pos == sorted(pos), f"order fault: {parts}")


def check_envelope(s):
    for x in (
        "ChildScriptPath", "HelperPath", "ProcessIdToSessionId", "WTSGetActiveConsoleSessionId",
        "CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)",
        "ConfigureJobWithFlags($job,[Sr0OwnedJobProcess]::JobObjectLimitJobMemory,1073741824)",
        "ReadJobFlags($job,[ref]$memoryFlags)", "JobObjectLimitJobMemory", "memoryFlags -ne",
        "CreateSuspended(", "CopyToAsync($outFile)", "CopyToAsync($errFile)",
        "AssignProcessToJobObject($job,$process)", "ResumeThread($thread,$process)",
        "WaitForSingleObject($x.Process,1000)", "TerminateJobObject($x.Job,124)",
        "ReadActiveProcessCount($x.Job", "cleanupZero=$cleanupZero", "GetExitCodeProcess($x.Process,[ref]$exitCode)",
        "streamsDrained", "activeProcesses=$active", "KillOnJobClose=$false", "runResult.exitCode -eq 0", "samplerResult.exitCode -eq 0", "runResult.timedOut", "samplerResult.timedOut", "if(-not $result.cleanupZero -or -not $result.exitAccepted){throw",
        "memoryLimitBytes=1073741824", "memoryLimitFlags=0x200", "taskQuiescent", "lockReleased",
        "[IO.FileMode]::CreateNew",
    ):
        need(x in s, f"missing envelope guard: {x}")
    for bad in ("ConfigureJob($job,1073741824)", "JobObjectLimitKillOnJobClose", "Register-ScheduledTask", "Start-ScheduledTask", "Start-Process", "Stop-Process", "taskkill", "PostMessage", "SendInput", "Get-Process"):
        need(bad not in s, f"forbidden envelope behavior: {bad}")
    ordered(s, "CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)", "$owned=Start-OwnedChild")
    ordered(s, "CopyToAsync($outFile)", "AssignProcessToJobObject($job,$process)", "ResumeThread($thread,$process)")
    need(s.count("ReadActiveProcessCount($x.Job") >= 2, "active process cleanup proof missing")
    need("$result.cleanupZero" in s and "$result.exitAccepted" in s and "$childReceiptValid" in s, "success proof incomplete")


def check_scheduler(s):
    for x in (
        "run-display-root-launch-v1.ps1", "run-one-diagnostic.ps1", "Sr0OwnedJobProcess.cs",
        "New-ScheduledTaskPrincipal", "-LogonType Interactive", "-RunLevel Highest",
        "Register-ScheduledTask", "Start-ScheduledTask", "interactive-highest", "0x200", "killOnJobClose=$false",
    ):
        need(x in s, f"missing scheduler binding: {x}")
    need("-Force" not in s and "Unregister-ScheduledTask" not in s, "scheduler overwrites/removes task")


def main():
    env = ENVELOPE.read_text(encoding="utf-8")
    sched = SCHEDULER.read_text(encoding="utf-8")
    for p in (ENVELOPE, SCHEDULER):
        need(p.stat().st_size <= 512 * 1024, f"source too large: {p}")
    check_envelope(env); check_scheduler(sched)
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    need(pins["runtimePolicy"]["killOnJobClose"] is False, "pin permits kill-on-close")
    need(pins["runtimePolicy"]["memoryLimitFlags"] == "0x200", "memory flag pin")
    faults = (
        ("drop-active-session", lambda x: x.replace("CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)", "MissingSessionCheck([ref]$currentSession,[ref]$activeConsoleSession)", 1)),
        ("enable-kill-on-close", lambda x: x.replace("JobObjectLimitJobMemory,1073741824", "JobObjectLimitKillOnJobClose,1073741824", 1)),
        ("drop-memory-flags", lambda x: x.replace("ReadJobFlags($job,[ref]$memoryFlags)", "MissingFlags($job,[ref]$memoryFlags)", 1)),
        ("resume-before-assignment", lambda x: x.replace("AssignProcessToJobObject($job,$process)", "ResumeThread($thread,$process)`n    AssignProcessToJobObject($job,$process)", 1)),
        ("drop-active-proof", lambda x: x.replace("ReadActiveProcessCount($x.Job", "MissingActiveCount($x.Job", 1)),
        ("drop-exit-proof", lambda x: x.replace("if(-not $result.cleanupZero -or -not $result.exitAccepted)", "if(-not $result.cleanupZero)", 1)),
    )
    for label, mutate in faults:
        try:
            check_envelope(mutate(env))
        except AssertionError:
            continue
        raise AssertionError(f"fault escaped: {label}")
    print("tuple12 root display launch controls: PASS source guards + exact mutation faults; no runtime launched")

if __name__ == "__main__":
    main()
