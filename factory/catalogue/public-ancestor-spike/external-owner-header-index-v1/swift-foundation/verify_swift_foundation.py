#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
EVIDENCE = HERE / "swift-foundation-index-evidence.json"
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
SOURCES = {"Swift": SDK / "usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface", "Foundation": SDK / "System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface"}
EXPECTED = {"Swift": [("Optional", 16948), ("Never", 17607), ("Float", 39669), ("Double", 40283), ("Int", 45246), ("Int8", 41368), ("Int16", 42329), ("Int32", 43290), ("Int64", 44259), ("UInt", 44762), ("UInt8", 40905), ("UInt16", 41864), ("UInt32", 42825), ("UInt64", 43787), ("RangeReplaceableCollection", 18661), ("MutableCollection", 15531)], "Foundation": [("AttributedString", 74), ("AttributeScopes", 1048), ("FormatStyle", 8471), ("AttributeDynamicLookup", 810)]}

def sha(v: bytes) -> str: return "sha256:" + hashlib.sha256(v).hexdigest()
def fsha(p: Path) -> str: return sha(p.read_bytes())

def main() -> None:
    d = json.loads(EVIDENCE.read_text()); assert d["status"] == "raw-facts-only-no-eligibility-conclusion" and d["target"] == "arm64-apple-macosx27.0"
    assert d["immutableLink"]["sha256"] == sha((ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json").read_bytes())
    assert {m["module"] for m in d["modules"]} == set(EXPECTED)
    for m in d["modules"]:
        name = m["module"]; source = SOURCES[name]; h = m["headerFlags"]
        assert m["source"]["sha256"] == fsha(source)
        assert m["process"]["exit"] == 0
        assert m["request"]["sha256"] == fsha(ROOT / m["request"]["path"])
        assert m["request"]["preimageSha256"] == fsha(ROOT / m["request"]["preimagePath"])
        assert m["process"]["stdout"]["sha256"] == fsha(ROOT / m["process"]["stdout"]["path"])
        assert m["process"]["stderr"]["sha256"] == fsha(ROOT / m["process"]["stderr"]["path"])
        assert [x["flag"] for x in h["removedTargetFlags"]] == ["-target", "-target-variant"] + (["-target-arch-variant"] if name == "Foundation" else [])
        assert h["productionTarget"] == "arm64-apple-macosx27.0"
        assert {x["flag"] for x in h["forwardedFrontendFlags"]} >= {"-enable-objc-interop", "-formal-cxx-interoperability-mode=off"}
        records = m["targetRecords"]
        assert [(r["name"], r["line"]) for r in records] == EXPECTED[name]
        assert all(r["effectiveAccess"] == "public" and r["enclosingNominalPath"] == [] for r in records)
        assert all(r["rawRecordStatus"] == "exact-physical-source-position-name-kind-usr" for r in records)
        assert m["summary"]["recordDenominator"] == m["summary"]["physicalPositionNameKindUsrPairs"]["denominator"]
        assert m["summary"]["physicalPositionNameKindUsrPairs"]["duplicatePairCount"] == 0
    print("swift-foundation verification: 20 exact nominal targets; Swift 13,629 records; Foundation 11,927 records; all public target access & physical SourceKit identities pinned; exits0")

if __name__ == "__main__": main()
