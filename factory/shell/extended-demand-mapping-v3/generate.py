#!/usr/bin/env python3
"""Build F12 v3 source-evidence mapping without registry promotion."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "factory/shell/extended-demand-mapping-v3"
V1 = ROOT / "factory/shell/extended-demand-mapping-v1/evidence"
V2 = ROOT / "factory/shell/extended-demand-mapping-v2/evidence"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def pin(path: Path) -> dict[str, object]:
    return {"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": sha(path)}


def snapshot_file(manifest_root: Path, snapshot_path: str) -> Path:
    rel = Path(snapshot_path)
    if rel.parts and rel.parts[0] == "evidence":
        rel = Path(*rel.parts[1:])
    return manifest_root / rel


def main() -> None:
    v1 = json.loads((V1 / "mapping-candidate.json").read_text())
    v2 = json.loads((V2 / "current-source-candidate.json").read_text())
    v1_manifest = json.loads((V1 / "source-snapshot-manifest.json").read_text())
    v2_manifest = json.loads((V2 / "source-snapshot-manifest.json").read_text())
    catalogue = json.loads((ROOT / "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json").read_text())
    catalogue_by_usr = {x["usr"]: x for x in catalogue["symbols"]}
    v2_by_key = {x["rowKey"]: x for x in v2["rows"]}
    snapshots = {i: s for manifest in (v1_manifest, v2_manifest) for s in manifest["sources"] for i in ([s["evidenceId"]] if "evidenceId" in s else s["inventoryEvidenceIds"])}
    rows = []
    for original in v1["rows"]:
        row = copy.deepcopy(v2_by_key[original["rowKey"]]) if original["rowKey"] in v2_by_key else copy.deepcopy(original)
        refs = []
        for evidence_id in original.get("inventoryEvidenceIds", []):
            source = snapshots[evidence_id]
            refs.append({"evidenceId": evidence_id, "sourcePath": source["sourcePath"], "snapshotPath": str(snapshot_file(V1 if "inventoryEvidenceIds" in source else V2, source["snapshotPath"]).relative_to(ROOT)), "bytes": source["bytes"], "sha256": source["sha256"]})
        usrs = []
        for group in ("catalogueIdentityReferences", "ambiguousCatalogueCandidates"):
            for identity in original.get(group, []):
                hit = catalogue_by_usr.get(identity["usr"])
                usrs.append({"path": identity["path"], "usr": identity["usr"], "cataloguePresent": hit is not None, "cataloguePath": hit.get("path") if hit else None, "catalogueStatus": hit.get("status") if hit else None})
        if row["rowKey"] in v2_by_key:
            resolution = "current-source-usage-confirmed"
            basis = "v2 exact source lines + source snapshot bytes + catalogue USRs; registry remains unbound"
        elif original["disposition"] == "non-swiftui-source-inventory":
            resolution = "source-inventory-only"
            basis = "current/stale source inventory evidence; service/platform ownership is not SwiftUI registry integration"
        elif original["disposition"] == "service-or-platform":
            resolution = "service-or-platform-held"
            basis = "service/platform demand; no SwiftUI USR or registry block emitted"
        elif original["disposition"] == "exact-catalogue-reference-only":
            resolution = "catalogue-reference-held"
            basis = "catalogue USRs verified, but no current exact usage binding or registry selector"
        elif original["disposition"] == "ambiguous-catalogue-candidates":
            resolution = "ambiguous-catalogue-held"
            basis = "multiple catalogue USRs; no unique declaration selected"
        else:
            resolution = "unmapped-held"
            basis = "no exact catalogue identity or registry selector established"
        row["v3Evidence"] = {"resolution": resolution, "basis": basis, "sourceSnapshots": refs, "catalogueUsrChecks": usrs, "registryPromotion": False}
        rows.append(row)
    counts = {}
    for row in rows:
        key = row["v3Evidence"]["resolution"]
        counts[key] = counts.get(key, 0) + 1
    mapping = {
        "kind": "f12-extended-demand-source-evidence-v3",
        "version": 3,
        "status": "source-evidence-candidate-no-registry-promotion",
        "scope": "107-demand denominator preserved; exact source/USR evidence is recorded where available; service/platform ownership & unresolved demands remain held.",
        "denominator": {"extendedDemandRows": len(rows), "registryMappedRows": 0, "currentSourceUsageRows": 2, "sourceInventoryEvidenceRows": sum(1 for x in rows if x["v3Evidence"]["resolution"] == "source-inventory-only")},
        "resolutionCounts": counts,
        "preservation": {"v1CandidateSha256": sha(V1 / "mapping-candidate.json"), "v2CandidateSha256": sha(V2 / "current-source-candidate.json"), "v1Denominator": v1["denominator"], "v2Denominator": v2["denominator"], "registryPromotion": False},
        "inputs": {k: pin(ROOT / p) for k, p in {"demand": "factory/shell/demand.json", "inventory": "factory/shell/inventory.json", "catalogue": "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json", "registry": "factory/registry/evidence/block-registry.json", "v1Candidate": "factory/shell/extended-demand-mapping-v1/evidence/mapping-candidate.json", "v2Candidate": "factory/shell/extended-demand-mapping-v2/evidence/current-source-candidate.json", "v1SourceManifest": "factory/shell/extended-demand-mapping-v1/evidence/source-snapshot-manifest.json", "v2SourceManifest": "factory/shell/extended-demand-mapping-v2/evidence/source-snapshot-manifest.json"}.items()},
        "rows": rows,
    }
    raw_files = []
    for p in [ROOT / "factory/shell/demand.json", ROOT / "factory/shell/inventory.json", ROOT / "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json", ROOT / "factory/registry/evidence/block-registry.json", V1 / "mapping-candidate.json", V2 / "current-source-candidate.json", V1 / "source-snapshot-manifest.json", V2 / "source-snapshot-manifest.json"]:
        raw_files.append(pin(p))
    for manifest_root, manifest in ((V1, v1_manifest), (V2, v2_manifest)):
        for source in manifest["sources"]:
            raw_files.append(pin(snapshot_file(manifest_root, source["snapshotPath"])))
    raw = {"kind": "f12-extended-demand-source-evidence-v3-raw-pins", "mappingSha256": None, "files": raw_files, "catalogueUsrChecks": sum((x["v3Evidence"]["catalogueUsrChecks"] for x in rows), [])}
    out_mapping = OUT / "mapping-v3.json"
    out_raw = OUT / "raw-pins-v3.json"
    out_mapping.write_text(json.dumps(mapping, indent=2, sort_keys=True) + "\n")
    raw["mappingSha256"] = sha(out_mapping)
    out_raw.write_text(json.dumps(raw, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": "ok", "rows": len(rows), "resolutionCounts": counts, "mappingSha256": raw["mappingSha256"]}, indent=2))


if __name__ == "__main__":
    main()
