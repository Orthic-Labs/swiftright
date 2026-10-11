from __future__ import annotations

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / "stage-manifest-v5.json"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    files = []
    for path in sorted(HERE.rglob("*")):
        if not path.is_file() or path == OUT or path.name == "SHA256SUMS-v5.txt" or "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        files.append({"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": digest(path)})
    dependencies = []
    for rel in [
        "factory/shell/extended-demand-mapping-v4/mapping-v4.json",
        "factory/shell/extended-demand-mapping-v4/stage-manifest-v4.json",
    ]:
        path = ROOT / rel
        dependencies.append({"path": rel, "bytes": path.stat().st_size, "sha256": digest(path)})
    manifest = {
        "kind": "v5-source-bound-observation-stage",
        "denominator": 107,
        "registryPromotion": False,
        "newFullDemandResolutions": 0,
        "files": files,
        "dependencies": dependencies,
        "exclusions": ["__pycache__", "*.pyc", "no external SDK/tool bytes"],
    }
    OUT.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    sums = HERE / "SHA256SUMS-v5.txt"
    lines = [f"{item['sha256']}  {item['path']}" for item in files]
    lines.append(f"{digest(OUT)}  {OUT.relative_to(ROOT)}")
    sums.write_text("\n".join(lines) + "\n")
    print(json.dumps({"files": len(files), "bytes": sum(x["bytes"] for x in files), "manifest": digest(OUT), "maxBytes": max(x["bytes"] for x in files)}))


if __name__ == "__main__":
    main()
