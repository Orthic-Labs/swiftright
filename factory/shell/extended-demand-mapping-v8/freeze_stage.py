from __future__ import annotations

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / "stage-manifest-v8.json"
SUM = HERE / "SHA256SUMS-v8.txt"
SKIP = {OUT.name, SUM.name}
files = []
for path in sorted(HERE.rglob("*")):
    if not path.is_file() or path.name in SKIP or "__pycache__" in path.parts or path.suffix == ".pyc":
        continue
    content = path.read_bytes()
    files.append({"path": path.relative_to(HERE).as_posix(), "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})

manifest = {
    "kind": "extended-demand-mapping-v8-stage",
    "version": "8",
    "status": "requirements-only",
    "denominator": 107,
    "rowCount": 107,
    "newFullDemandResolutions": 0,
    "registryPromotion": 0,
    "files": files,
    "dependencies": [
        {"path": "factory/shell/extended-demand-mapping-v7/mapping-v7-action-overlay.json", "sha256": hashlib.sha256((ROOT / "factory/shell/extended-demand-mapping-v7/mapping-v7-action-overlay.json").read_bytes()).hexdigest()},
        {"path": "factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json", "sha256": hashlib.sha256((ROOT / "factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json").read_bytes()).hexdigest()},
        {"path": "factory/registry/evidence/block-registry.json", "sha256": hashlib.sha256((ROOT / "factory/registry/evidence/block-registry.json").read_bytes()).hexdigest()},
    ],
}
OUT.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
SUM.write_text("".join(f"{item['sha256']}  {item['path']}\n" for item in files), encoding="utf-8")
print(json.dumps({"status": "PASS", "files": len(files), "bytes": sum(item["bytes"] for item in files)}))
