#!/usr/bin/env python3
"""Capture bounded raw facts for SwiftUI's external nominal owners.

This capture records source/header declarations plus compiler SourceKit joins.
It deliberately makes no public-ancestor or eligibility decision.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
SWIFTUI = SDK / "System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
PROBE = HERE / "probes/external-targets.swift"
REQUEST = HERE / "requests/external-targets.yaml"
RAW = HERE / "raw/external-targets.index.txt"
SWIFTC_STDOUT = HERE / "receipts/external-targets.stdout"
SWIFTC_STDERR = HERE / "receipts/external-targets.stderr"
SK_STDERR = HERE / "receipts/external-targets.sourcekit.stderr"
TARGET = "arm64-apple-macosx27.0"

def sha(data: bytes | str) -> str:
    if isinstance(data, str): data = data.encode()
    return "sha256:" + hashlib.sha256(data).hexdigest()

def file_sha(path: Path) -> str:
    return sha(path.read_bytes())

def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)

def lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()

def source_record(path: Path, line_no: int, role: str, text: str | None = None) -> dict:
    ls = lines(path)
    if line_no < 1 or line_no > len(ls):
        raise ValueError(f"bad source line {path}:{line_no}")
    return {"role": role, "path": rel(path), "sha256": file_sha(path),
            "line": line_no, "text": ls[line_no - 1] if text is None else text}

def find_lines(path: Path, pattern: str) -> list[dict]:
    rx = re.compile(pattern)
    return [source_record(path, i, "owner-declaration") for i, line in enumerate(lines(path), 1) if rx.search(line)]

def first_decl(path: Path, pattern: str) -> list[dict]:
    return find_lines(path, pattern)[:8]

SWIFT = SDK / "usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
COREFOUNDATION = SDK / "usr/lib/swift/CoreFoundation.swiftmodule/arm64e-apple-macos.swiftinterface"
OBSERVATION = SDK / "usr/lib/swift/Observation.swiftmodule/arm64e-apple-macos.swiftinterface"
SPATIAL = SDK / "usr/lib/swift/Spatial.swiftmodule/arm64e-apple-macos.swiftinterface"
SPATIAL_HEADER = SDK / "usr/include/Spatial/Structures.h"
SYMBOLS = SDK / "System/Library/Frameworks/Symbols.framework/Versions/A/Modules/Symbols.swiftmodule/arm64e-apple-macos.swiftinterface"
DEVELOPER = SDK / "System/Library/Frameworks/DeveloperToolsSupport.framework/Versions/A/Modules/DeveloperToolsSupport.swiftmodule/arm64e-apple-macos.swiftinterface"
FOUNDATION = SDK / "System/Library/Frameworks/Foundation.framework/Versions/C/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface"
FOUNDATION_USER = SDK / "System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSUserActivity.h"
APPKIT = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Modules/AppKit.swiftmodule/arm64e-apple-macos.swiftinterface"
NSANIMATION = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSAnimationContext.h"
NSAPPLICATION = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSApplication.h"
NSCOLOR = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSColor.h"
NSCONTROL = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSControl.h"
NSCELL = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSCell.h"
NSDIRECTIONAL = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSCollectionViewCompositionalLayout.h"
NSATTR = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSAttributedString.h"
NSWINDOW = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWindow.h"
CGTYPES = SDK / "System/Library/Frameworks/CoreFoundation.framework/Versions/A/Headers/CFCGTypes.h"
CGGEOM = SDK / "System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGGeometry.h"
COMBINE = SDK / "System/Library/Frameworks/Combine.framework/Versions/A/Modules/Combine.swiftmodule/arm64e-apple-macos.swiftinterface"

# target -> source module declaration evidence; imported ObjC owners use exact Clang headers.
OWNER_SPECS = {
    "Foundation.AttributedString": (FOUNDATION, r"@dynamicMemberLookup public struct AttributedString\b", "swift-interface"),
    "Foundation.AttributeDynamicLookup": (FOUNDATION, r"@dynamicMemberLookup @frozen public enum AttributeDynamicLookup\b", "swift-interface"),
    "Foundation.AttributeScopes": (FOUNDATION, r"@frozen public enum AttributeScopes\b", "swift-interface"),
    "Foundation.FormatStyle": (FOUNDATION, r"public protocol FormatStyle<", "swift-interface"),
    "Foundation.NSUserActivity": (FOUNDATION_USER, r"@interface NSUserActivity\b", "clang-header"),
    "Foundation.NSUserActivity.TypedPayloadError": (SWIFTUI, r"public enum TypedPayloadError : Swift\.Error", "swift-interface"),
    "Observation.Observable": (OBSERVATION, r"public protocol Observable\b", "swift-interface"),
    "DeveloperToolsSupport.Preview": (DEVELOPER, r"public struct Preview\b", "swift-interface"),
    "DeveloperToolsSupport.PreviewTrait": (DEVELOPER, r"public struct PreviewTrait<", "swift-interface"),
    "AppKit.NSAnimationContext": (NSANIMATION, r"@interface NSAnimationContext\b", "clang-header"),
    "AppKit.NSApplication": (NSAPPLICATION, r"@interface NSApplication\b", "clang-header"),
    "AppKit.NSColor": (NSCOLOR, r"@interface NSColor\b", "clang-header"),
    "AppKit.NSControl": (NSCONTROL, r"@interface NSControl\b", "clang-header"),
    "AppKit.NSControl.ControlSize": (NSCELL, r"typedef NS_ENUM\(NSUInteger, NSControlSize\)", "clang-header"),
    "AppKit.NSDirectionalEdgeInsets": (NSDIRECTIONAL, r"typedef struct .*NSDirectionalEdgeInsets \{", "clang-header"),
    "AppKit.NSUnderlineStyle": (NSATTR, r"typedef NS_OPTIONS\(NSInteger, NSUnderlineStyle\)", "clang-header"),
    "AppKit.NSWindow": (NSWINDOW, r"@interface NSWindow\b", "clang-header"),
    "Combine.ObservableObject": (COMBINE, r"public protocol ObservableObject : AnyObject", "swift-interface"),
    "CoreFoundation.CGFloat": (CGTYPES, r"typedef CGFLOAT_TYPE CGFloat", "clang-header"),
    "CoreFoundation.CGPoint": (CGGEOM, r"typedef struct CG_BOXABLE CGPoint CGPoint", "clang-header"),
    "CoreFoundation.CGSize": (CGGEOM, r"typedef struct CG_BOXABLE CGSize CGSize", "clang-header"),
    "CoreFoundation.CGRect": (CGGEOM, r"typedef struct CG_BOXABLE CGRect CGRect", "clang-header"),
    "Spatial.Size3D": (SPATIAL_HEADER, r"\}\s+SPSize3D$", "clang-header"),
    "Symbols.WiggleSymbolEffect": (SYMBOLS, r"public struct WiggleSymbolEffect\b", "swift-interface"),
}

# Probe source line -> exact SourceKit reference name. Values are stable source aliases, not inferred owners.
PROBE_REFS = {
    "DeveloperToolsSupport.Preview": (10, "Preview"), "DeveloperToolsSupport.PreviewTrait": (11, "PreviewTrait"),
    "Foundation.AttributedString": (12, "AttributedString"), "Foundation.NSUserActivity": (13, "NSUserActivity"),
    "Foundation.NSUserActivity.TypedPayloadError": (14, "TypedPayloadError"), "Foundation.AttributeScopes": (15, "AttributeScopes"),
    "Foundation.FormatStyle": (16, "FormatStyle"), "Foundation.AttributeDynamicLookup": (17, "AttributeDynamicLookup"),
    "Observation.Observable": (18, "Observable"), "AppKit.NSAnimationContext": (19, "NSAnimationContext"),
    "AppKit.NSApplication": (20, "NSApplication"), "AppKit.NSColor": (21, "NSColor"),
    "AppKit.NSControl": (22, "NSControl"), "AppKit.NSControl.ControlSize": (23, "ControlSize"),
    "AppKit.NSDirectionalEdgeInsets": (24, "NSDirectionalEdgeInsets"), "AppKit.NSUnderlineStyle": (25, "NSUnderlineStyle"),
    "AppKit.NSWindow": (26, "NSWindow"), "Combine.ObservableObject": (27, "ObservableObject"),
    "CoreFoundation.CGFloat": (28, "CGFloat"), "CoreFoundation.CGPoint": (29, "CGPoint"),
    "CoreFoundation.CGSize": (30, "CGSize"), "CoreFoundation.CGRect": (31, "CGRect"),
    "Spatial.Size3D": (32, "Size3D"), "Symbols.WiggleSymbolEffect": (33, "WiggleSymbolEffect"),
}

def parse_ref_entities(raw: str) -> list[dict]:
    # SourceKit's YAML-like stream is intentionally retained verbatim. This parser joins only exact ref blocks.
    pat = re.compile(r"\{\n\s+key\.kind: ([^,\n]+),\n\s+key\.name: \"([^\"]+)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)")
    return [{"kind": k.strip(), "name": n, "usr": u, "line": int(ln), "column": int(col)} for k,n,u,ln,col in pat.findall(raw)]

def extension_facts(target: str) -> list[dict]:
    # Keep exact source spelling, including conditions, for SwiftUI's external-owner extensions.
    out = []
    prefix = target.replace("::", ".")
    for i, line in enumerate(lines(SWIFTUI), 1):
        if re.match(r"^extension " + re.escape(prefix) + r"(?:[ :]|$)", line):
            out.append(source_record(SWIFTUI, i, "SwiftUI-external-owner-extension"))
    return out

def command_receipt() -> dict:
    swiftc = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
    sourcekit = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp")
    sourcekitd = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd")
    return {
        "swiftc": {"path": str(swiftc), "sha256": file_sha(swiftc)},
        "sourcekitLsp": {"path": str(sourcekit), "sha256": file_sha(sourcekit)},
        "sourcekitd": {"path": str(sourcekitd), "sha256": file_sha(sourcekitd)},
        "swiftcTypecheck": {"argv": ["xcrun", "--sdk", "macosx", "swiftc", "-typecheck", "-sdk", str(SDK), "-target", TARGET, rel(PROBE)], "exit": 0, "stdout": {"path": rel(SWIFTC_STDOUT), "sha256": file_sha(SWIFTC_STDOUT)}, "stderr": {"path": rel(SWIFTC_STDERR), "sha256": file_sha(SWIFTC_STDERR)}},
        "sourcekitIndex": {"argv": ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", rel(REQUEST)], "exit": 0, "request": {"path": rel(REQUEST), "sha256": file_sha(REQUEST)}, "output": {"path": rel(RAW), "sha256": file_sha(RAW)}, "stderr": {"path": rel(SK_STDERR), "sha256": file_sha(SK_STDERR)}},
    }

def capture() -> dict:
    if file_sha(LINK) != EXPECTED_LINK:
        raise SystemExit("immutable 836 changed")
    source_lines = lines(SWIFTUI)
    refs = parse_ref_entities(RAW.read_text(encoding="utf-8"))
    by_line_name = {(r["line"], r["name"]): r for r in refs if r["kind"].startswith("source.lang.swift.ref.")}
    targets = []
    for target, (path, pattern, kind) in OWNER_SPECS.items():
        decl = first_decl(path, pattern)
        if target == "Spatial.Size3D":
            decl.append(source_record(SPATIAL_HEADER, 131, "swift-name-annotation"))
        probe_line, ref_name = PROBE_REFS.get(target, (None, None))
        ref = by_line_name.get((probe_line, ref_name)) if probe_line else None
        declared_in = "SwiftUI" if path == SWIFTUI else target.split(".", 1)[0]
        if target.startswith("CoreFoundation.CGPoint") or target.startswith("CoreFoundation.CGSize") or target.startswith("CoreFoundation.CGRect"):
            declared_in = "CoreGraphics"
        targets.append({
            "target": target,
            "ownerSource": {"module": target.split(".", 1)[0], "declaredInModule": declared_in, "kind": kind, "records": decl, "status": "exact-source-record" if decl else "missing-source-record"},
            "swiftUIExtensionSources": extension_facts(target),
            "probeJoin": {"source": rel(PROBE), "sourceSha256": file_sha(PROBE), "line": probe_line, "referenceName": ref_name, "sourceKitReference": ref, "status": "exact-reference-usr" if ref else "missing-reference-usr"},
        })
    return {
        "kind": "f1-public-ancestor-external-owner-raw-capture",
        "version": 2,
        "status": "raw-facts-only-no-eligibility-conclusion",
        "method": "exact SDK interface/header declaration + SwiftUI extension source + SourceKit reference USR + pinned typecheck",
        "inputs": {"immutable836": {"path": rel(LINK), "sha256": file_sha(LINK)}, "sdk": str(SDK), "target": TARGET, "swiftUIInterface": {"path": str(SWIFTUI), "sha256": file_sha(SWIFTUI)}},
        "toolchain": command_receipt(),
        "targets": targets,
        "heldRules": ["graph absence is not exclusion", "imported/ObjC aliases retain source status", "no public/default-access inference", "all unknown or missing raw joins remain held"],
    }

if __name__ == "__main__":
    out = HERE / "external-owner-evidence-v2.json"
    data = capture()
    out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": rel(out), "sha256": file_sha(out), "targets": len(data["targets"]), "exactUsrs": sum(1 for x in data["targets"] if x["probeJoin"]["sourceKitReference"])}, indent=2))
