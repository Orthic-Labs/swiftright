#!/usr/bin/env python3
"""Pure source controls for tuple12 Workload coordinator v2."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/workload-coordinator-v2/workload-coordinator.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(s):
    for n in (
        "while (-not (Try-Acquire-Lock)) { Start-Sleep -Seconds 20 }",
        "[IO.FileShare]::None",
        "$lockOwner = \"$label $([DateTimeOffset]::UtcNow.ToString('o'))\"",
        "$orchestratorArgs = @(",
        "$psi.Arguments = (($orchestratorArgs | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')",
        "function Strict-RunProof([string]$text)",
        "if ($runs.Count -ne 3)",
        "stream_drains run=$id worker_stdout=1 worker_stderr=1 sampler_stdout=1 sampler_stderr=1",
        "function PresentMon-Proof([string]$text)",
        "if ($lines.Count -ne 1)",
        "kernel_exit=(?!259",
        "kernel_terminal=1",
        "stdout_drained=True stderr_drained=True",
        "$runProof=Strict-RunProof $resultText",
        "$presentMonProof=PresentMon-Proof $orchestrationText",
        "$releaseAllowed=($orchestratorTerminal -and $streamsDrained -and $taskQuiescent -and $presentMonProof)",
        "[IO.FileMode]::CreateNew",
        "Write-CreateNew",
        "$fs=[IO.File]::Open($path,[IO.FileMode]::CreateNew",
    ):
        if n not in s:
            fail("positive", n)
    for n in ("Remove-Item", "Unregister-ScheduledTask", ".Kill()", "Get-Process -Name"):
        if n in s:
            fail("forbidden", n)
    if "-f (Quote-Arg" in s:
        fail("arguments", "old malformed format expression remains")
    if "`$pid =" in s or " $pid =" in s:
        fail("variables", "automatic PID variable reused")


def main():
    s = SRC.read_text(encoding="utf-8")
    positive(s)
    mutations = (
        ("accept-two-runs", lambda x: x.replace("$runs.Count -ne 3", "$runs.Count -ne 2", 1)),
        ("remove-worker-exit", lambda x: x.replace("kernel_terminal=1", "kernel_terminal=0")),
        ("remove-drain-proof", lambda x: x.replace("sampler_stdout=1 sampler_stderr=1", "sampler_stdout=0 sampler_stderr=0", 1)),
        ("remove-presentmon-session-count", lambda x: x.replace("$lines.Count -ne 1", "$lines.Count -ne 0", 1)),
        ("remove-presentmon-native-exit", lambda x: x.replace("kernel_exit=(?!259", "kernel_exit=[0-9]+")),
        ("overwrite-receipt", lambda x: x.replace("[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)", "[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::Read)", 1)),

    )
    caught=[]
    for label, mutate in mutations:
        try: positive(mutate(s))
        except AssertionError: caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 workload coordinator v2 controls: PASS positive + 6 mutation faults")
    print("source_sha256=" + hashlib.sha256(SRC.read_bytes()).hexdigest())

if __name__ == "__main__":
    raise SystemExit(main())
