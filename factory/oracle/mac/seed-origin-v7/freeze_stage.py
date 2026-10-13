from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "stage-manifest.json"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    files = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path in {OUT, ROOT / "SHA256SUMS"} or "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        files.append({"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": sha(path)})
    manifest = {
        "kind": "seed-origin-v7-source-admission-stage",
        "seed": 14577611000270672472,
        "caseCount": 5,
        "captureStatus": "NOT_RUN",
        "files": files,
        "exclusions": ["__pycache__", "*.pyc", "capture outputs", "GUI/Accessibility capture"],
        "v6Admission": "admission/v6-admission-pins.json",
    }
    OUT.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    sums = ROOT / "SHA256SUMS"
    lines = [f"{row['sha256']}  {row['path']}" for row in files]
    lines.append(f"{sha(OUT)}  stage-manifest.json")
    sums.write_text("\n".join(lines) + "\n")
    print(json.dumps({"status": "PASS", "files": len(files), "bytes": sum(row["bytes"] for row in files), "manifestSha256": sha(OUT)}))


if __name__ == "__main__":
    main()
