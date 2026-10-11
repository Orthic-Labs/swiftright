#!/usr/bin/env python3
"""Run owned-witness AX projection over explicit paired observations."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ax_projection_v1 import Hold, normalize  # noqa: E402

MAX_JSON = 8 * 1024 * 1024


def read_json(path: Path) -> dict:
    if path.is_symlink() or not path.is_file():
        raise Hold("input missing or symlink")
    if path.stat().st_size > MAX_JSON:
        raise Hold("input exceeds bounded JSON read")
    raw = path.read_bytes()
    if len(raw) > MAX_JSON:
        raise Hold("input exceeds bounded JSON read")
    try:
        value = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise Hold("input JSON invalid") from exc
    if not isinstance(value, dict):
        raise Hold("input JSON must be object")
    return value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        bundle = read_json(args.input)
        result = normalize(bundle)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (Hold, OSError) as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    print(json.dumps({"status": result["typedStatus"], "count": len(result["captures"]), "proofStatus": result["proofController"]["status"], "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
