from __future__ import annotations

import copy
import json
import shutil
import tempfile
from pathlib import Path

import verify_v7 as v

ROOT = Path(__file__).resolve().parent
WORKSPACE = ROOT.parents[3]


def isolated() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="seed-origin-v7-controls-"))
    shutil.copytree(ROOT, tmp / "bundle", ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    return tmp / "bundle"


def reject(label, fn):
    try:
        fn()
    except (AssertionError, KeyError, TypeError, ValueError, OSError):
        return {"control": label, "acceptedBaseline": True, "rejected": True}
    raise AssertionError(f"fault accepted: {label}")


def main():
    baseline = v.validate(ROOT, WORKSPACE)
    assert baseline["status"] == "PASS"
    controls = []

    b = isolated()
    p = next((b / "inputs").glob("swiftui.disabled.recipe.gate-seeded.*.swift"))
    p.write_text(p.read_text() + "\n// drift\n")
    controls.append(reject("source-bytes-drift", lambda: v.validate_inputs(b)))

    b = isolated(); pins = json.loads((b / "input-pins.json").read_text()); pins["rows"][0]["source"]["sha256"] = "sha256:" + "0" * 64; (b / "input-pins.json").write_text(json.dumps(pins))
    controls.append(reject("source-pin-drift", lambda: v.validate_inputs(b)))

    b = isolated(); p = b / "inputs/swiftright-does-not-exist"; witness = next((b / "inputs").glob("swiftui.image.witness.swift")); witness.write_text(witness.read_text() + "\n// drift\n")
    controls.append(reject("witness-bytes-drift", lambda: v.validate_inputs(b)))

    b = isolated(); pins = json.loads((b / "input-pins.json").read_text()); pins["rows"][1]["caseID"] = pins["rows"][0]["caseID"]; (b / "input-pins.json").write_text(json.dumps(pins))
    controls.append(reject("duplicate-case-id", lambda: v.validate_inputs(b)))

    b = isolated(); recipe = next((b / "inputs").glob("swiftui.toggle.json")); data = json.loads(recipe.read_text()); data["assertions"][0]["expected"]["initial"] = False; recipe.write_text(json.dumps(data))
    controls.append(reject("recipe-canonical-drift", lambda: v.validate_inputs(b)))

    b = isolated(); dep = b / "runtime-deps/factory/core/artifacts.py"; dep.write_text(dep.read_text() + "\n# drift\n")
    controls.append(reject("dependency-bytes-drift", lambda: v.validate_dependencies(b)))

    b = isolated(); collector = b / "capture_origin.py"; collector.write_text(collector.read_text() + "\n# collector drift\n")
    controls.append(reject("collector-source-drift", lambda: v.validate_admission(b, WORKSPACE)))

    b = isolated(); host = b / "CaptureHost.swift"; host.write_text(host.read_text().replace("AXIsProcessTrusted()", "AXIsProcessTrustedWithOptions([:] as CFDictionary)"))
    controls.append(reject("permission-api-source-fault", lambda: v.validate_admission(b, WORKSPACE)))

    assert len(controls) == 8
    receipt = {
        "kind": "seed-origin-v7-source-admission-controls",
        "baseline": baseline,
        "captureStatus": "NOT_RUN",
        "controls": controls,
        "scope": "five remaining seeded Mac cases; no capture executed",
    }
    (ROOT / "controls/v7-controls.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": "PASS", "rows": 5, "controls": len(controls), "captureStatus": "NOT_RUN"}))


if __name__ == "__main__":
    main()
