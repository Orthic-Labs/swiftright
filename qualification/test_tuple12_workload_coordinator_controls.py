#!/usr/bin/env python3
"""Pure source controls for tuple12 Workload coordinator envelope v1."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/workload-coordinator-v1/workload-coordinator.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(s):
    for n in (
        "while (-not (Try-Acquire-Lock)) { Start-Sleep -Seconds 20 }",
        "[IO.FileShare]::None",
        "$lockOwner = \"$label $([DateTimeOffset]::UtcNow.ToString('o'))\"",
        "New-Object Diagnostics.ProcessStartInfo",
        "-NoActivate -LifecycleProof -Runs 3 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10",
        "$orchestratorHandle=$orchestratorProc.Handle",
        "CopyToAsync($outStream)",
        "CopyToAsync($errStream)",
        "$stdoutTask.Wait(15000)",
        "$stderrTask.Wait(15000)",
        "Kernel-Terminal $orchestratorHandle",
        "worker_terminal=1",
        "sampler_terminal=1",
        "task_quiescent=1",
        "$taskQuiescent=Task-Quiescent",
        "$nestedHandleProof=($orchestrationText -match 'presentmon .*handle='",
        "$releaseAllowed=($orchestratorTerminal -and $streamsDrained -and $taskQuiescent -and $nestedHandleProof)",
        "if ($lockHeld -and $releaseAllowed)",
        "[IO.FileMode]::CreateNew",
        "ExpectExe",
        "ExpectDll",
        "build.json lacks sealed exe_sha256/dll_sha256 fields",
    ):
        if n not in s:
            fail("positive", n)
    for n in ("Remove-Item", "Unregister-ScheduledTask", ".Kill()", "Get-Process -Name"):
        if n in s:
            fail("forbidden", n)
    if "while (-not (Try-Acquire-Lock))" not in s:
        fail("lock", "silent CAS loop missing")
    if s.count("[IO.FileShare]::None") < 2:
        fail("lock", "exclusive CAS/release handles missing")
    if "function Write-CreateNew" not in s or "function Write-CreateNew([string]$path,[string]$text) {" not in s:
        fail("receipt", "exclusive receipt helper missing")


def main():
    s = SRC.read_text(encoding="utf-8")
    positive(s)
    mutations = (
        ("release-without-terminal", lambda x: x.replace("$orchestratorTerminal -and $streamsDrained", "$streamsDrained", 1)),
        ("release-without-quiescence", lambda x: x.replace("-and $taskQuiescent -and $nestedHandleProof", "-and $nestedHandleProof", 1)),
        ("remove-lock-cas", lambda x: x.replace("[IO.FileShare]::None", "[IO.FileShare]::ReadWrite", 1)),
        ("remove-handle-retention", lambda x: x.replace("$orchestratorHandle=$orchestratorProc.Handle", "$orchestratorHandle=[IntPtr]::Zero", 1)),
        ("remove-worker-proof", lambda x: x.replace("worker_terminal=1", "worker_terminal=0", 1)),
        ("remove-sampler-proof", lambda x: x.replace("sampler_terminal=1", "sampler_terminal=0", 1)),
        ("remove-stream-drain", lambda x: x.replace("$stdoutTask.Wait(15000)", "$true", 1)),
        ("overwrite-receipt", lambda x: x.replace("[IO.FileMode]::CreateNew", "[IO.FileMode]::Create")),
    )
    caught=[]
    for label, mutate in mutations:
        try: positive(mutate(s))
        except AssertionError: caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 workload coordinator controls: PASS positive + 8 mutation faults")
    print("source_sha256=" + hashlib.sha256(SRC.read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
