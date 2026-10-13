#!/usr/bin/env python3
"""Pure controls for tuple12 workload background overlay source admission."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "qualification/tuple12-workload-background-overlay.patch"
BASE = ROOT / "probes/sr0-b/workload/scripts/task-workload.ps1"
RUN_PATCH = ROOT / "qualification/tuple12-workload-run-overlay.patch"
RUN_BASE = ROOT / "probes/sr0-b/workload/scripts/run-workload.ps1"
MANIFEST = ROOT / "qualification/tuple12-workload-source-manifest.json"


def fail(name: str, reason: str) -> None:
    raise AssertionError(f"{name}: {reason}")


def assert_orchestrator(text: str) -> None:
    required = {
        "NoActivate switch": "[switch]$NoActivate",
        "NoActivate log": "noactivate=$(if ($NoActivate)",
        "forward flag": "$(if ($NoActivate) { ' -NoActivate' })",
    }
    for name, needle in required.items():
        if needle not in text:
            fail(name, f"missing {needle!r}")


def assert_overlay(text: str) -> None:
    required = {
        "NoActivate switch": "[switch]$NoActivate",
        "HWND_BOTTOM": "(IntPtr)1",
        "SWP_NOACTIVATE": "SWP_NOACTIVATE",
        "SW_SHOWNOACTIVATE": "SW_SHOWNOACTIVATE",
        "startup guard": "startup_activation=guarded",
        "fail closed": "background-noactivate-failed",
        "no failure input": "{ -1 } else",
    }
    for name, needle in required.items():
        if needle not in text:
            fail(name, f"missing {needle!r}")
    if "SetForegroundWindow" in text[text.index("if ($NoActivate)"):text.index("} else {", text.index("if ($NoActivate)"))]:
        fail("noactivate branch", "foreground takeover present")
    if "[math]::Max($KeyRate, 1)" not in text:
        fail("zero-duration safety", "rate guard missing")


def main() -> int:
    text = PATCH.read_text(encoding="utf-8")
    base_text = BASE.read_text(encoding="utf-8")
    run_text = RUN_PATCH.read_text(encoding="utf-8")
    run_base_text = RUN_BASE.read_text(encoding="utf-8")
    assert_overlay(text)
    assert_orchestrator(run_text)
    for name, needle in (("targeted input", "PostMessage"), ("QPC input", "qpc_before"), ("activity metrics", "activity.csv")):
        if needle not in base_text:
            fail(name, f"base missing {needle!r}")
    manifest = json.loads(MANIFEST.read_text())
    for base_path, label in ((BASE, "task"), (RUN_BASE, "run")):
        if hashlib.sha256(base_path.read_bytes()).hexdigest() != next(
            e["sha256"] for e in manifest["entries"] if e["path"] == base_path.relative_to(ROOT).as_posix()
        ):
            fail(f"{label} base join", f"manifest {label} script hash does not match source")
    policy = manifest["runtime_policy"]
    if policy["workload_runs_per_configuration"] != 3 or policy["cross_compare_runs_per_side"] != 20:
        fail("run policy", "denominators drifted")
    if policy["three_run_exception"] is not False:
        fail("run policy", "three-run exception admitted")
    faults = []
    for label, needle in (("remove-window-bottom", "HWND_BOTTOM"), ("remove-noactivate", "SWP_NOACTIVATE"), ("remove-input", "PostMessage"), ("remove-metrics", "qpc_before")):
        mutated = (base_text + "\n" + text).replace(needle, "")
        try:
            assert_overlay(mutated)
            if needle not in mutated:
                fail(label, f"missing {needle!r}")
        except AssertionError:
            faults.append(label)
    if len(faults) != 4:
        fail("fault controls", f"caught {faults}")
    run_faults = []
    for label, needle in (("remove-run-switch", "[switch]$NoActivate"), ("remove-run-log", "noactivate=$(if ($NoActivate)"), ("remove-run-forward", "' -NoActivate'")):
        mutated = run_base_text + "\n" + run_text.replace(needle, "")
        try:
            assert_orchestrator(mutated)
        except AssertionError:
            run_faults.append(label)
    if len(run_faults) != 3:
        fail("orchestrator fault controls", f"caught {run_faults}")
    print("tuple12 workload overlay controls: PASS positive + 4 background + 3 orchestrator mutation faults")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
