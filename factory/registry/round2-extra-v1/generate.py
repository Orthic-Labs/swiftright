#!/usr/bin/env python3
"""Derive held Round 2 candidates from exact F1 catalogue paths.

This packet is source-bound identity evidence only. It never writes active
factory/registry/manifest.json or factory/registry/evidence/block-registry.json.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / "catalogue" / "evidence" / "catalogue.json"
ACTIVE_MANIFEST = ROOT / "registry" / "manifest.json"
ACTIVE_REGISTRY = ROOT / "registry" / "evidence" / "block-registry.json"

BLOCKS = [
    ("swiftui.popover", "Popover presentation", [
        "SwiftUI.View.popover(isPresented:attachmentAnchor:arrowEdge:content:)",
    ]),
    ("swiftui.animation.spring-interruption", "Spring animation interruption", [
        "SwiftUI.Animation.spring",
        "SwiftUI.withAnimation(_:_:)"],),
    ("swiftui.text-field-ime", "TextField IME editing", [
        "SwiftUI.TextField.init(text:prompt:label:)",
        "SwiftUI.TextField.init(text:prompt:axis:label:)"],),
    ("swiftui.environment-font-color-scheme", "Environment font and colour scheme", [
        "SwiftUI.View.environment(_:_:)" ,
        "SwiftUI.EnvironmentValues.font",
        "SwiftUI.EnvironmentValues.colorScheme"],),
    ("swiftui.context-menu", "Context menu presentation", [
        "SwiftUI.View.contextMenu(menuItems:)",
        "SwiftUI.View.contextMenu(menuItems:preview:)"],),
]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def load_json(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    return json.loads(raw), raw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, default=Path(__file__).with_name("candidate-manifest.json"))
    args = ap.parse_args()
    catalogue, cat_raw = load_json(CATALOGUE)
    active_manifest, active_manifest_raw = load_json(ACTIVE_MANIFEST)
    active_registry, active_registry_raw = load_json(ACTIVE_REGISTRY)
    if catalogue.get("kind") != "catalogue" or catalogue.get("version") != "0.1":
        raise SystemExit("invalid F1 catalogue")
    symbols = catalogue.get("symbols")
    if not isinstance(symbols, list): raise SystemExit("catalogue symbols missing")
    by_path: dict[str, list[dict]] = {}
    for item in symbols:
        if not isinstance(item, dict): raise SystemExit("non-object catalogue symbol")
        by_path.setdefault(item.get("path"), []).append(item)
    blocks = []
    for block_id, title, paths in BLOCKS:
        entries = []
        for path in paths:
            matches = by_path.get(path, [])
            if len(matches) != 1:
                raise SystemExit(f"{block_id}: expected one exact path match for {path!r}, got {len(matches)}")
            item = matches[0]
            if item.get("status") == "hidden": raise SystemExit(f"{block_id}: hidden {path}")
            if not isinstance(item.get("usr"), str) or not item["usr"]:
                raise SystemExit(f"{block_id}: missing USR {path}")
            entries.append({
                "selector": "usr:" + item["usr"],
                "path": path,
                "catalogueStatus": item.get("status"),
                "symbolEvidenceSha256": sha(canonical(item)),
            })
        blocks.append({
            "id": block_id,
            "round": 2,
            "title": title,
            "candidateStatus": "held-candidate",
            "coverageStatus": "identity-only",
            "nativeCoverage": "unsupported",
            "registryPromotion": False,
            "semanticDependencies": [],
            "dependencyBasis": "none-proven; recipe owner must provide a separate source-bound join",
            "symbols": entries,
            "unsupportedClaims": ["no native recipe", "no behavioral parity", "no qualification", "no active registry membership"],
        })
    out = {
        "kind": "round2-extra-candidate-manifest",
        "version": "0.1",
        "id": "swiftui-pilot-round2-extra-candidates-v1",
        "status": "held-source-bound-candidates",
        "activeRegistryMutation": False,
        "catalogue": {"path": "factory/catalogue/evidence/catalogue.json", "sha256": sha(cat_raw), "symbolCount": len(symbols)},
        "activeManifest": {"path": "factory/registry/manifest.json", "sha256": sha(active_manifest_raw), "blockIds": [b.get("id") for b in active_manifest.get("blocks", [])]},
        "activeRegistry": {"path": "factory/registry/evidence/block-registry.json", "sha256": sha(active_registry_raw), "blockIds": [b.get("id") for b in active_registry.get("blocks", [])]},
        "selectionRule": "Each path resolves to exactly one non-hidden catalogue symbol; emitted selector is exact usr:<USR> from that item.",
        "blocks": blocks,
        "recipeOwner": "factory/recipes/round2-extra-v1",
        "promotionRule": "Do not promote from this packet; candidate recipes require independent source, request, and behavioral evidence.",
    }
    args.output.write_bytes(canonical(out))
    print(json.dumps({"output": str(args.output), "sha256": sha(args.output.read_bytes()), "blocks": len(blocks), "symbols": sum(len(b["symbols"]) for b in blocks)}, sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
