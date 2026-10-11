#!/usr/bin/env python3
"""Validate inferred imported nominal roots against real Swift process outputs."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TARGET = "arm64-apple-macosx27.0"
RAW = HERE / "raw"
V3 = ROOT / "factory/catalogue/public-ancestor-spike/external-owner-capture/clang-external-process-v3"

EXPECTED = {
    "nsWindow": ("AppKit.NSWindow", 7, "NSWindow", "c:objc(cs)NSWindow", "source.lang.swift.ref.class", "NSWindow.Type", "__C.NSWindow.Type"),
    "nsApplication": ("AppKit.NSApplication", 8, "NSApplication", "c:objc(cs)NSApplication", "source.lang.swift.ref.class", "NSApplication.Type", "__C.NSApplication.Type"),
    "nsColor": ("AppKit.NSColor", 9, "NSColor", "c:objc(cs)NSColor", "source.lang.swift.ref.class", "NSColor.Type", "__C.NSColor.Type"),
    "nsControl": ("AppKit.NSControl", 10, "NSControl", "c:objc(cs)NSControl", "source.lang.swift.ref.class", "NSControl.Type", "__C.NSControl.Type"),
    "controlSize": ("AppKit.NSControl.ControlSize", 11, "ControlSize", "c:@E@NSControlSize", "source.lang.swift.ref.enum", "NSControl.ControlSize.Type", "__C.NSControlSize.Type"),
    "directionalInsets": ("AppKit.NSDirectionalEdgeInsets", 12, "NSDirectionalEdgeInsets", "c:@S@NSDirectionalEdgeInsets", "source.lang.swift.ref.struct", "NSDirectionalEdgeInsets.Type", "__C.NSDirectionalEdgeInsets.Type"),
    "underlineStyle": ("AppKit.NSUnderlineStyle", 13, "NSUnderlineStyle", "c:@E@NSUnderlineStyle", "source.lang.swift.ref.struct", "NSUnderlineStyle.Type", "__C.NSUnderlineStyle.Type"),
    "animationContext": ("AppKit.NSAnimationContext", 14, "NSAnimationContext", "c:objc(cs)NSAnimationContext", "source.lang.swift.ref.class", "NSAnimationContext.Type", "__C.NSAnimationContext.Type"),
    "activity": ("Foundation.NSUserActivity", 15, "NSUserActivity", "c:objc(cs)NSUserActivity", "source.lang.swift.ref.class", "NSUserActivity.Type", "__C.NSUserActivity.Type"),
    "point": ("CoreFoundation.CGPoint", 16, "CGPoint", "c:@S@CGPoint", "source.lang.swift.ref.struct", "CGPoint.Type", "__C.CGPoint.Type"),
    "size": ("CoreFoundation.CGSize", 17, "CGSize", "c:@S@CGSize", "source.lang.swift.ref.struct", "CGSize.Type", "__C.CGSize.Type"),
    "rect": ("CoreFoundation.CGRect", 18, "CGRect", "c:@S@CGRect", "source.lang.swift.ref.struct", "CGRect.Type", "__C.CGRect.Type"),
    "size3D": ("Spatial.Size3D", 19, "Size3D", "c:@UA@SPSize3D", "source.lang.swift.ref.struct", "Size3D.Type", "__C.SPSize3D.Type"),
}


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def need(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def variable_rows(text: str) -> list[dict]:
    pattern = re.compile(r'key\.kind: source\.lang\.swift\.decl\.var\.global,\n\s+key\.name: "([^\"]+)",\n\s+key\.usr: "([^\"]+)",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)')
    return [{"kind": "source.lang.swift.decl.var.global", "name": name, "usr": usr, "line": int(line), "column": int(column)} for name, usr, line, column in pattern.findall(text)]


def nominal_rows(text: str) -> list[dict]:
    pattern = re.compile(r'key\.kind: (source\.lang\.swift\.ref\.(?:class|struct|enum)),\n\s+key\.name: "([^\"]+)",\n\s+key\.usr: "([^\"]+)",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)')
    return [{"kind": kind, "name": name, "usr": usr, "line": int(line), "column": int(column)} for kind, name, usr, line, column in pattern.findall(text)]


def ast_rows(text: str) -> list[dict]:
    pattern = re.compile(r'\(var_decl .*range=\[[^\]]+:([0-9]+):[0-9]+ - line:[0-9]+:[0-9]+\] "([^"]+)" interface_type="([^"]+)"')
    return [{"name": name, "line": int(line), "interfaceType": interface_type} for line, name, interface_type in pattern.findall(text)]


def demangle_blocks(text: str) -> dict[str, str]:
    blocks = text.split("Demangling for ")[1:]
    result = {}
    for block in blocks:
        lines = block.splitlines()
        need(lines, "empty demangle block")
        symbol = lines[0].strip()
        need(symbol.startswith("$s"), f"demangle symbol {symbol}")
        raw_usr = "s:" + symbol[2:]
        result[raw_usr] = block
    return result


def source_record(path: Path, line: int) -> dict:
    lines = path.read_text().splitlines()
    need(0 < line <= len(lines), f"source line {path}:{line}")
    return {"path": str(path), "sha256": sha(path), "line": line, "text": lines[line - 1]}


def validate(e: dict) -> None:
    need(e["schema"] == "clang-nominal-import-v1", "schema")
    need(len(e["owners"]) == len(EXPECTED), "owner cardinality")
    need(set(item["variable"] for item in e["owners"]) == set(EXPECTED), "owner names")
    for name, item in ((item["variable"], item) for item in e["owners"]):
        target, line, nominal, usr, ref_kind, ast_type, demangle_type = EXPECTED[name]
        need(item["target"] == target and item["line"] == line, f"identity {name}")
        need(item["variableUSR"] == item["sourceKitVariable"]["usr"], f"variable USR binding {name}")
        need(item["variableUSR"].startswith("s:"), f"raw variable USR {name}")
        need(item["nominalUSR"] == usr and item["sourceKitNominal"]["usr"] == usr, f"nominal USR {name}")
        need(item["sourceKitVariable"]["name"] == name and item["sourceKitVariable"]["line"] == line, f"SourceKit variable {name}")
        need(item["sourceKitNominal"]["name"] == nominal and item["sourceKitNominal"]["line"] == line and item["sourceKitNominal"]["kind"] == ref_kind, f"SourceKit nominal {name}")
        need(item["compilerType"] == ast_type, f"compiler type {name}")
        need(item["demangleSummary"] == f"owners.{name} : {demangle_type}", f"demangle summary {name}")
        block = item["demangleBlock"]
        need(f'kind=Identifier, text="{name}"' in block, f"demangle variable tree {name}")
        demangled_nominal = demangle_type.rsplit(".", 1)[0].rsplit(".", 1)[-1]
        need(f'kind=Identifier, text="{demangled_nominal}"' in block, f"demangle nominal tree {name}")
        source = item["sourceToken"]
        source_path = Path(source["path"])
        need(source["line"] == line, f"source line {name}")
        need(source["sha256"] == sha(source_path), f"source hash {name}")
        need(source["text"] == source_path.read_text().splitlines()[line - 1], f"source text {name}")
    for run in e["processRuns"]:
        need(run["returncode"] == 0, f"returncode {run['name']}")
        need(run["cwd"] == str(ROOT), f"cwd {run['name']}")
        need(run["startedAt"] < run["endedAt"], f"timestamps {run['name']}")
        output = ROOT / run["stdout"]
        error = ROOT / run["stderr"]
        need(sha(output) == run["stdoutSha256"] and output.stat().st_size == run["stdoutBytes"], f"stdout {run['name']}")
        need(sha(error) == run["stderrSha256"] and error.stat().st_size == run["stderrBytes"], f"stderr {run['name']}")
        if run["name"] in {"swift-typecheck", "swift-ast-dump"}:
            need("-target" in run["argv"] and run["argv"][run["argv"].index("-target") + 1] == TARGET, f"Swift target {run['name']}")
            need("-sdk" in run["argv"] and run["argv"][run["argv"].index("-sdk") + 1] == str(SDK), f"Swift SDK {run['name']}")
        for binding in run.get("inputBindings", []):
            path = ROOT / binding["path"]
            need(path.exists() and sha(path) == binding["sha256"] and path.stat().st_size == binding["bytes"], f"input {run['name']}")
    frozen = e["frozenV3"]
    for ref in frozen.values():
        path = ROOT / ref["path"]
        need(path.exists() and sha(path) == ref["sha256"], f"frozen v3 pin {path}")


def build() -> dict:
    source = HERE / "probes/owners.swift"
    index_path = RAW / "owners.index.txt"
    ast_path = RAW / "owners.ast.txt"
    demangle_path = RAW / "demangle-expand.txt"
    indexed = variable_rows(index_path.read_text())
    nominal = nominal_rows(index_path.read_text())
    ast = ast_rows(ast_path.read_text())
    blocks = demangle_blocks(demangle_path.read_text())
    need(len(indexed) == len(EXPECTED), "indexed variables")
    need(len(ast) == len(EXPECTED), "AST variables")
    owners = []
    for name, (target, line, nominal_name, usr, ref_kind, ast_type, demangle_type) in EXPECTED.items():
        v = [row for row in indexed if row["name"] == name and row["line"] == line]
        need(len(v) == 1, f"variable row {name}")
        n = [row for row in nominal if row["name"] == nominal_name and row["usr"] == usr and row["line"] == line and row["kind"] == ref_kind]
        need(len(n) == 1, f"nominal row {name}")
        a = [row for row in ast if row["name"] == name and row["line"] == line and row["interfaceType"] == ast_type]
        need(len(a) == 1, f"AST row {name}")
        block = blocks.get(v[0]["usr"])
        need(block is not None, f"demangle row {name}")
        summary = [line_text for line_text in block.splitlines() if line_text.startswith(f"owners.{name} :")]
        need(len(summary) == 1, f"demangle summary row {name}")
        owners.append({"variable": name, "target": target, "line": line, "sourceToken": source_record(source, line), "variableUSR": v[0]["usr"], "sourceKitVariable": v[0], "nominalUSR": usr, "sourceKitNominal": n[0], "compilerType": ast_type, "compilerAST": a[0], "demangleSummary": summary[0], "demangleBlock": block})
    runs = json.loads((RAW / "process-runs.json").read_text())["runs"]
    v3_evidence = V3 / "raw/clang-external-process-v3.json"
    v3_runs = V3 / "raw/process-runs.json"
    v3_manifest = V3 / "stage-manifest.json"
    evidence = {"schema": "clang-nominal-import-v1", "sdk": {"path": str(SDK), "target": TARGET, "xcode": "Xcode-27-RC 27A266"}, "owners": owners, "sourceKitRaw": {"path": str(index_path.relative_to(ROOT)), "sha256": sha(index_path)}, "compilerASTRaw": {"path": str(ast_path.relative_to(ROOT)), "sha256": sha(ast_path)}, "demangleRaw": {"path": str(demangle_path.relative_to(ROOT)), "sha256": sha(demangle_path)}, "processRuns": runs, "frozenV3": {"evidence": {"path": str(v3_evidence.relative_to(ROOT)), "sha256": sha(v3_evidence)}, "processRuns": {"path": str(v3_runs.relative_to(ROOT)), "sha256": sha(v3_runs)}, "stageManifest": {"path": str(v3_manifest.relative_to(ROOT)), "sha256": sha(v3_manifest)}}, "controls": {"inferredLetNoAnyType": True, "exactVariableUSR": True, "exactNominalUSR": True, "exactSourceToken": True, "exactCompilerType": True, "exactFullDemangle": True, "explicitSwiftTarget": TARGET, "frozenV3Binding": True, "noASTRerun": True}}
    validate(evidence)
    output = RAW / "clang-nominal-import-v1.json"
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"path": str(output), "sha256": sha(output), "owners": len(owners), "processes": len(runs)}, indent=2))
    return evidence


if __name__ == "__main__":
    build()
