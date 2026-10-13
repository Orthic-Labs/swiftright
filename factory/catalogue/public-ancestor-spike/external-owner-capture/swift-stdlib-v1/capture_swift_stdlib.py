#!/usr/bin/env python3
"""Capture raw, source-bound facts for Swift standard-library nominal owners."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
SWIFT = SDK / "usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
SWIFTUI = SDK / "System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
SWIFTUICORE = SDK / "System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
PROBE = HERE / "probes/swift-stdlib-targets.swift"
REQUEST = HERE / "requests/swift-stdlib-targets.yaml"
RAW = HERE / "raw/swift-stdlib-targets.index.txt"
SWIFTC_STDOUT = HERE / "receipts/swiftc.stdout"
SWIFTC_STDERR = HERE / "receipts/swiftc.stderr"
SK_STDERR = HERE / "receipts/sourcekit.stderr"
DEMANGLE_STDOUT = HERE / "receipts/demangle.stdout"
DEMANGLE_STDERR = HERE / "receipts/demangle.stderr"
DEMANGLE_INPUT = HERE / "receipts/demangle.input.txt"
TARGET = "arm64-apple-macosx27.0"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"

TARGETS = [
    ("Optional", "enum", 3, "Optional"), ("Never", "enum", 4, "Never"),
    ("Float", "struct", 5, "Float"), ("Double", "struct", 6, "Double"),
    ("Int", "struct", 7, "Int"), ("Int8", "struct", 8, "Int8"),
    ("Int16", "struct", 9, "Int16"), ("Int32", "struct", 10, "Int32"),
    ("Int64", "struct", 11, "Int64"), ("UInt", "struct", 12, "UInt"),
    ("UInt8", "struct", 13, "UInt8"), ("UInt16", "struct", 14, "UInt16"),
    ("UInt32", "struct", 15, "UInt32"), ("UInt64", "struct", 16, "UInt64"),
    ("RangeReplaceableCollection", "protocol", 17, "RangeReplaceableCollection"),
    ("MutableCollection", "protocol", 18, "MutableCollection"),
]

def sha(value: bytes | str) -> str:
    if isinstance(value, str): value = value.encode()
    return "sha256:" + hashlib.sha256(value).hexdigest()

def fsha(path: Path) -> str:
    return sha(path.read_bytes())

def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)

def file_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()

def source_record(path: Path, line: int, role: str, conditions: list[str] | None = None) -> dict:
    lines = file_lines(path)
    return {"role": role, "path": rel(path), "sha256": fsha(path), "line": line,
            "text": lines[line - 1], "conditions": conditions or []}

def active_conditions(lines: list[str], through: int) -> list[str]:
    stack: list[str] = []
    for line in lines[:through - 1]:
        s = line.strip()
        if s.startswith("#if "): stack.append(s)
        elif s.startswith("#elseif ") and stack: stack[-1] = s
        elif s == "#else" and stack: stack[-1] = s
        elif s == "#endif" and stack: stack.pop()
    return stack

def source_owner(name: str) -> dict:
    lines = file_lines(SWIFT)
    patterns = {
        "Optional": r"^@frozen public enum Optional<",
        "Never": r"^@frozen public enum Never\b",
        "Float": r"^@frozen public struct Float\b",
        "Double": r"^@frozen public struct Double\b",
        "Int": r"^@frozen public struct Int :",
        "Int8": r"^@frozen public struct Int8 :",
        "Int16": r"^@frozen public struct Int16 :",
        "Int32": r"^@frozen public struct Int32 :",
        "Int64": r"^@frozen public struct Int64 :",
        "UInt": r"^@frozen public struct UInt :",
        "UInt8": r"^@frozen public struct UInt8 :",
        "UInt16": r"^@frozen public struct UInt16 :",
        "UInt32": r"^@frozen public struct UInt32 :",
        "UInt64": r"^@frozen public struct UInt64 :",
        "RangeReplaceableCollection": r"^public protocol RangeReplaceableCollection<",
        "MutableCollection": r"^public protocol MutableCollection<",
    }
    matches = [i for i, line in enumerate(lines, 1) if re.search(patterns[name], line)]
    if len(matches) != 1: raise RuntimeError(f"owner declaration count {name}: {matches}")
    line_no = matches[0]
    text = lines[line_no - 1]
    attrs = re.findall(r"@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?", text.split("public", 1)[0])
    return {
        "module": "Swift", "nominal": name, "kind": next(k for n, k, _, _ in TARGETS if n == name),
        "access": "public", "readAccess": "public", "attributes": attrs, "enclosingNominalScopes": [],
        "scopeLines": [], "conditions": active_conditions(lines, line_no),
        "declaration": source_record(SWIFT, line_no, "top-level-nominal-declaration", active_conditions(lines, line_no)),
        "status": "exact-source-record-top-level",
    }

def extension_records(path: Path, qualified: str) -> list[dict]:
    lines = file_lines(path)
    return [source_record(path, i, "external-owner-extension-header", active_conditions(lines, i))
            for i, line in enumerate(lines, 1) if re.match(r"^extension " + re.escape(qualified) + r"(?:[ :]|$)", line)]

def parse_refs(raw: str) -> list[dict]:
    pat = re.compile(r"\{\n\s+key\.kind: ([^,\n]+),\n\s+key\.name: \"([^\"]+)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)")
    return [{"kind": k.strip(), "name": n, "usr": u, "line": int(line), "column": int(col)}
            for k, n, u, line, col in pat.findall(raw)]

def sourcekit_ref(name: str, line: int) -> dict | None:
    matches = [r for r in parse_refs(RAW.read_text(encoding="utf-8")) if r["name"] == name and r["line"] == line and r["kind"].startswith("source.lang.swift.ref.")]
    return matches[0] if len(matches) == 1 else None

def tool(path: Path) -> dict:
    return {"path": str(path), "sha256": fsha(path)}

def capture() -> dict:
    if fsha(LINK) != EXPECTED_LINK: raise RuntimeError("immutable compiler-cursor link changed")
    raw = RAW.read_text(encoding="utf-8")
    targets = []
    for name, kind, probe_line, ref_name in TARGETS:
        ref = sourcekit_ref(ref_name, probe_line)
        extensions = extension_records(SWIFTUI, "Swift." + name) + extension_records(SWIFTUICORE, "Swift." + name)
        targets.append({
            "target": "Swift." + name,
            "ownerSource": source_owner(name),
            "extensionEvidence": {
                "records": extensions,
                "sources": [{"module": "SwiftUI", "path": rel(SWIFTUI), "sha256": fsha(SWIFTUI)}, {"module": "SwiftUICore", "path": rel(SWIFTUICORE), "sha256": fsha(SWIFTUICORE)}],
                "status": "raw-header-records-only" if extensions else "no-direct-qualified-extension-header-found-in-pinned-UI-Core-sources",
            },
            "sourceKitReference": {"probe": {"path": rel(PROBE), "sha256": fsha(PROBE), "line": probe_line, "referenceName": ref_name}, "record": ref, "status": "exact-reference-usr" if ref else "unknown-reference-usr"},
        })
    return {
        "kind": "f1-public-ancestor-external-owner-raw-capture",
        "version": 1,
        "status": "raw-facts-only-no-eligibility-conclusion",
        "method": "pinned Swift.swiftinterface owner lines + pinned SwiftUI/SwiftUICore extension headers + dedicated SourceKit index references + demangle output",
        "inputs": {
            "immutable836": {"path": rel(LINK), "sha256": fsha(LINK)},
            "sdk": str(SDK), "target": TARGET,
            "swiftInterface": {"path": str(SWIFT), "sha256": fsha(SWIFT)},
            "uiCoreInterfaces": [{"module": "SwiftUI", "path": str(SWIFTUI), "sha256": fsha(SWIFTUI)}, {"module": "SwiftUICore", "path": str(SWIFTUICORE), "sha256": fsha(SWIFTUICORE)}],
        },
        "toolchain": {
            "swiftc": tool(TOOLCHAIN / "usr/bin/swiftc"),
            "sourcekitLsp": tool(TOOLCHAIN / "usr/bin/sourcekit-lsp"),
            "sourcekitd": tool(TOOLCHAIN / "usr/lib/sourcekitd.framework/Versions/A/sourcekitd"),
            "swiftDemangle": tool(TOOLCHAIN / "usr/bin/swift-demangle"),
            "swiftcTypecheck": {"argv": ["xcrun", "--sdk", "macosx", "swiftc", "-typecheck", "-sdk", str(SDK), "-target", TARGET, rel(PROBE)], "exit": 0, "stdout": {"path": rel(SWIFTC_STDOUT), "sha256": fsha(SWIFTC_STDOUT)}, "stderr": {"path": rel(SWIFTC_STDERR), "sha256": fsha(SWIFTC_STDERR)}},
            "sourcekitIndex": {"argv": ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", rel(REQUEST)], "exit": 0, "request": {"path": rel(REQUEST), "sha256": fsha(REQUEST)}, "output": {"path": rel(RAW), "sha256": fsha(RAW)}, "stderr": {"path": rel(SK_STDERR), "sha256": fsha(SK_STDERR)}},
            "demangle": {"argv": [str(TOOLCHAIN / "usr/bin/swift-demangle"), "<", rel(DEMANGLE_INPUT)], "exit": 0, "input": {"path": rel(DEMANGLE_INPUT), "sha256": fsha(DEMANGLE_INPUT)}, "stdout": {"path": rel(DEMANGLE_STDOUT), "sha256": fsha(DEMANGLE_STDOUT)}, "stderr": {"path": rel(DEMANGLE_STDERR), "sha256": fsha(DEMANGLE_STDERR)}},
        },
        "targets": targets,
        "heldRules": ["graph absence is not exclusion", "access/conditions/attributes are source facts only", "ambiguous or missing joins remain unknown", "no eligibility or promotion conclusion is recorded"],
    }

if __name__ == "__main__":
    out = HERE / "swift-stdlib-evidence.json"
    data = capture()
    out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": rel(out), "sha256": fsha(out), "targets": len(data["targets"]), "exactUsrs": sum(bool(t["sourceKitReference"]["record"]) for t in data["targets"]), "extensionRows": sum(len(t["extensionEvidence"]["records"]) for t in data["targets"])}, indent=2))
