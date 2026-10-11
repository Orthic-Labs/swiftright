#!/usr/bin/env python3
"""Pure controls for strict Full16x20 assembler v4 + R5->R6 diagnostic overlay."""
from __future__ import annotations
import difflib
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ASSEMBLER = ROOT / "assemble-tuple12-windows-full-v4.py"
R5 = ROOT.parent / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r5.ps1"
R6 = ROOT / "tuple12-takeover/f3-ready-diagnosis-v1/drive-fixture-noactivate-focus-r6-diagnostic.ps1"
spec = importlib.util.spec_from_file_location("full_v4", ASSEMBLER)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
EXE, DLL = "a" * 64, "b" * 64
EXPECTED = {"exe": EXE, "renderer": DLL, "driver": mod.DRIVER_HASH,
            "worker": mod.WORKER_HASH, "coordinator": mod.COORDINATOR_HASH}

EXPECTED_ADDITIONS = [
    "    $readySeenMs = $rendererReadyWait.ElapsedMilliseconds",
    "    $readyReadWatch = [Diagnostics.Stopwatch]::StartNew()",
    "    $readyReadMs = $readyReadWatch.ElapsedMilliseconds",
    '    Log "renderer_ready_file_seen_ms=$readySeenMs read_ms=$readyReadMs bytes=$([Text.Encoding]::UTF8.GetByteCount($readyRaw))"',
]

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
        lines += ["ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS", "setfocus_attempt[Row 5]=0 noactivate=True", "provider_focus[Row 5]=False", "focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus", "SELFTEST F1: PASS (17/17 asserted; blocked=0; end=window-closed)"]
    return "\n".join(lines)

def fail(message):
    raise SystemExit(f"V3_CONTROLS_FAIL {message}")

def main():
    source = ASSEMBLER.read_text()
    for needle in ('DRIVER_BASE_HASH', 'DRIVER_HASH', 'requiredRuns": 320', 'runsPerConfig": 20', 'sr0-tuple12-windows-full-report-v4', 'approved r6 diagnostic'):
        if needle not in source: fail(f"assembler-missing={needle}")
    if len(mod.CONFIGS) != 16 or len(mod.EXPECTED_DENOMINATORS) != 16: fail("config-count")
    if mod.DRIVER_BASE_HASH != "5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4": fail("r5-base-pin")
    if mod.DRIVER_HASH != "0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c": fail("r6-pin")
    if mod.WORKER_HASH != "b039d4dce888e3dabbb7c3109bcd64abbf2b6313fdc818b4b11398460cdbac39": fail("worker-v5-pin")
    if mod.COORDINATOR_HASH != "e85c3c8f57b8e36d0df440bd60a884d28ce516824f8c127b5577345d1f982d6f": fail("coordinator-v5-pin")
    if mod.RUNNER_HASH != "cdff0f6771d8a380b3919a50f07a4637fc60db2af3df4395b6fa4573d1cbb437": fail("runner-v6-pin")
    worker = (ROOT / "tuple12-takeover/matrix-controls-v6/worker-v5.ps1").read_text()
    if "if ($Fixture -eq 'F6' -and $Variant -eq 'reduced') { \"$Fixture-$Variant\" }" not in worker: fail("f6-reduced-label-fix")
    if 'SELFTEST-STAGES {0}:" -f $selftestLabel' not in worker: fail("strict-worker-marker")
    if R5.exists() is False or R6.exists() is False: fail("overlay-source-missing")
    r5 = R5.read_text(encoding="utf-8").splitlines()
    r6 = R6.read_text(encoding="utf-8").splitlines()
    diff = list(difflib.ndiff(r5, r6))
    additions = [line[2:] for line in diff if line.startswith("+ ")]
    removals = [line[2:] for line in diff if line.startswith("- ")]
    if additions != EXPECTED_ADDITIONS: fail(f"overlay-additions={additions!r}")
    if removals: fail(f"overlay-removals={removals!r}")
    ok, errors = mod.marker_ok(trace(), "F1", "", EXPECTED)
    if not ok: fail(f"positive={errors}")
    mutations = {
        "denominator": trace().replace("17/17 asserted", "16/17 asserted", 1),
        "noactivate": trace().replace("SR0_NOACTIVATE guard=installed", "SR0_NOACTIVATE guard=missing", 1),
        "focus": trace().replace("fg_changes=0", "fg_changes=1", 1),
        "driver": trace().replace("driver_abort=none", "driver_abort=focus", 1),
    }
    for name, mutated in mutations.items():
        if mod.marker_ok(mutated, "F1", "", EXPECTED)[0]: fail(f"accepted={name}")
    if mod.DRIVER_HASH == "f" * 64: fail("impossible")
    print({"kind": "sr0-tuple12-windows-full-assembler-controls-v4", "status": "passed", "configs": 16, "runs": 320, "overlay": "R5->R6-four-lines", "faults": 4})

if __name__ == "__main__":
    main()
