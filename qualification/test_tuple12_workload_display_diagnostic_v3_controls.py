#!/usr/bin/env python3
"""Source-only controls for owned-job display diagnostic v3."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "tuple12-takeover/workload-display-diagnostic-v3/run-one-diagnostic.ps1"
SAMPLER = ROOT / "tuple12-takeover/workload-display-diagnostic-v3/display-context-sampler-v1.ps1"
PINS = ROOT / "tuple12-takeover/workload-display-diagnostic-v3/source-pins.json"


def need(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def check(source: str) -> None:
    for needle in (
        "workload-controls-v8", "run-workload.ps1", "display-context-sampler-v1.ps1",
        "..\\workload-incremental-v6\\shared\\Sr0OwnedJobProcess.cs",
        "CreateSuspended(", "ConfigureJob($job,1073741824)",
        "CopyToAsync($outFile)", "CopyToAsync($errFile)",
        "AssignProcessToJobObject($job,$process)", "ResumeThread($thread,$process)",
        "ReadActiveProcessCount($owned.Job", "activeReadable", "activeProcesses=$active",
        "cleanupZero=$terminal", "TerminateJobObject($owned.Job,124)",
        "TerminateProcess($process,124)", "WaitForSingleObject($owned.Process,1000)",
        "StreamCapBytes", "RssCapBytes", "8388608", "2147483648",
        "'-Runs','1'", "'-NoActivate'", "'-LifecycleProof'",
        "releaseAllowed=$runResult.cleanupZero -and -not $runResult.outputExceeded -and -not $runResult.rssExceeded",
        "Sr0DiagnosticSessionV3", "ProcessIdToSessionId", "WTSGetActiveConsoleSessionId",
        "CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)",
        "$sessionAdmission='rejected-session-mismatch'", "'session-mismatch'}elseif",
        "Close-Owned $samplerOwned", "Close-Owned $runOwned",
        "Try-Acquire-Lock", "Release-Lock", "[IO.FileMode]::CreateNew",
        "nativeConclusion='display-context-only; strict PresentMon displayed-row gate unchanged'",
    ):
        need(needle in source, f"missing v2 owned-job guard: {needle}")
    for forbidden in (
        "Start-Process", "ProcessStartInfo", ".Kill(", "Stop-Process", "SetWindowPos",
        "SetForegroundWindow", "ShowWindow", "PostMessage", "SendInput",
        "New-ScheduledTask", "Register-ScheduledTask", "Unregister-ScheduledTask",
    ):
        need(forbidden not in source, f"forbidden v2 mutation: {forbidden}")
    need(source.index("CopyToAsync($outFile)") < source.index("AssignProcessToJobObject($job,$process)"), "stdout reader must precede assignment")
    need(source.index("CopyToAsync($errFile)") < source.index("AssignProcessToJobObject($job,$process)"), "stderr reader must precede assignment")
    need(source.index("AssignProcessToJobObject($job,$process)") < source.index("ResumeThread($thread,$process)"), "assignment must precede resume")
    need(source.count("ReadActiveProcessCount($owned.Job") >= 2, "active process proof must be re-read after termination")
    need(source.count("Get-Item -LiteralPath $path).Length -gt $StreamCapBytes") >= 3, "stream cap must be checked before & after drain")
    need(source.count("CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)") >= 2, "session must be checked before run & sampler")
    need(source.count("if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch';") >= 2, "session mismatch must reject before run & sampler")


def check_sampler(source: str) -> None:
    for needle in ("Sr0DisplayDiagnosticV1", 'EntryPoint="WindowFromPoint"', "[Sr0DisplayDiagnosticV1]::WindowFromPoint(",
                   "DwmGetWindowAttribute", "ProcessIdToSessionId", "[IO.FileMode]::CreateNew",
                   "strictCauseConclusion='presentmon_display_rows_not_inferred'", "desktop_mutation=$false"):
        need(needle in source, f"missing sampler guard: {needle}")
    for forbidden in ("SetWindowPos", "SetForegroundWindow", "ShowWindow", "PostMessage", "SendInput", "ProcessStartInfo", "Start-Process", "Kill()"):
        need(forbidden not in source, f"forbidden sampler mutation: {forbidden}")


def main() -> int:
    source = SRC.read_text(encoding="utf-8")
    sampler = SAMPLER.read_text(encoding="utf-8")
    need(len(source.encode()) <= 512 * 1024, "v2 source exceeds bound")
    check(source); check_sampler(sampler)
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    need(pins["kind"] == "sr0-tuple12-workload-display-diagnostic-v3", "v3 pin kind")
    need(pins["shared_helper"]["path"].endswith("workload-incremental-v6/shared/Sr0OwnedJobProcess.cs"), "exact v6 helper pin")
    need(pins["limits"]["runs"] == 1 and pins["limits"]["active_processes"] == 0, "bounded one-run limits")
    faults = (
        ("drop-helper", lambda s: s.replace("..\\workload-incremental-v6\\shared\\Sr0OwnedJobProcess.cs", "..\\missing\\helper.cs", 1)),
        ("drop-assignment", lambda s: s.replace("AssignProcessToJobObject($job,$process)", "$true", 1)),
        ("reader-after-resume", lambda s: s.replace("$outTask=$outPipe.CopyToAsync($outFile)", "$outTask=$null", 1)),
        ("drop-active-proof", lambda s: s.replace("ReadActiveProcessCount($owned.Job", "ReadActiveProcessCount($owned.MissingJob", 1)),
        ("drop-cleanup", lambda s: s.replace("cleanupZero=$terminal", "cleanupZero=$true", 1)),
        ("three-runs", lambda s: s.replace("'-Runs','1'", "'-Runs','3'", 1)),
        ("unbounded-wait", lambda s: s.replace("WaitForSingleObject($owned.Process,1000)", "WaitForExit()", 1)),
        ("release-without-cleanup", lambda s: s.replace("$releaseAllowed=$runResult.cleanupZero -and -not $runResult.outputExceeded -and -not $runResult.rssExceeded", "$releaseAllowed=$true", 1)),
        ("drop-session-admission", lambda s: s.replace("CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)", "CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSessionRemoved)", 1)),
        ("allow-session-mismatch", lambda s: s.replace("if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch';", "if($false){$sessionAdmission='rejected-session-mismatch';", 1)),
    )
    caught = []
    for label, mutate in faults:
        try:
            check(mutate(source))
        except AssertionError:
            caught.append(label)
    need(len(caught) == len(faults), f"v2 mutation faults escaped: {set(label for label, _ in faults) - set(caught)}")
    print("tuple12 workload display diagnostic v2 controls: PASS owned v6 job, bounded drains, read-only sampler")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
