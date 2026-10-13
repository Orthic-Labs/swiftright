#!/usr/bin/env python3
"""Pure controls for read-only target display context probe."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "tuple12-takeover/workload-analysis-v3/display-context.ps1"


def main() -> int:
    s = SRC.read_text(encoding="utf-8")
    required = (
        "[Parameter(Mandatory)][int]$TargetPid",
        "[Parameter(Mandatory)][IntPtr]$TargetHwnd",
        "GetForegroundWindow",
        "GetWindowThreadProcessId",
        "GetWindowRect",
        "GetClientRect",
        "ClientToScreen",
        "MonitorFromWindow",
        "GetMonitorInfo",
        "ProcessIdToSessionId",
        "WTSGetActiveConsoleSessionId",
        "[IO.FileMode]::CreateNew",
        "foreground_is_target",
        "work_area",
        "single read-only snapshot",
    )
    for needle in required:
        if needle not in s:
            raise AssertionError(f"missing display probe guard: {needle}")
    for needle in ("SendInput", "SetForegroundWindow", "ShowWindow", "SetWindowPos", "Start-Process", "Remove-Item", "Get-Process", "schtasks", "desktop.lock"):
        if needle in s:
            raise AssertionError(f"forbidden display effect: {needle}")
    print("tuple12 display-context controls: PASS read-only HWND/work-area/foreground/session inventory")
    print("source_sha256=" + hashlib.sha256(SRC.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
