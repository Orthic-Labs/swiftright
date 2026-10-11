#!/usr/bin/env python3
"""Offline controls for explicit r7 proof bundle joins."""
from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / "factory").is_dir())
MAP = HERE / "r7-explicit-input-map-v2.json"
CAPTURES = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-output-r7.actual.json"
BUILDER = HERE / "build-windows-exit-proof-r2.py"


def run(map_path, output):
    return subprocess.run(
        [sys.executable, str(BUILDER), "--captures", str(CAPTURES), "--input-map", str(map_path), "--output", str(output), "--verify-gate"],
        cwd=REPO, capture_output=True, text=True,
    )


def main():
    m = json.loads(MAP.read_text())
    assert set(m["roles"]) == {"outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr"}
    assert m["sourceFacts"]["hostRows"] == 13 and m["sourceFacts"]["nativeRawRows"] == 24 and m["sourceFacts"]["runtimeTreeRows"] == 21
    assert len(m["runtimeTreeBindings"]) == 21
    assert len(m["runtimeModules"]) == 2
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)
        good_map = temp / "good-map.json"
        good_map.write_text(json.dumps(m))
        good_out = temp / "good.json"
        good = run(good_map, good_out)
        assert good.returncode == 0, good.stderr + good.stdout
        bundle = json.loads(good_out.read_text())
        assert bundle["status"] == "proofs-attached" and len(bundle["captures"]) == 1
        assert bundle["gateResults"][0]["status"] == "blocked"
        assert bundle["gateResults"][0]["issues"] == ["'actualSourceHash'"]
        # Fault 1: runtime source byte binding must reject drift.
        bad_runtime = copy.deepcopy(m)
        bad_runtime["runtimeTreeBindings"][0]["source"]["sha256"] = "sha256:" + "0" * 64
        bad_path = temp / "bad-runtime.json"
        bad_path.write_text(json.dumps(bad_runtime))
        bad = run(bad_path, temp / "bad-runtime-out.json")
        assert bad.returncode != 0 and "source ref drift" in (bad.stdout + bad.stderr)
        # Fault 2: every declared production proof role is mandatory.
        bad_role = copy.deepcopy(m)
        del bad_role["roles"]["runtimeReceipt"]
        bad_path = temp / "bad-role.json"
        bad_path.write_text(json.dumps(bad_role))
        bad = run(bad_path, temp / "bad-role-out.json")
        assert bad.returncode != 0 and "runtimeReceipt" in (bad.stdout + bad.stderr)
    print(json.dumps({"status": "pass", "positive": "proof-attached/gate-blocked-honestly", "faults": 2}, sort_keys=True))


if __name__ == "__main__":
    main()
