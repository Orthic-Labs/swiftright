#!/usr/bin/env python3
"""Pure source controls for tuple12 Workload coordinator v4."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/workload-coordinator-v4/workload-coordinator.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(s):
    required = (
        "function Strict-RunProof([string]$text)",
        "if ($runs.Count -ne 3)",
        "function PresentMon-Proof([string]$text)",
        "function Scoped-OwnedProcessClear([string]$ownedExe,[string]$runTag)",
        "Get-CimInstance Win32_Process -ErrorAction Stop",
        "function Started-CleanupProof([string]$text,[ref]$workerCount,[ref]$samplerCount)",
        "pid run=([A-Za-z0-9._-]+) pid=[0-9]+ handle=[1-9][0-9]*",
        "kernel_terminal=1",
        "stop=(?:natural|forced-owned)",
        "kernel_exit=(-?[0-9]+)",
        "return ($Matches[1] -eq $Matches[2]",
        "kernel_exit=(?!259",
        "stream_drains run=$id worker_stdout=1 worker_stderr=1 sampler_stdout=1 sampler_stderr=1",
        "$cleanupProof=Started-CleanupProof $resultText ([ref]$startedWorkers) ([ref]$startedSamplers)",
        "$cleanupMode='prelaunch-scoped-snapshot'",
        "$cleanupProof=($taskQuiescent -and (Scoped-OwnedProcessClear $exe $Tag))",
        "$presentMonRelease=($presentMonProof -or ($earlyNoResult",
        "$releaseAllowed=($orchestratorTerminal -and $streamsDrained -and $taskQuiescent -and $cleanupProof -and $presentMonRelease)",
        "startedWorkers=$startedWorkers; startedSamplers=$startedSamplers",
        "[IO.FileMode]::CreateNew",
    )
    for n in required:
        if n not in s:
            fail("positive", n)
    if s.count("kernel_terminal=1") < 3:
        fail("positive", "kernel terminal checks are incomplete")
    if s.count("stream_drains run=$id worker_stdout=1 worker_stderr=1 sampler_stdout=1 sampler_stderr=1") < 2:
        fail("positive", "started-run drain checks are incomplete")
    if s.count("[IO.FileMode]::CreateNew") < 2:
        fail("positive", "receipt/output creation is not exclusive")
    forbidden = ("Remove-Item", "Unregister-ScheduledTask", ".Kill()", "Get-Process -Name")
    for n in forbidden:
        if n in s:
            fail("forbidden", n)
    if "$pid =" in s or " $pid =" in s:
        fail("variables", "automatic PID variable reused")
    if "kind='sr0-tuple12-workload-coordinator-v2'" in s:
        fail("version", "v2 kind remains")


def main():
    s = SRC.read_text(encoding="utf-8")
    positive(s)
    mutations = (
        ("omit-started-worker-terminal", lambda x: x.replace("kernel_terminal=1", "kernel_terminal=0")),
        ("omit-started-stream-drain", lambda x: x.replace("sampler_stdout=1 sampler_stderr=1", "sampler_stdout=0 sampler_stderr=0")),
        ("omit-scoped-identity", lambda x: x.replace("Get-CimInstance Win32_Process -ErrorAction Stop", "Get-Process", 1)),
        ("release-without-cleanup", lambda x: x.replace(" -and $cleanupProof", "", 1)),
        ("release-without-pm", lambda x: x.replace(" -and $presentMonRelease", "", 1)),
        ("accept-two-semantic-runs", lambda x: x.replace("$runs.Count -ne 3", "$runs.Count -ne 2", 1)),
        ("overwrite-receipt", lambda x: x.replace("[IO.FileMode]::CreateNew", "[IO.FileMode]::Create")),
    )
    caught = []
    for label, mutate in mutations:
        try:
            positive(mutate(s))
        except AssertionError:
            caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 workload coordinator v4 controls: PASS positive + 7 mutation faults")
    print("source_sha256=" + hashlib.sha256(SRC.read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
