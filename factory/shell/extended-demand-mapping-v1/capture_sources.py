"""Capture exact source files referenced by pinned F12 inventory."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = HERE / "evidence/source-snapshots"
if OUT.exists() and any(OUT.iterdir()):
    raise SystemExit("source snapshot directory is non-empty; preserve existing capture")
inventory_path = ROOT / "factory/shell/inventory.json"
inventory = json.loads(inventory_path.read_bytes())
records = inventory["evidence"]
paths = sorted({row["path"] for row in records})
OUT.mkdir(parents=True, exist_ok=True)
manifest_rows = []
for index, source_path in enumerate(paths, 1):
    raw = Path(source_path).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    name = f"source-{index:02d}-{digest[:16]}.bin"
    (OUT / name).write_bytes(raw)
    manifest_rows.append({
        "sourcePath": source_path,
        "snapshotPath": f"evidence/source-snapshots/{name}",
        "bytes": len(raw),
        "sha256": digest,
        "inventoryEvidenceIds": sorted(row["id"] for row in records if row["path"] == source_path),
    })
manifest = {
    "kind": "f12-source-inventory-source-snapshot",
    "version": 1,
    "inventoryPath": "factory/shell/inventory.json",
    "inventorySha256": hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
    "sourceCount": len(manifest_rows),
    "sources": manifest_rows,
}
manifest_path = HERE / "evidence/source-snapshot-manifest.json"
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({"sources": len(manifest_rows), "manifestPath": str(manifest_path), "manifestSha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(), "totalBytes": sum(row["bytes"] for row in manifest_rows)}, sort_keys=True))
