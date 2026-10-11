#!/usr/bin/env python3
"""Build & validate bounded external-owner evidence from actual process receipts."""
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
RAW = HERE / "raw"


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise ValueError(message)


def need(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def source(path: Path, line: int) -> dict:
    lines = path.read_text().splitlines()
    need(0 < line <= len(lines), f"source line range {path}:{line}")
    return {"path": str(path), "sha256": sha(path), "line": line, "text": lines[line - 1]}


def refs(raw: str) -> list[dict]:
    pattern = re.compile(
        r'key\.kind: ([^,\n]+),\n\s+key\.name: "([^\"]+)",\n'
        r'\s+key\.usr: "([^\"]+)",\n\s+key\.line: (\d+),\n'
        r'\s+key\.column: (\d+)'
    )
    return [
        {"kind": kind, "name": name, "usr": usr, "line": int(line), "column": int(column)}
        for kind, name, usr, line, column in pattern.findall(raw)
    ]


EXPECTED = {
    "AppKit.NSWindow": ("NSWindow", "c:objc(cs)NSWindow", "ObjCInterfaceDecl", "source.lang.swift.ref.class"),
    "AppKit.NSApplication": ("NSApplication", "c:objc(cs)NSApplication", "ObjCInterfaceDecl", "source.lang.swift.ref.class"),
    "AppKit.NSColor": ("NSColor", "c:objc(cs)NSColor", "ObjCInterfaceDecl", "source.lang.swift.ref.class"),
    "AppKit.NSControl": ("NSControl", "c:objc(cs)NSControl", "ObjCInterfaceDecl", "source.lang.swift.ref.class"),
    "AppKit.NSControl.ControlSize": ("ControlSize", "c:@E@NSControlSize", "TypedefDecl", "source.lang.swift.ref.enum"),
    "AppKit.NSDirectionalEdgeInsets": ("NSDirectionalEdgeInsets", "c:@S@NSDirectionalEdgeInsets", "TypedefDecl", "source.lang.swift.ref.struct"),
    "AppKit.NSUnderlineStyle": ("NSUnderlineStyle", "c:@E@NSUnderlineStyle", "TypedefDecl", "source.lang.swift.ref.struct"),
    "AppKit.NSAnimationContext": ("NSAnimationContext", "c:objc(cs)NSAnimationContext", "ObjCInterfaceDecl", "source.lang.swift.ref.class"),
    "Foundation.NSUserActivity": ("NSUserActivity", "c:objc(cs)NSUserActivity", "ObjCInterfaceDecl", "source.lang.swift.ref.class"),
    "CoreFoundation.CGPoint": ("CGPoint", "c:@S@CGPoint", "TypedefDecl", "source.lang.swift.ref.struct"),
    "CoreFoundation.CGSize": ("CGSize", "c:@S@CGSize", "TypedefDecl", "source.lang.swift.ref.struct"),
    "CoreFoundation.CGRect": ("CGRect", "c:@S@CGRect", "TypedefDecl", "source.lang.swift.ref.struct"),
    "Spatial.Size3D": ("Size3D", "c:@UA@SPSize3D", "TypedefDecl", "source.lang.swift.ref.struct"),
}
REQUESTED = set(EXPECTED) - {"AppKit.NSControl"}
SOURCE_LINES = {
    "AppKit.NSWindow": 7, "AppKit.NSApplication": 8, "AppKit.NSColor": 9,
    "AppKit.NSControl": 10, "AppKit.NSControl.ControlSize": 11,
    "AppKit.NSDirectionalEdgeInsets": 12, "AppKit.NSUnderlineStyle": 13,
    "AppKit.NSAnimationContext": 14, "Foundation.NSUserActivity": 15,
    "CoreFoundation.CGPoint": 16, "CoreFoundation.CGSize": 17,
    "CoreFoundation.CGRect": 18, "Spatial.Size3D": 19,
}
HEADER_LINES = {
    "AppKit.NSWindow": 283, "AppKit.NSApplication": 194, "AppKit.NSColor": 77,
    "AppKit.NSControl": 19, "AppKit.NSControl.ControlSize": 91,
    "AppKit.NSDirectionalEdgeInsets": 53, "AppKit.NSUnderlineStyle": 61,
    "AppKit.NSAnimationContext": 19, "Foundation.NSUserActivity": 56,
    "CoreFoundation.CGPoint": 51, "CoreFoundation.CGSize": 59,
    "CoreFoundation.CGRect": 77, "Spatial.Size3D": 129,
}


def check_ast_identity(target: dict) -> None:
    ast = target["astOutput"]
    path = ROOT / ast["path"]
    need(path.exists(), f"missing AST output {target['target']}")
    need(sha(path) == ast["sha256"], f"AST output hash {target['target']}")
    rows = json.loads(path.read_text())
    name, _, kind, _ = EXPECTED[target["target"]]
    ast_name = {"AppKit.NSControl.ControlSize": "NSControlSize", "Spatial.Size3D": "SPSize3D"}.get(target["target"], name)
    matches = [row for row in rows if row.get("name") == ast_name and row.get("kind") == kind]
    need(len(matches) == 1, f"AST owner cardinality {target['target']}")
    if target["target"] == "AppKit.NSControl.ControlSize":
        need(any(row.get("name") == "NSControlSize" and row.get("kind") == kind for row in rows), "ControlSize AST spelling")
    elif target["target"] == "Spatial.Size3D":
        need(any(row.get("name") == "SPSize3D" and row.get("kind") == kind for row in rows), "Size3D AST spelling")


def validate_evidence(e: dict) -> None:
    need(e.get("schema") == "clang-external-process-v2", "schema")
    need(len(e.get("targets", [])) == len(EXPECTED), "target cardinality")
    targets = {item["target"]: item for item in e["targets"]}
    need(set(targets) == set(e["targetNames"]), "target names")
    need(set(targets) == set(EXPECTED), "expected target set")
    need(set(e.get("requestedTargetNames", [])) == REQUESTED, "requested target set")
    for name, (_, usr, kind, _) in EXPECTED.items():
        item = targets.get(name)
        need(item is not None, f"missing target {name}")
        need(item["usr"] == usr and item["astKind"] == kind, f"identity {name}")
        need(item["status"] == "public-header-exported", f"status {name}")
        origin = item["source"]
        origin_path = Path(origin["path"])
        need(origin["text"], f"source text {name}")
        need(origin["line"] == HEADER_LINES[name], f"source line {name}")
        need(origin["text"] == origin_path.read_text().splitlines()[origin["line"] - 1], f"source text binding {name}")
        need(origin["sha256"] == sha(origin_path), f"source hash {name}")
        need(item["sourceKit"]["usr"] == usr, f"SourceKit usr {name}")
        need(item["sourceKit"]["kind"].startswith("source.lang.swift.ref."), f"SourceKit kind {name}")
        check_ast_identity(item)
    runs = e["processRuns"]
    need(len(runs) == 7, "process count")
    expected_runs = {"swift-typecheck", "sourcekit-index", "clang-appkit-ast", "clang-foundation-ast", "clang-corefoundation-ast", "clang-coregraphics-ast", "clang-spatial-ast"}
    need({run["name"] for run in runs} == expected_runs, "process set")
    for run in runs:
        need(run["returncode"] == 0, f"return code {run['name']}")
        need(run["cwd"] == str(ROOT), f"cwd {run['name']}")
        need(run["argv"] and run["argv"][0] == "xcrun", f"argv {run['name']}")
        need(run["startedAt"] < run["endedAt"], f"timestamps {run['name']}")
        output = ROOT / run["stdout"]
        error = ROOT / run["stderr"]
        need(sha(output) == run["stdoutSha256"], f"stdout hash {run['name']}")
        need(sha(error) == run["stderrSha256"], f"stderr hash {run['name']}")
        need(run["stdoutBytes"] == output.stat().st_size and run["stderrBytes"] == error.stat().st_size, f"byte sizes {run['name']}")
        if run["stdout"].endswith(".gz"):
            raw_bytes = gzip.decompress(output.read_bytes())
            need("sha256:" + hashlib.sha256(raw_bytes).hexdigest() == run["rawStdoutSha256"], f"raw stdout hash {run['name']}")
            need(len(raw_bytes) == run["rawStdoutBytes"], f"raw stdout bytes {run['name']}")
        for binding in run.get("inputBindings", []):
            input_path = Path(binding["path"])
            if not input_path.is_absolute():
                input_path = ROOT / input_path
            need(input_path.exists(), f"input missing {run['name']}")
            need(sha(input_path) == binding["sha256"], f"input hash {run['name']}:{input_path}")
    for module in e["moduleMaps"]:
        path = Path(module["path"])
        text = path.read_text()
        need(sha(path) == module["sha256"], f"module map {module['module']}")
        need("export *" in text, f"module export {module['module']}")
        expected_export = ["framework module AppKit", "export *"] if module["module"] == "AppKit" else ["export *", "module * { export * }"]
        need(module["exportEvidence"] == expected_export, f"module export evidence {module['module']}")
    need(len(e["astRawRuns"]) == 5, "AST raw run set")


def input_binding(path: Path) -> dict:
    return {"path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path), "sha256": sha(path)}


def build() -> dict:
    receipt = json.loads((RAW / "process-runs.json").read_text())
    runs = receipt["runs"]
    by = {item["name"]: item for item in runs}
    sourcekit_raw = RAW / "owners.index.txt"
    parsed = refs(sourcekit_raw.read_text())
    need(len(parsed) >= len(EXPECTED), "SourceKit raw parse")
    modules = {
        "AppKit": SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Modules/module.modulemap",
        "Foundation": SDK / "System/Library/Frameworks/Foundation.framework/Versions/C/Modules/module.modulemap",
        "CoreFoundation": SDK / "System/Library/Frameworks/CoreFoundation.framework/Versions/A/Modules/module.modulemap",
        "Spatial": SDK / "usr/include/Spatial/module.modulemap",
    }
    module_maps = []
    for module, path in modules.items():
        text = path.read_text()
        evidence = ["export *"]
        if "module * {" in text and "export *" in text:
            evidence.append("module * { export * }")
        if module == "AppKit":
            evidence = ["framework module AppKit", "export *"]
        need("export *" in text, f"export evidence {module}")
        module_maps.append({"module": module, "path": str(path), "sha256": sha(path), "exportEvidence": evidence})
    hdr = {
        "AppKit.NSWindow": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWindow.h", 283),
        "AppKit.NSApplication": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSApplication.h", 194),
        "AppKit.NSColor": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSColor.h", 77),
        "AppKit.NSControl": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSControl.h", 19),
        "AppKit.NSControl.ControlSize": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSCell.h", 91),
        "AppKit.NSDirectionalEdgeInsets": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSCollectionViewCompositionalLayout.h", 53),
        "AppKit.NSUnderlineStyle": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSAttributedString.h", 61),
        "AppKit.NSAnimationContext": source(SDK / "System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSAnimationContext.h", 19),
        "Foundation.NSUserActivity": source(SDK / "System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSUserActivity.h", 56),
        "CoreFoundation.CGPoint": source(SDK / "System/Library/Frameworks/CoreFoundation.framework/Versions/A/Headers/CFCGTypes.h", 51),
        "CoreFoundation.CGSize": source(SDK / "System/Library/Frameworks/CoreFoundation.framework/Versions/A/Headers/CFCGTypes.h", 59),
        "CoreFoundation.CGRect": source(SDK / "System/Library/Frameworks/CoreFoundation.framework/Versions/A/Headers/CFCGTypes.h", 77),
        "Spatial.Size3D": source(SDK / "usr/include/Spatial/Structures.h", 129),
    }
    ast_files = {"AppKit": "appkit-targets.ast.json", "Foundation": "foundation-targets.ast.json", "CoreFoundation": "corefoundation-targets.ast.json", "Spatial": "spatial-targets.ast.json"}
    ast_meta = {module: {"path": str((RAW / filename).relative_to(ROOT)), "sha256": sha(RAW / filename), "records": len(json.loads((RAW / filename).read_text()))} for module, filename in ast_files.items()}
    targets = []
    for name, (refname, usr, ast_kind, sourcekit_kind) in EXPECTED.items():
        matches = [item for item in parsed if item["name"] == refname and item["line"] == SOURCE_LINES[name] and item["usr"] == usr and item["kind"] == sourcekit_kind]
        need(len(matches) == 1, f"SourceKit cardinality {name}")
        module = name.split(".")[0]
        targets.append({"target": name, "module": module, "usr": usr, "astKind": ast_kind, "source": hdr[name], "sourceKit": matches[0], "astOutput": ast_meta[module], "status": "public-header-exported", "eligibilityEvidence": ["exact compiler AST owner", "exact public SDK header line", "exported module map", "successful actual import/typecheck"]})
    bindings = {
        "swift-typecheck": [HERE / "probes/owners.swift"],
        "sourcekit-index": [HERE / "requests/owners.yaml"],
        "clang-appkit-ast": [HERE / "probes/appkit_ast.m"],
        "clang-foundation-ast": [HERE / "probes/foundation_ast.m"],
        "clang-corefoundation-ast": [HERE / "probes/corefoundation_ast.c"],
        "clang-coregraphics-ast": [HERE / "probes/coregraphics_ast.c"],
        "clang-spatial-ast": [HERE / "probes/spatial_ast.c"],
    }
    process_runs = []
    for run in runs:
        item = dict(run)
        item["inputBindings"] = [input_binding(path) for path in bindings[run["name"]]]
        process_runs.append(item)
    evidence = {
        "schema": "clang-external-process-v2",
        "sdk": {"path": str(SDK), "target": TARGET, "xcode": "Xcode-27-RC 27A266"},
        "targetNames": list(EXPECTED),
        "requestedTargetNames": sorted(REQUESTED),
        "targets": targets,
        "moduleMaps": module_maps,
        "processRuns": process_runs,
        "sourcekitRaw": {"path": str(sourcekit_raw.relative_to(ROOT)), "sha256": sha(sourcekit_raw), "runName": "sourcekit-index"},
        "astRawRuns": {module: by[name] for module, name in (("AppKit", "clang-appkit-ast"), ("Foundation", "clang-foundation-ast"), ("CoreFoundation", "clang-corefoundation-ast"), ("CoreGraphics", "clang-coregraphics-ast"), ("Spatial", "clang-spatial-ast"))},
        "controls": {"exactRawUSR": True, "exactSourceLine": True, "exactASTKind": True, "actualReturnCode": True, "actualArgvCwdTimestamps": True, "sourceRequestHashes": True, "rawStdoutHashes": True, "moduleMapExportReconstructed": True, "wrongSourceRejects": True, "wrongUSRRejects": True, "wrongKindRejects": True, "wrongProcessRejects": True, "wrongExportRejects": True, "extraTargetRejects": True, "noAbsenceInference": True},
    }
    validate_evidence(evidence)
    output = RAW / "clang-external-process-v2.json"
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"path": str(output), "sha256": sha(output), "targets": len(targets), "requestedTargets": len(REQUESTED), "processes": len(runs)}, indent=2))
    return evidence


if __name__ == "__main__":
    build()
