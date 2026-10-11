#!/usr/bin/env python3
"""Pure v5 controls: exact derived joins, gate faults, immutable inputs."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / "factory").is_dir())
sys.path.insert(0, str(REPO))
CAP = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-output-r7.actual.json"
BUNDLE = REPO / "factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r2/proof-bundle-r7-v2.json"
DERIVE = HERE / "derive-v5.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod


def main():
    original = CAP.read_bytes()
    derive = load(DERIVE, "derive_v5")
    gate = load(REPO / "factory/native/windows/remaining-five-hosts-v5/dependencies/windows_exit_admission.py", "gate_v5")
    captures = json.loads(original.decode("utf-8-sig"))["captures"]
    bundle = json.loads(BUNDLE.read_text())
    derived = derive.derive(captures, bundle)[0]
    archive = bundle["archiveBindings"]["1"]

    def reader(path):
        return Path(archive[path]["sourcePath"]).read_bytes()

    positive = gate.verify_windows_exit_admission(derived, read_bytes=reader)
    assert positive["status"] == "blocked" and positive["issues"] == ["'rawHashStates'"]
    assert hashlib.sha256(CAP.read_bytes()).hexdigest() == hashlib.sha256(original).hexdigest()
    faults = []
    for field, expected in (
        ("actualSourceHash", "Witness source identity mismatch"),
        ("actualHostExecutableHash", "actual executable bytes mismatch"),
        ("rawReceiptHash", "observation/clock raw join"),
    ):
        bad = copy.deepcopy(derived)
        bad["meta"]["conditions"][field] = "sha256:" + "0" * 64
        result = gate.verify_windows_exit_admission(bad, read_bytes=reader)
        assert result["status"] == "blocked" and expected in result["issues"], (field, result)
        faults.append(field)
    print(json.dumps({"status": "pass", "positive": positive["issues"], "faults": faults, "nativeWindowActions": 0}, sort_keys=True))


if __name__ == "__main__":
    main()
