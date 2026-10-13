#!/usr/bin/env python3
"""Source-only negative controls for strict Windows r11 replay admission."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
PACKET = ROOT / "factory/oracle/mac/padding-origin-r11-source-v1"
GEN = PACKET / "generated/13bfe5b8fbd9"
WIN = ROOT / "factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1"
FRESH = PACKET / "windows-replay-admission-r1/fresh-windows-source-r11-h13bfe5b8fbd9"
ACT = WIN / "observed-native20-r7/actual-repeat-r1"
ADAPTER = WIN / "adapter-v6-r7"
ARCHIVE = ADAPTER / "trusted-reader-archive-r7/capture-bd1cba8c7017fc5cfc343288191ebd130f6f38730f69266301194ebcac81e7de"
ADMIT = Path(__file__).with_name("admit-windows-replay-v2.py")


def run(case_name: str, mutate, td: Path) -> list[str]:
    files = {
        "case": GEN / "cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json",
        "manifest": GEN / "manifests/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.manifest.json",
        "tuple": GEN / "candidate-tuple.json",
        "donor-tuple": ACT / "candidate-tuple.json",
        "windows-executable": ARCHIVE / "FactoryProbe.exe",
        "witness-manifest": FRESH / "witness.manifest.json",
        "witness-source": FRESH / "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.swift",
        "actual-receipt": ACT / "observation.json",
        "actual-plan": ACT / "plan.json",
        "actual-binding": ACT / "candidate-binding.json",
        "actual-proof-bundle": ADAPTER / "proof-bundle-r7-v2c.actual.json",
        "actual-reader": ADAPTER / "trusted-reader-count20-r7.actual.json",
        "actual-compiler": ARCHIVE / "tool/compiler.bin",
        "actual-runtime-receipt": ACT / "runtime-source-receipt.json",
        "actual-runtime-tree": ACT / "runtime-source-tree.json",
    }
    td.mkdir(parents=True, exist_ok=True)
    local = {}
    for key, source in files.items():
        dest = td / source.name if key in ('witness-source', 'witness-manifest') else td / (key.replace('-', '_') + source.suffix)
        shutil.copyfile(source, dest)
        local[key] = dest
    mutate(local)
    output = td / (case_name + ".json")
    command = [sys.executable, str(ADMIT)]
    for key, path in local.items():
        command += ["--" + key, str(path)]
    command += ["--output", str(output)]
    completed = subprocess.run(command, text=True, capture_output=True)
    if completed.returncode != 2:
        raise AssertionError(f"{case_name}: expected typed reject exit 2, got {completed.returncode}\n{completed.stdout}\n{completed.stderr}")
    result = json.loads(output.read_text())
    if result.get("status") != "fresh-windows-compile-required":
        raise AssertionError(f"{case_name}: wrong status {result.get('status')}")
    return result["reasons"]


def main() -> int:
    checks = {}
    with tempfile.TemporaryDirectory(prefix="r11-replay-v2-controls-") as name:
        root = Path(name)
        checks["empty-receipt"] = run("empty-receipt", lambda f: f["actual-receipt"].write_text("{}\n"), root / "empty")
        checks["self-authored-receipt"] = run("self-authored-receipt", lambda f: shutil.copyfile(FRESH / "compiler-receipt-ref.json", f["actual-receipt"]), root / "self")
        def wrong_source(f):
            f["witness-source"].write_bytes(f["witness-source"].read_bytes() + b"\nchanged-input\n")
        checks["wrong-source"] = run("wrong-source", wrong_source, root / "source")
        def changed_inputs(f):
            doc = json.loads(f["manifest"].read_text())
            doc["sourceHash"] = "sha256:" + "0" * 64
            f["manifest"].write_text(json.dumps(doc, sort_keys=True) + "\n")
        checks["changed-inputs"] = run("changed-inputs", changed_inputs, root / "inputs")
        def hash_spoof(f):
            f["windows-executable"].write_bytes(f["windows-executable"].read_bytes() + b"spoof")
        checks["hash-spoof"] = run("hash-spoof", hash_spoof, root / "exe")
        def missing_roles(f):
            f["actual-proof-bundle"].write_text(json.dumps({"archiveBindings": {}}) + "\n")
        checks["missing-roles"] = run("missing-roles", missing_roles, root / "roles")
    expected = {
        "empty-receipt": "actual producer receipt is not successful",
        "self-authored-receipt": "actual producer receipt is not successful",
        "wrong-source": "witness source differs from fresh Mac manifest",
        "changed-inputs": "witness source differs from fresh Mac manifest",
        "hash-spoof": "Windows executable hash differs from fresh tuple",
        "missing-roles": "proof archive missing roles",
    }
    for name, needle in expected.items():
        if not any(needle in reason for reason in checks[name]):
            raise AssertionError(f"{name}: missing expected reason {needle!r}: {checks[name]}")
    print(json.dumps({"status": "PASS", "controls": {k: len(v) for k, v in checks.items()}}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
