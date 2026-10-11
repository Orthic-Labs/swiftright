"""Source-pinned adapter from F12 shell demand to F9 report demand."""

from __future__ import annotations

from collections import Counter
from copy import deepcopy
import hashlib
from pathlib import Path
from typing import Any, Mapping

from factory.tools import canonical_json


REVIEWED_CROSSWALK_SHA256 = "236cd68a95830970513950c1d4a2d88201a72d2a966d26359d594292a9fd17d3"
REVIEWED_MAPPING = {
    "shape": "swiftui.shapes.fill-stroke",
    "image": "swiftui.image",
    "stack-overlay": "swiftui.stack-overlay",
    "text": "swiftui.text.bundled-font",
    "custom-layout": "swiftui.custom-layout",
    "scroll": "swiftui.scroll-view",
    "toggle": "swiftui.toggle",
    "disabled": "swiftui.disabled",
    "padding-frame": "swiftui.padding-frame",
    "preference": "swiftui.preference-key",
}


def load_source_json(path: str | Path) -> tuple[Any, bytes, str]:
    """Parse exact file bytes & return value, consumed bytes, and raw SHA-256."""
    payload = Path(path).read_bytes()
    value = canonical_json.loads(payload)
    return value, payload, hashlib.sha256(payload).hexdigest()


class ReportDemandError(ValueError):
    """F12 demand cannot be mapped to the current curated F2 registry."""


def build_report_demand(
    demand_bytes: bytes,
    manifest_bytes: bytes,
    registry_bytes: bytes,
    crosswalk_bytes: bytes,
) -> dict[str, Any]:
    """Parse pinned input bytes & adapt those exact bytes for F9."""
    if not all(isinstance(value, bytes) for value in (demand_bytes, manifest_bytes, registry_bytes, crosswalk_bytes)):
        raise ReportDemandError("F12/F2 report inputs must be raw bytes")
    try:
        demand = canonical_json.loads(demand_bytes)
        manifest = canonical_json.loads(manifest_bytes)
        registry = canonical_json.loads(registry_bytes)
        crosswalk = canonical_json.loads(crosswalk_bytes)
    except canonical_json.CanonicalJSONError as exc:
        raise ReportDemandError(f"invalid strict JSON report input: {exc}") from exc
    return _build_report_demand(
        demand,
        manifest,
        registry,
        crosswalk,
        demand_sha256=hashlib.sha256(demand_bytes).hexdigest(),
        manifest_sha256=hashlib.sha256(manifest_bytes).hexdigest(),
        registry_sha256=hashlib.sha256(registry_bytes).hexdigest(),
        crosswalk_sha256=hashlib.sha256(crosswalk_bytes).hexdigest(),
    )


def _build_report_demand(
    demand: Mapping[str, Any],
    manifest: Mapping[str, Any],
    registry: Mapping[str, Any],
    crosswalk: Mapping[str, Any],
    *,
    demand_sha256: str,
    manifest_sha256: str,
    registry_sha256: str,
    crosswalk_sha256: str,
) -> dict[str, Any]:
    """Adapt F12 rows without inventing capabilities or registry semantics.

    Crosswalk source hashes bind the exact F12 demand and curated F2 manifest.
    Registry progress, dependencies, and symbol selectors are deliberately not
    copied into report-demand associations.
    """
    if crosswalk.get("kind") != "f12-f9-pilot-block-crosswalk" or crosswalk.get("version") != "1":
        raise ReportDemandError("unsupported F12-to-F9 crosswalk")
    if crosswalk_sha256 != REVIEWED_CROSSWALK_SHA256:
        raise ReportDemandError("crosswalk bytes differ from reviewed mapping")
    refs = crosswalk.get("sourceRefs")
    if not isinstance(refs, Mapping):
        raise ReportDemandError("crosswalk sourceRefs must be an object")
    expected_refs = {
        "demand": ("factory/shell/demand.json", demand_sha256),
        "registryManifest": ("factory/registry/manifest.json", manifest_sha256),
    }
    if set(refs) != set(expected_refs):
        raise ReportDemandError("crosswalk sourceRefs do not match expected source set")
    for key, (expected_path, expected_hash) in expected_refs.items():
        ref = refs[key]
        if not isinstance(ref, Mapping) or ref.get("path") != expected_path or ref.get("sha256") != expected_hash:
            raise ReportDemandError(f"crosswalk source pin is stale or misbound: {key}")

    if demand.get("schema_version") != 1:
        raise ReportDemandError("unsupported F12 demand schema")
    pilot = demand.get("pilot_blocks")
    if not isinstance(pilot, Mapping):
        raise ReportDemandError("F12 pilot_blocks must be an object")
    shared = pilot.get("shared_pilot_block_ids")
    round1, round2 = pilot.get("round_1"), pilot.get("round_2")
    if not all(isinstance(values, list) for values in (shared, round1, round2)):
        raise ReportDemandError("F12 pilot block lists are malformed")
    if any(not isinstance(value, str) or not value for value in shared + round1 + round2):
        raise ReportDemandError("F12 pilot block IDs must be non-empty strings")
    if len(shared) != len(set(shared)) or Counter(round1 + round2) != Counter(shared):
        raise ReportDemandError("F12 shared pilot IDs do not equal its round membership")

    manifest_blocks = manifest.get("blocks")
    if manifest.get("version") != "0.1" or not isinstance(manifest_blocks, list):
        raise ReportDemandError("input is not the curated F2 manifest")
    manifest_ids = [block.get("id") if isinstance(block, Mapping) else None for block in manifest_blocks]
    if any(not isinstance(value, str) or not value for value in manifest_ids) or len(manifest_ids) != len(set(manifest_ids)):
        raise ReportDemandError("curated manifest has malformed or duplicate block IDs")
    known_manifest_ids = set(manifest_ids)
    blocks = registry.get("blocks")
    if registry.get("kind") != "block-registry" or not isinstance(blocks, list):
        raise ReportDemandError("input is not a block registry")
    registry_ids = [block.get("id") if isinstance(block, Mapping) else None for block in blocks]
    if any(not isinstance(value, str) or not value for value in registry_ids):
        raise ReportDemandError("registry has malformed block IDs")
    if len(registry_ids) != len(set(registry_ids)):
        raise ReportDemandError("registry contains duplicate block IDs")
    known_registry_ids = set(registry_ids)

    mappings = crosswalk.get("mappings")
    if not isinstance(mappings, list):
        raise ReportDemandError("crosswalk mappings must be a list")
    mapping: dict[str, str] = {}
    used_registry_ids: set[str] = set()
    for row in mappings:
        if not isinstance(row, Mapping) or set(row) != {"pilotBlockId", "registryBlockId"}:
            raise ReportDemandError("crosswalk mapping rows must contain exactly pilotBlockId and registryBlockId")
        pilot_id, registry_id = row.get("pilotBlockId"), row.get("registryBlockId")
        if not isinstance(pilot_id, str) or not pilot_id or not isinstance(registry_id, str) or not registry_id:
            raise ReportDemandError("crosswalk mapping IDs must be non-empty strings")
        if pilot_id in mapping:
            raise ReportDemandError(f"duplicate F12 pilot mapping: {pilot_id}")
        if registry_id in used_registry_ids:
            raise ReportDemandError(f"duplicate F2 registry mapping: {registry_id}")
        if registry_id not in known_registry_ids:
            raise ReportDemandError(f"crosswalk target is absent from registry: {registry_id}")
        if registry_id not in known_manifest_ids:
            raise ReportDemandError(f"crosswalk target is absent from curated F2 manifest: {registry_id}")
        mapping[pilot_id] = registry_id
        used_registry_ids.add(registry_id)
    if set(mapping) != set(shared):
        raise ReportDemandError("crosswalk pilot IDs do not exactly cover F12 shared pilot set")
    if mapping != REVIEWED_MAPPING:
        raise ReportDemandError("crosswalk differs from reviewed F12-to-F2 mapping")

    journey_rows = demand.get("journey_demands")
    if not isinstance(journey_rows, list):
        raise ReportDemandError("F12 journey_demands must be a list")
    journeys: list[dict[str, Any]] = []
    seen_journeys: set[str] = set()
    all_extended: list[str] = []
    for row in journey_rows:
        if not isinstance(row, Mapping):
            raise ReportDemandError("F12 journey demand row must be an object")
        journey_id = row.get("journey_id")
        pilots = row.get("pilot_blocks")
        extended = row.get("extended_demands")
        if not isinstance(journey_id, str) or not journey_id or journey_id in seen_journeys:
            raise ReportDemandError("F12 journey IDs must be unique non-empty strings")
        if not isinstance(pilots, list) or any(not isinstance(value, str) for value in pilots):
            raise ReportDemandError(f"{journey_id}: pilot_blocks must be a string list")
        if len(pilots) != len(set(pilots)):
            raise ReportDemandError(f"{journey_id}: duplicate pilot block reference")
        if not isinstance(extended, list) or any(not isinstance(value, str) or not value for value in extended):
            raise ReportDemandError(f"{journey_id}: extended_demands must be a string list")
        unknown = set(pilots) - set(mapping)
        if unknown:
            raise ReportDemandError(f"{journey_id}: unknown F12 pilot block(s): {', '.join(sorted(unknown))}")
        seen_journeys.add(journey_id)
        all_extended.extend(extended)
        journeys.append({"id": journey_id, "name": journey_id, "blocks": [mapping[value] for value in pilots]})

    unmapped = demand.get("unmapped_demands")
    if not isinstance(unmapped, list):
        raise ReportDemandError("F12 unmapped_demands must be a list")
    for row in unmapped:
        if not isinstance(row, Mapping) or set(row) not in (
            {"demand", "registry_block_id", "status"},
            {"demand", "journey_id", "registry_block_id", "status"},
        ):
            raise ReportDemandError("unmapped demand rows have an unexpected shape")
        status = row.get("status")
        if row.get("registry_block_id") is not None or not isinstance(status, str) or status not in {"unmapped", "source_inventory_only"}:
            raise ReportDemandError("extended demands must remain explicitly null and unmapped")
        if not isinstance(row.get("demand"), str) or not row["demand"]:
            raise ReportDemandError("unmapped demand text must be non-empty")
        if "journey_id" in row and row["journey_id"] not in seen_journeys:
            raise ReportDemandError("unmapped demand references unknown journey")
    if Counter(all_extended) != Counter(row["demand"] for row in unmapped):
        raise ReportDemandError("F12 extended demands and unmapped rows differ")

    return {
        "blockCapabilities": {},
        "journeys": journeys,
        "unmappedDemands": deepcopy(unmapped),
        "integration": {
            "kind": "f12-f9-report-demand",
            "version": "1",
            "f12DemandSha256": demand_sha256,
            "f2ManifestSha256": manifest_sha256,
            "blockRegistrySha256": registry_sha256,
            "crosswalkSha256": crosswalk_sha256,
            "mappingCount": len(mapping),
            "journeyCount": len(journeys),
            "unmappedDemandCount": len(unmapped),
            "capabilityMapping": "none",
        },
    }
