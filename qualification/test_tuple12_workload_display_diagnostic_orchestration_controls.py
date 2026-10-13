#!/usr/bin/env python3
"""Source-only controls for one-run workload + read-only display sampler envelope."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "tuple12-takeover/workload-display-diagnostic-v1/run-one-diagnostic.ps1"


def need(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def check(source: str) -> None:
    for needle in (
        "run-workload.ps1", "display-context-sampler-v1.ps1", "'-Runs','1'",
        "'-NoActivate'", "'-LifecycleProof'", "Try-Acquire-Lock", "Release-Lock",
        "Start-PowerShellScript", "CopyToAsync", "Kernel-Terminal", "runHandle", "samplerHandle",
        "DiscoverySeconds", "Warmup", "Measure", "$runDeadline", "$samplerDeadline",
        "$runTerminal -and $runStdoutDrained -and $runStderrDrained -and $taskQuiescent",
        "$samplerStarted -and $samplerTerminal -and $samplerStdoutDrained -and $samplerStderrDrained",
        "nativeConclusion='display-context-only; strict PresentMon displayed-row gate unchanged'",
        "display-context.stdout.txt", "display-context.stderr.txt", "diagnostic-receipt.json",
    ):
        need(needle in source, f"missing orchestration guard: {needle}")
    for forbidden in (
        "SetWindowPos", "SetForegroundWindow", "ShowWindow", "PostMessage", "SendInput",
        "Register-ScheduledTask", "New-ScheduledTask", "Unregister-ScheduledTask", "Stop-Process", "Kill()",
    ):
        need(forbidden not in source, f"new desktop/process mutation retained: {forbidden}")
    need(source.count("[IO.FileMode]::CreateNew") >= 1, "receipt/output creation must be exclusive")
    need("$orchestratorStdout" in source and "$samplerStdoutPath" in source, "owned child streams must be distinct")


def main() -> int:
    source = SRC.read_text(encoding="utf-8")
    need(len(source.encode()) <= 512 * 1024, "orchestration source exceeds bound")
    check(source)
    for label, mutated in (
        ("three-runs", source.replace("'-Runs','1'", "'-Runs','3'", 1)),
        ("release-without-sampler", source.replace("$samplerStarted -and $samplerTerminal", "$true", 1)),
        ("desktop-mutation", source.replace("# This envelope adds no GUI operation", "SetWindowPos", 1)),
    ):
        try:
            check(mutated)
        except AssertionError:
            continue
        raise AssertionError(f"orchestration mutation escaped: {label}")
    print("tuple12 workload display diagnostic orchestration controls: PASS one-run lock-owned source")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
