#!/usr/bin/env python3
"""Bounded source controls for tuple12 incremental adapter v2.

Controls inspect source, exercise count/timeout/drain helpers with owned no-op
processes, & never invoke Swift, PowerShell, GUI, lock, native, network, or Git.
"""
from pathlib import Path
import hashlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
ADAPTER = ROOT / "tuple12-takeover/workload-incremental-v2/build-incremental-tuple12.ps1"
DERIVE = ROOT / "tuple12-takeover/workload-incremental-v2/derive-release-metadata.ps1"


def reject_static(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


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
        "Read-BoundedBytes $target 1048576",
        "Read-BoundedBytes $path 33554432",
        "compiled manifest files array mismatch",
        "compiled manifest source file count mismatch",
        "compiled_manifest_sha256",
        "Add-Marker $target $i $runId",
        "Restore-Bytes $target $sourceBefore",
        "New-Object Diagnostics.ProcessStartInfo",
        "$originalHandle = $proc.Handle",
        "WaitForSingleObject($originalHandle, 1000)",
        "GetExitCodeProcess($originalHandle",
        "TerminateJobObject($jobHandle",
        "ConfigureJob($jobHandle, 1073741824)",
        "Swift compiler path differs from sealed receipt",
        "Swift compiler hash differs from sealed receipt",
        "foreach ($path in $artifactPaths) { Restore-Bytes $path $artifactBytes[$path] }",
        "CopyToAsync($outStream)",
        "CopyToAsync($errStream)",
        "$outTask.Wait(15000)",
        "$errTask.Wait(15000)",
        "Get-BoundedLineCount $shimLog",
        "$shimCountAfter = Get-BoundedLineCount $shimLog",
        "shim_line_count_before=$shimCountBefore",
        "shim_line_count_after=$shimCountAfter",
        "shim_log_line_count_total=",
        "rustInvocations = $shimCountAfter - $shimCountBefore",
        "RUSTC_WRAPPER",
        "rust_invocations_total=$rustTotal",
        "source_restored=$sourceRestored",
        "hashes_identical=$artifactIdentity",
        "final_noop_identity_check=$false",
        "artifact_restoration_only=$true",
        "owned_namespace=$true",
        "desktop_lock_touched=$false",
        "gui_launched=$false",
        "native_input=$false",
    )
    for needle in required:
        reject_static(needle in src, f"missing adapter control: {needle}")
    before = src.index("$shimCountBefore = Get-BoundedLineCount $shimLog")
    start = src.index("if (-not $proc.Start())")
    wait = src.index("$kernelWait = [Sr0IncrementalKernelV2]::WaitForSingleObject")
    after = src.index("$shimCountAfter = Get-BoundedLineCount $shimLog")
    reject_static(before < start < wait < after, "shim count evidence is not start/terminal ordered")
    reject_static("$watch.Elapsed.TotalSeconds -ge 900" in src, "compiler deadline missing")
    reject_static("if ($timedOut -or $outputExceeded) {" in src, "owned timeout/output termination branch missing")
    reject_static("$outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()" in src, "final drain result missing")
    reject_static("final_noop_identity_check=$true" not in src, "positive source accidentally claims final no-op build")
    for needle in ("Remove-Item", "Copy-Item", "Start-Process", "schtasks", "Get-Process", "Stop-Process"):
        reject_static(needle not in src, f"forbidden destructive/global control: {needle}")


def check_derive(src: str) -> None:
    required = (
        "build --jobs 1 -c release --product WorkloadWin",
        "sourceFilesVerified -ne 54",
        "compilerKernelHandleRetained",
        "manifestOK",
        "nativeLaunches",
        "lockActions",
        "root-sr0-workload-materialized-source-v1",
        "planManifestSha256 -cne",
        "files must be an array",
        "@($m.files).Count -ne 54",
        "patchesApplied -ne 3",
        "guardImport -cne 'SwiftRightBridge'",
        "hold-build-native",
        "configuration='release'",
        "derivation='argv -c release from sealed root build receipt'",
        "sr0-tuple12-derived-release-build-metadata-v2",
        "[IO.FileMode]::CreateNew",
    )
    for needle in required:
        reject_static(needle in src, f"missing metadata derivation control: {needle}")
    for needle in ("Remove-Item", "Copy-Item", "Start-Process", "Set-Content"):
        reject_static(needle not in src, f"forbidden metadata mutation: {needle}")


def count_delta(before: int, after: int) -> int:
    if before < 0 or after < before:
        raise ValueError("invalid shim count ordering")
    return after - before


def owned_terminal_and_drain() -> None:
    """Exercise terminal & two-stream drain proofs with owned no-op children."""
    code = "import sys; sys.stdout.write('out\\n'); sys.stderr.write('err\\n')"
    proc = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = proc.communicate(timeout=2)
    reject_static(proc.returncode == 0, "owned no-op exit proof failed")
    reject_static(out == b"out\n" and err == b"err\n", "owned no-op stream drain failed")
    reject_static(count_delta(3, 3) == 0, "zero shim delta proof failed")
    try:
        count_delta(4, 3)
    except ValueError:
        pass
    else:
        raise AssertionError("decreasing shim count was accepted")

    sleeper = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(2)"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        sleeper.communicate(timeout=0.05)
    except subprocess.TimeoutExpired:
        sleeper.terminate()
        out, err = sleeper.communicate(timeout=2)
        reject_static(sleeper.returncode is not None, "owned timeout child remained live")
        reject_static(out == b"" and err == b"", "timeout drain changed expected streams")
    else:
        raise AssertionError("timeout control child exited before timeout")


def mutation_controls(adapter: str, derive: str) -> None:
    mutations = (
        ("count-before-start", lambda s: s.replace("$shimCountBefore = Get-BoundedLineCount $shimLog", "$shimCountBefore = 0", 1)),
        ("drop-timeout-kill", lambda s: s.replace("if ($timedOut -or $outputExceeded) {", "if ($false) {", 1)),
        ("drop-stream-drain", lambda s: s.replace("$outTask.Wait(15000)", "$outTask.Wait(0)", 1)),
        ("drop-memory-cap", lambda s: s.replace("ConfigureJob($jobHandle, 1073741824)", "ConfigureJob($jobHandle, 0)", 1)),
        ("drop-shim-total", lambda s: s.replace("shim_log_line_count_total=", "shim_log_line_count_removed=", 1)),
        ("claim-final-noop", lambda s: s.replace("final_noop_identity_check=$false", "final_noop_identity_check=$true", 1)),
    )
    caught = []
    for label, mutate in mutations:
        mutated = mutate(adapter)
        try:
            check_adapter(mutated)
        except (AssertionError, ValueError):
            caught.append(label)
    reject_static(len(caught) == len(mutations), f"adapter faults caught {caught}")

    derive_mutations = (
        ("accept-wrong-files-count", lambda s: s.replace("@($m.files).Count -ne 54", "@($m.files).Count -ne 1", 1)),
        ("drop-plan-join", lambda s: s.replace("planManifestSha256 -cne", "planManifestSha256 -ceq", 1)),
        ("accept-wrong-kind", lambda s: s.replace("root-sr0-workload-materialized-source-v1", "wrong-manifest-kind", 1)),
    )
    caught_derive = []
    for label, mutate in derive_mutations:
        try:
            check_derive(mutate(derive))
        except (AssertionError, ValueError):
            caught_derive.append(label)
    reject_static(len(caught_derive) == len(derive_mutations), f"deriver faults caught {caught_derive}")


def main() -> int:
    adapter = ADAPTER.read_text(encoding="utf-8")
    derive = DERIVE.read_text(encoding="utf-8")
    check_adapter(adapter)
    check_derive(derive)
    owned_terminal_and_drain()
    mutation_controls(adapter, derive)
    print("tuple12 incremental v2 controls: PASS positive + owned count/timeout/drain + 9 mutation faults")
    print("adapter_sha256=" + hashlib.sha256(ADAPTER.read_bytes()).hexdigest())
    print("derive_sha256=" + hashlib.sha256(DERIVE.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
