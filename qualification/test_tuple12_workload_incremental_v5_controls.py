#!/usr/bin/env python3
"""Source controls for tuple12 incremental v5.

These checks perform no PowerShell, compiler, native, GUI, lock, network, or
Git action. Dell root runs job-controls-v2.ps1 separately with real children.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
BASE = ROOT / "tuple12-takeover/workload-incremental-v5"
ADAPTER = BASE / "build-incremental-tuple12.ps1"
DERIVE = BASE / "derive-release-metadata.ps1"
HELPER = BASE / "shared/Sr0OwnedJobProcess.cs"
CONTROLS = BASE / "job-controls-v2.ps1"


def need(ok: bool, msg: str) -> None:
    if not ok:
        raise AssertionError(msg)


def ordered(src: str, *parts: str) -> None:
    positions = [src.index(part) for part in parts]
    need(positions == sorted(positions), f"ordering fault: {parts}")


def check_helper(src: str) -> None:
    for needle in (
        "struct StartupInfo", "public int Cb", "public IntPtr StdOutput",
        "Marshal.SizeOf(typeof(StartupInfo))", "STARTUPINFO",
        "CreateSuspended", "CreateProcess(", "ref startup, out info", "CreateSuspendedFlag | CreateNoWindow | CreateUnicodeEnvironment",
        "BuildCommandLine", "QuoteWindowsArgument", "Created[process] = false",
        "resume refused before job assignment", "AssignProcessToJobObjectNative",
        "JobObjectLimitKillOnJobClose", "JobObjectLimitJobMemory",
        "JobObjectLimitProcessMemory", "ProcessMemoryLimit = (UIntPtr)memoryBytes",
        "JobObjectExtendedLimitInformation", "JobObjectBasicAccountingInformation",
        "ReadActiveProcessCount", "return returned >= (uint)size",
    ):
        need(needle in src, f"missing shared-helper guard: {needle}")
    need("PtrToStructure" in src, "native job structs are not read with alignment-aware marshal")
    need("Created.TryRemove(handle" in src, "owned process state was not released with handle")
    need("DllImport(\"kernel32.dll\"" in src, "kernel boundary missing")


def check_adapter(src: str) -> None:
    for needle in (
        "if ($Edits -ne 3)", "SourceRoot escaped StageRoot",
        "BuildMetadata kind mismatch", "sr0-tuple12-derived-release-build-metadata-v5",
        "compiled manifest files array mismatch", "compiled manifest source file count mismatch",
        "Read-BoundedBytes $target 1048576", "Read-BoundedBytes $path 33554432",
        "Require-File $dll 33554432", "Add-Type -Path $helperPath",
        "BuildCommandLine($SwiftPath, $swiftArgs)", "CreateSuspended(",
        "AssignProcessToJobObject($jobHandle, $originalHandle)",
        "ResumeThread($threadHandle, $originalHandle)",
        "ConfigureJob($jobHandle, 1073741824)", "ReadActiveProcessCount($jobHandle",
        "WaitForSingleObject($originalHandle, 1000)", "$watch.Elapsed.TotalSeconds -ge 900",
        "CopyToAsync($outStream)", "CopyToAsync($errStream)", "$outTask.Wait(15000)",
        "$errTask.Wait(15000)", "TerminateJobObject($jobHandle",
        "stdout_sha256", "stderr_sha256", "stream exceeded bounded receipt size",
        "$allJobsQuiescent", "if ($allJobsQuiescent)", "restoration_allowed=$false",
        "kind='sr0-tuple12-ui-only-incremental-v5'", "final_noop_identity_check=$false",
        "artifact_restoration_only=$true", "job_quiescence_required=$true",
        "catch {", "restoration proof incomplete", "$heldMutation = $true",
    ):
        need(needle in src, f"missing adapter guard: {needle}")
    ordered(src, "CreateSuspended(", "AssignProcessToJobObject($jobHandle, $originalHandle)", "ResumeThread($threadHandle, $originalHandle)")
    ordered(src, "$outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()", "Restore-Bytes $target $sourceBefore")
    ordered(src, "$allJobsQuiescent", "Restore-Bytes $target $sourceBefore")
    need("$kernelTerminal = $true" not in src, "cleanup may claim terminal without wait result")
    for bad in ("Start-Process", "ProcessStartInfo", "Get-Process", "Stop-Process", "schtasks", "Remove-Item", "Copy-Item"):
        need(bad not in src, f"unsafe/global control retained: {bad}")


def check_deriver(src: str) -> None:
    for needle in (
        "sourceFilesVerified -ne 54", "compilerKernelHandleRetained", "manifestOK",
        "nativeLaunches", "lockActions", "root-sr0-workload-materialized-source-v1",
        "planManifestSha256 -cne", "files must be an array", "@($m.files).Count -ne 54",
        "patchesApplied -ne 3", "guardImport -cne 'SwiftRightBridge'",
        "hold-build-native", "configuration='release'",
        "sr0-tuple12-derived-release-build-metadata-v5", "[IO.FileMode]::CreateNew",
    ):
        need(needle in src, f"missing derivation guard: {needle}")
    for bad in ("Remove-Item", "Copy-Item", "Start-Process", "Set-Content"):
        need(bad not in src, f"unsafe derivation mutation: {bad}")


def check_controls(src: str) -> None:
    for needle in (
        "Add-Type -Path $helperPath", "CreateSuspended(", "AssignProcessToJobObject",
        "ResumeThread($thread, $process)", "spawned-descendant", "timeout", "output-cap",
        "ReadJobFlags", "[uint32]0x2000", "[uint32]0x200", "[uint32]0x100", "1073741824", "TerminateJobObject($job",
        "ReadActiveProcessCount($job", "CopyToAsync($outFile)", "CopyToAsync($errFile)",
        "-gt 8388608", "Get-FileHash -LiteralPath $stdoutPath", "stdout_sha256", "stderr_sha256",
        "OutRoot", ".work", "control-receipt.json", "Assert-ReleaseAdmission",
        "job-controls-", "resume-before-assignment guard exercised:", "[uint32]::MaxValue", "EXPECTED-REJECTED", "TerminateProcess($process",
    ):
        need(needle in src, f"missing headless control: {needle}")
    need("Stop-Process" not in src and "Get-Process" not in src, "global process control retained")
    need("$releaseAdmitted = Assert-ReleaseAdmission $terminal $outDone $errDone $false 1" in src,
         "active-query omission does not exercise release admission")
    need("$activeReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($job, [ref]$active)" in src,
         "active query result was discarded")
    need("$terminal = ($wait -eq [Sr0OwnedJobProcess]::WaitObject0)" in src,
         "termination terminal state was asserted without wait proof")
    need("$failureMessage -like 'resume-before-assignment guard exercised:*'" in src and
         "$failureMessage -like 'release admission refused:*'" in src,
         "negative control accepted unrelated failure")
    need("$outcome = 'failed'" in src and "failure=$failureMessage" in src,
         "fault receipt does not preserve failure")
    ordered(src, "CreateSuspended(", "if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job, $process))", "if ([Sr0OwnedJobProcess]::ResumeThread($thread, $process) -eq [uint32]::MaxValue)")


def mutations(adapter: str, helper: str, controls: str) -> None:
    adapter_faults = (
        ("drop-argv0-quote", lambda s: s.replace("BuildCommandLine($SwiftPath, $swiftArgs)", "$swiftArgs", 1)),
        ("resume-before-assignment", lambda s: s.replace("AssignProcessToJobObject($jobHandle, $originalHandle)", "ResumeThread($threadHandle, $originalHandle)`n      AssignProcessToJobObject($jobHandle, $originalHandle)", 1)),
        ("drop-active-query", lambda s: s.replace("ReadActiveProcessCount($jobHandle", "RemovedActiveCount($jobHandle")),
        ("restore-v4-kind", lambda s: s.replace("sr0-tuple12-ui-only-incremental-v5", "sr0-tuple12-ui-only-incremental-v4")),
        ("drop-quiescent-restore-gate", lambda s: s.replace("if ($allJobsQuiescent)", "if ($true)", 1)),
        ("restore-small-artifact-cap", lambda s: s.replace("Require-File $dll 33554432", "Require-File $dll", 1)),
    )
    for label, mutate in adapter_faults:
        try:
            check_adapter(mutate(adapter))
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"adapter mutation escaped: {label}")
    helper_faults = (
        ("null-startupinfo", lambda s: s.replace("ref startup, out info", "IntPtr.Zero, out info")),
        ("allow-unassigned-resume", lambda s: s.replace('throw new InvalidOperationException("resume refused before job assignment");', "return 0;", 1)),
        ("drop-memory-flag", lambda s: s.replace("JobObjectLimitJobMemory", "0x100")),
    )
    for label, mutate in helper_faults:
        try:
            check_helper(mutate(helper))
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"helper mutation escaped: {label}")
    need("wrong-memory-flag" in controls, "wrong-memory control missing")


def main() -> int:
    adapter = ADAPTER.read_text(encoding="utf-8")
    helper = HELPER.read_text(encoding="utf-8")
    derive = DERIVE.read_text(encoding="utf-8")
    controls = CONTROLS.read_text(encoding="utf-8")
    for path, text in ((ADAPTER, adapter), (HELPER, helper), (DERIVE, derive), (CONTROLS, controls)):
        need(len(text.encode()) <= 8 * 1024 * 1024, f"source exceeds bound: {path}")
    check_helper(helper); check_adapter(adapter); check_deriver(derive); check_controls(controls)
    mutations(adapter, helper, controls)
    print("tuple12 incremental v5 source controls: PASS positive + shared-helper + signed-max resume guard + 9 mutation faults")
    print("adapter_sha256=" + hashlib.sha256(ADAPTER.read_bytes()).hexdigest())
    print("helper_sha256=" + hashlib.sha256(HELPER.read_bytes()).hexdigest())
    print("derive_sha256=" + hashlib.sha256(DERIVE.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
