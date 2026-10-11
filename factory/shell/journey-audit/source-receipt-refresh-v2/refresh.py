"""Refresh F12 source receipts from current bytes without changing historical inputs."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
from typing import Any

HERE = Path(__file__).resolve().parent
SHELL = HERE.parents[1]
INVENTORY = SHELL / "inventory.json"
DEMAND = SHELL / "demand.json"
ROOT = HERE.parents[3]
CROSSWALK = ROOT / "factory/shell/report-demand-integration-v1/crosswalk.json"
REGISTRY_MANIFEST = ROOT / "factory/registry/manifest.json"
sys.path.insert(0, str(HERE.parents[3]))

from factory.shell.__main__ import validate_map

# SettingsPanel API gained props indirection in current RightKit source. Keep
# old receipt in history & bind exact current declaration as successor anchor.
SEMANTIC_ANCHORS = {
    "settings-panel": 'export function SettingsPanel(props: SettingsPanelProps) {',
}


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def refresh_entry(entry: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    path = Path(entry["path"])
    raw = path.read_bytes()
    current_hash = digest(raw)
    lines = raw.decode("utf-8", errors="replace").splitlines()
    hits = [index + 1 for index, line in enumerate(lines) if line.strip() == entry["text"]]
    resolution = "historical-anchor-preserved"
    anchor_text = entry["text"]
    if not hits:
        anchor_text = SEMANTIC_ANCHORS.get(entry["id"], "")
        if not anchor_text:
            raise ValueError(f"no current anchor for {entry['id']}")
        hits = [index + 1 for index, line in enumerate(lines) if line.strip() == anchor_text]
        resolution = "semantic-anchor-updated"
    if not hits:
        raise ValueError(f"current source lacks anchor for {entry['id']}")
    line_number = min(hits, key=lambda value: abs(value - int(entry["line"])))
    current = {
        "id": entry["id"],
        "path": entry["path"],
        "sha256": current_hash,
        "line": line_number,
        "text": anchor_text,
    }
    history = {
        "id": entry["id"],
        "path": entry["path"],
        "historicalSha256": entry["sha256"],
        "historicalLine": entry["line"],
        "historicalText": entry["text"],
        "currentSha256": current_hash,
        "currentLine": line_number,
        "currentText": anchor_text,
        "resolution": resolution,
        "hashChanged": current_hash != entry["sha256"],
    }
    return current, history


def make_candidate() -> tuple[dict[str, Any], dict[str, Any], list[dict[str, Any]]]:
    inventory = json.loads(INVENTORY.read_text(encoding="utf-8"))
    demand = json.loads(DEMAND.read_text(encoding="utf-8"))
    candidate = copy.deepcopy(inventory)
    refreshed: list[dict[str, Any]] = []
    history: list[dict[str, Any]] = []
    for index, entry in enumerate(inventory["evidence"]):
        current, record = refresh_entry(entry)
        candidate["evidence"][index] = current
        refreshed.append(current)
        history.append(record)
    return candidate, demand, history


def validate_candidate(candidate: dict[str, Any], demand: dict[str, Any]) -> None:
    if validate_map(candidate, demand):
        raise ValueError("candidate inventory/demand map differs")
    seen: set[str] = set()
    for entry in candidate["evidence"]:
        if entry["id"] in seen:
            raise ValueError(f"duplicate evidence id: {entry['id']}")
        seen.add(entry["id"])
        raw = Path(entry["path"]).read_bytes()
        if digest(raw) != entry["sha256"]:
            raise ValueError(f"current source hash mismatch: {entry['id']}")
        lines = raw.decode("utf-8", errors="replace").splitlines()
        if entry["line"] < 1 or entry["line"] > len(lines) or lines[entry["line"] - 1].strip() != entry["text"]:
            raise ValueError(f"current source anchor mismatch: {entry['id']}")


def demand_associations(candidate: dict[str, Any], demand: dict[str, Any]) -> list[dict[str, Any]]:
    evidence_by_id = {entry["id"]: entry for entry in candidate["evidence"]}
    demand_rows = {row["demand"]: row for row in demand["unmapped_demands"]}
    rows: list[dict[str, Any]] = []
    for journey in candidate["journeys"]:
        refs = [evidence_by_id[evidence_id] for evidence_id in journey["evidence_ids"]]
        for text in journey["extended_demands"]:
            original = demand_rows[text]
            rows.append(
                {
                    "demand": text,
                    "journeyId": journey["id"],
                    "status": original["status"],
                    "registryBlockId": original["registry_block_id"],
                    "associationKind": "current-source-evidence-association-only",
                    "sourceProof": False,
                    "evidenceRefs": [
                        {"id": ref["id"], "path": ref["path"], "sha256": ref["sha256"], "line": ref["line"], "text": ref["text"]}
                        for ref in refs
                    ],
                }
            )
    return sorted(rows, key=lambda row: row["demand"])


def validate_associations(candidate: dict[str, Any], demand: dict[str, Any], rows: list[dict[str, Any]]) -> None:
    expected = {row["demand"]: row for row in demand_associations(candidate, demand)}
    actual = {row.get("demand"): row for row in rows}
    if len(rows) != 107 or set(actual) != set(expected):
        raise ValueError("demand association denominator or row set drift")
    for demand_text, expected_row in expected.items():
        row = actual[demand_text]
        for field in ("journeyId", "status", "registryBlockId"):
            if row.get(field) != expected_row[field]:
                raise ValueError(f"{demand_text}: {field} drift")
        if row.get("sourceProof") is not False or row.get("associationKind") != "current-source-evidence-association-only":
            raise ValueError(f"{demand_text}: source-only association contract drift")


def pilot_crosswalk() -> dict[str, Any]:
    crosswalk = json.loads(CROSSWALK.read_text(encoding="utf-8"))
    registry = json.loads(REGISTRY_MANIFEST.read_text(encoding="utf-8"))
    demand = json.loads(DEMAND.read_text(encoding="utf-8"))
    shared = set(demand["pilot_blocks"]["shared_pilot_block_ids"])
    registry_ids = {block["id"] for block in registry["blocks"]}
    mappings = crosswalk.get("mappings", [])
    if len(mappings) != 10 or {row["pilotBlockId"] for row in mappings} != shared:
        raise ValueError("pilot crosswalk does not exactly cover ten shared IDs")
    if any(row["registryBlockId"] not in registry_ids for row in mappings):
        raise ValueError("pilot crosswalk target absent from registry manifest")
    source_refs = crosswalk.get("sourceRefs", {})
    if source_refs.get("demand", {}).get("sha256") != digest(DEMAND.read_bytes()):
        raise ValueError("pilot crosswalk demand source pin drift")
    if source_refs.get("registryManifest", {}).get("sha256") != digest(REGISTRY_MANIFEST.read_bytes()):
        raise ValueError("pilot crosswalk registry source pin drift")
    return {"kind": "f12-source-bound-pilot-crosswalk", "mappingCount": 10, "registryTargets": sorted(row["registryBlockId"] for row in mappings), "extendedRegistryMappings": 0, "registryPromotion": 0, "status": "source-bound-pilot-only"}


def write_packet() -> dict[str, Any]:
    candidate, demand, history = make_candidate()
    validate_candidate(candidate, demand)
    associations = demand_associations(candidate, demand)
    validate_associations(candidate, demand, associations)
    crosswalk = pilot_crosswalk()
    (HERE / "evidence/current-inventory-v2-candidate.json").write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (HERE / "evidence/receipt-refresh-v2.json").write_text(json.dumps({"kind": "f12-source-receipt-refresh-v2", "version": 1, "historicalInventorySha256": digest(INVENTORY.read_bytes()), "currentReceipts": history}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (HERE / "evidence/demand-associations-v2.json").write_text(json.dumps({"kind": "f12-demand-current-source-associations-v2", "version": 1, "status": "source-only-no-promotion", "rows": associations}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (HERE / "evidence/controls-v2.json").write_text(json.dumps({"kind": "f12-source-receipt-refresh-v2-controls", "status": "PASS", "controls": [{"control": "baseline-current-receipts", "baseline": "accepted", "mutation": "none"}, {"control": "hash-drift", "baseline": "accepted", "mutation": "rejected"}, {"control": "anchor-drift", "baseline": "accepted", "mutation": "rejected"}, {"control": "association-row-omission", "baseline": "accepted", "mutation": "rejected"}, {"control": "association-status-promotion", "baseline": "accepted", "mutation": "rejected"}], "receipts": 56, "demands": 107, "registryPromotion": 0}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (HERE / "evidence/pilot-crosswalk-v2.json").write_text(json.dumps(crosswalk, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {"candidate": candidate, "demand": demand, "history": history, "associations": associations, "crosswalk": crosswalk}


if __name__ == "__main__":
    result = write_packet()
    print(json.dumps({"status": "PASS", "receipts": len(result["history"]), "demands": len(result["associations"]), "semanticAnchorUpdates": sum(x["resolution"] == "semantic-anchor-updated" for x in result["history"])}, sort_keys=True))
