#!/usr/bin/env python3
"""Bounded source controls for Image provider hold; never compiles or captures."""
from __future__ import annotations
import argparse
from pathlib import Path

MAX = 128 * 1024

def text(root: Path, rel: str) -> str:
    path = root / rel
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX:
        raise ValueError(f"bounded regular source required: {rel}")
    return path.read_text(encoding="utf-8")

def validate(root: Path, *, symbol: str = "star.fill", require_provider: bool = False) -> None:
    witness = text(root, "factory/pipeline/pilot-next-source-v1/image-baseline-v1/witness.swift")
    recipe = text(root, "factory/pipeline/pilot-next-source-v1/image-baseline-v1/recipe.json")
    plan = text(root, "factory/native/windows/remaining-five-hosts-v2/image/package/plan.json")
    renderer = text(root, "factory/native/windows/remaining-five-hosts-v2/image/package/Sources/FactoryProbe/main.swift")
    bridge = text(root, "factory/native/windows/remaining-five-hosts-v2/dependencies/staged-bridge-inputs-r09/Sources/SwiftRightBridge/Bridge.swift")
    if f'Image(systemName: "{symbol}")' not in witness or '"symbol": "star.fill"' not in recipe:
        raise ValueError("Image recipe/witness symbol join mismatch")
    if "swr_image_register" not in bridge or "swr_image_release" not in bridge:
        raise ValueError("ABI 0.6 image register/release evidence missing")
    if require_provider and "sfSymbolProvider" not in plan:
        raise ValueError("SF Symbol provider admission required")
    if "case \"Image\"" in renderer and "sfSymbolProvider" not in plan:
        raise ValueError("renderer Image branch lacks source-bound provider")
    if not require_provider and "sfSymbolProvider" in plan:
        raise ValueError("provider claim must not be inferred from hold plan")

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--root", type=Path, required=True); ap.add_argument("--fault", choices=["wrong-symbol", "provider-claim", "renderer-branch"])
    args = ap.parse_args(); root = args.root.resolve()
    if args.fault == "wrong-symbol":
        validate(root, symbol="heart.fill")
    elif args.fault == "provider-claim":
        validate(root, require_provider=True)
    elif args.fault == "renderer-branch":
        renderer = text(root, "factory/native/windows/remaining-five-hosts-v2/image/package/Sources/FactoryProbe/main.swift")
        if "case \"Image\"" not in renderer:
            raise ValueError("renderer Image branch absent")
    else:
        validate(root)
    print("source-control-pass")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
