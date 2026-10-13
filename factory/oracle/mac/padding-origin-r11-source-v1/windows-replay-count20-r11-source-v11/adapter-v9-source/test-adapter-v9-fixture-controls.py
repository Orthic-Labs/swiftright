#!/usr/bin/env python3
"""Synthetic validator controls; never native evidence or fresh-r11 qualification."""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
for parent in HERE.parents:
    if (parent / "factory").is_dir():
        sys.path.insert(0, str(parent))
        break


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"validator unavailable: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, value: dict) -> dict:
    raw = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(raw)
    return {"path": path.name, "sha256": "sha256:" + hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}


def write_blob(path: Path, data: bytes) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(data)
    return {"path": path.name, "sha256": "sha256:" + hashlib.sha256(data).hexdigest(), "bytes": len(data)}


def expected_profile() -> dict:
    return {
        "id": "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011",
        "caseID": "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9",
        "caseHash": "sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de",
        "sourceHash": "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b",
        "macHostHash": "sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777",
        "windowsHostHash": "sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a",
    }


def make_fixture(root: Path) -> tuple[dict, dict, dict]:
    profile = expected_profile()
    archive = root / "archive"
    plan = {
        "kind": "factory-fresh-r11-count20-adapter-plan-v1",
        "count": 20,
        "tuple": profile,
        "captureIdentity": {"capturePattern": r"^capture/[0-9a-f]{32}$", "imagePattern": r"^image/[0-9a-f]{32}$"},
    }
    captures = []
    for ordinal in range(1, 21):
        token = f"{ordinal:032x}"
        captures.append({"captureID": f"capture/{token}", "imageID": f"image/{token}"})
    issued = {"expectedCount": 20, "frozenTupleBound": False, "sourceHash": profile["sourceHash"], "captures": captures}
    tuple_doc = {"candidateID": profile["id"], "case": {"id": profile["caseID"], "hash": profile["caseHash"]}, "tuple": {"id": profile["id"], "hostHashes": {"macos": profile["macHostHash"], "windows": profile["windowsHostHash"]}, "rendererHash": "sha256:" + "1" * 64}}
    refs = {}
    refs["issuedMetadata"] = write_json(archive / "issued-metadata.json", issued)
    refs["tuple"] = write_json(archive / "candidate-tuple.json", tuple_doc)
    generic = {"fixture": True, "nativeEvidence": False}
    for name in ("candidateBinding", "plan", "compile", "exe", "renderer", "manifest", "coordinator"):
        refs[name] = write_json(archive / f"{name}.json", generic)
    runs = []
    for ordinal in range(1, 21):
        refs[f"run-{ordinal}"] = write_blob(archive / f"run-{ordinal}.bin", f"synthetic-run-{ordinal}\n".encode())
        runs.append({"run": ordinal, "outcome": {"fixture": True}, "measurement": {"fixture": True}, "fixtureRef": refs[f"run-{ordinal}"]})
    document = {"roles": {name: refs[name] for name in ("issuedMetadata", "tuple", "candidateBinding", "plan", "compile", "exe", "renderer", "manifest", "coordinator")}, "runs": runs}
    bundle_captures = []
    for row in captures:
        proof_files = {f"role-{index}": {"fixture": True} for index in range(1, 14)}
        bundle_captures.append({"id": row["captureID"], "images": [{"id": row["imageID"]}], "case": {"id": profile["caseID"], "hash": profile["caseHash"]}, "provenance": {"sourceHash": profile["sourceHash"], "producer": "synthetic-control-fixture"}, "meta": {"conditions": {"windowsExitProof": {"files": proof_files}}}})
    bundle = {"status": "proofs-attached", "captures": bundle_captures}
    return plan, document, bundle


def check(label: str, action, expected_reject: bool) -> dict:
    accepted, error = True, ""
    try:
        action()
    except Exception as exc:
        accepted, error = False, str(exc)
    if accepted == expected_reject:
        raise RuntimeError(f"fixture control failed: {label}: {error}")
    return {"name": label, "accepted": accepted, "expectedRejected": expected_reject, "error": error}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--control-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.control_root.exists() or args.control_root.is_symlink():
        raise RuntimeError("control root must be fresh")
    args.control_root.mkdir(parents=True)
    producer = load("adapter_v9_fixture_producer", HERE / "produce-inputs-v9.py")
    reader = load("adapter_v9_fixture_reader", HERE / "run-trusted-reader-v9.py")
    plan, document, bundle = make_fixture(args.control_root)
    results = []
    results.append(check("producer-synthetic-baseline", lambda: producer.validate(document, args.control_root / "archive", plan), False))
    bad_hash = copy.deepcopy(document); bad_hash["roles"]["tuple"]["sha256"] = "sha256:" + "0" * 64
    results.append(check("producer-wrong-tuple-hash", lambda: producer.validate(bad_hash, args.control_root / "archive", plan), True))
    bad_bytes = copy.deepcopy(document); bad_bytes["roles"]["tuple"]["bytes"] += 1
    results.append(check("producer-wrong-tuple-bytes", lambda: producer.validate(bad_bytes, args.control_root / "archive", plan), True))
    bad_runs = copy.deepcopy(document); bad_runs["runs"].pop()
    results.append(check("producer-missing-run-row", lambda: producer.validate(bad_runs, args.control_root / "archive", plan), True))
    results.append(check("reader-synthetic-baseline", lambda: reader.validate_plan(bundle, plan), False))
    bad_id = copy.deepcopy(bundle); bad_id["captures"][1]["id"] = bad_id["captures"][0]["id"]
    results.append(check("reader-duplicate-capture-id", lambda: reader.validate_plan(bad_id, plan), True))
    bad_case = copy.deepcopy(bundle); bad_case["captures"][0]["case"]["id"] = "wrong-case"
    results.append(check("reader-wrong-case", lambda: reader.validate_plan(bad_case, plan), True))
    bad_proof = copy.deepcopy(bundle); bad_proof["captures"][0]["meta"]["conditions"]["windowsExitProof"]["files"].pop("role-13")
    results.append(check("reader-missing-proof-role", lambda: reader.validate_plan(bad_proof, plan), True))
    result = {"schema": "factory-fresh-r11-adapter-v9-synthetic-controls-v1", "status": "passed-synthetic-source-only", "nativeEvidence": False, "qualification": "fixture-only-no-fresh-qualification", "controls": results, "nativeWindowActions": 0, "compilerActions": 0, "remoteActions": 0, "lockActions": 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True); handle.write("\n")
    print(json.dumps({"status": result["status"], "controls": len(results), "nativeEvidence": False}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
