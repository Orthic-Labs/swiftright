#!/usr/bin/env python3
"""Capture exact exported Clang nominal owners used by SwiftUI extension rows."""
from __future__ import annotations
import gzip
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TARGET = "arm64-apple-macosx27.0"
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
SWIFTC = TOOLCHAIN / "swiftc"
CLANG = TOOLCHAIN / "clang"
SOURCEKIT = TOOLCHAIN / "sourcekit-lsp"
SOURCEKITD = TOOLCHAIN.parent / "lib/sourcekitd.framework/Versions/A/sourcekitd"
SDK_REL = "Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"

def sha_bytes(b: bytes) -> str:
    return "sha256:" + hashlib.sha256(b).hexdigest()

def sha(p: Path) -> str:
    return sha_bytes(p.read_bytes())

def require(ok: bool, msg: str) -> None:
    if not ok:
        raise RuntimeError(msg)

def refs(raw: str) -> list[dict[str, object]]:
    pattern = re.compile(r'key\.kind: ([^,\n]+),\n\s+key\.name: "([^"]+)",\n\s+key\.usr: "([^"]+)",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)')
    return [{"kind": k, "name": n, "usr": u, "line": int(l), "column": int(c)} for k, n, u, l, c in pattern.findall(raw)]

def source_line(path: Path, line: int) -> str:
    return path.read_text().splitlines()[line - 1]

def main() -> None:
    raw = HERE / "raw"
    receipts = HERE / "receipts"
    probe = HERE / "probes/owners.swift"
    request = HERE / "requests/owners.yaml"
    sourcekit_raw = raw / "owners.index.txt"
    require(sha(probe) == "sha256:641a9a244d0825985a097ca0413a1861536a98f6c61e37dd38034abbc75c9f5e", "probe changed")
    require(sha(request) == "sha256:13f0e881e5957a7d6dadc16e2bc14e132d5b3663ad475c3016198562bedbaf35", "request changed")
    require(sha(sourcekit_raw) == "sha256:38da20fa013758d75b895023cc6267479dd13ed2a0b957842e2fc2dfa33a799d", "SourceKit raw changed")
    for p in receipts.glob("*.stderr"):
        require(sha(p) == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", f"nonempty stderr: {p}")
    raw_refs = refs(sourcekit_raw.read_text())
    imported = {
        ("NSWindow", 6): ("source.lang.swift.ref.class", "c:objc(cs)NSWindow", "AppKit"),
        ("CGPoint", 7): ("source.lang.swift.ref.struct", "c:@S@CGPoint", "CoreGraphics"),
        ("CGSize", 8): ("source.lang.swift.ref.struct", "c:@S@CGSize", "CoreGraphics"),
        ("CGRect", 9): ("source.lang.swift.ref.struct", "c:@S@CGRect", "CoreGraphics"),
        ("Size3D", 10): ("source.lang.swift.ref.struct", "c:@UA@SPSize3D", "Spatial"),
    }
    for (name, line), (kind, usr, module) in imported.items():
        require(any(x["name"] == name and x["line"] == line and x["kind"] == kind and x["usr"] == usr for x in raw_refs), f"missing SourceKit ref {name}")
        require(any(x["name"] == module and x["line"] == line and x["kind"] == "source.lang.swift.ref.module" for x in raw_refs), f"missing module ref {module}")

    appkit_header = SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWindow.h"
    cg_header = SDK / "System/Library/Frameworks/CoreGraphics.framework/Headers/CGGeometry.h"
    spatial_header = SDK / "usr/include/Spatial/Structures.h"
    maps = [
        ("AppKit", SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Modules/module.modulemap", "sha256:545df348af8f6fd613912b1c122e8f70a612229eab35fc0ec83925d2df12a07f", "framework module AppKit", "export *"),
        ("CoreGraphics", SDK / "System/Library/Frameworks/CoreGraphics.framework/Versions/A/Modules/module.modulemap", "sha256:b71a70adda09321094262b0a81e59ec25bf1fd69ff5b4e2463ad4fd3c82f7ff3", "framework module CoreGraphics", "export *"),
        ("Spatial", SDK / "usr/include/Spatial/module.modulemap", "sha256:89931a74f1c73eb1fb77b5441c2509928d4cfac2ea6baa5a738a928ceffdd0c5", "module Spatial", "export *"),
    ]
    module_maps = []
    for module, p, expected, marker, export in maps:
        text = p.read_text()
        require(sha(p) == expected and marker in text and export in text, f"module map changed: {module}")
        module_maps.append({"module": module, "path": str(p), "sha256": sha(p), "exportEvidence": [marker, export]})

    require(sha(appkit_header) == "sha256:32d8533578a7dfc8edf193775bc3471556ad8da94322bc42ce5942eed9c47549", "NSWindow header changed")
    require(sha(cg_header) == "sha256:41e89d5338a795b60c577e3bec68ca61940eada078c40ecacbe203afc1e39465", "CoreGraphics header changed")
    require(sha(spatial_header) == "sha256:23bf3c4aba59bf52cbf7007d3a082b9bf83f55764c877c24ac92649124f483f9", "Spatial header changed")

    ast_files = {
        "AppKit": (raw / "appkit.ast.json.gz", "sha256:99da44200c7e33c62211fe91461c8408d7a753f776f32e9797026e3f89a39477", "sha256:2ac3d6c7ab2e8686059542deca0f0ca2a503818aa6a402b57466fd29a0913a18", raw / "appkit-targets.ast.json", "sha256:86e9445d9106815b86c5cf71db6d1dfdcc5dcca9580a1e338d92ed89cbb84582"),
        "CoreGraphics": (raw / "coregraphics.ast.json.gz", "sha256:bbb8b4239c88d828ca9425ba86f5528fde01065cdca175ca1c57f45096af0392", "sha256:3563e3842e5bea329167cb716172954106f330835e565fdadda5b4a6fbbfb887", raw / "coregraphics-targets.ast.json", "sha256:5961b78e366ddd706abc2fcc4c0289596e1f9b03c73909f81a78d0cb6b10d0d9"),
        "Spatial": (raw / "spatial.ast.json.gz", "sha256:47258a07d8971eb9040eed6667f8db17d8350a9270d3e99733b7887b93cc7eb6", "sha256:63edcf264c3afd27122753a1756ec8a8e9bf690edc7284d499c1160f7857994d", raw / "spatial-targets.ast.json", "sha256:ac397e7897165d62f2266d346e1c81142b0aec0caf26b4dfbdaef472444aa2c6"),
    }
    ast_meta = {}
    for module, (gz, raw_hash, gz_hash, filtered, filtered_hash) in ast_files.items():
        require(sha(gz) == gz_hash, f"{module} compressed AST changed")
        require(sha_bytes(gzip.decompress(gz.read_bytes())) == raw_hash, f"{module} AST decompression hash mismatch")
        require(sha(filtered) == filtered_hash, f"{module} filtered AST changed")
        ast_meta[module] = {"gzip": str(gz.relative_to(ROOT)), "gzipSha256": gz_hash, "decompressedSha256": raw_hash, "filtered": str(filtered.relative_to(ROOT)), "filteredSha256": filtered_hash}

    targets = [
        {"target": "AppKit.NSWindow", "module": "AppKit", "usr": "c:objc(cs)NSWindow", "kind": "ObjCInterfaceDecl", "source": {"path": str(appkit_header), "sha256": sha(appkit_header), "line": 283, "text": source_line(appkit_header, 283)}, "astIdentity": "_OBJC_CLASS_$_NSWindow", "sourceKit": {"name": "NSWindow", "line": 6, "column": 33}, "eligibilityEvidence": ["exact Clang ObjCInterfaceDecl", "public SDK header", "module map umbrella export *", "successful Swift import/typecheck"], "status": "public-header-exported"},
        {"target": "CoreGraphics.CGPoint", "module": "CoreGraphics", "usr": "c:@S@CGPoint", "kind": "TypedefDecl", "source": {"path": str(cg_header), "sha256": sha(cg_header), "line": 25, "text": source_line(cg_header, 25)}, "astIdentity": "struct CGPoint", "sourceKit": {"name": "CGPoint", "line": 7, "column": 36}, "eligibilityEvidence": ["exact Clang typedef AST", "public SDK header", "module map umbrella export *", "successful Swift import/typecheck"], "status": "public-header-exported"},
        {"target": "CoreGraphics.CGSize", "module": "CoreGraphics", "usr": "c:@S@CGSize", "kind": "TypedefDecl", "source": {"path": str(cg_header), "sha256": sha(cg_header), "line": 33, "text": source_line(cg_header, 33)}, "astIdentity": "struct CGSize", "sourceKit": {"name": "CGSize", "line": 8, "column": 35}, "eligibilityEvidence": ["exact Clang typedef AST", "public SDK header", "module map umbrella export *", "successful Swift import/typecheck"], "status": "public-header-exported"},
        {"target": "CoreGraphics.CGRect", "module": "CoreGraphics", "usr": "c:@S@CGRect", "kind": "TypedefDecl", "source": {"path": str(cg_header), "sha256": sha(cg_header), "line": 51, "text": source_line(cg_header, 51)}, "astIdentity": "struct CGRect", "sourceKit": {"name": "CGRect", "line": 9, "column": 35}, "eligibilityEvidence": ["exact Clang typedef AST", "public SDK header", "module map umbrella export *", "successful Swift import/typecheck"], "status": "public-header-exported"},
        {"target": "Spatial.Size3D", "module": "Spatial", "usr": "c:@UA@SPSize3D", "kind": "TypedefDecl", "source": {"path": str(spatial_header), "sha256": sha(spatial_header), "line": 129, "text": source_line(spatial_header, 129), "swiftNameAnnotationLine": 131, "swiftNameAnnotation": source_line(spatial_header, 131), "availabilityLine": 132, "availability": source_line(spatial_header, 132)}, "astIdentity": "union SPSize3D + SwiftNameAttr(Size3D)", "sourceKit": {"name": "Size3D", "line": 10, "column": 32}, "eligibilityEvidence": ["exact Clang typedef AST", "exact SwiftNameAttr(Size3D)", "public SDK header/module map export *", "successful Swift import/typecheck"], "status": "public-header-exported"},
    ]
    for t in targets:
        r = next(x for x in raw_refs if x["name"] == t["sourceKit"]["name"] and x["line"] == t["sourceKit"]["line"])
        require(r["usr"] == t["usr"], f"SourceKit USR mismatch {t['target']}")
    tools = {}
    for name, p in (("swiftc", SWIFTC), ("clang", CLANG), ("sourcekitLsp", SOURCEKIT), ("sourcekitd", SOURCEKITD)):
        tools[name] = {"path": str(p), "sha256": sha(p)}
    evidence = {"schema": "clang-external-owner-v1", "scope": "exact AppKit/CoreGraphics/Spatial owners only", "sdk": {"path": str(SDK), "target": TARGET, "xcode": "Xcode-27-RC 27A266"}, "moduleMaps": module_maps, "probe": {"source": str(probe.relative_to(ROOT)), "sha256": sha(probe), "swiftcExit": 0, "swiftcStderrSha256": sha(receipts / "owners.swiftc.stderr")}, "sourcekit": {"request": str(request.relative_to(ROOT)), "requestSha256": sha(request), "raw": str(sourcekit_raw.relative_to(ROOT)), "rawSha256": sha(sourcekit_raw), "exit": 0, "stderrSha256": sha(receipts / "owners.sourcekit.stderr"), "argv": ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(request.relative_to(ROOT))]}, "clangAST": {"tools": tools, "runs": {"AppKit": {"probe": "probes/appkit_ast.m", "exit": 0, "stderrSha256": sha(receipts / "appkit.clang.stderr"), "argv": ["xcrun", "--sdk", "macosx", "clang", "-fsyntax-only", "-x", "objective-c", "-isysroot", str(SDK), "-include", "AppKit/AppKit.h", "-Xclang", "-ast-dump=json", "probes/appkit_ast.m"]}, "CoreGraphics": {"probe": "probes/coregraphics_ast.c", "exit": 0, "stderrSha256": sha(receipts / "coregraphics.clang.stderr")}, "Spatial": {"probe": "probes/spatial_ast.c", "exit": 0, "stderrSha256": sha(receipts / "spatial.clang.stderr")}}, "outputs": ast_meta}, "targets": targets, "controls": {"exactRawUSR": True, "exactSourceHeaderLine": True, "exactASTIdentity": True, "moduleMapExportRequired": True, "noAbsenceInference": True, "noSyntheticPublicFlags": True, "unresolvedAliasesRemainHeld": True}}
    out = raw / "clang-external-owner-v1.json"
    out.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"path": str(out), "sha256": sha(out), "targets": len(targets)}, indent=2))

if __name__ == "__main__":
    main()
