#!/usr/bin/env python3
"""Pure positive/fault controls for r5 Windows F1 receipt admission."""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("windows_assembler", ROOT / "assemble-tuple12-windows-f1.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)
EXE = "a" * 64
DLL = "b" * 64


def trace() -> str:
    return "\n".join([
        "renderer_ready_event=True",
        "SR0_NOACTIVATE guard=installed",
        "SR0_RENDERER_READY file=created",
        "record=renderer-ready",
        "phase=first-ready",
        "source=Bridge.onReady",
        "renderer_window_revalidate=PASS",
        "WindowMetrics phase=startup hwnd=0x10 pid=12 client_ok=True window_ok=True same_process=True",
        "client_ok=True",
        "same_process=True",
        "run_summary keymode=char delivery=targeted fg_changes=0 driver_abort=none",
        "SELFTEST F1: PASS (17/17)",
        "ASSERT F1 focus-stays-row5: PASS",
        "ASSERT F1 row5-text: PASS",
        "ASSERT F1 ax-focus-delivered: PASS",
        "setfocus_attempt[Row 5]=0 noactivate=True",
        "provider_focus[Row 5]=False",
        "focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus",
        "driver_abort=none",
        "driver_close_ready_file=True",
        "close_window=WM_CLOSE posted=True",
        "same_hwnd=True",
        "same_handle=True",
        "exit=0",
        f"ARTIFACTS exe={EXE} renderer={DLL}",
    ])


def main() -> int:
    good = trace()
    expected = {"exe": EXE, "renderer": DLL}
    ok, missing = MOD.marker_ok(good, EXE, DLL)
    if not ok:
        raise SystemExit(f"WINDOWS_ASSEMBLER_CONTROLS_FAIL positive:{missing}")
    faults = {
        "window-revalidation": good.replace("renderer_window_revalidate=PASS", "renderer_window_revalidate=FAIL", 1),
        "client-geometry": good.replace("client_ok=True", "client_ok=False"),
        "owner-process": good.replace("same_process=True", "same_process=False"),
        "native-17": good.replace("SELFTEST F1: PASS (17/17)", "SELFTEST F1: PASS (16/17)", 1),
        "foreground": good.replace("fg_changes=0", "fg_changes=1", 1),
        "retained-hwnd": good.replace("same_hwnd=True", "same_hwnd=False", 1),
    }
    rejected = []
    for name, mutated in faults.items():
        if MOD.marker_ok(mutated, EXE, DLL)[0]:
            raise SystemExit(f"WINDOWS_ASSEMBLER_CONTROLS_FAIL accepted:{name}")
        rejected.append(name)
    print({"kind": "sr0-tuple12-windows-f1-assembler-controls-v2", "status": "passed", "positive": 1, "faults": rejected})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
