"""Build & validate a reviewed block registry against one F1 catalogue."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import re
import sys
from pathlib import Path
from typing import Any, Mapping

from factory.core.artifacts import canonical_hash, file_hash, provenance, write_artifact
from factory.tools.canonical_json import CanonicalJSONError, load
from factory.tools.schema_validate import load_registry as load_schemas
from factory.tools.schema_validate import validate_artifact


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = Path(__file__).with_name("manifest.json")
DEFAULT_CATALOGUE = ROOT / "catalogue" / "evidence" / "catalogue.json"
DEFAULT_OUTPUT = Path(__file__).with_name("evidence") / "block-registry.json"


class RegistryBuildError(ValueError):
    """Curated membership cannot be resolved or violates registry rules."""


def _read_manifest(manifest: Mapping[str, Any] | str | Path | None) -> dict[str, Any]:
    if manifest is None:
        manifest = DEFAULT_MANIFEST
    if isinstance(manifest, (str, Path)):
        try:
            value = json.loads(Path(manifest).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise RegistryBuildError(f"cannot read curated manifest {manifest}: {exc}") from exc
    else:
        value = dict(manifest)
    if value.get("version") != "0.1" or not isinstance(value.get("blocks"), list):
        raise RegistryBuildError("curated manifest must have version 0.1 & a blocks array")
    if not isinstance(value.get("id"), str) or not value["id"]:
        raise RegistryBuildError("curated manifest needs a non-empty id")
    unknown = set(value) - {"version", "id", "blocks"}
    if unknown:
        raise RegistryBuildError(f"curated manifest has unknown fields: {', '.join(sorted(unknown))}")
    return value


def _validate_cycles(blocks: list[dict[str, Any]]) -> None:
    """Reject dangling edges & require each dependency cycle to name a bootstrap group."""
    by_id = {block["id"]: block for block in blocks}
    for block in blocks:
        for dependency in block["semanticDependencies"]:
            if dependency not in by_id:
                raise RegistryBuildError(
                    f"{block['id']}: semantic dependency {dependency!r} is not in this registry"
                )

    visiting: list[str] = []
    visited: set[str] = set()
    cycles: set[tuple[str, ...]] = set()

    def visit(block_id: str) -> None:
        if block_id in visiting:
            cycle = visiting[visiting.index(block_id) :]
            cycles.add(tuple(sorted(cycle)))
            return
        if block_id in visited:
            return
        visiting.append(block_id)
        for dependency in by_id[block_id]["semanticDependencies"]:
            visit(dependency)
        visiting.pop()
        visited.add(block_id)

    for block_id in by_id:
        visit(block_id)
    for cycle in cycles:
        groups = {by_id[block_id].get("bootstrapGroup") for block_id in cycle}
        if len(groups) != 1 or None in groups:
            joined = " -> ".join(cycle)
            raise RegistryBuildError(
                f"semantic dependency cycle [{joined}] requires one shared bootstrapGroup"
            )


def validate_registry(artifact: Mapping[str, Any]) -> list[str]:
    """Run schema validation & registry-specific cross-reference checks."""
    errors: list[str] = []
    pre_blocks = artifact.get("blocks") if isinstance(artifact, Mapping) else None
    if isinstance(pre_blocks, list):
        for block in pre_blocks:
            if isinstance(block, dict) and block.get("progress") == "blocked":
                detail = block.get("blocked")
                if not isinstance(detail, dict) or not all(
                    isinstance(detail.get(key), str) and detail[key]
                    for key in ("reason", "openedAt", "owner")
                ):
                    errors.append(
                        f"{block.get('id', '<unknown>')}: blocked progress requires a reason, openedAt & owner"
                    )
    if errors:
        return errors
    schema_registry, documents = load_schemas(ROOT / "spec" / "schema")
    errors.extend(validate_artifact(dict(artifact), schema_registry, documents))
    if errors:
        return errors
    blocks = artifact["blocks"]
    ids = [block["id"] for block in blocks]
    if len(ids) != len(set(ids)):
        errors.append("block IDs must be unique")
    try:
        _validate_cycles(blocks)
    except RegistryBuildError as exc:
        errors.append(str(exc))
    for block in blocks:
        if block["progress"] == "blocked" and not block.get("blocked"):
            errors.append(f"{block['id']}: blocked progress requires a reason, openedAt & owner")
        if block["progress"] != "blocked" and "blocked" in block:
            errors.append(f"{block['id']}: blocked detail requires progress='blocked'")
        if block["progress"] == "parity" and block["inventoryStatus"] != "adapted":
            errors.append(f"{block['id']}: parity must be explicitly paired with inventoryStatus='adapted'")
    return errors


def build_registry(
    catalogue: Mapping[str, Any],
    *,
    manifest: Mapping[str, Any] | str | Path | None = None,
    catalogue_hash: str | None = None,
    created_at: str | None = None,
    producer: str = "factory/registry",
) -> dict[str, Any]:
    """Resolve curated symbol paths to catalogue USRs, then emit schema-valid artifact.

    Manifest member `symbols` accept exact `usr:<USR>` references, or exact
    `path:<module-qualified path>` selectors. Each must resolve to exactly one
    non-hidden symbol; no status is inferred from a symbol. Inventory status &
    progress come only from the curated manifest.
    """
    manifest_source = Path(manifest) if isinstance(manifest, (str, Path)) else None
    curated = _read_manifest(manifest)
    if catalogue.get("kind") != "catalogue" or catalogue.get("version") != "0.1":
        raise RegistryBuildError("input is not a v0.1 F1 catalogue")
    if not isinstance(catalogue.get("symbols"), list):
        raise RegistryBuildError("catalogue has no symbols array")
    source_id = catalogue.get("id")
    if not isinstance(source_id, str) or not source_id:
        raise RegistryBuildError("catalogue has no artifact id")

    by_path: dict[str, list[dict[str, Any]]] = {}
    by_usr: dict[str, dict[str, Any]] = {}
    for item in catalogue["symbols"]:
        if not isinstance(item, dict):
            raise RegistryBuildError("catalogue symbols must be objects")
        usr = item.get("usr")
        path = item.get("path")
        if not isinstance(usr, str) or not usr or not isinstance(path, str) or not path:
            raise RegistryBuildError("each catalogue symbol needs non-empty usr & path")
        if usr in by_usr:
            raise RegistryBuildError(f"catalogue repeats USR {usr!r}")
        by_usr[usr] = item
        by_path.setdefault(path, []).append(item)

    output_blocks: list[dict[str, Any]] = []
    for spec in curated["blocks"]:
        if not isinstance(spec, dict):
            raise RegistryBuildError("manifest blocks must be objects")
        unknown = set(spec) - {
            "id", "symbols", "inventoryStatus", "progress", "semanticDependencies",
            "bootstrapGroup", "blocked", "waiver",
        }
        if unknown:
            raise RegistryBuildError(
                f"{spec.get('id', '<unknown>')}: manifest has unknown fields: {', '.join(sorted(unknown))}"
            )
        block_id = spec.get("id")
        selectors = spec.get("symbols")
        if not isinstance(block_id, str) or not isinstance(selectors, list) or not selectors:
            raise RegistryBuildError("each manifest block needs an id & non-empty symbols selectors")
        resolved: list[str] = []
        for selector in selectors:
            if not isinstance(selector, str) or not selector:
                raise RegistryBuildError(f"{block_id}: symbol selectors must be non-empty strings")
            if selector.startswith("usr:"):
                usr = selector.removeprefix("usr:")
                item = by_usr.get(usr)
                matches = [item] if item else []
            else:
                path_selector = selector.removeprefix("path:")
                matches = by_path.get(path_selector, [])
            if not matches:
                raise RegistryBuildError(
                    f"{block_id}: catalogue selector {selector!r} has no exact match"
                )
            if len(matches) != 1:
                usrs = ", ".join(sorted(item["usr"] for item in matches))
                raise RegistryBuildError(
                    f"{block_id}: path selector {selector!r} is ambiguous ({usrs}); curate precise USRs"
                )
            item = matches[0]
            if item.get("status") == "hidden":
                raise RegistryBuildError(f"{block_id}: selector {selector!r} resolves to hidden USR {item['usr']}")
            resolved.append(item["usr"])
        if len(resolved) != len(set(resolved)):
            raise RegistryBuildError(f"{block_id}: repeated resolved USR")
        block: dict[str, Any] = {
            "id": block_id,
            "symbols": resolved,
            "inventoryStatus": spec.get("inventoryStatus", "inventory"),
            "progress": spec.get("progress", "not-started"),
            "semanticDependencies": spec.get("semanticDependencies", []),
        }
        for optional in ("bootstrapGroup", "blocked", "waiver"):
            if optional in spec:
                block[optional] = spec[optional]
        output_blocks.append(block)

    if len({block["id"] for block in output_blocks}) != len(output_blocks):
        raise RegistryBuildError("manifest block IDs must be unique")
    _validate_cycles(output_blocks)
    try:
        source_hash = file_hash(manifest_source) if manifest_source else canonical_hash(curated)
        input_hash = catalogue_hash or canonical_hash(catalogue)
    except (CanonicalJSONError, OSError) as exc:
        raise RegistryBuildError(f"cannot hash registry inputs: {exc}") from exc
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", input_hash):
        raise RegistryBuildError("catalogue_hash must be sha256: plus 64 lowercase hex digits")
    timestamp = created_at or datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    artifact = {
        "kind": "block-registry",
        "version": "0.1",
        "id": f"{curated['id']}.block-registry",
        "provenance": provenance(source_hash, [{"id": source_id, "hash": input_hash}],
                                  producer=producer, created_at=timestamp),
        "blocks": output_blocks,
    }
    errors = validate_registry(artifact)
    if errors:
        raise RegistryBuildError("built registry failed validation: " + "; ".join(errors))
    return artifact


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="build the curated block registry from an F1 catalogue")
    parser.add_argument("--catalogue", type=Path, default=DEFAULT_CATALOGUE)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    arguments = parser.parse_args(argv)
    try:
        catalogue = load(arguments.catalogue)
        artifact = build_registry(catalogue, manifest=arguments.manifest)
        write_artifact(arguments.output, artifact)
    except (OSError, CanonicalJSONError, RegistryBuildError) as exc:
        print(f"block-registry: {exc}", file=sys.stderr)
        return 2
    print(f"{arguments.output}: wrote {len(artifact['blocks'])} curated blocks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
