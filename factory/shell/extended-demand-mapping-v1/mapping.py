"""Source-pinned, non-promotional references for F12 extended demands."""
from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
INPUT_PATHS = {
    "demand": "factory/shell/demand.json",
    "inventory": "factory/shell/inventory.json",
    "catalogue": "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json",
    "catalogueManifest": "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.manifest.json",
    "registryManifest": "factory/registry/manifest.json",
    "registry": "factory/registry/evidence/block-registry.json",
    "sourceSnapshotManifest": "factory/shell/extended-demand-mapping-v1/evidence/source-snapshot-manifest.json",
}
EXPECTED_SHA256 = {
    "demand": "45c48393b06b65b1b156f01272eb5c95517876df0aae790203bdbaa2ebbaf835",
    "inventory": "62e65c87a5fcd38610fb6a8a8c290e0eb6c889f308e444b244c0863c9e7b9eba",
    "catalogue": "fd453b6345f83b49931c7194c2e1127538e2de4ceb0de4c25f715ac6d85ac4f2",
    "catalogueManifest": "322543df1789a202301ac159089ec33b20487fe268db90d90d3a2948888fbbb4",
    "registryManifest": "7a2e80bf7ce132955e46b676c4818f96bfaebde279f5d5a4868da5d3bb482cf1",
    "registry": "1ad0a508bb0b721a31f9e2ecdf209a217d20c52d2666a14d3eaf970653d8b983",
    "sourceSnapshotManifest": "d28b8b6fe006b0980e31b65ea3b8a0b4e4655dadbe85ad1c15a92c693ce60fcb",
}

# Exact SDK path + USR pairs. These are catalogue references only; none of
# these identities belongs to one of current curated F2 block selectors.
EXACT_REFERENCES = {
    "List/ForEach/onMove": [
        ("SwiftUI.List", "s:7SwiftUI4ListV"),
        ("SwiftUI.ForEach", "s:7SwiftUI7ForEachV"),
        ("SwiftUI.DynamicViewContent.onMove(perform:)", "s:7SwiftUI18DynamicViewContentPAAE6onMove7performQry10Foundation8IndexSetV_SitcSg_tF"),
    ],
    "TextField/FocusState": [
        ("SwiftUI.TextField", "s:7SwiftUI9TextFieldV"),
        ("SwiftUI.FocusState", "s:7SwiftUI10FocusStateV"),
    ],
}
AMBIGUOUS_REFERENCES = {
    "Binding(get:set:)": [
        ("SwiftUI.Binding.init(get:set:)", "s:7SwiftUI7BindingV3get3setACyxGxyc_yx_AA11TransactionVtctcfc"),
        ("SwiftUI.Binding.init(get:set:)", "s:7SwiftUI7BindingV3get3setACyxGxyc_yxctcfc"),
    ],
    "Button actions": [
        ("SwiftUI.Button", "s:7SwiftUI6ButtonV"),
        ("SwiftUI.Button.init(action:label:)", "s:7SwiftUI6ButtonV6action5labelACyxGyyc_xyXEtcfc"),
    ],
    "radio/checkbox controls": [
        ("SwiftUI.RadioGroupPickerStyle", "s:7SwiftUI21RadioGroupPickerStyleV"),
        ("SwiftUI.CheckboxToggleStyle", "s:7SwiftUI19CheckboxToggleStyleV"),
    ],
}

# Exact labels whose wording identifies app/OS/service responsibilities. This
# is a review disposition, not an inferred SwiftUI implementation mapping.
SERVICE_LABELS = {
    "HTML media element and codec recovery", "PDF.js worker/render pipeline",
    "async loading and external-change reconciliation", "crash-safe atomic write",
    "document/file adapter", "download progress/cancel/retry", "download/install progress",
    "duplicate/window targeting policy", "durable state + service sequencing",
    "external-link policy", "fullscreen host API", "large resource lifecycle",
    "media conversion service", "native menu/tray lifecycle", "native open/save/print dialogs",
    "permission prompts", "persistence", "platform installer and rollback",
    "receipt persistence/hash", "restart/recovery strategy", "schema migration",
    "settings storage/revision service", "startup/window recovery",
    "storage adapters and cross-process consistency", "update service/auth",
    "version policy", "view-state persistence",
}


class MappingError(ValueError):
    pass


def _decode(data: bytes, label: str) -> Any:
    if not isinstance(data, bytes):
        raise MappingError(f"{label} input must be exact raw bytes")
    try:
        return json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MappingError(f"{label} input is not valid JSON") from exc


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _source_observation(record: dict[str, Any], raw: bytes) -> dict[str, Any]:
    lines = raw.decode("utf-8", errors="replace").splitlines()
    line = record["line"]
    anchor = 1 <= line <= len(lines) and lines[line - 1] == record["text"]
    digest = _sha(raw)
    if digest == record["sha256"] and anchor:
        status = "current"
    else:
        status = "stale"
    return {"status": status, "observedSha256": digest, "anchorMatches": anchor}


def build_mapping(
    demand_bytes: bytes,
    inventory_bytes: bytes,
    catalogue_bytes: bytes,
    catalogue_manifest_bytes: bytes,
    registry_manifest_bytes: bytes,
    registry_bytes: bytes,
    source_snapshot_manifest_bytes: bytes,
    source_snapshots: dict[str, bytes],
) -> dict[str, Any]:
    """Build inventory with no registry promotion from the exact pinned inputs."""
    payloads = {
        "demand": demand_bytes,
        "inventory": inventory_bytes,
        "catalogue": catalogue_bytes,
        "catalogueManifest": catalogue_manifest_bytes,
        "registryManifest": registry_manifest_bytes,
        "registry": registry_bytes,
        "sourceSnapshotManifest": source_snapshot_manifest_bytes,
    }
    for key, raw in payloads.items():
        if not isinstance(raw, bytes):
            raise MappingError(f"{key} input must be exact raw bytes")
        if _sha(raw) != EXPECTED_SHA256[key]:
            raise MappingError(f"pinned input changed: {key}")
    demand = _decode(demand_bytes, "demand")
    inventory = _decode(inventory_bytes, "inventory")
    catalogue = _decode(catalogue_bytes, "catalogue")
    cat_manifest = _decode(catalogue_manifest_bytes, "catalogue manifest")
    registry_manifest = _decode(registry_manifest_bytes, "registry manifest")
    registry = _decode(registry_bytes, "registry")
    source_snapshot_manifest = _decode(source_snapshot_manifest_bytes, "source snapshot manifest")

    if catalogue.get("kind") != "catalogue" or catalogue.get("version") != "0.1":
        raise MappingError("unexpected F1 catalogue")
    if cat_manifest.get("catalogueSha256") not in (None, EXPECTED_SHA256["catalogue"]):
        raise MappingError("F1 catalogue manifest does not bind current catalogue")
    manifest_ids = [b.get("id") for b in registry_manifest.get("blocks", [])]
    registry_ids = [b.get("id") for b in registry.get("blocks", [])]
    if not manifest_ids or len(manifest_ids) != len(set(manifest_ids)) or set(manifest_ids) != set(registry_ids):
        raise MappingError("curated registry and manifest identities differ")
    registry_selectors: dict[str, list[str]] = {}
    for block in registry_manifest["blocks"]:
        for selector in block.get("symbols", []):
            usr = selector.removeprefix("usr:")
            registry_selectors.setdefault(usr, []).append(block["id"])

    symbols = catalogue.get("symbols")
    if not isinstance(symbols, list):
        raise MappingError("F1 catalogue symbols are malformed")
    by_pair: dict[tuple[str, str], list[dict[str, Any]]] = {}
    by_usr: dict[str, list[dict[str, Any]]] = {}
    for symbol in symbols:
        if not isinstance(symbol, dict) or not isinstance(symbol.get("path"), str) or not isinstance(symbol.get("usr"), str):
            raise MappingError("catalogue symbol row malformed")
        by_pair.setdefault((symbol["path"], symbol["usr"]), []).append(symbol)
        by_usr.setdefault(symbol["usr"], []).append(symbol)

    for label, references in (EXACT_REFERENCES | AMBIGUOUS_REFERENCES).items():
        for path, usr in references:
            matches = by_pair.get((path, usr), [])
            if len(matches) != 1 or matches[0].get("status") != "inventory":
                raise MappingError(f"exact catalogue identity did not resolve uniquely: {label}: {path}")

    evidence = inventory.get("evidence")
    journeys = inventory.get("journeys")
    journey_demands = demand.get("journey_demands")
    unmapped = demand.get("unmapped_demands")
    if not all(isinstance(x, list) for x in (evidence, journeys, journey_demands, unmapped)):
        raise MappingError("F12 source inventory/demand arrays malformed")
    evidence_by_id = {x.get("id"): x for x in evidence if isinstance(x, dict)}
    journey_by_id = {x.get("id"): x for x in journeys if isinstance(x, dict)}
    if len(evidence_by_id) != len(evidence) or len(journey_by_id) != len(journeys):
        raise MappingError("F12 source evidence or journey IDs are duplicated")
    indexed_journeys: dict[str, list[dict[str, Any]]] = {}
    for row in journey_demands:
        if not isinstance(row, dict) or not isinstance(row.get("journey_id"), str):
            raise MappingError("F12 journey demand malformed")
        for label in row.get("extended_demands", []):
            indexed_journeys.setdefault(label, []).append(row)
    if Counter(indexed_journeys.keys()) != Counter(r["demand"] for r in unmapped):
        raise MappingError("F12 flattened demand labels differ from journey source rows")

    if source_snapshot_manifest.get("kind") != "f12-source-inventory-source-snapshot" or source_snapshot_manifest.get("inventorySha256") != EXPECTED_SHA256["inventory"]:
        raise MappingError("source snapshot manifest does not bind pinned F12 inventory")
    source_by_path = {}
    snapshot_rows = source_snapshot_manifest.get("sources")
    if not isinstance(snapshot_rows, list) or source_snapshot_manifest.get("sourceCount") != len(snapshot_rows):
        raise MappingError("source snapshot manifest is malformed")
    for snapshot_row in snapshot_rows:
        source_path = snapshot_row.get("sourcePath")
        snapshot_path = snapshot_row.get("snapshotPath")
        raw = source_snapshots.get(snapshot_path)
        if not isinstance(source_path, str) or not isinstance(snapshot_path, str) or not isinstance(raw, bytes):
            raise MappingError("source snapshot bytes are missing")
        if len(raw) != snapshot_row.get("bytes") or _sha(raw) != snapshot_row.get("sha256"):
            raise MappingError("source snapshot bytes do not match manifest")
        if source_path in source_by_path:
            raise MappingError("source snapshot path is duplicated")
        source_by_path[source_path] = (snapshot_row, raw)
    expected_source_paths = {record.get("path") for record in evidence if isinstance(record, dict)}
    if set(source_by_path) != expected_source_paths or set(source_snapshots) != {row["snapshotPath"] for row in snapshot_rows}:
        raise MappingError("source snapshot set differs from F12 inventory evidence")

    current_rows = []
    all_inventory_refs = {}
    for evidence_row in evidence:
        source = source_by_path.get(evidence_row.get("path"))
        if source is None:
            raise MappingError("F12 evidence source has no captured bytes")
        obs = _source_observation(evidence_row, source[1])
        all_inventory_refs[evidence_row["id"]] = {
            "id": evidence_row["id"],
            "path": evidence_row["path"],
            "sha256": evidence_row["sha256"],
            "line": evidence_row["line"],
            "text": evidence_row["text"],
            "observed": obs,
        }
    for index, row in enumerate(unmapped):
        label = row.get("demand")
        if not isinstance(label, str) or row.get("registry_block_id") is not None:
            raise MappingError("extended demand row malformed or already promoted")
        if row.get("status") not in {"unmapped", "source_inventory_only"}:
            raise MappingError("unknown F12 extended-demand status")
        if row.get("journey_id"):
            source_journeys = [journey_by_id.get(row["journey_id"])]
            if source_journeys[0] is None:
                raise MappingError("extended demand references unknown inventory journey")
        else:
            source_journeys = [journey_by_id.get(j["journey_id"]) for j in indexed_journeys.get(label, [])]
            if any(j is None for j in source_journeys):
                raise MappingError("extended demand references missing source journey")
        if not source_journeys:
            raise MappingError("extended demand has no journey source link")
        evidence_ids = sorted({eid for journey in source_journeys for eid in journey.get("evidence_ids", [])})
        if any(eid not in evidence_by_id for eid in evidence_ids):
            raise MappingError("journey references missing inventory evidence")
        refs = [all_inventory_refs[eid] for eid in evidence_ids]
        freshness = "current" if all(ref["observed"]["status"] == "current" for ref in refs) else "stale"

        refs_for_row = EXACT_REFERENCES.get(label, [])
        ambiguous = AMBIGUOUS_REFERENCES.get(label, [])
        identity_refs = [
            {"path": path, "usr": usr, "status": "inventory", "registryBlockIds": sorted(set(registry_selectors.get(usr, [])))}
            for path, usr in refs_for_row
        ]
        ambiguous_refs = [
            {"path": path, "usr": usr, "status": "inventory", "registryBlockIds": sorted(set(registry_selectors.get(usr, [])))}
            for path, usr in ambiguous
        ]
        if identity_refs:
            disposition = "exact-catalogue-reference-only"
            reason = "Demand names these exact F1 SDK declarations; current F2 manifest has no matching selector, so registryBlockId remains null."
        elif ambiguous_refs:
            disposition = "ambiguous-catalogue-candidates"
            reason = "Related F1 declarations exist, but demand wording does not select a unique declaration or prove behavior; no registry link is emitted."
        elif row["status"] == "source_inventory_only":
            disposition = "non-swiftui-source-inventory"
            reason = "F12 explicitly marks this row source_inventory_only; preserve source references without assigning a SwiftUI registry block."
        elif label in SERVICE_LABELS:
            disposition = "service-or-platform"
            reason = "Demand label identifies service, platform, persistence, or host work; no exact curated F2 selector represents it."
        else:
            disposition = "unmapped"
            reason = "No exact catalogue identity or curated registry selector is established by this source record."
        current_rows.append({
            "rowKey": f"f12-extended-{index + 1:03d}",
            "demand": label,
            "inventoryStatus": row["status"],
            "journeyIds": sorted({j["id"] for j in source_journeys}),
            "inventoryEvidenceIds": evidence_ids,
            "inventoryEvidenceFreshness": freshness,
            "disposition": disposition,
            "reason": reason,
            "catalogueIdentityReferences": identity_refs,
            "ambiguousCatalogueCandidates": ambiguous_refs,
            "registryBlockId": None,
        })

    if len(current_rows) != 107 or len({r["rowKey"] for r in current_rows}) != len(current_rows):
        raise MappingError("F12 extended demand denominator or row identity changed")
    if any(r["registryBlockId"] is not None for r in current_rows):
        raise MappingError("this candidate may not promote registry mappings")
    dispositions = Counter(r["disposition"] for r in current_rows)
    return {
        "kind": "f12-extended-demand-identity-review",
        "version": "1",
        "status": "candidate-source-identity-review",
        "scope": "Exact SDK identity references are evidence links only; registry IDs, semanticDependencies, capabilities, progress, and native coverage are unchanged.",
        "inputs": {key: {"path": INPUT_PATHS[key], "sha256": _sha(payloads[key])} for key in INPUT_PATHS},
        "denominator": {"extendedDemandRows": len(current_rows), "registryMappedRows": 0, "sourceInventoryOnly": sum(r["inventoryStatus"] == "source_inventory_only" for r in current_rows)},
        "dispositionCounts": dict(sorted(dispositions.items())),
        "f1CatalogueIdentityCount": sum(len(r["catalogueIdentityReferences"]) for r in current_rows),
        "ambiguousCandidateCount": sum(len(r["ambiguousCatalogueCandidates"]) for r in current_rows),
        "inventoryEvidence": all_inventory_refs,
        "rows": current_rows,
    }


def load_pinned_inputs(root: Path = ROOT) -> dict[str, bytes]:
    return {key: (root / relative).read_bytes() for key, relative in INPUT_PATHS.items()}


def load_pinned_source_snapshots(root: Path = ROOT) -> dict[str, bytes]:
    manifest = _decode((root / INPUT_PATHS["sourceSnapshotManifest"]).read_bytes(), "source snapshot manifest")
    base = root / "factory/shell/extended-demand-mapping-v1"
    return {row["snapshotPath"]: (base / row["snapshotPath"]).read_bytes()
            for row in manifest.get("sources", [])}


def validate_candidate(candidate: Any, payloads: dict[str, bytes], source_snapshots: dict[str, bytes]) -> None:
    """Rebuild from pinned inputs and reject any changed or promoted row."""
    expected = build_mapping(*(payloads[key] for key in INPUT_PATHS), source_snapshots)
    if candidate != expected:
        raise MappingError("candidate differs from independent exact-input reconstruction")
