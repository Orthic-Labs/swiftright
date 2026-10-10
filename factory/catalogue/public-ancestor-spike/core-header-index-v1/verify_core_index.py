#!/usr/bin/env python3
"""Verify frozen Core header-index capture & diagnostic counts."""
from __future__ import annotations
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EVIDENCE = HERE / "core-header-index-evidence.json"
SOURCE = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface")
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
RAW = HERE / "sourcekit-index-core-header.stdout"

def sha(v: bytes) -> str: return "sha256:" + hashlib.sha256(v).hexdigest()
def fsha(p: Path) -> str: return sha(p.read_bytes())

def main() -> None:
    d = json.loads(EVIDENCE.read_text())
    assert d["status"] == "raw-facts-only-no-eligibility-conclusion"
    assert d["source"]["sha256"] == fsha(SOURCE) == "sha256:4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13"
    assert d["source"]["immutableLink"]["sha256"] == fsha(LINK) == "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
    h = d["headerFlags"]
    assert [x["flag"] for x in h["removedTargetFlags"]] == ["-target", "-target-variant", "-target-arch-variant"]
    assert h["productionTarget"] == "arm64-apple-macosx27.0"
    assert h["moduleABIName"] == h["publicModuleName"] == "SwiftUI"
    assert h["moduleNameFromHeader"] == "SwiftUICore"
    assert {x["flag"] for x in h["forwardedFrontendFlags"]} == {"-enable-objc-interop", "-formal-cxx-interoperability-mode=off"}
    assert d["response"]["exit"] == 0 and d["response"]["stdout"]["sha256"] == fsha(RAW)
    s = d["summary"]
    assert (s["recordDenominator"], s["publicEffectiveAccessFieldCount"], s["publicAttributeFieldCount"]) == (8506, 7515, 8709)
    assert s["physicalPositionNameKindUsrPairs"] == {"denominator": 8506, "unique": 8506, "duplicatePairCount": 0}
    assert s["nominalUsrPrefixCounts"]["SwiftUI"] == 650 and s["nominalUsrPrefixCounts"]["SwiftUICore"] == 0
    assert s["varUsrPrefixCounts"]["SwiftUI"] == 1679 and s["varUsrPrefixCounts"]["SwiftUICore"] == 0
    raw = RAW.read_text()
    assert len(re.findall(r"key\.kind: source\.lang\.swift\.decl\.[^,\n]+,\n\s+key\.name: \"[^\"]*\",\n\s+key\.usr: \"[^\"]+\",\n\s+key\.line: \d+,\n\s+key\.column: \d+", raw)) == 8506
    assert json.loads((HERE / "attempts/initial-failed.json").read_text())["exit"] == 1
    print("core-header-index-v1 verification: exit0; 8506 records; 7515 effective-public; 8709 public attributes; 8506 unique physical pairs; ABI SwiftUI nominal/var prefixes pinned; initial exit1 preserved")

if __name__ == "__main__": main()
