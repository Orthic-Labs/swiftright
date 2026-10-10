#!/usr/bin/env python3
"""Verify fixed81 source/manifest lineage & bounded Foundation corrections."""

from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
OLD = REPO / "factory/pipeline/probes"
CASES = REPO / "factory/pipeline/cases"
RECIPES = REPO / "factory/recipes/data"
ANALYSIS = REPO / "factory/native/windows/source-sweep-bbceb5a1-20261011/sweep-analysis.json"


def raw_hash(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def artifact(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_hash(value: object) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def safe(path: Path) -> Path:
    if not path.is_file():
        raise AssertionError(f"missing file: {path}")
    return path


def foundation_only(old: bytes, current: bytes) -> bool:
    marker = b"#endif\n\n"
    expected = old.replace(marker, marker + b"import Foundation\n\n", 1)
    return old.count(b"import Foundation") == 0 and current == expected


def without_source_hash(value: dict) -> dict:
    result = dict(value)
    result.pop("sourceHash", None)
    witness = dict(result.get("witness", {}))
    # Current generator records witness.resourcePath; original81 manifests predate it.
    witness.pop("resourcePath", None)
    if "witness" in result:
        result["witness"] = witness
    return result


def main() -> int:
    lineage = artifact(HERE / "lineage.json")
    pins = artifact(HERE / "source-pins.json")
    analysis = artifact(ANALYSIS)
    rows = lineage.get("rows", [])
    if len(rows) != 81 or [row.get("index") for row in rows] != list(range(1, 82)):
        raise AssertionError("lineage must contain ordered cases 1..81")
    if len(list((HERE / "manifests").glob("*.manifest.json"))) != 81 or len(list((HERE / "manifests").glob("*.swift"))) != 81:
        raise AssertionError("manifests directory must contain 81 manifests & co-located sources")
    if lineage.get("runtimeCommit") != analysis.get("runtimeCommit"):
        raise AssertionError("runtime commit drift")
    if pins.get("runtimeCommit") != analysis.get("runtimeCommit") or pins.get("runtimeSourceTreeHash") != analysis.get("runtimeSourceTreeHash"):
        raise AssertionError("source pin drift")
    for pin in pins.get("preservedSeededCorrections", []):
        if raw_hash(REPO / pin["path"]) != "sha256:" + pin["sha256"]:
            raise AssertionError(f"seeded correction drift: {pin['path']}")
    expected_by_index = {row["index"]: row for row in analysis["rows"]}
    changes: Counter[str] = Counter()
    classifications: Counter[str] = Counter()
    for row in rows:
        index = row["index"]
        expected = expected_by_index[index]
        case_id = row["case"]["id"]
        if row["classification"] != expected["classification"] or case_id != expected["case"]["id"]:
            raise AssertionError(f"analysis lineage drift at case {index}")
        name = case_id.replace("/", "_")
        old_source = safe(OLD / f"{name}.swift")
        old_manifest = safe(OLD / f"{name}.manifest.json")
        current_source = safe(HERE / "sources" / f"{name}.swift")
        current_manifest = safe(HERE / "manifests" / f"{name}.manifest.json")
        co_located_source = safe(HERE / "manifests" / f"{name}.swift")
        if co_located_source.read_bytes() != current_source.read_bytes():
            raise AssertionError(f"co-located source drift at case {index}")
        if raw_hash(old_source) != row["source"]["oldHash"] or raw_hash(current_source) != row["source"]["currentHash"]:
            raise AssertionError(f"source hash drift at case {index}")
        if raw_hash(old_manifest) != row["manifest"]["oldHash"] or raw_hash(current_manifest) != row["manifest"]["currentHash"]:
            raise AssertionError(f"manifest hash drift at case {index}")
        if len({row["source"][key] for key in ("currentHash", "macOSHash", "windowsHash")}) != 1:
            raise AssertionError(f"Mac/Windows source mismatch at case {index}")
        case_path = safe(REPO / row["case"]["path"])
        recipe_path = safe(REPO / row["recipe"]["path"])
        case = artifact(case_path)
        recipe = artifact(recipe_path)
        if canonical_hash(case) != row["case"]["hash"] or canonical_hash(recipe) != row["recipe"]["hash"]:
            raise AssertionError(f"recipe/case hash drift at case {index}")
        old_value = artifact(old_manifest)
        current_value = artifact(current_manifest)
        if old_value["case"] != current_value["case"] or old_value["recipe"] != current_value["recipe"]:
            raise AssertionError(f"manifest recipe/case drift at case {index}")
        if current_value["sourceHash"] != row["source"]["currentHash"]:
            raise AssertionError(f"current manifest/source mismatch at case {index}")
        if old_value["sourceHash"] != row["source"]["oldHash"]:
            raise AssertionError(f"original manifest/source mismatch at case {index}")
        if without_source_hash(old_value) != without_source_hash(current_value):
            raise AssertionError(f"unplanned manifest change at case {index}")
        old_bytes = old_source.read_bytes()
        current_bytes = current_source.read_bytes()
        change = row["change"]
        changes[change] += 1
        classifications[row["classification"]] += 1
        if change == "foundation-import" and not foundation_only(old_bytes, current_bytes):
            raise AssertionError(f"non-Foundation source delta at case {index}")
        if change == "negative-generator-refresh":
            if not foundation_only(old_bytes, current_bytes):
                raise AssertionError(f"negative generator delta is not Foundation-only at case {index}")
            if current_value["compileExpectation"] != "failure":
                raise AssertionError(f"negative compile expectation changed at case {index}")
        if change == "existing-primary-correction":
            correction = safe(REPO / "factory/pipeline/corrections" / f"{name}.swift")
            correction_manifest = safe(REPO / "factory/pipeline/corrections" / f"{name}.manifest.json")
            if current_source.read_bytes() != correction.read_bytes() or current_manifest.read_bytes() != correction_manifest.read_bytes():
                raise AssertionError(f"primary correction bytes drift at case {index}")
            if not foundation_only(old_bytes, current_bytes):
                raise AssertionError(f"primary correction is not Foundation-only at case {index}")
        if change == "unchanged" and old_bytes != current_bytes:
            raise AssertionError(f"unplanned source change at case {index}")
    expected_changes = lineage["expectedChanges"]
    if changes != Counter({"foundation-import": 14, "existing-primary-correction": 2, "negative-generator-refresh": 2, "unchanged": 63}):
        raise AssertionError(f"change counts drift: {changes}")
    if classifications != Counter({"positive-pass": 58, "foundation-import-gap": 14, "expected-negative": 9}):
        raise AssertionError(f"classification counts drift: {classifications}")
    if expected_changes["foundationImportCases"] != [row["case"]["id"] for row in rows if row["change"] == "foundation-import"]:
        raise AssertionError("Foundation case list drift")
    if expected_changes["negativeGeneratorRefreshCases"] != [row["case"]["id"] for row in rows if row["change"] == "negative-generator-refresh"]:
        raise AssertionError("negative generator case list drift")
    print("fixed81 verification: 81 lineage rows; 14 Foundation-only positive deltas; 2 preserved primary corrections; 2 expected-negative generator refreshes; 63 unchanged; Mac/Windows source hashes match")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, json.JSONDecodeError) as exc:
        print(f"fixed81 verification: FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
