#!/usr/bin/env python3
"""Build the immutable-input, observational-only three-case report."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from adapter import build_report, load_pinned_inputs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    manifest, payloads = load_pinned_inputs(args.repo)
    report = build_report(manifest, payloads)
    encoded = (json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    output = args.output or Path(__file__).resolve().parent / "evidence" / "report-v1.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(encoded)
    print(json.dumps({
        "status": report["status"],
        "caseCount": report["caseCount"],
        "MacRunsPerCase": report["denominators"]["MacRunsPerCase"],
        "WindowsRunsPerCase": report["denominators"]["WindowsRunsPerCase"],
        "output": str(output),
        "bytes": len(encoded),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
