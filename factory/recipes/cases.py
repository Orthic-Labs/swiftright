"""Deterministic recipe expansion and exact expected-case manifests."""

from __future__ import annotations

from dataclasses import dataclass
from itertools import product
import random
import re
from typing import Any

from factory.core.artifacts import canonical_hash, provenance, validate_artifact

_HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
_TUPLE_KEYS = {
    "id", "sdk", "macosBuild", "toolchains", "runtimeCommit", "rendererHash",
    "hostHashes", "factoryVersion", "acceptanceConfigHash",
}


class CaseManifestError(ValueError):
    """Recipe expansion or case-set completeness failed."""


@dataclass(frozen=True)
class _PlannedCase:
    case_id: str
    inputs: dict[str, Any]
    coverage: str
    seed: int | None = None

    def descriptor(self) -> dict[str, Any]:
        result = {"id": self.case_id, "inputs": self.inputs, "coverage": self.coverage}
        if self.seed is not None:
            result["seed"] = self.seed
        return result


def _validate_tuple(tuple_value: dict[str, Any]) -> None:
    if not isinstance(tuple_value, dict) or set(tuple_value) != _TUPLE_KEYS:
        missing = sorted(_TUPLE_KEYS - set(tuple_value if isinstance(tuple_value, dict) else ()))
        extra = sorted(set(tuple_value if isinstance(tuple_value, dict) else ()) - _TUPLE_KEYS)
        raise CaseManifestError(f"tuple must match schema 0.1 fields (missing={missing}, extra={extra})")
    for key in ("rendererHash", "acceptanceConfigHash"):
        if not isinstance(tuple_value[key], str) or not _HASH.fullmatch(tuple_value[key]):
            raise CaseManifestError(f"tuple.{key} must be an observed sha256 value")
    if not isinstance(tuple_value["hostHashes"], dict) or not tuple_value["hostHashes"]:
        raise CaseManifestError("tuple.hostHashes must contain measured host hashes")
    if any(not isinstance(value, str) or not _HASH.fullmatch(value)
           for value in tuple_value["hostHashes"].values()):
        raise CaseManifestError("tuple.hostHashes values must be observed sha256 values")
    if not isinstance(tuple_value["toolchains"], dict) or not tuple_value["toolchains"]:
        raise CaseManifestError("tuple.toolchains must contain measured toolchain versions")
    if not re.fullmatch(r"[0-9a-f]{7,64}", str(tuple_value["runtimeCommit"])):
        raise CaseManifestError("tuple.runtimeCommit must be a measured commit hash")


def _axis_rows(axes: list[dict[str, Any]], seed: int) -> tuple[list[dict[str, Any]], str]:
    if not axes:
        return [{}], "declared"
    names = [axis["id"] for axis in axes]
    if len(names) != len(set(names)):
        raise CaseManifestError("recipe contains duplicate axis IDs")
    values = [axis["values"] for axis in axes]
    if any(not choices for choices in values):
        raise CaseManifestError("recipe axis has no values")
    candidates = [dict(zip(names, row)) for row in product(*values)]
    full_product = any(axis.get("coverage") == "full-product" for axis in axes)
    if full_product or len(candidates) == 1:
        return candidates, "full-product" if full_product else "declared"

    # Pairwise obligations include each axis value, then every value pair across axes.
    obligations: set[tuple[Any, ...]] = set()
    for index, choices in enumerate(values):
        obligations.update((index, choice) for choice in choices)
    for left in range(len(names)):
        for right in range(left + 1, len(names)):
            obligations.update((left, a, right, b) for a in values[left] for b in values[right])
    rng = random.Random(seed)
    rng.shuffle(candidates)
    selected: list[dict[str, Any]] = []
    covered: set[tuple[Any, ...]] = set()
    while obligations - covered:
        best: dict[str, Any] | None = None
        best_gain: set[tuple[Any, ...]] = set()
        for row in candidates:
            gain = _row_obligations(row, names) & (obligations - covered)
            if len(gain) > len(best_gain):
                best, best_gain = row, gain
        if best is None or not best_gain:
            raise CaseManifestError("pairwise generator could not satisfy declared axis values")
        selected.append(best)
        covered.update(best_gain)
        candidates.remove(best)
    return selected, "pairwise"


def _row_obligations(row: dict[str, Any], names: list[str]) -> set[tuple[Any, ...]]:
    values = [row[name] for name in names]
    result = {(index, value) for index, value in enumerate(values)}
    for left in range(len(values)):
        for right in range(left + 1, len(values)):
            result.add((left, values[left], right, values[right]))
    return result


def _validate_recipe(recipe: dict[str, Any]) -> None:
    validate_artifact(recipe)
    if recipe.get("kind") != "recipe" or recipe.get("version") != "0.1":
        raise CaseManifestError("only recipe schema 0.1 is supported")


def _planned_cases(recipe: dict[str, Any], seed: int) -> list[_PlannedCase]:
    axes = recipe["axes"]
    rows, coverage = _axis_rows(axes, seed)
    planned = []
    for row in rows:
        digest = canonical_hash(row).split(":", 1)[1][:16]
        planned.append(_PlannedCase(f'{recipe["id"]}/case/{digest}', row, coverage, seed if coverage == "pairwise" else None))

    # Transparency and negative witnesses are mandatory, individually named cases.
    axis_baseline = {axis["id"]: axis["values"][0] for axis in axes}
    transparency = recipe["instrumentationTransparency"]
    planned.append(_PlannedCase(transparency["case"], axis_baseline, "declared"))
    for negative in recipe.get("negativeCases", []):
        planned.append(_PlannedCase(negative["id"], {}, "declared"))
    ids = [case.case_id for case in planned]
    if len(ids) != len(set(ids)):
        raise CaseManifestError("recipe produces duplicate case IDs")
    return planned


def expand_cases(
    recipe: dict[str, Any],
    tuple_value: dict[str, Any],
    seed: int | None = None,
    *,
    snapshot_created_at: str | None = None,
) -> dict[str, Any]:
    """Expand one recipe into case artifacts plus immutable expected-set manifest.

    ``tuple_value`` must be a schema-valid measured tuple; no placeholder hashes are
    generated here. Pairwise generation uses ``seed`` (default 0) deterministically.
    Case provenance timestamps default to the recipe's pinned ``createdAt`` so
    repeated expansion produces identical full case artifacts. Callers may supply
    ``snapshot_created_at`` to pin a distinct snapshot timestamp explicitly.
    """
    _validate_recipe(recipe)
    _validate_tuple(tuple_value)
    seed = 0 if seed is None else seed
    if not isinstance(seed, int) or isinstance(seed, bool):
        raise CaseManifestError("seed must be an integer")
    created_at = recipe["provenance"]["createdAt"] if snapshot_created_at is None else snapshot_created_at
    if not isinstance(created_at, str) or not created_at:
        raise CaseManifestError("snapshot_created_at must be a non-empty RFC 3339 timestamp")
    planned = _planned_cases(recipe, seed)
    # Keep exact payload aligned with F10's independently recomputed case-set hash.
    set_rows = [
        {"id": case.case_id, "inputs": case.inputs, "coverage": case.coverage}
        for case in planned
    ]
    set_rows.sort(key=lambda row: (row["id"], canonical_hash(row["inputs"])))
    expected_hash = canonical_hash(set_rows)
    recipe_hash = canonical_hash(recipe)
    cases: list[dict[str, Any]] = []
    for item in planned:
        case = {
            "kind": "case", "version": "0.1", "id": item.case_id,
            "provenance": provenance(
                item.descriptor(), inputs=[{"id": recipe["id"], "hash": recipe_hash}],
                producer="factory/recipes.expand_cases", created_at=created_at),
            "recipe": {"id": recipe["id"], "hash": recipe_hash},
            "block": recipe["block"], "inputs": item.inputs,
            "expectedCaseSetHash": expected_hash, "coverage": item.coverage,
            "tuple": tuple_value,
        }
        if item.seed is not None:
            case["seed"] = item.seed
        validate_artifact(case)
        cases.append(case)
    manifest = {
        "kind": "case-manifest", "version": "0.1", "recipe": recipe["id"],
        "recipeHash": recipe_hash, "seed": seed, "expectedCaseSetHash": expected_hash,
        "caseIds": [item.case_id for item in planned],
        "expectedCases": [
            {"id": case["id"], "hash": canonical_hash(case)} for case in cases
        ],
        "coverageCounts": {coverage: sum(item.coverage == coverage for item in planned)
                           for coverage in sorted({item.coverage for item in planned})},
    }
    return {"manifest": manifest, "cases": cases}


def validate_case_manifest(expansion: dict[str, Any], cases: list[dict[str, Any]] | None = None) -> None:
    """Reject missing, extra, duplicate, or hash-inconsistent expected cases."""
    manifest = expansion["manifest"]
    supplied = expansion["cases"] if cases is None else cases
    expected = manifest["caseIds"]
    actual = [case["id"] for case in supplied]
    if len(actual) != len(set(actual)):
        raise CaseManifestError("duplicate case ID in supplied case set")
    if set(actual) != set(expected):
        missing, extra = sorted(set(expected) - set(actual)), sorted(set(actual) - set(expected))
        raise CaseManifestError(f"case set mismatch (missing={missing}, extra={extra})")
    expected_hashes = {entry["id"]: entry["hash"] for entry in manifest["expectedCases"]}
    for case in supplied:
        if canonical_hash(case) != expected_hashes[case["id"]]:
            raise CaseManifestError(f"case content differs from expansion: {case['id']}")
    if any(case["expectedCaseSetHash"] != manifest["expectedCaseSetHash"] for case in supplied):
        raise CaseManifestError("case expectedCaseSetHash does not match manifest")
