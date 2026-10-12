#!/usr/bin/env python3
"""Materialize fresh Text baseline case from measured tuple bytes only."""
from __future__ import annotations
import argparse, hashlib, json, re
from datetime import datetime, timezone
from pathlib import Path
from factory.core.artifacts import canonical_hash, write_artifact

PACKET = Path(__file__).resolve().parent
MAX_JSON = 2 * 1024 * 1024
HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RENDERER = "sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
INPUTS = {
    "text": "Aa",
    "font": {"family": "system", "size": 24, "weight": "regular", "design": "default"},
    "foreground": "primary",
    "colorScheme": "light",
    "viewport": {"width": 120, "height": 48, "alignment": "center"},
}

def bounded_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded regular JSON required: {path}")
    return json.loads(path.read_bytes())

def bounded_hash(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded regular source required: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()

def validate_tuple(value: dict) -> None:
    required = {"id", "sdk", "macosBuild", "toolchains", "runtimeCommit", "rendererHash", "hostHashes", "factoryVersion", "acceptanceConfigHash"}
    if set(value) != required:
        raise ValueError("tuple keys must match common schema")
    if value["runtimeCommit"] != RUNTIME or not re.fullmatch(r"[0-9a-f]{40}", value["runtimeCommit"]):
        raise ValueError("tuple runtime commit is not measured current runtime")
    if value["rendererHash"] != RENDERER:
        raise ValueError("tuple renderer hash drift")
    hosts = value["hostHashes"]
    if set(hosts) != {"macos", "windows"} or any(not HASH.fullmatch(str(v)) for v in hosts.values()):
        raise ValueError("both measured host hashes are required")
    if not HASH.fullmatch(str(value["acceptanceConfigHash"])):
        raise ValueError("acceptance config hash is not measured")
    if not all(isinstance(value[k], str) and value[k].strip() for k in ("id", "sdk", "macosBuild", "factoryVersion")):
        raise ValueError("tuple identity field is empty")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tuple", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    tuple_value = bounded_json(args.tuple)
    validate_tuple(tuple_value)
    recipe = bounded_json(PACKET / "recipe.json")
    witness = PACKET / "witness.swift"
    recipe_hash = canonical_hash(recipe)
    witness_hash = bounded_hash(witness)
    tuple_suffix = canonical_hash(tuple_value).split(":", 1)[1][:16]
    case_id = f"swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.{tuple_suffix}"
    case = {
        "kind": "case", "version": "0.1", "id": case_id, "block": "swiftui.text.layout.baseline",
        "inputs": INPUTS, "coverage": "declared", "expectedCaseSetHash": canonical_hash([{"id": case_id, "inputs": INPUTS, "coverage": "declared"}]),
        "provenance": {"sourceHash": recipe_hash, "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "producer": "factory/pipeline/pilot-next-source-v1/text-baseline-v1"},
        "recipe": {"id": recipe["id"], "hash": recipe_hash}, "tuple": tuple_value,
        "witness": {"path": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/witness.swift", "sourceHash": witness_hash},
    }
    case_hash = canonical_hash(case)
    manifest = {
        "kind": "generated-probe", "version": "0.1", "block": "swiftui.text.layout.baseline",
        "compileExpectation": "success", "executionEligible": True, "scenario": "baseline",
        "recipeFile": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/recipe.json",
        "recipe": {"id": recipe["id"], "hash": recipe_hash}, "case": {"id": case_id, "hash": case_hash},
        "caseInputs": INPUTS, "environmentInputs": {"colorScheme": "light", "font": INPUTS["font"], "viewport": INPUTS["viewport"]},
        "sourceFile": "witness.swift", "sourceRepositoryPath": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/witness.swift", "sourceHash": witness_hash,
        "witness": {"id": "swiftui.text.layout.baseline.witness", "sourceHash": witness_hash}, "witnessType": "Witness_swiftui_text_layout_baseline", "tupleId": tuple_value["id"],
        "channels": {
            "assertionChannels": ["layout", "paint", "text-observation"],
            "geometry": [{"channel": "layout", "hostHookRequired": True, "probeTag": "swiftui.text.layout.baseline", "viewInstrumentationInserted": False}],
            "text": {"rawAXPreserved": True, "rawUIAPreserved": True, "fallbackFamilyMeasured": True, "baselineMeasured": True},
            "viewport": INPUTS["viewport"], "font": INPUTS["font"], "native": [], "provider": [],
            "transparency": {"channels": ["layout", "paint", "text-observation"], "enabled": False, "viewIsolatedFromInstrumentation": True},
        },
        "candidate": "swiftui.text.layout.baseline.pilot-next",
    }
    output = args.output.expanduser().resolve()
    if output.exists() and any(output.iterdir()):
        raise ValueError("output must be fresh")
    write_artifact(output / "manifest.json", manifest)
    (output / "witness.swift").parent.mkdir(parents=True, exist_ok=True)
    (output / "witness.swift").write_bytes(witness.read_bytes())
    write_artifact(output / "cases" / f"{case_id}.json", case)
    write_artifact(output / "tuple.json", tuple_value)
    print(json.dumps({"caseId": case_id, "caseHash": case_hash, "recipeHash": recipe_hash, "witnessHash": witness_hash}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
