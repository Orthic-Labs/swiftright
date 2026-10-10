"""Build local Markdown and HTML reports from factory JSON artifacts."""

import argparse
import json
from pathlib import Path

from .report import build_report


def _load_json(path: str):
    with Path(path).open(encoding="utf-8") as source:
        return json.load(source)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True, help="block-registry JSON file")
    parser.add_argument("--cases", required=True, help="fixed case manifest JSON file")
    parser.add_argument("--captures", required=True, help="capture list or object JSON file")
    parser.add_argument("--verdicts", required=True, help="verdict list or object JSON file")
    parser.add_argument("--output-dir", required=True, help="local output directory")
    parser.add_argument("--demand", help="optional shell-demand JSON file")
    parser.add_argument("--gate-receipts", help="optional passing F10 gate receipt JSON file(s)")
    args = parser.parse_args(argv)
    build_report(
        _load_json(args.registry),
        _load_json(args.cases),
        _load_json(args.captures),
        _load_json(args.verdicts),
        args.output_dir,
        _load_json(args.demand) if args.demand else None,
        gate_receipts=_load_json(args.gate_receipts) if args.gate_receipts else None,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
