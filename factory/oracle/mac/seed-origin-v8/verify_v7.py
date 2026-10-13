#!/usr/bin/env python3
"""Offline source/admission verifier for five remaining seed-origin cases."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

EXPECTED = {
    "swiftui.disabled.recipe.gate-seeded.ca4e13f820f5d258",
    "swiftui.image.recipe.gate-seeded.ca4e13f820f5d258",
    "swiftui.shapes.fill-stroke.recipe.gate-seeded.ca4e13f820f5d258",
    "swiftui.text.bundled-font.recipe.gate-seeded.ca4e13f820f5d258",
    "swiftui.toggle.recipe.gate-seeded.ca4e13f820f5d258",
}
SEED = 14577611000270672472


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: Any) -> str:
    return "sha256:" + hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def check_file(root: Path, row: dict, label: str) -> Path:
    path = root / row["path"]
    if not path.is_file():
        raise ValueError(f"{label} missing: {row['path']}")
    if path.stat().st_size != row["bytes"] or sha(path) != row["sha256"]:
        raise ValueError(f"{label} bytes/hash drift: {row['path']}")
    return path


def validate_inputs(root: Path) -> dict:
    pins = load(root / "input-pins.json")
    if pins.get("kind") != "seed-origin-v7-input-pins" or pins.get("seed") != SEED:
        raise ValueError("pin kind/seed")
    if pins.get("captureStatus") != "NOT_RUN":
        raise ValueError("capture already claimed")
    rows = pins.get("rows")
    if not isinstance(rows, list) or len(rows) != 5:
        raise ValueError("expected five rows")
    ids = [row.get("caseID") for row in rows]
    if set(ids) != EXPECTED or len(ids) != len(set(ids)):
        raise ValueError("case identity/cardinality")
    for row in rows:
        if row.get("seed") != SEED:
            raise ValueError("row seed")
        manifest_path = check_file(root, row["manifest"], "manifest")
        recipe_path = root / row["recipe"]["path"]
        if not recipe_path.is_file() or recipe_path.stat().st_size != row["recipe"]["bytes"] or sha(recipe_path) != row["recipe"]["rawSha256"]:
            raise ValueError(f"recipe bytes/hash drift: {row['recipe']['path']}")
        source_path = check_file(root, row["source"], "source")
        witness_path = check_file(root, row["witness"], "witness")
        check_file(root, row["negative"], "negative")
        manifest = load(manifest_path)
        recipe = load(recipe_path)
        if manifest.get("block") != row["block"] or manifest.get("case", {}).get("id") != row["caseID"]:
            raise ValueError("manifest identity")
        if manifest.get("case", {}).get("hash") != row["case"]["manifestCaseHash"]:
            raise ValueError("manifest case hash")
        if manifest.get("sourceFile") != source_path.name or manifest.get("sourceHash") != sha(source_path):
            raise ValueError("manifest/source join")
        witness_hash = sha(witness_path)
        if manifest.get("witness", {}).get("sourceHash") != witness_hash:
            raise ValueError("manifest/witness join")
        if recipe.get("id") != manifest.get("recipe", {}).get("id"):
            raise ValueError("recipe identity")
        if recipe.get("block") != row["block"] or recipe.get("provenance", {}).get("sourceHash") != witness_hash:
            raise ValueError("recipe block/witness join")
        if manifest.get("recipe", {}).get("hash") != canonical(recipe):
            raise ValueError("recipe canonical hash")
        if row["recipe"].get("canonicalSha256") != canonical(recipe):
            raise ValueError("recipe pin canonical hash")
        if manifest.get("compileExpectation") != "success" or manifest.get("executionEligible") is not True:
            raise ValueError("manifest execution contract")
    return {"status": "PASS", "rows": len(rows), "seed": SEED, "captureStatus": "NOT_RUN"}


def validate_admission(root: Path, workspace: Path) -> dict:
    pins = load(root / "admission/v6-admission-pins.json")
    if pins.get("decision") != "READY_FOR_BOUNDED_CAPTURE" or pins.get("collectorSourceUnchanged") is not True:
        raise ValueError("v6 admission decision")
    for item in pins["files"]:
        if "archivePath" in item:
            p = root / item["archivePath"]
            if not p.is_file() or p.stat().st_size != item["bytes"] or sha(p) != item["sha256"]:
                raise ValueError(f"v6 archived dependency drift: {item['archivePath']}")
        else:
            p = workspace / item["path"]
            if not p.is_file() or p.stat().st_size != item["bytes"] or sha(p) != item["sha256"]:
                raise ValueError(f"v6 admission receipt drift: {item['path']}")
    if (root / "capture_origin.py").read_bytes() != (workspace / "factory/oracle/mac/seed-origin-v6/capture_origin.py").read_bytes():
        raise ValueError("collector differs from admitted v6")
    collector = (root / "capture_origin.py").read_text()
    if "def _compiler_build_common" not in collector or "auxiliary_compiler_build(copied, evidence, executable)" not in collector:
        raise ValueError("bounded compiler route missing")
    if "logged(['/usr/bin/xcrun', 'swiftc'" in collector:
        raise ValueError("direct unbounded compiler route")
    for source_name in ("AXClient.swift", "CaptureHost.swift"):
        source = (root / source_name).read_text()
        forbidden = ("AXIsProcessTrustedWithOptions", "AXMakeProcessTrusted", "CGRequestScreenCaptureAccess", "requestScreenCaptureAccess")
        if "AXIsProcessTrusted" not in source or any(token in source for token in forbidden):
            raise ValueError(f"no-prompt source guard: {source_name}")
    return {"status": "PASS", "v6Decision": pins["decision"], "collectorReused": True, "admissionFiles": len(pins["files"])}


def validate_dependencies(root: Path) -> dict:
    manifest = load(root / "runtime-deps/dependency-hashes.json")
    rows = manifest.get("files", [])
    if len(rows) != 23:
        raise ValueError("dependency cardinality")
    for row in rows:
        p = root / row["archivePath"]
        if not p.is_file() or p.stat().st_size != row["bytes"] or sha(p) != row["sha256"]:
            raise ValueError(f"dependency drift: {row['archivePath']}")
    return {"status": "PASS", "dependencies": len(rows), "runtimeCopies": True}


def validate(root: Path, workspace: Path) -> dict:
    return {"status": "PASS", "inputs": validate_inputs(root), "admission": validate_admission(root, workspace), "dependencies": validate_dependencies(root)}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path, nargs="?", default=Path(__file__).resolve().parent)
    parser.add_argument("--workspace", type=Path, default=Path(__file__).resolve().parents[4])
    args = parser.parse_args()
    print(json.dumps(validate(args.root, args.workspace), indent=2, sort_keys=True))
