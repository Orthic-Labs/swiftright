#!/usr/bin/env python3
"""Pure controls for tuple12 incremental adapter & receipt derivation.

No compiler, file mutation, GUI, lock, native input, network, or Git action.
"""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
ADAPTER = ROOT / "tuple12-takeover/workload-incremental-v1/build-incremental-tuple12.ps1"
DERIVE = ROOT / "tuple12-takeover/workload-incremental-v1/derive-release-metadata.ps1"


def check_adapter(src: str) -> None:
    required = (
        "[Parameter(Mandatory)][string]$StageRoot",
        "[Parameter(Mandatory)][string]$SourceRoot",
        "[Parameter(Mandatory)][string]$BuildMetadata",
        "if ($Edits -ne 3)",
        "SourceRoot escaped StageRoot",
        "artifact escaped StageRoot",
        "build --jobs 1 -c release --product WorkloadWin",
        "New-OwnedDirectory",
        "[IO.FileMode]::CreateNew",
        "[IO.File]::ReadAllBytes($target)",
        "Add-Marker $target $i $runId",
        "Restore-Bytes $target $sourceBefore",
        "New-Object Diagnostics.ProcessStartInfo",
        "$originalHandle = $proc.Handle",
        "WaitForSingleObject($originalHandle",
        "GetExitCodeProcess($originalHandle",
        "Swift compiler path differs from sealed receipt",
        "Swift compiler hash differs from sealed receipt",
        "foreach ($path in $artifactPaths) { Restore-Bytes $path $artifactBytes[$path] }",
        "CopyToAsync($outStream)",
        "CopyToAsync($errStream)",
        "$outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()",
        "RUSTC_WRAPPER",
        "rust_invocations_total",
        "source_restored=$sourceRestored",
        "hashes_identical=$artifactIdentity",
        "if (-not $artifactIdentity) { throw 'final artifact identity mismatch' }",
        "owned_namespace=$true",
        "desktop_lock_touched=$false",
        "gui_launched=$false",
        "native_input=$false",
    )
    for needle in required:
        if needle not in src:
            raise AssertionError(f"missing adapter control: {needle}")
    forbidden = ("Remove-Item", "Copy-Item", "Start-Process", "schtasks", "Get-Process", "Stop-Process")
    for needle in forbidden:
        if needle in src:
            raise AssertionError(f"forbidden destructive/global control: {needle}")


def check_derive(src: str) -> None:
    required = (
        "build --jobs 1 -c release --product WorkloadWin",
        "sourceFilesVerified -ne 54",
        "compilerKernelHandleRetained",
        "manifestOK",
        "nativeLaunches",
        "lockActions",
        "hold-native",
        "configuration='release'",
        "derivation='argv -c release from sealed root build receipt'",
        "[IO.FileMode]::CreateNew",
    )
    for needle in required:
        if needle not in src:
            raise AssertionError(f"missing metadata derivation control: {needle}")
    for needle in ("Remove-Item", "Copy-Item", "Start-Process", "Set-Content"):
        if needle in src:
            raise AssertionError(f"forbidden metadata mutation: {needle}")


def main() -> int:
    adapter = ADAPTER.read_text(encoding="utf-8")
    derive = DERIVE.read_text(encoding="utf-8")
    check_adapter(adapter)
    check_derive(derive)
    mutations = (
        ("drop-original-handle", lambda s: s.replace("$originalHandle = $proc.Handle", "$originalHandle = [IntPtr]::Zero", 1)),
        ("drop-kernel-wait", lambda s: s.replace("$kernelWait = [Sr0IncrementalKernelV1]::WaitForSingleObject($originalHandle, 900000)", "$kernelWait = 0", 1)),
        ("drop-stdout-drain", lambda s: s.replace("$outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()", "$errTask.GetAwaiter().GetResult()", 1)),
        ("allow-two-edits", lambda s: s.replace("if ($Edits -ne 3)", "if ($Edits -ne 2)", 1)),
        ("drop-source-restore", lambda s: s.replace("Restore-Bytes $target $sourceBefore", "# omitted", 1)),
        ("drop-artifact-proof", lambda s: s.replace("if (-not $artifactIdentity) { throw 'final artifact identity mismatch' }", "# omitted", 1)),
        ("drop-release-proof", lambda s: s.replace("build --jobs 1 -c release --product WorkloadWin", "build --jobs 1 --product WorkloadWin", 1)),
    )
    caught = []
    for label, mutate in mutations:
        try:
            check_adapter(mutate(adapter))
        except AssertionError:
            caught.append(label)
    if len(caught) != len(mutations):
        raise AssertionError(f"fault controls caught {caught}; expected {len(mutations)}")
    print("tuple12 incremental v1 controls: PASS positive + 7 mutation faults")
    print("adapter_sha256=" + hashlib.sha256(ADAPTER.read_bytes()).hexdigest())
    print("derive_sha256=" + hashlib.sha256(DERIVE.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
