"""Source-only controls for v8 SwiftPM manifest diagnostic; root runs it."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "tuple12-takeover/workload-incremental-v8/diagnose-manifest.ps1"
PINS = ROOT / "tuple12-takeover/workload-incremental-v8/source-pins.json"


def need(ok: bool, msg: str) -> None:
    if not ok:
        raise AssertionError(msg)


def positive(src: str) -> None:
    for token in (
        "[Parameter(Mandatory)][string]$PackagePath",
        "Add-Type -Path $helper",
        "Need-File $manifest 1048576",
        "CreateSuspended(",
        "CopyToAsync($outFile)", "CopyToAsync($errFile)",
        "AssignProcessToJobObject($job, $process)",
        "ResumeThread($thread, $process)",
        "ConfigureJob($job, 1073741824)",
        "ReadActiveProcessCount($job",
        "GetExitCodeProcess($process",
        "TerminateJobObject($job, 124)",
        "TerminateProcess($process, 124)",
        "package dump-package",
        "package show-dependencies --format json",
        "CompilerBin", "RuntimeBin", "environment.json",
        "manifest-diagnostic.json", "$receiptPath", "New-Text $receiptPath",
        "StreamCapBytes", "$DeadlineSeconds",
        "stdoutDrained", "stderrDrained", "cleanupZero",
        "noMutation=$true", "OutRoot must be fresh",
        "reparse directory rejected", "reparse file rejected",
        "finally { $env:Path = $oldPath",
    ):
        need(token in src, f"missing manifest diagnostic guard: {token}")
    need(src.index("CopyToAsync($outFile)") < src.index("AssignProcessToJobObject($job, $process)"), "stdout reader starts after assignment")
    need(src.index("CopyToAsync($errFile)") < src.index("AssignProcessToJobObject($job, $process)"), "stderr reader starts after assignment")
    need(src.count("Get-Item -LiteralPath $stdout") >= 2, "stdout cap is not checked during & after execution")
    need(src.count("Get-Item -LiteralPath $stderr") >= 2, "stderr cap is not checked during & after execution")
    need(src.count("ReadActiveProcessCount($job") >= 2, "active-process proof has no initial query & bounded retry")
    need(src.index("CreateSuspended(") < src.index("CopyToAsync($outFile)"), "suspended process must precede readers")
    need(src.index("AssignProcessToJobObject($job, $process)") < src.index("ResumeThread($thread, $process)"), "assignment must precede resume")
    need("[uint32]$childPid" in src and "[uint32]$pid" not in src, "automatic PowerShell PID variable was avoided")


def forbidden(src: str) -> None:
    for token in ("Start-Process", "ProcessStartInfo", "Get-Process", "Stop-Process", "taskkill", "Remove-Item", "Copy-Item", "Register-ScheduledTask"):
        need(token not in src, f"unsafe launch or global cleanup retained: {token}")


def mutations(src: str) -> None:
    faults = (
        ("drop-probe", lambda s: s.replace("package dump-package", "package omitted", 1)),
        ("drop-dependencies", lambda s: s.replace("package show-dependencies --format json", "package omitted", 1)),
        ("drop-helper", lambda s: s.replace("Add-Type -Path $helper", "# helper omitted", 1)),
        ("reader-after-resume", lambda s: s.replace("$outTask = $outPipe.CopyToAsync($outFile); $errTask = $errPipe.CopyToAsync($errFile)", "# readers omitted", 1)),
        ("drop-active-query", lambda s: s.replace("ReadActiveProcessCount($job", "RemovedActiveProcessCount($job", 1)),
        ("drop-receipt", lambda s: s.replace("manifest-diagnostic.json", "manifest-diagnostic-omitted.json", 1)),
    )
    for label, mutate in faults:
        try:
            positive(mutate(src))
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"manifest diagnostic mutation escaped: {label}")


def main() -> int:
    src = SCRIPT.read_text(encoding="utf-8")
    pins = PINS.read_text(encoding="utf-8")
    need(len(src.encode()) <= 2 * 1024 * 1024, "diagnostic source exceeds bound")
    positive(src); forbidden(src); mutations(src)
    need('"manifest_diagnostic"' in pins and '"source_mutation": false' in pins, "manifest diagnostic provenance missing")
    print("tuple12 incremental v8 manifest diagnostic source controls: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
