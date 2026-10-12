#!/usr/bin/env python3
"""Bounded source controls for explicit ABI 0.6 RGBA image proposal."""
from __future__ import annotations
import argparse
from pathlib import Path

MAX = 128 * 1024

def read(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX:
        raise ValueError(f"bounded regular source required: {path}")
    return path.read_text(encoding="utf-8")

def validate(packet: Path) -> None:
    witness = read(packet / "witness-rgba.swift")
    asset = read(packet / "image-asset.swift")
    branch = read(packet / "image-render-branch.swift")
    recipe = read(packet / "rgba-recipe.json")
    if 'Image("factory.rgba.square.v1")' not in witness or "systemName" in witness:
        raise ValueError("RGBA witness must use named asset & exclude SF Symbol")
    for marker in ("sourceRGBA", "nearestUpsampledRGBA", "targetWidth = 32", "targetHeight = 32"):
        if marker not in asset:
            raise ValueError(f"asset recipe marker missing: {marker}")
    for marker in ("registerImage", "bridge.release", "ImageReference.named", "Primitive", "FactoryRGBAAsset.name"):
        if marker not in branch:
            raise ValueError(f"host branch marker missing: {marker}")
    if '"sourceToTarget": "nearest"' not in recipe or '"admission": "source-bound-RGBA-only; no-SF-Symbol-equivalence"' not in recipe:
        raise ValueError("sampling/admission recipe drift")

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--packet", type=Path, required=True)
    args = ap.parse_args(); validate(args.packet.resolve()); print("rgba-source-control-pass"); return 0

if __name__ == "__main__":
    raise SystemExit(main())
