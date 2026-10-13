#!/usr/bin/env python3
"""Pure source + marker controls for strict v2 Full matrix assembler."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PATH = ROOT / "assemble-tuple12-windows-full-v2.py"
spec = importlib.util.spec_from_file_location("full_v2", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
EXE, DLL = "a" * 64, "b" * 64
EXPECTED = {"exe": EXE, "renderer": DLL, "driver": mod.DRIVER_HASH, "worker": mod.WORKER_HASH, "coordinator": mod.COORDINATOR_HASH}

def trace(fixture="F1", variant=""):
    label = mod._config_label(fixture, variant)
    den = mod.EXPECTED_DENOMINATORS[(fixture, variant)]
    lines = [
        "renderer_ready_event=True", "SR0_NOACTIVATE guard=installed", "SR0_RENDERER_READY file=created",
        "record=renderer-ready", "phase=first-ready", "source=Bridge.onReady", "renderer_window_revalidate=PASS",
        "WindowMetrics phase=startup client_ok=True same_process=True", "run_summary keymode=char delivery=targeted fg_changes=0",
        f"SELFTEST-STAGES {label}:", f"ASSERT {label} script-completed: PASS", f"ASSERT {label} renderer-no-violations: PASS",
        f"ASSERT {label} commits-accepted: PASS", f"ASSERT {label} no-measure-or-draw-failures: PASS",
        f"SELFTEST {label}: PASS ({den}/{den} asserted; blocked=0; end=window-closed)", "driver_abort=none",
        "driver_close_ready_file=True", "close_window=WM_CLOSE posted=True", "same_hwnd=True", "same_handle=True", "exit=0",
        f"ARTIFACTS exe={EXE} renderer={DLL}",
    ]
    if fixture == "F1":
        lines += ["ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS", "setfocus_attempt[Row 5]=0 noactivate=True", "provider_focus[Row 5]=False", "focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus", f"SELFTEST F1: PASS (17/17 asserted; blocked=0; end=window-closed)"]
    return "\n".join(lines)

def main():
    source = PATH.read_text()
    required = ("WORKER_HASH", "COORDINATOR_HASH", "RUNNER_HASH", 'kind": "sr0-tuple12-matrix-run-v5"', 'requiredRuns": 320', 'passedRuns": len(rows)', 'expected-runner', 'runner-path')
    for needle in required:
        if needle not in source:
            raise SystemExit(f"V2_CONTROLS_FAIL missing={needle}")
    if len(mod.CONFIGS) != 16 or len(mod.EXPECTED_DENOMINATORS) != 16:
        raise SystemExit("V2_CONTROLS_FAIL config-count")
    ok, errors = mod.marker_ok(trace(), "F1", "", EXPECTED)
    if not ok:
        raise SystemExit(f"V2_CONTROLS_FAIL positive={errors}")
    for name, mutated in {
        "denominator": trace().replace("17/17 asserted", "16/17 asserted", 1),
        "noactivate": trace().replace("SR0_NOACTIVATE guard=installed", "SR0_NOACTIVATE guard=missing", 1),
        "focus": trace().replace("fg_changes=0", "fg_changes=1", 1),
        "driver": trace().replace("driver_abort=none", "driver_abort=focus", 1),
    }.items():
        if mod.marker_ok(mutated, "F1", "", EXPECTED)[0]:
            raise SystemExit(f"V2_CONTROLS_FAIL accepted={name}")
    print({"kind": "sr0-tuple12-windows-full-assembler-controls-v2", "status": "passed", "configs": 16, "runs": 320, "faults": 4})

if __name__ == "__main__":
    main()
