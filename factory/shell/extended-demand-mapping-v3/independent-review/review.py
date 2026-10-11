#!/usr/bin/env python3
"""Offline independent review of extended-demand-mapping-v3."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HERE = ROOT / "factory/shell/extended-demand-mapping-v3"
V1_ROOT = ROOT / "factory/shell/extended-demand-mapping-v1/root-completed-stage-manifest.json"
V2_ROOT = ROOT / "factory/shell/extended-demand-mapping-v2/root-completed-stage.json"
CATALOGUE = ROOT / "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json"
V2_SOURCE_MANIFEST = ROOT / "factory/shell/extended-demand-mapping-v2/evidence/source-snapshot-manifest.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def check_file(path: Path, expected_bytes: int, expected_sha: str) -> None:
    assert path.is_file(), path
    assert not path.is_symlink(), path
    data = path.read_bytes()
    assert len(data) == expected_bytes, path
    assert hashlib.sha256(data).hexdigest() == expected_sha, path


def check_stage_manifest() -> dict:
    manifest = load(HERE / "stage-manifest-v3.json")
    assert manifest["kind"] == "f12-extended-demand-mapping-v3-stage"
    assert manifest["fileCount"] == len(manifest["files"])
    for entry in manifest["files"]:
        check_file(HERE / entry["path"], entry["bytes"], entry["sha256"])
    assert manifest["totalBytes"] == sum(x["bytes"] for x in manifest["files"])
    assert manifest["maxFileBytes"] == max(x["bytes"] for x in manifest["files"])
    return {"fileCount": len(manifest["files"]), "totalBytes": manifest["totalBytes"]}


def check_historic_manifest(path: Path) -> dict:
    manifest = load(path)
    files = manifest["files"]
    if "fileCount" in manifest:
        assert manifest["fileCount"] == len(files)
    for entry in files:
        check_file(ROOT / entry["path"], entry["bytes"], entry["sha256"])
    return {"path": str(path.relative_to(ROOT)), "manifestSha256": digest(path), "fileCount": len(files)}


def check_raw(mapping: dict, raw: dict) -> dict:
    assert raw["kind"] == "f12-extended-demand-source-evidence-v3-raw-pins"
    entries = raw["files"]
    assert len({x["path"] for x in entries}) == len(entries)
    for entry in entries:
        check_file(ROOT / entry["path"], entry["bytes"], entry["sha256"])
    assert raw["mappingSha256"] == digest(HERE / "mapping-v3.json")
    by_path = {entry["path"]: entry for entry in entries}
    key_paths = (
        "factory/shell/demand.json",
        "factory/shell/inventory.json",
        "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json",
        "factory/shell/extended-demand-mapping-v1/evidence/mapping-candidate.json",
        "factory/shell/extended-demand-mapping-v2/evidence/current-source-candidate.json",
        "factory/shell/extended-demand-mapping-v1/evidence/source-snapshot-manifest.json",
        "factory/shell/extended-demand-mapping-v2/evidence/source-snapshot-manifest.json",
    )
    assert all(path in by_path for path in key_paths)
    return {
        "fileCount": len(entries),
        "mappingSha256": raw["mappingSha256"],
        "rawPinsSha256": digest(HERE / "raw-pins-v3.json"),
        "keyPins": {path: by_path[path]["sha256"] for path in key_paths},
    }


def check_mapping(mapping: dict, raw: dict) -> dict:
    assert mapping["kind"] == "f12-extended-demand-source-evidence-v3"
    assert mapping["version"] == 3
    assert mapping["status"] == "source-evidence-candidate-no-registry-promotion"
    assert mapping["denominator"]["extendedDemandRows"] == 107
    assert mapping["denominator"]["registryMappedRows"] == 0
    assert mapping["denominator"]["currentSourceUsageRows"] == 2
    assert mapping["denominator"]["sourceInventoryEvidenceRows"] == 46
    rows = mapping["rows"]
    assert len(rows) == 107
    assert len({row["rowKey"] for row in rows}) == 107
    assert sum(mapping["resolutionCounts"].values()) == 107
    assert mapping["preservation"]["registryPromotion"] is False

    catalogue = load(CATALOGUE)
    by_usr = {entry["usr"]: entry for entry in catalogue["symbols"]}
    source_manifest = load(V2_SOURCE_MANIFEST)
    source_by_path = {entry["sourcePath"]: entry for entry in source_manifest["sources"]}

    registry_links = 0
    unexpected_registry_values = []

    def scan_registry(value, path=""):
        if isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}/{key}"
                if "registry" in key.lower() and child not in (None, False, 0, "", []):
                    if child_path != "/inputs/registry":
                        unexpected_registry_values.append(child_path)
                scan_registry(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                scan_registry(child, f"{path}/{index}")

    scan_registry(mapping)
    assert not unexpected_registry_values, unexpected_registry_values
    current_rows = []
    for row in rows:
        assert row.get("registryBlockId") in (None, "")
        assert not row.get("registryBlockIds")
        evidence = row["v3Evidence"]
        assert evidence["registryPromotion"] is False
        assert not row.get("catalogueIdentityReferences")
        if row.get("currentUsageReferences"):
            current_rows.append(row)
        for key in ("registryBlockId", "registryBlockIds"):
            value = row.get(key)
            registry_links += int(bool(value))
        for check in evidence["catalogueUsrChecks"]:
            assert check["cataloguePresent"] is True
            hit = by_usr.get(check["usr"])
            assert hit is not None
            assert check["path"] == hit["path"]
            assert check["cataloguePath"] == hit["path"]
            assert check["catalogueStatus"] == hit["status"]
        for snapshot in evidence["sourceSnapshots"]:
            check_file(ROOT / snapshot["snapshotPath"], snapshot["bytes"], snapshot["sha256"])
        for usage in row.get("currentUsageReferences", []):
            hit = by_usr.get(usage["usr"])
            assert hit is not None
            assert usage["path"] == hit["path"]
            assert usage["catalogueStatus"] == hit["status"]
            source = source_by_path.get(usage["sourcePath"])
            assert source is not None
            assert usage["sourceBytes"] == source["bytes"]
            assert usage["sourceSha256"] == source["sha256"]
            snapshot_path = ROOT / "factory/shell/extended-demand-mapping-v2/evidence" / Path(source["snapshotPath"]).relative_to("evidence")
            lines = snapshot_path.read_text().splitlines()
            assert 1 <= usage["line"] <= len(lines)
            assert lines[usage["line"] - 1] == usage["exactLine"]
            assert not usage.get("registryBlockIds")
    assert registry_links == 0
    return {"rowCount": len(rows), "currentUsageRowCount": len(current_rows), "registryLinks": registry_links}


def check_held_rows(mapping: dict) -> dict:
    v2 = load(ROOT / "factory/shell/extended-demand-mapping-v2/evidence/current-source-candidate.json")
    held = {row["rowKey"]: row["currentUsageReferences"] for row in v2["rows"]}
    current = {row["rowKey"]: row["currentUsageReferences"] for row in mapping["rows"] if row.get("currentUsageReferences")}
    assert set(held) == {"f12-extended-004", "f12-extended-006"}
    assert current == held
    return {
        "rowKeys": sorted(current),
        "exactUsrCount": sum(len(refs) for refs in current.values()),
        "heldCandidateSha256": digest(ROOT / "factory/shell/extended-demand-mapping-v2/evidence/current-source-candidate.json"),
    }


def validate(mapping: dict, raw: dict) -> None:
    check_mapping(mapping, raw)
    check_raw(mapping, raw)


def check_controls(mapping: dict, raw: dict) -> dict:
    mutations = {
        "row-omission": lambda m, r: m["rows"].pop(),
        "duplicate-row-key": lambda m, r: m["rows"][-1].__setitem__("rowKey", m["rows"][0]["rowKey"]),
        "invented-registry-link": lambda m, r: m["rows"][0].__setitem__("registryBlockId", "invented"),
        "held-usr-mutation": lambda m, r: m["rows"][3]["currentUsageReferences"][0].__setitem__("usr", "invented-usr"),
        "source-snapshot-mutation": lambda m, r: m["rows"][0]["v3Evidence"]["sourceSnapshots"][0].__setitem__("sha256", "0" * 64),
        "input-pin-mutation": lambda m, r: r["files"][0].__setitem__("sha256", "0" * 64),
    }
    outcomes = {}
    for name, mutate in mutations.items():
        mutated_mapping = copy.deepcopy(mapping)
        mutated_raw = copy.deepcopy(raw)
        mutate(mutated_mapping, mutated_raw)
        try:
            validate(mutated_mapping, mutated_raw)
        except (AssertionError, KeyError, IndexError, ValueError):
            outcomes[name] = "rejected"
        else:
            outcomes[name] = "accepted-BUG"
    assert all(value == "rejected" for value in outcomes.values()), outcomes
    return outcomes


def main() -> None:
    mapping = load(HERE / "mapping-v3.json")
    raw = load(HERE / "raw-pins-v3.json")
    stage = check_stage_manifest()
    mapping_summary = check_mapping(mapping, raw)
    raw_summary = check_raw(mapping, raw)
    held_summary = check_held_rows(mapping)
    controls = check_controls(mapping, raw)
    historic = [check_historic_manifest(V1_ROOT), check_historic_manifest(V2_ROOT)]
    review = {
        "kind": "f12-extended-demand-mapping-v3-independent-review",
        "version": 1,
        "scope": "Offline independent review; v3 producer, v1/v2 evidence, registry, source, catalogue, SSH, GUI, Pulse, & binary execution untouched.",
        "stage": stage,
        "inputSourceCataloguePins": raw_summary,
        "denominator": {"extendedDemandRows": 107, "registryMappedRows": 0, "mappingRows": mapping_summary["rowCount"]},
        "exactHeldUsrRows": held_summary,
        "registryLinks": mapping_summary["registryLinks"],
        "controls": {"count": len(controls), "outcomes": controls},
        "historicV1V2Immutability": {"manifests": historic, "allPinnedFilesMatch": True},
        "disposition": "independent review passes 107-row source-evidence mapping; exactly two held current-source rows match v2; zero registry links; six controls reject; v1/v2 pinned files unchanged",
    }
    (HERE / "independent-review/review.json").write_text(json.dumps(review, indent=2) + "\n")
    print(json.dumps({"status": "pass", "rows": 107, "exactHeldUsrRows": 2, "registryLinks": 0, "controls": 6, "historicV1V2": True}, sort_keys=True))


if __name__ == "__main__":
    main()
