#!/usr/bin/env python3
"""Source controls for production identity/count/terminal gates.

Controls intentionally call production `compare`, not a duplicate predicate.
They create only small temporary JSON fixtures when root executes this file.
"""
from __future__ import annotations

import json
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("text_paint_production", HERE / "compare_text_paint.py")
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def check() -> None:
    source_row = {"bytes": mod.SOURCE_BYTES, "sha256": mod.SOURCE_HASH}
    base_summary = {"compilerReceipt": {"compiler": {
        "sourceBefore": {"Witness.swift": source_row},
        "sourceAfter": {"Witness.swift": dict(source_row)},
    }}}
    base_capture = {"provenance": {
        "producer": "factory/native/macos",
        "sourceHash": "sha256:" + "1" * 64,
        "inputs": [{"id": "macos.capture.binary", "hash": mod.MAC_HOST_HASH}],
    }}
    mod.validate_mac_provenance(base_summary, base_capture)
    for name, mutate in (
        ("missing-source-receipt", lambda s, c: s["compilerReceipt"]["compiler"].pop("sourceAfter")),
        ("missing-capture-provenance", lambda s, c: c.pop("provenance")),
        ("wrong-source-bytes", lambda s, c: s["compilerReceipt"]["compiler"]["sourceAfter"]["Witness.swift"].update(bytes=404)),
        ("wrong-host-input", lambda s, c: c["provenance"]["inputs"][0].update(hash="sha256:" + "2" * 64)),
    ):
        s = json.loads(json.dumps(base_summary)); c = json.loads(json.dumps(base_capture)); mutate(s, c)
        try:
            mod.validate_mac_provenance(s, c)
        except mod.Hold:
            pass
        else:
            raise AssertionError(name)

    # Geometry controls exercise production coordinate/DPI derivation.  Raw
    # host coordinates remain intact; only measured dimensions are converted.
    mac_geometry = mod.derive_mac_text_geometry({
        "role": "AXStaticText", "value": "Aa",
        "frame": {"x": 166, "y": 922, "w": 28, "h": 28},
    })
    assert mac_geometry["dimensionsDip"] == {"width": 28.0, "height": 28.0}
    win_geometry = mod.derive_windows_text_geometry({
        "controlType": "ControlType.Text", "value": "Aa",
        "bounds": [1693, 1072, 70, 72],
    }, 240)
    assert win_geometry["dimensionsDip"] == {"width": 28.0, "height": 28.8}
    for name, fn in (
        ("mac-missing-frame", lambda: mod.derive_mac_text_geometry({"role": "AXStaticText"})),
        ("mac-negative-size", lambda: mod.derive_mac_text_geometry({"frame": {"x": 0, "y": 0, "w": -1, "h": 2}})),
        ("windows-bad-bounds", lambda: mod.derive_windows_text_geometry({"bounds": [1, 2, 3]}, 240)),
        ("windows-bad-dpi", lambda: mod.derive_windows_text_geometry({"bounds": [1, 2, 3, 4]}, 0)),
    ):
        try:
            fn()
        except mod.Hold:
            pass
        else:
            raise AssertionError(name)

    mac_owned = {"retainedProcessHandle": True}
    assert mod.mac_terminal_observation_hold(mac_owned) == "Mac original-process exit/cleanup evidence absent"
    nonzero_owned = {"retainedProcessHandle": True, "exitCode": 17}
    assert mod.mac_terminal_observation_hold(nonzero_owned) == "Mac original-process exit code nonzero: 17"
    incomplete_owned = {"retainedProcessHandle": True, "exitCode": 0, "cleanup": {"completed": False}}
    assert mod.mac_terminal_observation_hold(incomplete_owned) == "Mac original-process cleanup evidence absent"
    complete_owned = {"retainedProcessHandle": True, "exitCode": 0, "cleanup": {"completed": True}}
    assert mod.mac_terminal_observation_hold(complete_owned) is None

    base_coordinator = {
        "count": 20, "status": "completed-source-bound-observation", "wholeBatchExitConfirmed": True,
        "lockReleased": True, "cleanupErrors": [],
        "taskParentProof": {"kernelWait": 0, "retainedHandle": 1920, "kernelExitCode": 0,
                             "kernelExitCodeSigned": 0, "dotNetExited": True, "dotNetExitCode": 0},
    }
    base_task = {
        "count": 20, "status": "completed-source-bound-observation",
        "memoryReceipt": {"status": "passed", "activeProcessCount": 1,
                           "jobMemoryLimitBytes": 1073741824, "limitFlags": 512, "killOnJobClose": False},
    }
    mod.validate_windows_control(base_coordinator, base_task)
    # Production Windows terminal predicate rejects each mutation; no mirror
    # validator or synthetic native evidence is used.
    for name, mutate in (
        ("count19", lambda c, t: c.update(count=19)),
        ("lock-held", lambda c, t: c.update(lockReleased=False)),
        ("parent-kernel", lambda c, t: c["taskParentProof"].update(kernelWait=1)),
        ("parent-dotnet", lambda c, t: c["taskParentProof"].update(dotNetExitCode=17)),
        ("memory-active", lambda c, t: t["memoryReceipt"].update(activeProcessCount=0)),
        ("memory-budget", lambda c, t: t["memoryReceipt"].update(jobMemoryLimitBytes=536870912)),
        ("memory-kill", lambda c, t: t["memoryReceipt"].update(killOnJobClose=True)),
    ):
        c = json.loads(json.dumps(base_coordinator)); t = json.loads(json.dumps(base_task)); mutate(c, t)
        try:
            mod.validate_windows_control(c, t)
        except mod.Hold:
            pass
        else:
            raise AssertionError(name)


if __name__ == "__main__":
    check()
    print("text-paint production controls: PASS")
