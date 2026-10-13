#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
EVIDENCE = HERE / "external-owner-evidence-v2.json"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_TARGETS = {
    "Foundation.AttributedString", "Foundation.AttributeDynamicLookup", "Foundation.AttributeScopes", "Foundation.FormatStyle",
    "Foundation.NSUserActivity", "Foundation.NSUserActivity.TypedPayloadError", "Observation.Observable",
    "DeveloperToolsSupport.Preview", "DeveloperToolsSupport.PreviewTrait", "AppKit.NSAnimationContext",
    "AppKit.NSApplication", "AppKit.NSColor", "AppKit.NSControl", "AppKit.NSControl.ControlSize",
    "AppKit.NSDirectionalEdgeInsets", "AppKit.NSUnderlineStyle", "AppKit.NSWindow", "Combine.ObservableObject",
    "CoreFoundation.CGFloat", "CoreFoundation.CGPoint", "CoreFoundation.CGSize", "CoreFoundation.CGRect",
    "Spatial.Size3D", "Symbols.WiggleSymbolEffect",
}

def sha(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()

def check(ok: bool, msg: str) -> None:
    if not ok:
        raise AssertionError(msg)

def main() -> None:
    check(sha(LINK.read_bytes()) == EXPECTED_LINK, "immutable 836 changed")
    d = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    check(d["status"] == "raw-facts-only-no-eligibility-conclusion", "unexpected status")
    check(not any(k in json.dumps(d).lower() for k in ("eligible", "promotion")), "eligibility claim leaked")
    rows = d["targets"]
    check({x["target"] for x in rows} == EXPECTED_TARGETS, "target set changed")
    check(len(rows) == len(EXPECTED_TARGETS), "target cardinality changed")
    raw = ROOT / next(x["path"] for x in [d["toolchain"]["sourcekitIndex"]["output"]])
    raw_text = raw.read_text(encoding="utf-8")
    for row in rows:
        owner = row["ownerSource"]
        for source in owner["records"]:
            p = ROOT / source["path"]
            check(sha(p.read_bytes()) == source["sha256"], f"source changed: {p}")
            check(p.read_text(encoding="utf-8", errors="replace").splitlines()[source["line"] - 1] == source["text"], f"source line changed: {p}:{source['line']}")
        for source in row["swiftUIExtensionSources"]:
            p = ROOT / source["path"]
            check(sha(p.read_bytes()) == source["sha256"], f"SwiftUI source changed: {p}")
        ref = row["probeJoin"]["sourceKitReference"]
        check(ref is not None, f"missing compiler USR: {row['target']}")
        check(ref["usr"] in raw_text, f"USR absent raw output: {row['target']}")
        check(row["probeJoin"]["sourceSha256"] == sha((ROOT / row["probeJoin"]["source"]).read_bytes()), f"probe changed: {row['target']}")
    spatial = next(x for x in rows if x["target"] == "Spatial.Size3D")
    check(spatial["ownerSource"]["status"] == "exact-source-record", "Spatial Clang source missing")
    check(d["toolchain"]["swiftcTypecheck"]["exit"] == 0, "typecheck exit changed")
    check(d["toolchain"]["sourcekitIndex"]["exit"] == 0, "SourceKit exit changed")
    print(f"PASS targets={len(rows)} exact_usrs={sum(x['probeJoin']['sourceKitReference'] is not None for x in rows)} clang_spatial={spatial['ownerSource']['records'][0]['path']}")

if __name__ == "__main__":
    main()
