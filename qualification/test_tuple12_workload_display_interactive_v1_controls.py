#!/usr/bin/env python3
"""Source-only controls for interactive diagnostic envelope v1."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
BASE = ROOT / "tuple12-takeover/workload-display-interactive-v1"
SRC = BASE / "run-interactive-diagnostic.ps1"
PINS = BASE / "source-pins.json"


def need(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def check(source: str) -> None:
    for needle in (
        "workload-display-diagnostic-v3", "..\\workload-display-diagnostic-v3\\run-one-diagnostic.ps1",
        "..\\workload-incremental-v6\\shared\\Sr0OwnedJobProcess.cs",
        "Sr0InteractiveSessionV1", "ProcessIdToSessionId", "WTSGetActiveConsoleSessionId",
        "CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)",
        "if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch';", "$sessionAdmission='rejected-session-mismatch'", "'session-mismatch'",
        "CreateSuspended(", "ConfigureJob($job,1073741824)",
        "CopyToAsync($outFile)", "CopyToAsync($errFile)",
        "AssignProcessToJobObject($job,$process)", "ResumeThread($thread,$process)",
        "WaitForSingleObject($x.Process,1000)", "TerminateJobObject($x.Job,124)",
        "ReadActiveProcessCount($x.Job", "activeProcesses=$active", "cleanupZero=$cleanupZero",
        "GetExitCodeProcess($x.Process,[ref]$exitCode)", "exitAccepted=$exitAccepted", "exitCode=[int64]$exitCode",
        "StreamCapBytes", "8388608", "ChildDeadlineSeconds", "originalHandleRetained=$true",
        "v3 diagnostic receipt missing", "ReparsePoint", "ReadAllBytes($childReceiptPath)", "2097152", "childReceiptValid=", "lockReleased", "releaseAllowed", "taskQuiescent",
        "lockProtocol='delegated-to-v3-child'", "[IO.FileMode]::CreateNew",
    ):
        need(needle in source, f"missing interactive envelope guard: {needle}")
    for forbidden in (
        "Start-Process", "ProcessStartInfo", "Register-ScheduledTask", "Start-ScheduledTask",
        "New-ScheduledTask", "SetForegroundWindow", "SetWindowPos", "ShowWindow", "PostMessage",
        "SendInput", "Stop-Process", ".Kill(", "taskkill", "Get-Process",
    ):
        need(forbidden not in source, f"interactive envelope performs forbidden action: {forbidden}")
    need(source.index("$sessionMatch=[Sr0InteractiveSessionV1]::CurrentMatchesActive") < source.index("$owned=Start-OwnedChild"), "session admission must precede child launch")
    need(source.index("CopyToAsync($outFile)") < source.index("AssignProcessToJobObject($job,$process)"), "stdout reader must precede assignment")
    need(source.index("CopyToAsync($errFile)") < source.index("AssignProcessToJobObject($job,$process)"), "stderr reader must precede assignment")
    need(source.index("AssignProcessToJobObject($job,$process)") < source.index("ResumeThread($thread,$process)"), "assignment must precede resume")
    need(source.count("ReadActiveProcessCount($x.Job") >= 2, "active count must be re-read after cleanup")
    need(source.count("Get-Item -LiteralPath $p).Length -gt $StreamCapBytes") >= 3, "stream caps require post-drain checks")
    need("$null -eq $failure" in source, "failure must block completed status")
    need("$result.exitAccepted" in source and "$childReceiptValid" in source, "child exit & receipt must gate success")
    need("$exitAccepted=$terminal -and $exitReadable -and $exitCode -ne 259 -and $exitCode -eq 0" in source, "exit 0 proof missing")
    need("$childReceiptValid=([string]$childReceipt.kind -ceq 'sr0-tuple12-workload-display-diagnostic-v3'" in source, "child receipt validation missing")


def main() -> int:
    source = SRC.read_text(encoding="utf-8")
    need(len(source.encode()) <= 512 * 1024, "interactive envelope exceeds bound")
    check(source)
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    need(pins["kind"] == "sr0-tuple12-workload-display-interactive-v1", "interactive pin kind")
    need(pins["shared_helper"]["path"].endswith("workload-incremental-v6/shared/Sr0OwnedJobProcess.cs"), "v6 helper lineage")
    need(pins["admission"]["ssh_session0_must_reject_before_child"], "SSH mismatch admission")
    need(pins["workload"] == {"runs": 1, "no_activate": True, "background_no_activate": True, "input": False}, "workload safety pins")
    faults = (
        ("drop-session-check", lambda s: s.replace("CurrentMatchesActive([ref]$currentSession,[ref]$activeConsoleSession)", "MissingSessionCheck([ref]$currentSession,[ref]$activeConsoleSession)", 1)),
        ("allow-session0", lambda s: s.replace("if(-not $sessionMatch){$sessionAdmission='rejected-session-mismatch';", "if($false){$sessionAdmission='rejected-session-mismatch';", 1)),
        ("drop-helper", lambda s: s.replace("..\\workload-incremental-v6\\shared\\Sr0OwnedJobProcess.cs", "..\\missing\\helper.cs", 1)),
        ("reader-after-resume", lambda s: s.replace("$outTask=$outPipe.CopyToAsync($outFile)", "$outTask=$null", 1)),
        ("drop-active-proof", lambda s: s.replace("ReadActiveProcessCount($x.Job", "MissingActiveCount($x.Job", 1)),
        ("drop-cleanup", lambda s: s.replace("cleanupZero=$cleanupZero", "cleanupZero=$true", 1)),
        ("unbounded-wait", lambda s: s.replace("WaitForSingleObject($x.Process,1000)", "WaitForExit()", 1)),
        ("drop-exit-proof", lambda s: s.replace("$exitAccepted=$terminal -and $exitReadable -and $exitCode -ne 259 -and $exitCode -eq 0", "$exitAccepted=$true", 1)),
        ("drop-child-receipt", lambda s: s.replace("$childReceiptValid=([string]$childReceipt.kind", "$childReceiptValid=$true; $unused=([string]$childReceipt.kind", 1)),
        ("ignore-failure", lambda s: s.replace("$null -eq $failure", "$true", 1)),
    )
    caught = []
    for label, mutate in faults:
        try:
            check(mutate(source))
        except AssertionError:
            caught.append(label)
    need(len(caught) == len(faults), f"interactive faults escaped: {set(label for label, _ in faults) - set(caught)}")
    print("tuple12 interactive display envelope controls: PASS source guards + 7 mutation faults; no runtime launched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
