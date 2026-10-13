#!/usr/bin/env python3
"""Offline v8 source-admission verifier with canonical full case binding."""
from __future__ import annotations
import hashlib, json
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
    rel = row.get("path")
    if not isinstance(rel, str) or Path(rel).is_absolute() or ".." in Path(rel).parts:
        raise ValueError(f"{label} unsafe path")
    path = root / rel
    if not path.is_file():
        raise ValueError(f"{label} missing: {rel}")
    if path.stat().st_size != row.get("bytes") or sha(path) != row.get("sha256"):
        raise ValueError(f"{label} bytes/hash drift: {rel}")
    return path

def validate_inputs(root: Path) -> dict:
    pins = load(root / "input-pins.json")
    if pins.get("kind") != "seed-origin-v8-input-pins" or pins.get("seed") != SEED:
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
        case_pin = row.get("case")
        if not isinstance(case_pin, dict) or case_pin.get("kind") != "canonical-full-case":
            raise ValueError("canonical case pin missing")
        case_path = check_file(root, case_pin, "canonical case")
        case = load(case_path)
        if case.get("kind") != "case" or case.get("id") != row["caseID"] or case.get("block") != row["block"] or case.get("seed") != SEED:
            raise ValueError("canonical case identity")
        if case_pin.get("id") != row["caseID"] or case_pin.get("block") != row["block"] or case_pin.get("seed") != SEED:
            raise ValueError("canonical case pin identity")
        if case_pin.get("manifestCaseHash") != case_pin.get("sha256"):
            raise ValueError("canonical case hash/manifest mismatch")
        manifest_path = check_file(root, row["manifest"], "manifest")
        recipe_path = check_file(root, {"path":row["recipe"]["path"], "bytes":row["recipe"]["bytes"], "sha256":row["recipe"]["rawSha256"]}, "recipe")
        source_path = check_file(root, row["source"], "source")
        witness_path = check_file(root, row["witness"], "witness")
        check_file(root, row["negative"], "negative")
        manifest = load(manifest_path); recipe = load(recipe_path)
        if manifest.get("block") != row["block"] or manifest.get("case", {}).get("id") != row["caseID"]:
            raise ValueError("manifest identity")
        if manifest.get("case", {}).get("hash") != case_pin["sha256"]:
            raise ValueError("manifest/canonical case hash join")
        if manifest.get("sourceFile") != source_path.name or manifest.get("sourceHash") != sha(source_path):
            raise ValueError("manifest/source join")
        witness_hash = sha(witness_path)
        if manifest.get("witness", {}).get("sourceHash") != witness_hash:
            raise ValueError("manifest/witness join")
        if recipe.get("id") != manifest.get("recipe", {}).get("id"):
            raise ValueError("recipe identity")
        if recipe.get("block") != row["block"] or recipe.get("provenance", {}).get("sourceHash") != witness_hash:
            raise ValueError("recipe block/witness join")
        if manifest.get("recipe", {}).get("hash") != canonical(recipe) or row["recipe"].get("canonicalSha256") != canonical(recipe):
            raise ValueError("recipe canonical hash")
        if case.get("recipe", {}).get("hash") != canonical(recipe) or case.get("recipe", {}).get("id") != recipe.get("id"):
            raise ValueError("canonical case/recipe join")
        if case.get("provenance", {}).get("sourceHash") != canonical(recipe):
            raise ValueError("canonical case provenance")
        if manifest.get("compileExpectation") != "success" or manifest.get("executionEligible") is not True:
            raise ValueError("manifest execution contract")
    return {"status":"PASS", "rows":len(rows), "seed":SEED, "captureStatus":"NOT_RUN", "canonicalCases":5}

def validate_command(root: Path) -> dict:
    plan = load(root / "capture-command.json")
    if plan.get("kind") != "seed-origin-v8-capture-command-plan" or plan.get("status") != "NOT_RUN" or plan.get("captureStatus") != "NOT_RUN" or plan.get("noCaptureExecuted") is not True:
        raise ValueError("capture command status")
    if plan.get("caseRoot") != "factory/oracle/mac/seed-origin-v8/inputs":
        raise ValueError("case-root is not v8 inputs")
    if "seed-origin-v7" in json.dumps(plan) or "seed-origin-v6" in json.dumps(plan):
        raise ValueError("stale case-root")
    if plan.get("collector") != "factory/oracle/mac/seed-origin-v8/capture_origin.py":
        raise ValueError("collector command pin")
    if plan.get("runsPerCase") != 20 or sorted(plan.get("manifests", [])) != sorted([f"inputs/{x}.manifest.json" for x in sorted(EXPECTED)]):
        raise ValueError("manifest command scope")
    if sorted(plan.get("canonicalCases", [])) != sorted([f"inputs/{x}.json" for x in sorted(EXPECTED)]):
        raise ValueError("canonical command scope")
    return {"status":"PASS", "caseRoot":plan["caseRoot"], "captureStatus":"NOT_RUN"}

def validate_admission(root: Path, workspace: Path) -> dict:
    pins=load(root/"admission/v6-admission-pins.json")
    if pins.get("decision") != "READY_FOR_BOUNDED_CAPTURE" or pins.get("collectorSourceUnchanged") is not True: raise ValueError("v6 admission decision")
    for item in pins["files"]:
        p=(root/item["archivePath"]) if "archivePath" in item else (workspace/item["path"])
        if not p.is_file() or p.stat().st_size != item["bytes"] or sha(p) != item["sha256"]: raise ValueError(f"v6 dependency drift: {item.get('archivePath',item.get('path'))}")
    if (root/"capture_origin.py").read_bytes() != (workspace/"factory/oracle/mac/seed-origin-v6/capture_origin.py").read_bytes(): raise ValueError("collector differs from admitted v6")
    collector=(root/"capture_origin.py").read_text()
    if "def _compiler_build_common" not in collector or "auxiliary_compiler_build(copied, evidence, executable)" not in collector or "logged(['/usr/bin/xcrun', 'swiftc'" in collector: raise ValueError("bounded compiler route")
    for source_name in ("AXClient.swift","CaptureHost.swift"):
        source=(root/source_name).read_text(); forbidden=("AXIsProcessTrustedWithOptions","AXMakeProcessTrusted","CGRequestScreenCaptureAccess","requestScreenCaptureAccess")
        if "AXIsProcessTrusted" not in source or any(token in source for token in forbidden): raise ValueError(f"no-prompt source guard: {source_name}")
    return {"status":"PASS","v6Decision":pins["decision"],"collectorReused":True,"admissionFiles":len(pins["files"])}

def validate_dependencies(root: Path) -> dict:
    manifest=load(root/"runtime-deps/dependency-hashes.json"); rows=manifest.get("files",[])
    if len(rows)!=23: raise ValueError("dependency cardinality")
    for row in rows:
        p=root/row["archivePath"]
        if not p.is_file() or p.stat().st_size != row["bytes"] or sha(p) != row["sha256"]: raise ValueError(f"dependency drift: {row['archivePath']}")
    return {"status":"PASS","dependencies":len(rows),"runtimeCopies":True}

def validate(root: Path, workspace: Path) -> dict:
    return {"status":"PASS","inputs":validate_inputs(root),"command":validate_command(root),"admission":validate_admission(root,workspace),"dependencies":validate_dependencies(root)}

if __name__ == "__main__":
    import argparse
    p=argparse.ArgumentParser(); p.add_argument("root",type=Path,nargs="?",default=Path(__file__).resolve().parent); p.add_argument("--workspace",type=Path,default=Path(__file__).resolve().parents[4]); a=p.parse_args(); print(json.dumps(validate(a.root,a.workspace),indent=2,sort_keys=True))
