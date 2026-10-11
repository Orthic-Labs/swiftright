#!/usr/bin/env python3
"""Fail-closed source-bound admission for tuple12 noactivate traces.

Pure receipt check; never launches, edits, deletes, or contacts Windows. --fault-controls
mutates an in-memory copy of one retained trace and proves each gate rejects it.
"""
from __future__ import annotations
import argparse
from pathlib import Path

FOCUS_ROWS = {"F1": "Row 5", "F2": "Row 3", "F3": "Row 4", "F7": "Row 2", "F8": "Row 3"}

def required(fixture: str, exe: str, dll: str) -> list[str]:
    out = [
        "renderer_ready_event=True", "SR0_NOACTIVATE guard=installed", "SR0_RENDERER_READY file=created",
        "record=renderer-ready", "phase=first-ready", "source=Bridge.onReady", "WindowMetrics phase=startup",
        "client_ok=True", "same_process=True", "run_summary keymode=char delivery=targeted fg_changes=0",
        f"SELFTEST {fixture}: PASS", "driver_abort=none", "driver_close_ready_file=True",
        "close_window=WM_CLOSE posted=True", "same_hwnd=True", "same_handle=True", "exit=0",
        f"ARTIFACTS exe={exe} renderer={dll}",
    ]
    if fixture in FOCUS_ROWS:
        row = FOCUS_ROWS[fixture]
        out += [f"setfocus_attempt[{row}]=0 noactivate=True", f"provider_focus[{row}]=False",
                f"focus[{row}]=NOT_CONFIRMED provider=HasKeyboardFocus"]
    if fixture == "F1":
        out += ["SELFTEST F1: PASS (17/17", "ASSERT F1 focus-stays-row5: PASS",
                "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS"]
    return out

def verify(text: str, fixture: str, exe: str, dll: str) -> tuple[bool, list[str]]:
    missing = [needle for needle in required(fixture, exe, dll) if needle.lower() not in text.lower()]
    guard = text.lower().find("sr0_noactivate guard=installed")
    ready = text.lower().find("sr0_renderer_ready file=created")
    if guard < 0 or ready <= guard:
        missing.append("guard-before-renderer-ready")
    return not missing, missing

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--trace", type=Path, required=True)
    ap.add_argument("--fixture", choices=sorted({"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9"}), required=True)
    ap.add_argument("--expect-exe", required=True)
    ap.add_argument("--expect-dll", required=True)
    ap.add_argument("--fault-controls", action="store_true")
    ns = ap.parse_args()
    text = ns.trace.read_text(encoding="utf-8")
    ok, missing = verify(text, ns.fixture, ns.expect_exe.lower(), ns.expect_dll.lower())
    if not ok:
        print("ADMISSION_FAIL missing=" + ",".join(missing))
        return 1
    print("ADMISSION_PASS trace=" + str(ns.trace))
    if ns.fault_controls:
        faults = {
            "missing-17-assertions": ("SELFTEST F1: PASS (17/17", "SELFTEST F1: PASS (16/17"),
            "wrong-node": ("ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 focus-stays-row3: PASS"),
            "activation": ("SR0_NOACTIVATE guard=installed", "SR0_NOACTIVATE guard=missing"),
            "abort": ("driver_abort=none", "driver_abort=foreground-lost"),
        }
        for name, (old, new) in faults.items():
            if old.lower() not in text.lower():
                print(f"FAULT_CONTROL_FAIL {name}: source marker absent")
                return 1
            mutated = text.replace(old, new, 1)
            fault_ok, _ = verify(mutated, ns.fixture, ns.expect_exe.lower(), ns.expect_dll.lower())
            if fault_ok:
                print(f"FAULT_CONTROL_FAIL {name}: mutation admitted")
                return 1
            print(f"FAULT_CONTROL_PASS {name}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
