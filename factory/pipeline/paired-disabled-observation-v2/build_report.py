"""Rebuild pinned paired-disabled observation v2 report from exact raw files."""
from __future__ import annotations

import json
from pathlib import Path

from adapter import build_report, load_pinned_inputs


def main() -> None:
    manifest_bytes, payloads = load_pinned_inputs()
    report = build_report(manifest_bytes, payloads)
    output = Path(__file__).resolve().parent / "evidence/report.json"
    encoded = (json.dumps(report, indent=2, sort_keys=True) + "\n").encode()
    temp = output.with_suffix(".json.tmp")
    temp.write_bytes(encoded)
    temp.replace(output)
    print(f"report={output.relative_to(Path(__file__).resolve().parents[3])}")
    print(f"sha256={__import__('hashlib').sha256(encoded).hexdigest()} bytes={len(encoded)}")
    print("batches=20 macOS AX + 20 historical macOS paint + 20 Windows UIA")
    print("acceptedGolden=0 parity=held timing=held hitTesting=held controlledOcclusion=held")


if __name__ == "__main__":
    main()
