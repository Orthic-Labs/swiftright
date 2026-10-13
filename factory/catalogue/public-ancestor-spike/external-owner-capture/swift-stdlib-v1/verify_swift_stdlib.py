#!/usr/bin/env python3
"""Verify Swift stdlib-v1 capture without making an eligibility decision."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
EVIDENCE = HERE / "swift-stdlib-evidence.json"
SWIFT = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface")
SWIFTUI = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface")
SWIFTUICORE = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface")
RAW = HERE / "raw/swift-stdlib-targets.index.txt"

EXPECTED = ["Optional", "Never", "Float", "Double", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "RangeReplaceableCollection", "MutableCollection"]
KINDS = {"Optional": "enum", "Never": "enum", "Float": "struct", "Double": "struct", "Int": "struct", "Int8": "struct", "Int16": "struct", "Int32": "struct", "Int64": "struct", "UInt": "struct", "UInt8": "struct", "UInt16": "struct", "UInt32": "struct", "UInt64": "struct", "RangeReplaceableCollection": "protocol", "MutableCollection": "protocol"}

def sha(data: bytes | str) -> str:
    if isinstance(data, str): data = data.encode()
    return "sha256:" + hashlib.sha256(data).hexdigest()

def fsha(path: Path) -> str: return sha(path.read_bytes())
def lines(path: Path) -> list[str]: return path.read_text(encoding="utf-8", errors="replace").splitlines()
def rel(path: Path) -> str: return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)

def conditions(path: Path, through: int) -> list[str]:
    stack: list[str] = []
    for line in lines(path)[:through - 1]:
        s = line.strip()
        if s.startswith("#if "): stack.append(s)
        elif s.startswith("#elseif ") and stack: stack[-1] = s
        elif s == "#else" and stack: stack[-1] = s
        elif s == "#endif" and stack: stack.pop()
    return stack

def refs() -> list[dict]:
    pat = re.compile(r"\{\n\s+key\.kind: ([^,\n]+),\n\s+key\.name: \"([^\"]+)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)")
    return [{"kind": k.strip(), "name": n, "usr": u, "line": int(l), "column": int(c)} for k, n, u, l, c in pat.findall(RAW.read_text())]

def main() -> None:
    d = json.loads(EVIDENCE.read_text())
    assert d["status"] == "raw-facts-only-no-eligibility-conclusion"
    assert [t["target"].removeprefix("Swift.") for t in d["targets"]] == EXPECTED
    swift_lines = lines(SWIFT)
    for target in d["targets"]:
        name = target["target"].removeprefix("Swift.")
        owner = target["ownerSource"]
        decl = owner["declaration"]
        assert owner["module"] == "Swift" and owner["kind"] == KINDS[name]
        assert owner["access"] == "public" and owner["readAccess"] == "public"
        assert owner["enclosingNominalScopes"] == [] and owner["scopeLines"] == []
        assert decl["path"] == rel(SWIFT) and decl["sha256"] == fsha(SWIFT)
        assert decl["text"] == swift_lines[decl["line"] - 1]
        assert decl["conditions"] == conditions(SWIFT, decl["line"])
        ex = target["extensionEvidence"]
        assert {s["module"] for s in ex["sources"]} == {"SwiftUI", "SwiftUICore"}
        assert ex["sources"][0]["sha256"] == fsha(SWIFTUI) and ex["sources"][1]["sha256"] == fsha(SWIFTUICORE)
        for rec in ex["records"]:
            p = Path(rec["path"]); source_lines = lines(p)
            assert rec["text"] == source_lines[rec["line"] - 1]
            assert rec["conditions"] == conditions(p, rec["line"])
        join = target["sourceKitReference"]
        assert join["probe"]["path"].endswith("probes/swift-stdlib-targets.swift")
        rec = join["record"]
        assert rec and rec["name"] == name and rec["line"] == join["probe"]["line"]
        assert rec["kind"] == "source.lang.swift.ref." + KINDS[name]
        assert any(r == rec for r in refs())
    assert d["inputs"]["swiftInterface"]["sha256"] == fsha(SWIFT)
    assert d["inputs"]["uiCoreInterfaces"][0]["sha256"] == fsha(SWIFTUI)
    assert d["inputs"]["uiCoreInterfaces"][1]["sha256"] == fsha(SWIFTUICORE)
    for section in d["toolchain"].values():
        if isinstance(section, dict):
            for key in ("stdout", "stderr", "input", "request", "output"):
                pin = section.get(key)
                if pin and "path" in pin: assert sha((ROOT / pin["path"]).read_bytes()) == pin["sha256"]
            if "path" in section: assert sha(Path(section["path"]).read_bytes()) == section["sha256"]
    demangled = (HERE / "receipts/demangle.stdout").read_text().splitlines()
    assert demangled == ["Swift." + n for n in EXPECTED]
    print(f"swift-stdlib-v1 verification: {len(EXPECTED)} targets; {len(EXPECTED)} exact SourceKit USRs; {sum(len(t['extensionEvidence']['records']) for t in d['targets'])} UI/Core extension rows; owner ancestry/access/conditions/attrs pinned")

if __name__ == "__main__": main()
