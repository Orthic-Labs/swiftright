#!/usr/bin/env python3
"""Source-only mutation controls for tuple12 incremental v3.

This file performs no compiler, PowerShell, native, GUI, lock, network, or Git
operation. Root runs Windows lifecycle controls separately after review.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
ADAPTER = ROOT / "tuple12-takeover/workload-incremental-v3/build-incremental-tuple12.ps1"
DERIVE = ROOT / "tuple12-takeover/workload-incremental-v3/derive-release-metadata.ps1"


def need(ok: bool, msg: str) -> None:
    if not ok:
        raise AssertionError(msg)


def ordered(src: str, *parts: str) -> None:
    pos = [src.index(p) for p in parts]
    need(pos == sorted(pos), f"ordering fault: {parts}")


def check_adapter(src: str) -> None:
    required = (
        "if ($Edits -ne 3)",
        "SourceRoot escaped StageRoot",
        "compiled manifest files array mismatch",
        "compiled manifest source file count mismatch",
        "Read-BoundedBytes $target 1048576",
        "Read-BoundedBytes $path 33554432",
        "Require-File $dll 33554432",
        "CREATE_SUSPENDED|CREATE_NO_WINDOW|CREATE_UNICODE_ENVIRONMENT",
        "CreateSuspended(",
        "AssignProcessToJobObject($jobHandle, $originalHandle)",
        "ResumeThread($threadHandle)",
        "x.basic.flags = 0x2000u | 0x200u",
        "SetInformationJobObject(job, 9",
        "QueryInformationJobObject(job,1",
        "JobActiveCount($jobHandle",
        "job_active_processes=$jobActive",
        "job_active_readable=$jobActiveReadable",
        "owned_descendants=($jobActiveReadable -and $jobActive -eq 0)",
        "[IO.FileMode]::CreateNew",
        "WaitForSingleObject($originalHandle, 1000)",
        "$watch.Elapsed.TotalSeconds -ge 900",
        "CopyToAsync($outStream)",
        "CopyToAsync($errStream)",
        "$outTask.Wait(15000)",
        "$errTask.Wait(15000)",
        "TerminateJobObject($jobHandle",
        "TerminateProcess($originalHandle, 124)",
        "job assignment before resume failed",
        "kind='sr0-tuple12-ui-only-incremental-v3'",
        "job_quiescence_required=$true",
        "source_restored=$sourceRestored",
        "hashes_identical=$artifactIdentity",
    )
    for needle in required:
        need(needle in src, f"missing adapter guard: {needle}")
    need("CREATE_SUSPENDED" in src, "suspended launch flag missing")
    ordered(src, "[Sr0IncrementalKernelV3]::CreateSuspended(", "AssignProcessToJobObject($jobHandle, $originalHandle)", "ResumeThread($threadHandle)")
    ordered(src, "$shimCountBefore = Get-BoundedLineCount $shimLog", "[Sr0IncrementalKernelV3]::CreateSuspended(", "$shimCountAfter = Get-BoundedLineCount $shimLog")
    ordered(src, "$outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()", "$trials +=")
    need("0x100u" not in src, "per-process memory flag accidentally retained")
    need("Start-Process" not in src and "ProcessStartInfo" not in src, "pre-assignment ProcessStart retained")
    need("WaitForExit()" not in src, "unbounded wait retained")
    for bad in ("Remove-Item", "Copy-Item", "Stop-Process", "Get-Process", "schtasks"):
        need(bad not in src, f"unsafe/global control retained: {bad}")


def check_deriver(src: str) -> None:
    for needle in (
        "sourceFilesVerified -ne 54", "compilerKernelHandleRetained", "manifestOK",
        "nativeLaunches", "lockActions", "root-sr0-workload-materialized-source-v1",
        "planManifestSha256 -cne", "files must be an array", "@($m.files).Count -ne 54",
        "patchesApplied -ne 3", "guardImport -cne 'SwiftRightBridge'",
        "hold-build-native", "configuration='release'",
        "sr0-tuple12-derived-release-build-metadata-v3", "[IO.FileMode]::CreateNew",
    ):
        need(needle in src, f"missing derivation guard: {needle}")
    for bad in ("Remove-Item", "Copy-Item", "Start-Process", "Set-Content"):
        need(bad not in src, f"unsafe derivation mutation: {bad}")


def mutations(adapter: str, derive: str) -> None:
    adapter_faults = (
        ("wrong-job-memory-flag", lambda s: s.replace("0x200u", "0x100u", 1)),
        ("resume-before-assignment", lambda s: s.replace("AssignProcessToJobObject($jobHandle, $originalHandle)", "ResumeThread($threadHandle)`n      AssignProcessToJobObject($jobHandle, $originalHandle)", 1)),
        ("drop-active-count", lambda s: s.replace("JobActiveCount($jobHandle", "RemovedJobActiveCount($jobHandle", 1)),
        ("drop-v3-kind", lambda s: s.replace("sr0-tuple12-ui-only-incremental-v3", "sr0-tuple12-ui-only-incremental-v2", 1)),
        ("restore-small-dll-cap", lambda s: s.replace("Require-File $dll 33554432", "Require-File $dll", 1)),
        ("reintroduce-process-start", lambda s: s.replace("CreateSuspended(", "ProcessStartInfo(", 1)),
    )
    for label, mutate in adapter_faults:
        try:
            check_adapter(mutate(adapter))
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"adapter mutation escaped: {label}")
    derive_faults = (
        ("drop-source-count", lambda s: s.replace("sourceFilesVerified -ne 54", "sourceFilesVerified -ne 1", 1)),
        ("drop-plan-join", lambda s: s.replace("planManifestSha256 -cne", "planManifestSha256 -ceq", 1)),
        ("drop-v3-kind", lambda s: s.replace("sr0-tuple12-derived-release-build-metadata-v3", "sr0-tuple12-derived-release-build-metadata-v2", 1)),
    )
    for label, mutate in derive_faults:
        try:
            check_deriver(mutate(derive))
        except (AssertionError, ValueError):
            continue
        raise AssertionError(f"deriver mutation escaped: {label}")


def main() -> int:
    adapter = ADAPTER.read_text(encoding="utf-8")
    derive = DERIVE.read_text(encoding="utf-8")
    need(len(adapter.encode()) <= 8 * 1024 * 1024, "adapter exceeds source bound")
    need(len(derive.encode()) <= 8 * 1024 * 1024, "deriver exceeds source bound")
    check_adapter(adapter)
    check_deriver(derive)
    mutations(adapter, derive)
    print("tuple12 incremental v3 source controls: PASS positive + 9 mutation faults")
    print("adapter_sha256=" + hashlib.sha256(ADAPTER.read_bytes()).hexdigest())
    print("derive_sha256=" + hashlib.sha256(DERIVE.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
