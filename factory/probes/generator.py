#!/usr/bin/env python3
"""Render same-source Swift probe files from schema-valid recipes & cases.

The generated Swift keeps the witness view independent from host instrumentation.
No renderer or runtime bridge ABI is assumed here; host-specific collection is
described in the deterministic JSON manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[1]
RECIPE_DIR = ROOT / "recipes" / "data"
CASE_DIR = ROOT / "recipes" / "cases"
WITNESS_DIR = ROOT / "recipes" / "witnesses"
GENERATED_DIR = Path(__file__).resolve().parent / "generated"
SCHEMA_DIR = ROOT / "spec" / "schema"

from factory.tools import canonical_json
from factory.tools.schema_validate import load_registry, validate_artifact


class ProbeError(ValueError):
    """Recipe or case cannot safely produce a Swift witness probe."""


_SAFE_ID = re.compile(r"^[a-z][a-z0-9._/-]{1,159}$")
_AXIS_TOKEN = re.compile(r"^[A-Za-z0-9_.$(), :.+\-\"]+$")
_PLACEHOLDER = re.compile(r"\{\{([a-z][a-z0-9-]*)\}\}")
_HOST_ENVIRONMENT_AXES = {"color-scheme": "colorScheme"}
_HOST_ENVIRONMENT_VALUES = {"color-scheme": frozenset({"light", "dark"})}
_SUPPORTED_BLOCKS = frozenset(
    {
        "swiftui.shapes.fill-stroke",
        "swiftui.image",
        "swiftui.stack-overlay",
        "swiftui.text.bundled-font",
        "swiftui.custom-layout",
        "swiftui.scroll-view",
        "swiftui.toggle",
        "swiftui.disabled",
        "swiftui.padding-frame",
        "swiftui.preference-key",
    }
)
_FOUNDATION_TYPE_BLOCKS = frozenset({"swiftui.custom-layout", "swiftui.preference-key"})
_IMPORTS = """#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif
"""


def _read_artifact(value: Mapping[str, Any] | str | Path, expected: str) -> tuple[dict[str, Any], Path | None]:
    if isinstance(value, Mapping):
        return dict(value), None
    path = Path(value).resolve()
    try:
        artifact = canonical_json.load(path)
    except (OSError, canonical_json.CanonicalJSONError) as exc:
        raise ProbeError(f"cannot read {expected}: {exc}") from exc
    if not isinstance(artifact, dict):
        raise ProbeError(f"{expected} must be a JSON object")
    return artifact, path


def _validate(artifact: dict[str, Any], kind: str) -> None:
    registry, documents = load_registry(SCHEMA_DIR)
    errors = validate_artifact(artifact, registry, documents)
    if errors:
        raise ProbeError(f"invalid {kind}: " + "; ".join(errors))


def _hash_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _hash_file(path: Path) -> str:
    try:
        return _hash_bytes(path.read_bytes())
    except OSError as exc:
        raise ProbeError(f"cannot read witness resource {path}: {exc}") from exc


def _safe_filename(identifier: str) -> str:
    if not _SAFE_ID.fullmatch(identifier):
        raise ProbeError(f"unsafe artifact id {identifier!r}")
    if any(part in {".", ".."} for part in identifier.split("/")):
        raise ProbeError(f"unsafe path segment in artifact id {identifier!r}")
    return identifier.replace("/", "_")


def _input_scenario(recipe: dict[str, Any], case: dict[str, Any]) -> str:
    axes = {axis["id"]: axis["values"] for axis in recipe.get("axes", [])}
    inputs = case.get("inputs", {})
    unsupported = sorted(set(inputs) - set(axes))
    if unsupported:
        raise ProbeError(f"unsupported case inputs: {', '.join(unsupported)}")
    for axis_id, actual in inputs.items():
        if actual not in axes[axis_id]:
            raise ProbeError(f"case input {axis_id!r} is not declared by recipe")
    scenario = inputs.get("scenario", "baseline")
    if not isinstance(scenario, str) or scenario not in {"baseline", "instrumentation-transparency"}:
        raise ProbeError(f"unsupported scenario input {scenario!r}")
    return scenario


def _specialize_witness(recipe: dict[str, Any], case: dict[str, Any], witness_source: bytes) -> bytes:
    """Apply every normal-case axis using explicit recipe-authored Swift tokens."""
    try:
        source = witness_source.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ProbeError("witness resource is not UTF-8") from exc
    placeholders = set(_PLACEHOLDER.findall(source))
    negative_ids = {item["id"] for item in recipe.get("negativeCases", [])}
    if case["id"] in negative_ids:
        return witness_source
    inputs = case.get("inputs", {})
    unsupported = sorted(set(inputs) - placeholders - set(_HOST_ENVIRONMENT_AXES))
    missing = sorted(placeholders - set(inputs))
    if unsupported:
        raise ProbeError(f"unsupported case inputs without witness placeholder: {', '.join(unsupported)}")
    if missing:
        raise ProbeError(f"witness placeholders lack case inputs: {', '.join(missing)}")
    values: dict[str, str] = {}
    for axis_id, value in inputs.items():
        if axis_id in _HOST_ENVIRONMENT_VALUES and value not in _HOST_ENVIRONMENT_VALUES[axis_id]:
            raise ProbeError(f"unsupported environment value for {axis_id!r}: {value!r}")
        if isinstance(value, bool):
            literal = "true" if value else "false"
        elif isinstance(value, int):
            literal = str(value)
        elif isinstance(value, str) and _AXIS_TOKEN.fullmatch(value):
            literal = value
        else:
            raise ProbeError(f"unsupported Swift axis token for {axis_id!r}: {value!r}")
        values[axis_id] = literal
    rendered = _PLACEHOLDER.sub(lambda match: values[match.group(1)], source)
    if _PLACEHOLDER.search(rendered):
        raise ProbeError("unresolved witness placeholder")
    return rendered.encode("utf-8")


def _resolve_witness_root(value: str | Path | None) -> Path:
    factory_root = ROOT.resolve(strict=True)
    if value is None:
        candidate = WITNESS_DIR
    else:
        candidate = Path(value)
        if not candidate.is_absolute():
            candidate = ROOT.parent / candidate
    candidate = Path(os.path.abspath(candidate))
    if not candidate.is_relative_to(factory_root):
        raise ProbeError("witness root must be inside the factory subtree")
    current = factory_root
    for part in candidate.relative_to(factory_root).parts:
        current = current / part
        if current.is_symlink():
            raise ProbeError("witness root cannot contain symlink paths")
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as exc:
        raise ProbeError(f"cannot resolve witness root {candidate}: {exc}") from exc
    if not resolved.is_relative_to(factory_root) or not resolved.is_dir():
        raise ProbeError("witness root must be an existing directory inside the factory subtree")
    return resolved


def _witness_path(witness_id: str, witness_root: Path) -> Path:
    _safe_filename(witness_id)
    path = witness_root / f"{witness_id}.swift"
    current = witness_root
    for part in Path(f"{witness_id}.swift").parts:
        current = current / part
        if current.is_symlink():
            raise ProbeError("witness resource cannot contain symlink paths")
    try:
        resolved = path.resolve(strict=True)
    except OSError as exc:
        raise ProbeError(f"cannot resolve witness resource {path}: {exc}") from exc
    if not resolved.is_relative_to(witness_root) or not resolved.is_relative_to(ROOT.resolve()):
        raise ProbeError("witness resource escapes selected root or factory subtree")
    if not resolved.is_file():
        raise ProbeError(f"witness resource is not a file: {resolved}")
    return resolved


def _witness(recipe: dict[str, Any], witness_root: Path) -> tuple[dict[str, Any], bytes]:
    if recipe["block"] not in _SUPPORTED_BLOCKS:
        raise ProbeError(f"unsupported block {recipe['block']!r}")
    if len(recipe.get("witnesses", [])) != 1:
        raise ProbeError("probe generation requires exactly one declared witness")
    witness = recipe["witnesses"][0]
    resources = witness.get("resources", [])
    if len(resources) != 1:
        raise ProbeError("probe generation requires exactly one Swift witness resource")
    resource = resources[0]
    witness_id = witness["id"]
    _safe_filename(witness_id)
    if resource.get("id") != f"{witness_id}.swift":
        raise ProbeError("witness resource id must be <witness id>.swift")
    path = _witness_path(witness_id, witness_root)
    actual_hash = _hash_file(path)
    expected_hash = resource.get("hash")
    if expected_hash != actual_hash or witness.get("sourceHash") != actual_hash:
        raise ProbeError(f"witness resource hash mismatch for {witness_id}")
    source = path.read_bytes()
    try:
        text = source.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ProbeError(f"witness resource is not UTF-8: {witness_id}") from exc
    declaration = re.search(r"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b", text)
    if declaration is None:
        raise ProbeError(f"witness {witness_id} must declare one struct conforming to View")
    if re.search(r"^\s*import\s+", text, flags=re.MULTILINE):
        raise ProbeError("witness resource must not declare imports")
    relative_path = path.relative_to(ROOT.parent.resolve()).as_posix()
    return {**witness, "swiftType": declaration.group(1), "resourcePath": relative_path}, source


def _negative_witness(negative: dict[str, Any], witness_root: Path) -> tuple[dict[str, Any], bytes]:
    identifier = negative["id"]
    path = _witness_path(identifier, witness_root)
    source = path.read_bytes()
    actual_hash = _hash_bytes(source)
    if negative.get("sourceHash") != actual_hash:
        raise ProbeError(f"negative witness resource hash mismatch for {identifier}")
    try:
        text = source.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ProbeError(f"negative witness resource is not UTF-8: {identifier}") from exc
    if re.search(r"^\s*import\s+", text, flags=re.MULTILINE):
        raise ProbeError("negative witness resource must not declare imports")
    declaration = re.search(r"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b", text)
    if declaration is None:
        raise ProbeError(f"negative witness {identifier} must declare one struct conforming to View")
    relative_path = path.relative_to(ROOT.parent.resolve()).as_posix()
    return {"id": identifier, "sourceHash": actual_hash, "swiftType": declaration.group(1), "resourcePath": relative_path}, source


def _channel_plan(recipe: dict[str, Any], scenario: str, active_witness: dict[str, Any]) -> dict[str, Any]:
    assertions = recipe.get("assertions", [])
    channels = sorted({item["channel"] for item in assertions})
    return {
        "geometry": [
            {
                "probeTag": f"{recipe['block']}:{w['id']}",
                "channel": "layout",
                "hostHookRequired": True,
                "viewInstrumentationInserted": False,
            }
            for w in [active_witness]
        ],
        "witnesses": [
            {"id": w["id"], "sourceHash": w["sourceHash"]}
            for w in [active_witness]
        ],
        "provider": [channel for channel in channels if channel.startswith("provider.")],
        "native": [channel for channel in channels if channel.startswith(("native.", "ax.", "uia."))],
        "assertionChannels": channels,
        "adapters": {
            "provider": "host-specific adapter required; no renderer ABI assumed",
            "native": "native host capture required",
            "text": "host-specific measurement adapter required" if recipe["block"] == "swiftui.text.bundled-font" else "not-declared",
            "customLayout": "host-specific callback adapter required" if recipe["block"] == "swiftui.custom-layout" else "not-declared",
        },
        "transparency": {
            "enabled": scenario == "instrumentation-transparency",
            "viewIsolatedFromInstrumentation": True,
            "channels": recipe["instrumentationTransparency"]["channels"],
        },
    }


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def generate_probe(
    recipe: Mapping[str, Any] | str | Path,
    case: Mapping[str, Any] | str | Path,
    output_dir: str | Path,
    witness_root: str | Path | None = None,
) -> dict[str, Any]:
    """Validate inputs, emit deterministic Swift & manifest, then return manifest.

    ``recipe`` and ``case`` may be mappings or paths. Output consists of
    ``<case-id>.swift`` and ``<case-id>.manifest.json`` under ``output_dir``.
    """
    recipe_obj, _ = _read_artifact(recipe, "recipe")
    case_obj, _ = _read_artifact(case, "case")
    _validate(recipe_obj, "recipe")
    _validate(case_obj, "case")
    if case_obj["recipe"]["id"] != recipe_obj["id"]:
        raise ProbeError("case references a different recipe id")
    if case_obj["block"] != recipe_obj["block"]:
        raise ProbeError("case and recipe block ids differ")
    recipe_hash = canonical_json.sha256(recipe_obj)
    if case_obj["recipe"]["hash"] != recipe_hash:
        raise ProbeError("case recipe hash does not match canonical recipe contents")
    scenario = _input_scenario(recipe_obj, case_obj)
    if case_obj["id"] == recipe_obj["instrumentationTransparency"]["case"]:
        scenario = "instrumentation-transparency"
    negative_ids = {negative["id"]: negative for negative in recipe_obj.get("negativeCases", [])}
    resource_root = _resolve_witness_root(witness_root)
    negative = negative_ids.get(case_obj["id"])
    if negative:
        witness, witness_source = _negative_witness(negative, resource_root)
        scenario = f"negative:{negative['mode']}"
    else:
        witness, witness_source = _witness(recipe_obj, resource_root)
        witness_source = _specialize_witness(recipe_obj, case_obj, witness_source)
    imports = _IMPORTS + ("\nimport Foundation\n" if recipe_obj["block"] in _FOUNDATION_TYPE_BLOCKS else "")
    swift = imports.encode("utf-8") + b"\n" + witness_source.rstrip() + b"\n"
    manifest: dict[str, Any] = {
        "kind": "generated-probe",
        "version": "0.1",
        "recipe": {"id": recipe_obj["id"], "hash": recipe_hash},
        "case": {"id": case_obj["id"], "hash": canonical_json.sha256(case_obj)},
        "caseInputs": case_obj["inputs"],
        "environmentInputs": {
            _HOST_ENVIRONMENT_AXES[key]: value
            for key, value in case_obj["inputs"].items()
            if key in _HOST_ENVIRONMENT_AXES
        },
        "block": recipe_obj["block"],
        "scenario": scenario,
        "witness": {
            "id": witness["id"],
            "sourceHash": witness["sourceHash"],
            "resourcePath": witness["resourcePath"],
        },
        "witnessType": witness["swiftType"],
        "executionEligible": case_obj["tuple"]["sdk"] != "synthetic",
        "compileExpectation": "failure" if negative and negative["mode"] == "must-not-compile" else "success",
        "sourceFile": f"{_safe_filename(case_obj['id'])}.swift",
        "sourceHash": _hash_bytes(swift),
        "channels": _channel_plan(recipe_obj, scenario, witness),
    }
    output = Path(output_dir)
    filename = _safe_filename(case_obj["id"])
    _atomic_write(output / f"{filename}.swift", swift)
    _atomic_write(
        output / f"{filename}.manifest.json",
        (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8"),
    )
    return manifest


def generate_all(output_dir: str | Path = GENERATED_DIR, witness_root: str | Path | None = None) -> list[dict[str, Any]]:
    """Generate probes for all data recipes crossed with their declared cases."""
    recipes: dict[str, tuple[dict[str, Any], Path]] = {}
    for path in sorted(RECIPE_DIR.glob("*.json")):
        artifact, _ = _read_artifact(path, "recipe")
        recipes[artifact.get("id", "")] = (artifact, path)
    cases = []
    for path in sorted(CASE_DIR.glob("*.json")):
        artifact, _ = _read_artifact(path, "case")
        if artifact.get("kind") == "case":
            cases.append(path)
    if not recipes:
        raise ProbeError(f"no recipe data found under {RECIPE_DIR}")
    results: list[dict[str, Any]] = []
    if not cases:
        example_case = canonical_json.load(ROOT / "spec" / "examples" / "rectangle-v0.1" / "example-case.json")
        for recipe_id, (recipe, _) in sorted(recipes.items()):
            safe_id = _safe_filename(recipe["block"])
            recipe_hash = canonical_json.sha256(recipe)
            case = dict(example_case)
            case["id"] = f"factory.probes.smoke.{safe_id}"
            case["recipe"] = {"id": recipe_id, "hash": recipe_hash}
            case["block"] = recipe["block"]
            case["inputs"] = {axis["id"]: axis["values"][0] for axis in recipe.get("axes", [])}
            case["provenance"] = {
                "sourceHash": canonical_json.sha256({"recipe": recipe_hash, "case": case["id"]}),
                "createdAt": "2026-10-10T00:00:00Z",
                "producer": "factory/probes/compile-only-smoke",
                "inputs": [{"id": recipe_id, "hash": recipe_hash}],
            }
            results.append(generate_probe(recipe, case, output_dir, witness_root))
        return results
    for path in cases:
        case, _ = _read_artifact(path, "case")
        recipe_pair = recipes.get(case.get("recipe", {}).get("id"))
        if recipe_pair is None:
            raise ProbeError(f"case {case.get('id')} references unknown recipe")
        results.append(generate_probe(recipe_pair[0], case, output_dir, witness_root))
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recipe", type=Path, help="single recipe JSON")
    parser.add_argument("--case", type=Path, help="single case JSON")
    parser.add_argument("--output-dir", type=Path, default=GENERATED_DIR)
    parser.add_argument("--witness-root", type=Path, help="witness directory inside factory subtree")
    arguments = parser.parse_args(argv)
    try:
        if arguments.recipe or arguments.case:
            if not arguments.recipe or not arguments.case:
                raise ProbeError("--recipe and --case must be supplied together")
            result = [generate_probe(arguments.recipe, arguments.case, arguments.output_dir, arguments.witness_root)]
        else:
            result = generate_all(arguments.output_dir, arguments.witness_root)
    except (ProbeError, OSError) as exc:
        print(f"probe-generator: {exc}", file=sys.stderr)
        return 2
    for item in result:
        print(f"{item['case']['id']} {item['sourceHash']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
