#!/usr/bin/env python3
"""Emit fresh Text host source admitting only measured system-primary paint."""
from __future__ import annotations
import argparse, hashlib, json, os, stat
from pathlib import Path

MAX_SOURCE = 64 * 1024 * 1024
CHUNK = 1024 * 1024
OLD_STYLE = '''guard request.fontID == "body", request.fontMetadata == nil, request.lineLimit == nil,
                  Float(request.scale) == scale else { throw NSError(domain: "FactoryUnsupportedMeasurementStyle", code: 1) }'''
NEW_STYLE = '''let metadata = request.fontMetadata
            let expectedFont = Font.system(size: 24, weight: .regular, design: .default)
            guard metadata != nil,
                  request.fontID == expectedFont.id,
                  metadata?.familyName == nil,
                  metadata?.pointSize == 24,
                  metadata?.weight == .regular,
                  metadata?.design == .default,
                  metadata?.isCustom == false,
                  request.lineLimit == nil,
                  Float(request.scale) == scale else { throw NSError(domain: "FactoryUnsupportedMeasurementStyle", code: 1) }'''
OLD_PAINT = 'guard n.style.foreground == nil, n.opacity == 1 else { throw NSError(domain: "FactoryUnsupportedTextPaintStyle", code: 1) }'
NEW_PAINT = '''_ = try factoryTextPaint(n.style.foreground, opacity: n.opacity)'''
PAINT_HELPER = '''func factoryTextPaint(_ foreground: ResolvedColor?, opacity: Double) throws -> UInt32 {
    // Bridge color contract is packed RGBA8: label -> 0x1f1f1fff (alpha 0xff).
    guard opacity.isFinite, opacity == 1 else {
        throw NSError(domain: "FactoryUnsupportedTextPaintStyle", code: 1)
    }
    guard let foreground, case .semantic("label") = foreground else {
        throw NSError(domain: "FactoryUnsupportedTextPaintStyle", code: 1)
    }
    return 0x1f1f1fff
}
'''

def regular(path: Path) -> int:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
        raise RuntimeError(f"regular non-symlink required: {path}")
    if st.st_size > MAX_SOURCE:
        raise RuntimeError(f"source exceeds {MAX_SOURCE} bytes: {path}")
    return st.st_size

def read_bounded(path: Path) -> tuple[str, int, str]:
    size = regular(path)
    digest = hashlib.sha256()
    chunks: list[bytes] = []
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            total += len(chunk)
            if total > MAX_SOURCE:
                raise RuntimeError(f"source grew beyond bound: {path}")
            digest.update(chunk)
            chunks.append(chunk)
    if total != size:
        raise RuntimeError(f"source changed while read: {path}")
    data = b"".join(chunks)
    return data.decode("utf-8"), total, digest.hexdigest()

def write_fresh(path: Path, data: bytes) -> tuple[int, str]:
    if path.exists() or path.is_symlink():
        raise RuntimeError(f"fresh output required: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)
    return len(data), hashlib.sha256(data).hexdigest()

def transform(source: str) -> str:
    """Pure source transform used by staging & source mutation controls."""
    if source.count(OLD_STYLE) != 1:
        raise RuntimeError("expected exactly one legacy measurement guard")
    if source.count(OLD_PAINT) != 1:
        raise RuntimeError("expected exactly one legacy text paint guard")
    if "factoryTextPaint(_ foreground:" in source or "FactoryTextPaintDefaultV1" in source:
        raise RuntimeError("text paint overlay already present")
    result = source.replace(OLD_STYLE, NEW_STYLE, 1)
    helper_at = result.find("func factoryResolvedFill")
    if helper_at < 0:
        raise RuntimeError("expected FactoryProbe fill helper anchor")
    result = result[:helper_at] + PAINT_HELPER + result[helper_at:]
    return result.replace(OLD_PAINT, NEW_PAINT, 1)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-main", required=True, type=Path)
    ap.add_argument("--output-main", required=True, type=Path)
    ap.add_argument("--source-root", required=True, type=Path)
    ns = ap.parse_args()
    source, source_bytes, source_hash = read_bounded(ns.input_main)
    result = transform(source)
    output_bytes, output_hash = write_fresh(ns.output_main, result.encode("utf-8"))
    receipt = {
        "kind": "factory-text-paint-default-overlay-v1",
        "sourceRoot": str(ns.source_root),
        "inputMain": str(ns.input_main), "inputBytes": source_bytes, "inputSha256": source_hash,
        "outputMain": str(ns.output_main), "outputBytes": output_bytes, "outputSha256": output_hash,
        "acceptedFont": {"fontID": "Font.system(size:24,weight:regular,design:default).id", "familyName": None, "pointSize": 24, "weight": "regular", "design": "default", "isCustom": False, "lineLimit": None},
        "acceptedPaint": {"semantic": "label", "swiftUIOrigin": "Color.primary", "packedRGBA8": "0x1f1f1fff", "red": 31, "green": 31, "blue": 31, "alpha": 255, "opacity": 1},
        "rejectedPaint": ["nil", "semantic-secondaryLabel", "semantic-system.red", "rgba-custom", "opacity-drift"],
        "nativeActions": 0, "compilerActions": 0,
    }
    receipt_data = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode("utf-8")
    receipt_path = ns.output_main.with_name("text-paint-default-overlay-receipt.json")
    write_fresh(receipt_path, receipt_data)
    print(json.dumps({"status": "staged-source-only", "output": str(ns.output_main), "receipt": str(receipt_path), "outputSha256": output_hash}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
