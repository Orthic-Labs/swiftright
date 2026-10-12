#!/usr/bin/env python3
"""Materialize fresh Circle case, manifest, & tuple from measured tuple bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
from datetime import datetime, timezone
from pathlib import Path

from factory.core.artifacts import write_artifact

PACKET = Path(__file__).resolve().parent
RECIPE_REF = "factory/pipeline/pilot-next-source-v1/circle-fixed-v1/recipe.json"
INPUTS_REF = "factory/pipeline/pilot-next-source-v1/circle-fixed-v1/case-inputs.json"
WITNESS_REF = "factory/pipeline/pilot-next-source-v1/circle-fixed-v1/witness.swift"
MAX_JSON = 2 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
CHUNK = 1024 * 1024
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RENDERER = "sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")


def regular(path: Path, limit: int) -> int:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return st.st_size


def bounded_json(path: Path) -> object:
    size = regular(path, MAX_JSON)
    data = bytearray()
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            data.extend(chunk)
            if len(data) > MAX_JSON:
                raise ValueError(f"JSON grew beyond bound: {path}")
    if len(data) != size:
        raise ValueError(f"JSON changed while read: {path}")
    return json.loads(bytes(data).decode("utf-8"))


def streamed_hash(path: Path, limit: int) -> str:
    size = regular(path, limit)
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"file grew beyond bound: {path}")
            digest.update(chunk)
    if total != size:
        raise ValueError(f"file changed while hashed: {path}")
    return "sha256:" + digest.hexdigest()


def canonical(value: object) -> str:
    data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(data).hexdigest()


def copy_bounded(source: Path, target: Path, limit: int) -> None:
    size = regular(source, limit)
    if target.exists() or target.is_symlink():
        raise ValueError(f"fresh output required: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    with source.open("rb") as src, target.open("xb") as dst:
        while chunk := src.read(CHUNK):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"source grew beyond bound: {source}")
            dst.write(chunk)
    if total != size:
        raise ValueError(f"source changed while copied: {source}")


def validate_tuple(value: object) -> dict:
    required = {"id", "sdk", "macosBuild", "toolchains", "runtimeCommit", "rendererHash", "hostHashes", "factoryVersion", "acceptanceConfigHash"}
    if not isinstance(value, dict) or set(value) != required:
        raise ValueError("tuple keys must match common schema")
    if value["runtimeCommit"] != RUNTIME or not re.fullmatch(r"[0-9a-f]{40}", str(value["runtimeCommit"])):
        raise ValueError("tuple runtime commit is not current measured runtime")
    if value["rendererHash"] != RENDERER:
        raise ValueError("tuple renderer hash drift")
    hosts = value["hostHashes"]
    if not isinstance(hosts, dict) or set(hosts) != {"macos", "windows"} or any(not HASH.fullmatch(str(v)) for v in hosts.values()):
        raise ValueError("both measured host hashes are required")
    if not HASH.fullmatch(str(value["acceptanceConfigHash"])):
        raise ValueError("acceptance config hash is not measured")
    if not isinstance(value["toolchains"], dict) or not value["toolchains"]:
        raise ValueError("tuple toolchains are required")
    if any(not isinstance(value[key], str) or not value[key].strip() for key in ("id", "sdk", "macosBuild", "factoryVersion")):
        raise ValueError("tuple identity field is empty")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tuple", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    tuple_value = validate_tuple(bounded_json(args.tuple))
    recipe_path = PACKET / "recipe.json"
    inputs_path = PACKET / "case-inputs.json"
    witness_path = PACKET / "witness.swift"
    recipe = bounded_json(recipe_path)
    case_inputs = bounded_json(inputs_path)
    if not isinstance(recipe, dict) or recipe.get("kind") != "recipe" or recipe.get("id") != "swiftui.circle.fixed.recipe":
        raise ValueError("Circle recipe identity drift")
    if recipe.get("provenance", {}).get("runtimeCommit") != RUNTIME or recipe.get("provenance", {}).get("runtimeSourceTreeHash") != "sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e":
        raise ValueError("Circle recipe runtime provenance drift")
    recipe_inputs = recipe.get("inputs", {})
    expected_inputs = {"shape": "Circle()", "style": "fill(Color.blue)", "colorScheme": "light", "frameDip": {"width": 40, "height": 40}, "viewportDip": {"width": 320, "height": 240}}
    if recipe_inputs.get("shape") != expected_inputs["shape"] or recipe_inputs.get("style") != expected_inputs["style"] or recipe_inputs.get("colorScheme") != expected_inputs["colorScheme"] or recipe_inputs.get("frameDip") != expected_inputs["frameDip"] or recipe_inputs.get("viewportDip") != expected_inputs["viewportDip"] or recipe_inputs.get("semanticColor") != "system.blue":
        raise ValueError("Circle recipe inputs drift")
    if not isinstance(case_inputs, dict) or case_inputs.get("candidate") != "swiftui.circle.fixed.pilot-next" or case_inputs.get("inputs") != expected_inputs:
        raise ValueError("Circle case-input context drift")
    recipe_hash = streamed_hash(recipe_path, MAX_JSON)
    canonical_recipe_hash = canonical(recipe)
    witness_hash = streamed_hash(witness_path, MAX_SOURCE)
    # case-inputs.sha256 binds raw recipe bytes; generated recipe.hash binds
    # canonical JSON. They are intentionally distinct evidence joins.
    if case_inputs.get("recipe", {}).get("sha256") != recipe_hash:
        raise ValueError("case-input recipe byte hash mismatch")
    if case_inputs.get("assertions", {}).get("semanticColor") != "system.blue":
        raise ValueError("Circle semantic color assertion drift")
    tuple_hash = canonical(tuple_value)
    tuple_suffix = tuple_hash.split(":", 1)[1][:16]
    case_id = f"swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light.{tuple_suffix}"
    inputs = case_inputs["inputs"]
    descriptor = {"id": case_id, "inputs": inputs, "coverage": "declared"}
    case = {
        "kind": "case",
        "version": "0.1",
        "candidate": "swiftui.circle.fixed.pilot-next",
        "id": case_id,
        "block": "swiftui.circle.fixed",
        "inputs": inputs,
        "coverage": "declared",
        "expectedCaseSetHash": canonical([descriptor]),
        "provenance": {"sourceHash": canonical(recipe), "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "producer": "factory/pipeline/pilot-next-source-v1/circle-fixed-v1"},
        "recipe": {"id": recipe["id"], "hash": canonical(recipe), "sha256": recipe_hash},
        "tuple": tuple_value,
        "witness": {"path": WITNESS_REF, "sourceHash": witness_hash},
    }
    case_hash = canonical(case)
    manifest = {
        "kind": "generated-probe",
        "version": "0.1",
        "block": "swiftui.circle.fixed",
        "candidate": "swiftui.circle.fixed.pilot-next",
        "compileExpectation": "success",
        "executionEligible": True,
        "qualification": "held-until-measured-capture",
        "scenario": "baseline",
        "recipeFile": RECIPE_REF,
        "recipe": {"id": recipe["id"], "hash": canonical(recipe), "sha256": recipe_hash},
        "case": {"id": case_id, "hash": case_hash},
        "tuple": {"id": tuple_value["id"], "hash": tuple_hash},
        "caseInputs": inputs,
        "environmentInputs": {"colorScheme": "light", "frameDip": inputs["frameDip"], "viewportDip": inputs["viewportDip"], "semanticColor": recipe_inputs["semanticColor"]},
        "sourceFile": "witness.swift",
        "sourceRepositoryPath": WITNESS_REF,
        "sourceHash": witness_hash,
        "sourceBindings": {"recipe": {"path": RECIPE_REF, "sha256": recipe_hash}, "caseInputs": {"path": INPUTS_REF, "sha256": streamed_hash(inputs_path, MAX_JSON)}, "witness": {"path": WITNESS_REF, "sha256": witness_hash}},
        "witness": {"id": "swiftui.circle.fixed.witness", "sourceHash": witness_hash},
        "witnessType": "Witness_circle_fixed",
        "tupleId": tuple_value["id"],
        "channels": {"assertionChannels": ["layout", "paint"], "geometry": [{"channel": "layout", "hostHookRequired": True, "probeTag": "swiftui.circle.fixed", "viewInstrumentationInserted": False}], "circle": {"shape": "circle", "frameDip": inputs["frameDip"], "backendPrimitive": "rect-radius-20", "semanticColor": "system.blue", "rawAXPreserved": True, "rawUIAPreserved": True, "rawPixelsPreserved": True}, "viewport": inputs["viewportDip"], "native": [], "provider": [], "transparency": {"channels": ["layout", "paint"], "enabled": False, "viewIsolatedFromInstrumentation": True}},
        "dispatch": {"first": {"count": 1}, "repeat": {"count": 20}},
        "replays": 20,
    }
    output = args.output.expanduser().resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("output must be a fresh directory")
    output.mkdir(parents=True, exist_ok=True)
    write_artifact(output / "manifest.json", manifest)
    write_artifact(output / "cases" / f"{case_id}.json", case)
    write_artifact(output / "tuple.json", tuple_value)
    copy_bounded(witness_path, output / "witness.swift", MAX_SOURCE)
    copy_bounded(recipe_path, output / "recipe.json", MAX_JSON)
    print(json.dumps({"caseId": case_id, "caseHash": case_hash, "tupleId": tuple_value["id"], "tupleHash": tuple_hash, "recipeHash": recipe_hash, "witnessHash": witness_hash, "replays": 20}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
