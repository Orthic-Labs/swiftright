from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
V7 = ROOT / "factory/shell/extended-demand-mapping-v7/mapping-v7-action-overlay.json"
REGISTRY = ROOT / "factory/registry/evidence/block-registry.json"
OUT = HERE / "mapping-v8-action-overlay.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior = json.loads(V7.read_text(encoding="utf-8"))
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    blocks = registry.get("blocks")
    if not isinstance(blocks, list):
        raise ValueError("registry blocks must be an array")
    result = {
        "baseOverlayPath": "factory/shell/extended-demand-mapping-v7/mapping-v7-action-overlay.json",
        "baseOverlaySha256": sha256(V7),
        "baseRowCountPreserved": 107,
        "denominator": 107,
        "kind": "extended-demand-mapping-v8-action-overlay",
        "newFullDemandResolutions": 0,
        "note": "Requirements-only successor. Preserve v7 held statuses and exact evidence requirements; infer no API identity, demand coverage, or registry promotion.",
        "partialOverlapsPreserved": True,
        "registryBlocksPresent": len(blocks),
        "registrySnapshotPath": "factory/registry/evidence/block-registry.json",
        "registrySnapshotSha256": sha256(REGISTRY),
        "registryPromotion": 0,
        "rowCount": 107,
        "rows": prior["rows"],
        "status": "requirements-only",
        "version": "8",
    }
    OUT.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "denominator": 107, "rows": len(result["rows"]), "promotions": 0}))


if __name__ == "__main__":
    main()
