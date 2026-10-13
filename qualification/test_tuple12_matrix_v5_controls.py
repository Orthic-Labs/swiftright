#!/usr/bin/env python3
"""Pure source controls for strict tuple12 matrix runner v5."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/matrix-controls-v5"
WORKER = SRC / "worker-v4.ps1"
COORD = SRC / "coordinator-v4.ps1"
RUNNER = SRC / "run-matrix-v5.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(worker, coord, runner):
    for n in (
        "kind = 'sr0-tuple12-startupguard-matrix-worker-v4'",
        "$selftestLabel = if ($Variant)",
        "SELFTEST-STAGES {0}:",
        "SELFTEST {0}: PASS ({1}/{1} asserted",
        "if ($cfg.Variant) { $coordinatorArguments += @('-Variant',$cfg.Variant) }",
    ):
        if n not in worker + coord + runner:
            fail("positive", n)
    for n in (
        "kind='sr0-tuple12-matrix-run-v5'",
        "Add-Type -TypeDefinition @'",
        "public static class Sr0MatrixRunnerV5Kernel",
        "WaitForSingleObject",
        "GetExitCodeProcess",
        "function Lock-Free([string]$path)",
        "if (-not (Lock-Free $Lock))",
        "Retain original coordinator handle before waiting",
        "$handle=$proc.Handle",
        "$failedCount++",
        "CopyToAsync",
        "$outDone=$outTask.Wait(30000); $errDone=$errTask.Wait(30000)",
        "all case receipts preserved",
        "MATRIX_PASS mode=",
        "MATRIX_FAIL mode=",
        "targetedDelivery=$true",
        "noActivate=$true",
        "[IO.FileMode]::CreateNew",
    ):
        if n not in runner:
            fail("runner", n)
    if runner.count("CopyToAsync") < 2:
        fail("runner", "both coordinator streams must drain")
    if runner.count("MATRIX_FAIL mode=") != 1:
        fail("runner", "failure aggregate missing")
    if runner.count("noActivate=$true") < 1:
        fail("runner", "noactivate admission missing")
    if runner.count("[IO.FileMode]::CreateNew") < 2:
        fail("runner", "case outputs must be exclusive")
    if "throw \"coordinator failed" not in runner:
        fail("runner", "failed coordinator path not recorded")
    if "throw $failure" in runner:
        fail("runner", "case failure must be recorded & continue")
    if "Remove-Item" in runner or ".Kill()" in runner or "Unregister-ScheduledTask" in runner:
        fail("destructive", "destructive process/output action")
    if "Get-Process -Name" in runner:
        fail("scope", "global process polling")


def main():
    worker = WORKER.read_text(encoding="utf-8")
    coord = COORD.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    positive(worker, coord, runner)
    mutations = (
        ("drop-original-handle", lambda x: x.replace("$handle=$proc.Handle", "$handle=[IntPtr]::Zero", 1)),
        ("drop-stream-drain", lambda x: x.replace("$outDone=$outTask.Wait(30000); $errDone=$errTask.Wait(30000)", "$outDone=$false; $errDone=$false")),
        ("abort-on-failure", lambda x: x.replace("$failedCount++", "$failedCount++; throw $failure", 1)),
        ("drop-failure-summary", lambda x: x.replace("MATRIX_FAIL mode=", "MATRIX_DONE mode=", 1)),
        ("drop-noactivate", lambda x: x.replace("noActivate=$true", "noActivate=$false")),
        ("overwrite-case-output", lambda x: x.replace("[IO.FileMode]::CreateNew", "[IO.FileMode]::Create")),
    )
    caught=[]
    for label, mutate in mutations:
        try: positive(worker, coord, mutate(runner))
        except AssertionError: caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 matrix v5 controls: PASS positive + 6 mutation faults")
    for path in (WORKER, COORD, RUNNER):
        print(path.name + "_sha256=" + hashlib.sha256(path.read_bytes()).hexdigest())
    print("controls_sha256=" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
