#!/usr/bin/env python3
"""Create fresh Text NativeMeasurer source with exact system-font admission."""
from __future__ import annotations
import argparse, hashlib, json, os, stat
from pathlib import Path

MAX_SOURCE = 64 * 1024 * 1024
CHUNK = 1024 * 1024
OLD = """guard request.fontID == \"body\", request.fontMetadata == nil, request.lineLimit == nil,
                  Float(request.scale) == scale else { throw NSError(domain: \"FactoryUnsupportedMeasurementStyle\", code: 1) }"""
NEW = """let metadata = request.fontMetadata
            let expectedFont = Font.system(size: 24, weight: .regular, design: .default)
            guard metadata != nil,
                  request.fontID == expectedFont.id,
                  metadata?.familyName == nil,
                  metadata?.pointSize == 24,
                  metadata?.weight == .regular,
                  metadata?.design == .default,
                  metadata?.isCustom == false,
                  request.lineLimit == nil,
                  Float(request.scale) == scale else { throw NSError(domain: \"FactoryUnsupportedMeasurementStyle\", code: 1) }"""

def regular(path: Path) -> int:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        raise RuntimeError(f"regular non-symlink required: {path}")
    if st.st_size > MAX_SOURCE:
        raise RuntimeError(f"source exceeds {MAX_SOURCE} bytes: {path}")
    return st.st_size

def read_bounded(path: Path) -> tuple[str, int, str]:
    size = regular(path)
    h = hashlib.sha256()
    chunks: list[bytes] = []
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            total += len(chunk)
            if total > MAX_SOURCE:
                raise RuntimeError(f"source grew beyond bound: {path}")
            h.update(chunk)
            chunks.append(chunk)
    if total != size:
        raise RuntimeError(f"source changed while read: {path}")
    return b"".join(chunks).decode("utf-8"), total, h.hexdigest()

def write_fresh(path: Path, text: str) -> tuple[int, str]:
    if path.exists() or path.is_symlink():
        raise RuntimeError(f"fresh output required: {path}")
    data = text.encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)
    return len(data), hashlib.sha256(data).hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-main", required=True, type=Path)
    ap.add_argument("--output-main", required=True, type=Path)
    ap.add_argument("--source-root", required=True, type=Path)
    ns = ap.parse_args()
    source, source_bytes, source_hash = read_bounded(ns.input_main)
    if source.count(OLD) != 1:
        raise RuntimeError("expected exactly one legacy style guard")
    if "fontMetadata?.pointSize == 24" in source or "FactoryTextSystemStyleV1" in source:
        raise RuntimeError("style overlay already present")
    result = source.replace(OLD, NEW, 1)
    output_bytes, output_hash = write_fresh(ns.output_main, result)
    receipt = {
        "kind": "factory-text-measurer-style-overlay-v1",
        "sourceRoot": str(ns.source_root),
        "inputMain": str(ns.input_main),
        "inputBytes": source_bytes,
        "inputSha256": source_hash,
        "outputMain": str(ns.output_main),
        "outputBytes": output_bytes,
        "outputSha256": output_hash,
        "acceptedStyle": {"familyName": None, "pointSize": 24, "weight": "regular", "design": "default", "isCustom": False, "lineLimit": None},
        "rejectedStyles": ["legacy-body-without-metadata", "custom-family", "wrong-size", "wrong-weight", "wrong-design", "line-limit", "scale-drift"],
        "nativeActions": 0,
    }
    receipt_path = ns.output_main.with_name("text-measurer-style-overlay-receipt.json")
    write_fresh(receipt_path, json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": "staged-source-only", "output": str(ns.output_main), "receipt": str(receipt_path), "outputSha256": output_hash}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
