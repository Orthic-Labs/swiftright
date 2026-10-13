#!/usr/bin/env python3
"""Source-only controls for bounded read-only workload display diagnostic."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "tuple12-takeover/workload-display-diagnostic-v1/display-context-sampler-v1.ps1"
PINS = ROOT / "tuple12-takeover/workload-display-diagnostic-v1/source-pins.json"


def need(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def check(source: str) -> None:
    for needle in (
        "Sr0DisplayDiagnosticV1", 'EntryPoint="WindowFromPoint"', "[Sr0DisplayDiagnosticV1]::WindowFromPoint(", "GetAncestor", "DwmGetWindowAttribute",
        "ProcessIdToSessionId", "WTSGetActiveConsoleSessionId", "GetMonitorInfo",
        "ValidateRange(1,120)", "ValidateRange(100,2000)", "$maxSamples", "for ($i=0; $i -lt $maxSamples; $i++)",
        "[IO.FileMode]::CreateNew", "strictCauseConclusion='presentmon_display_rows_not_inferred'",
        "desktop_mutation=$false", "permission_change=$false", "process_launch=$false",
        "unoccluded-observation", "background-or-occluded-observation", "interactive-session-unavailable",
    ):
        need(needle in source, f"missing diagnostic guard: {needle}")
    for forbidden in (
        "SetWindowPos", "SetForegroundWindow", "ShowWindow", "PostMessage", "SendInput",
        "Start-Process", "ProcessStartInfo", "New-ScheduledTask", "Register-ScheduledTask",
        "Unregister-ScheduledTask", "Stop-Process", "Kill()", "AdjustTokenPrivileges",
    ):
        need(forbidden not in source, f"desktop/process mutation retained: {forbidden}")
    need(source.count("[IO.FileMode]::CreateNew") >= 2, "raw & summary outputs must be create-new")
    need("Start-Sleep -Milliseconds $SampleMilliseconds" in source, "bounded sampling interval missing")


def main() -> int:
    source = SRC.read_text(encoding="utf-8")
    need(len(source.encode()) <= 512 * 1024, "diagnostic source exceeds bound")
    check(source)
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    need(pins["kind"] == "sr0-tuple12-workload-display-diagnostic-v1", "diagnostic source pin kind")
    need(pins["limits"]["runs"] == 1, "diagnostic source pin run count")
    need(pins["workload_controls"]["path"].endswith("workload-controls-v8/run-workload.ps1"), "v8 workload binding")
    need(pins["mutation"] == {"desktop": False, "permissions": False, "new_tasks": False, "input": False, "process_kill": False}, "mutation declaration")
    for label, mutated in (
        ("drop-occlusion", source.replace("[Sr0DisplayDiagnosticV1]::WindowFromPoint(", "[Sr0DisplayDiagnosticV1]::RemovedWindowFromPoint(", 1)),
        ("allow-activation", source.replace("# Read-only HWND/session/occlusion sampling.", "SetWindowPos", 1)),
        ("overwrite-output", source.replace("[IO.FileMode]::CreateNew", "[IO.FileMode]::Create", 1)),
    ):
        try:
            check(mutated)
        except AssertionError:
            continue
        raise AssertionError(f"diagnostic mutation escaped: {label}")
    print("tuple12 workload display diagnostic controls: PASS bounded read-only occlusion/session source")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
