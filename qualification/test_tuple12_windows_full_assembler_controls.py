#!/usr/bin/env python3
"""Pure positive/fault controls for strict tuple12 Full assembler."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("full_assembler", ROOT / "assemble-tuple12-windows-full-v1.py")
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)
EXE = "a" * 64; DLL = "b" * 64; WORKER = "c" * 64; COORD = "d" * 64
EXPECTED = {"exe": EXE, "renderer": DLL, "driver": MOD.DRIVER_HASH, "worker": WORKER, "coordinator": COORD}


def trace(fixture="F1", variant=""):
    label = MOD._config_label(fixture, variant)
    lines = [
        "renderer_ready_event=True", "SR0_NOACTIVATE guard=installed",
        "SR0_RENDERER_READY file=created", "record=renderer-ready",
        "phase=first-ready", "source=Bridge.onReady", "renderer_window_revalidate=PASS",
        "WindowMetrics phase=startup hwnd=0x10 pid=12 client_ok=True window_ok=True same_process=True",
        "client_ok=True", "same_process=True",
        "run_summary keymode=char delivery=targeted fg_changes=0 driver_abort=none",
        f"SELFTEST-STAGES {label}: stages", f"ASSERT {label} script-completed: PASS",
        f"ASSERT {label} renderer-no-violations: PASS", f"ASSERT {label} commits-accepted: PASS",
        f"ASSERT {label} no-measure-or-draw-failures: PASS",
        f"SELFTEST {label}: PASS ({MOD.EXPECTED_DENOMINATORS[(fixture, variant)]}/{MOD.EXPECTED_DENOMINATORS[(fixture, variant)]} asserted; blocked=0; end=window-closed)",
        "driver_close_ready_file=True", "close_window=WM_CLOSE posted=True",
        "same_hwnd=True", "same_handle=True", "exit=0", f"ARTIFACTS exe={EXE} renderer={DLL}",
    ]
    if fixture == "F1":
        lines += ["ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS", "setfocus_attempt[Row 5]=0 noactivate=True", "provider_focus[Row 5]=False", "focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus", "SELFTEST F1: PASS (17/17 asserted; blocked=0; end=window-closed)"]
    return "\n".join(lines)


def main():
    text = trace()
    ok, failures = MOD.marker_ok(text, "F1", "", EXPECTED)
    if not ok: raise SystemExit(f"WINDOWS_FULL_CONTROLS_FAIL positive={failures}")
    faults = {
        "wrong-native-denominator": text.replace("17/17 asserted", "16/17 asserted", 1),
        "missing-variant-stage": text.replace("SELFTEST-STAGES F1:", "SELFTEST-STAGES F2:", 1),
        "activation": text.replace("SR0_NOACTIVATE guard=installed", "SR0_NOACTIVATE guard=missing", 1),
        "foreground": text.replace("fg_changes=0", "fg_changes=1", 1),
        "renderer-join": text.replace(f"ARTIFACTS exe={EXE} renderer={DLL}", f"ARTIFACTS exe={EXE} renderer={'e'*64}", 1),
        "window-identity": text.replace("same_hwnd=True", "same_hwnd=False", 1),
    }
    rejected = []
    for name, mutated in faults.items():
        if MOD.marker_ok(mutated, "F1", "", EXPECTED)[0]: raise SystemExit(f"WINDOWS_FULL_CONTROLS_FAIL accepted={name}")
        rejected.append(name)
    if MOD.parse_case("F3-list-1s-r1-0123456789abcdef0123456789abcdef") != (("F3", "list-1s"), 1):
        raise SystemExit("WINDOWS_FULL_CONTROLS_FAIL variant-parse")
    if MOD.parse_case("F3-list-2s-r1-0123456789abcdef0123456789abcdef") is not None:
        raise SystemExit("WINDOWS_FULL_CONTROLS_FAIL unknown-variant")
    for fixture, variant in (("F3", "list-1s"), ("F6", "reduced")):
        variant_ok, variant_failures = MOD.marker_ok(trace(fixture, variant), fixture, variant, EXPECTED)
        if not variant_ok: raise SystemExit(f"WINDOWS_FULL_CONTROLS_FAIL variant={fixture}-{variant}:{variant_failures}")
    if len(MOD.CONFIGS) != 16 or len(MOD.EXPECTED_DENOMINATORS) != 16:
        raise SystemExit("WINDOWS_FULL_CONTROLS_FAIL config-denominators")
    print({"kind": "sr0-tuple12-windows-full-assembler-controls-v1", "status": "passed", "positive": 1, "faults": rejected, "configs": 16, "runs": 320})


if __name__ == "__main__": main()
