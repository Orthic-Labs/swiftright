#!/usr/bin/env python3
"""Join SourceKit indexsource entities to v6 interface residual rows by source location."""
from __future__ import annotations
import hashlib, json, re, subprocess
from pathlib import Path
from strict_match import (entity_access_matches, entity_context_matches, entity_kind_matches,
                          cursor_result_usr, entity_matches, request_identity_matches,
                          unique_entity_usr)

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
AUDIT = ROOT / "factory/catalogue/evidence/interface-audit-v6.json"
CATALOGUE = ROOT / "factory/catalogue/evidence/catalogue.json"
RESIDUALS = {"active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained"}


def entities(path: Path) -> list[dict]:
    result = []
    stack: list[dict] = []
    for line in path.read_text().splitlines():
        opened = re.match(r"^(\s*)\{$", line)
        if opened:
            stack.append({"indent": len(opened.group(1)), "fields": {}})
            continue
        closed = re.match(r"^(\s*)\}(?:,)?$", line)
        if closed:
            indent = len(closed.group(1))
            while stack and stack[-1]["indent"] >= indent:
                closed_record = stack.pop()
                record = closed_record["fields"]
                if str(record.get("kind", "")).startswith("source.lang.swift.decl.") and all(k in record for k in ("name", "usr", "line")):
                    containers = []
                    for parent in stack:
                        fields = parent["fields"]
                        kind = str(fields.get("kind", ""))
                        if (kind.startswith("source.lang.swift.decl.extension") or
                            kind in {"source.lang.swift.decl.struct", "source.lang.swift.decl.enum",
                                     "source.lang.swift.decl.protocol", "source.lang.swift.decl.class",
                                     "source.lang.swift.decl.actor"}):
                            containers.append({"kind": kind, "name": fields.get("name"), "usr": fields.get("usr")})
                    record["sourcekitContext"] = containers
                    result.append(record)
            continue
        field = re.match(r"^(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?)(?:,)?$", line)
        if field and stack:
            indent, key, value = len(field.group(1)), field.group(2), field.group(3)
            if stack[-1]["indent"] + 2 == indent:
                if value.startswith('"'):
                    value = json.loads(value)
                elif value.isdigit():
                    value = int(value)
                elif value in ("0", "1"):
                    value = value == "1"
                stack[-1]["fields"][key] = value
    return result


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cursor_usr(path: Path) -> str | None:
    return cursor_result_usr(path.read_text())


audit = json.loads(AUDIT.read_text())
catalogue = json.loads(CATALOGUE.read_text())
interfaces = {
    "SwiftUI": Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"),
    "SwiftUICore": Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"),
}
audit_interface_rows = {(item["module"], item["file"]): item for item in audit["interfaces"]}
for module, path in interfaces.items():
    digest = "sha256:" + sha(path)
    row = audit_interface_rows.get((module, path.name))
    if row is None or row.get("sha256") != digest:
        raise ValueError(f"v6 audit interface pin does not match live {module} source {path}")
extraction_summary = ROOT / "factory/catalogue/evidence/extraction-summary.json"
if (audit.get("symbolgraphTarget") != "arm64-apple-macosx27.0" or
    audit.get("graphTargetEvidence", {}).get("graphInputs") != "factory/out/catalogue/raw" or
    audit.get("graphTargetEvidence", {}).get("sourceHash") != "sha256:" + sha(extraction_summary)):
    raise ValueError("v6 audit symbolgraph target/provenance does not match current raw extraction summary")
index_paths = {"SwiftUI": HERE / "index-interface-output.txt", "SwiftUICore": HERE / "index-core-output.txt"}
index_requests = {"SwiftUI": HERE / "request-index-interface.yaml", "SwiftUICore": HERE / "request-index-core.yaml"}
sdk_path = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
for module, request in index_requests.items():
    request_text = request.read_text()
    if not request_identity_matches(request_text, interface=str(interfaces[module]), sdk=sdk_path,
                                    target="arm64-apple-macosx27.0", module=module):
        raise ValueError(f"SourceKit request identity mismatch for {module}: {request}")
by_module = {module: entities(index_paths[module]) for module in interfaces}
symbols = {}
for symbol in catalogue["symbols"]:
    symbols.setdefault(symbol["usr"], []).append(symbol)
raw_graph_paths = sorted((ROOT / "factory/out/catalogue/raw").rglob("*.symbols.json"))
raw_graph_usrs = set()
for path in raw_graph_paths:
    graph = json.loads(path.read_text())
    raw_graph_usrs.update(item["identifier"]["precise"] for item in graph.get("symbols", []))
catalogue_usrs = {symbol["usr"] for symbol in catalogue["symbols"]}
if raw_graph_usrs != catalogue_usrs:
    raise ValueError("normalized catalogue USR set does not equal pinned raw graph USR set")

rows = []
for row in audit["declarations"]:
    if row["classification"] not in RESIDUALS:
        continue
    index_entities = by_module.get(row["module"], [])
    on_line = [e for e in index_entities if e["line"] == row["line"] and not e.get("is_implicit", False)]
    target_name = row["name"].strip("`")
    declaration = re.search(r"\b(?:func|var|let|typealias|struct|enum|class|protocol|actor|init|subscript)\s+`?([A-Za-z_$][A-Za-z0-9_$]*)", row["signature"])
    signature_name = declaration.group(1) if declaration else target_name
    name_candidates = [e for e in on_line if e["name"].strip("`").split("(", 1)[0] in (target_name, signature_name)]
    kind_candidates = [e for e in name_candidates if entity_kind_matches(row, e)]
    context_candidates = [e for e in kind_candidates if entity_context_matches(row, e)]
    exact = [e for e in context_candidates if entity_access_matches(row, e)
             and entity_matches({**row, "sourceHash": "sha256:" + sha(interfaces[row["module"]])}, e,
                                module=row["module"], live_interface_hash="sha256:" + sha(interfaces[row["module"]]))]
    expected_access = re.search(r"\b(public|open|package|internal|fileprivate|private)\b", row["signature"])
    expected_access = expected_access.group(1) if expected_access else None
    if not name_candidates:
        held_reason = "no-same-line-name-entity"
    elif not kind_candidates:
        held_reason = "declaration-kind-mismatch"
    elif not context_candidates:
        held_reason = "enclosing-context-mismatch"
    elif expected_access is None:
        held_reason = "expected-access-unavailable"
    elif not exact:
        held_reason = "effective-access-mismatch"
    elif len(exact) != 1:
        held_reason = "duplicate-raw-entity-records"
    else:
        held_reason = None
    by_usr: dict[str, list[dict]] = {}
    for entity in exact:
        by_usr.setdefault(entity["usr"], []).append(entity)
    rows.append({
        "module": row["module"], "interface": row["interface"], "line": row["line"],
        "auditRowKey": "sha256:" + hashlib.sha256(json.dumps(
            {"module": row["module"], "interface": row["interface"], "line": row["line"],
             "signature": row["signature"], "sourceHash": "sha256:" + sha(interfaces[row["module"]])},
            sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
        "context": row["context"], "kind": row["kind"], "name": row["name"],
        "classification": row["classification"], "searchReason": row.get("v6Evidence", {}).get("reason"),
        "signature": row["signature"], "sourceHash": "sha256:" + sha(interfaces[row["module"]]),
        "expectedAccess": expected_access,
        "linkHoldReason": held_reason,
        "sameLineEntityCount": len(on_line),
        "sameLineNameEntityCount": len(name_candidates),
        "sameLineKindEntityCount": len(kind_candidates),
        "sameLineContextEntityCount": len(context_candidates),
        "compilerEvidence": {
            "method": "sourcekit-indexsource-exact-interface-line-and-declaration-name",
            "request": "factory/catalogue/compiler-cursor-spike/request-index-" + ("interface" if row["module"] == "SwiftUI" else "core") + ".yaml",
            "requestSha256": "sha256:" + sha(HERE / ("request-index-interface.yaml" if row["module"] == "SwiftUI" else "request-index-core.yaml")),
            "response": str(index_paths[row["module"]].relative_to(ROOT)),
            "responseSha256": "sha256:" + sha(index_paths[row["module"]]),
            "compilerIdentity": "toolchainEvidence.compiler",
            "validatedTarget": "arm64-apple-macosx27.0",
        },
        "sourcekitEntityCount": len(exact),
        "distinctCompilerUsrCount": len(by_usr),
        "indexMatchCount": len(by_usr),
        "linkEligibility": unique_entity_usr(exact) is not None,
        "indexMatches": [{"kind": entities_for_usr[0]["kind"], "usr": usr,
                           "sourcekitContexts": [e.get("sourcekitContext", []) for e in entities_for_usr],
                           "effectiveAccesses": [e.get("effective_access") for e in entities_for_usr],
                           "sourcekitEntityOccurrences": len(entities_for_usr),
                           "columns": [e.get("column") for e in entities_for_usr],
                           "occurrences": [{k: e.get(k) for k in
                                            ("kind", "name", "usr", "line", "column", "effective_access", "sourcekitContext", "is_implicit")}
                                           for e in entities_for_usr],
                           "symbolGraphMatches": symbols.get(usr, [])}
                          for usr, entities_for_usr in by_usr.items()],
    })

linked = [r for r in rows if r["linkEligibility"]]
summary = {
    "kind": "sourcekit-interface-index-link-spike", "version": 1,
    "pinnedInputs": {
        "xcode": "Xcode 27.0 (27A266)", "compiler": "Apple Swift 6.4.0.34.1",
        "sdk": "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk",
        "target": "arm64-apple-macos27.0", "audit": "factory/catalogue/evidence/interface-audit-v6.json",
        "auditHash": audit["auditHash"], "auditFileByteSha256": "sha256:" + sha(AUDIT),
        "symbolCatalogue": "factory/catalogue/evidence/catalogue.json",
        "symbolCatalogueHash": "sha256:" + sha(CATALOGUE),
        "symbolGraphDirectory": "factory/out/catalogue/raw",
        "symbolGraphTarget": "arm64-apple-macosx27.0",
        "extractionSummary": "factory/catalogue/evidence/extraction-summary.json",
        "extractionSummarySha256": "sha256:" + sha(extraction_summary),
    },
    "method": "sourcekit-lsp debug run-sourcekitd-request with source.request.indexsource on each live-hash-verified arm64e .swiftinterface, using parsed exact -sdk/-target/-module-name/sourcefile request identity. A residual is link-eligible only when exactly one raw SourceKit declaration entity matches exact line/name, declaration kind, enclosing context, and effective access. Raw duplicate records are retained and held even when USR repeats. USRs are compiler output, not inferred.",
    "interfaces": [{"module": m, "path": str(interfaces[m]), "sha256": "sha256:" + sha(interfaces[m]),
                    "indexOutput": str(index_paths[m].relative_to(ROOT)), "indexOutputSha256": "sha256:" + sha(index_paths[m]),
                    "indexRequest": str(index_requests[m].relative_to(ROOT)), "indexRequestSha256": "sha256:" + sha(index_requests[m]),
                    "requestIdentity": {"sourcefile": str(interfaces[m]), "sdk": "MacOSX27.0.sdk",
                                        "target": "arm64-apple-macosx27.0", "moduleName": m},
                    "declEntityCount": len(by_module[m])} for m in interfaces],
    "summary": {
        "residualRows": len(rows), "exactSingleIndexMatch": len(linked),
        "singleDistinctUsrRows": sum(r["distinctCompilerUsrCount"] == 1 for r in rows),
        "repeatedEntityRowsHeld": sum(r["sourcekitEntityCount"] > 1 and r["distinctCompilerUsrCount"] == 1 for r in rows),
        "noOrMultipleIndexMatch": len(rows) - len(linked),
        "exactlyOneSourceKitEntity": sum(r["sourcekitEntityCount"] == 1 for r in rows),
        "repeatedSameUsrEntityRows": sum(r["sourcekitEntityCount"] > 1 and r["distinctCompilerUsrCount"] == 1 for r in rows),
        "sourceKitEntityOccurrences": sum(r["sourcekitEntityCount"] for r in rows),
        "sameLineNameCandidates": sum(r["sameLineNameEntityCount"] > 0 for r in rows),
        "sameLineNameKindCandidates": sum(r["sameLineKindEntityCount"] > 0 for r in rows),
        "sameLineNameKindContextCandidates": sum(r["sameLineContextEntityCount"] > 0 for r in rows),
        "sameLineNameKindContextAccessCandidates": sum(r["sourcekitEntityCount"] > 0 for r in rows),
        "exactMatchesWithSymbolGraphUsr": sum(bool(r["indexMatches"][0]["symbolGraphMatches"]) for r in linked),
        "exactMatchesWithoutSymbolGraphUsr": sum(not r["indexMatches"][0]["symbolGraphMatches"] for r in linked),
        "byReason": {},
        "heldByGate": {},
    },
    "examples": [], "rows": rows,
}
from collections import Counter
summary["summary"]["byReason"] = dict(sorted(Counter(r["searchReason"] or "(not recorded)" for r in rows).items()))
summary["summary"]["heldByGate"] = dict(sorted(Counter(
    r["linkHoldReason"] for r in rows if r["linkHoldReason"] is not None
).items()))
for wanted in [("SwiftUI", 852, "accessibilityLabel"), ("SwiftUI", 2690, "sensoryFeedback"),
               ("SwiftUI", 2701, "onDrop"), ("SwiftUI", 2703, "onDrop")]:
    summary["examples"].extend(r for r in linked if (r["module"], r["line"], r["name"]) == wanted)

def control(name: str, request: str, response: str, line: int | None = None) -> dict:
    req, out = HERE / request, HERE / response
    return {"name": name, "interfaceLine": line, "request": str(req.relative_to(ROOT)),
            "requestSha256": "sha256:" + sha(req), "response": str(out.relative_to(ROOT)),
            "responseSha256": "sha256:" + sha(out), "usr": cursor_usr(out)}

summary["controls"] = {
    "directInterfaceCursorInfo": control("SwiftUI.View.accessibilityLabel(content:)",
        "request-interface-module-name.yaml", "interface-cursor-module-name-output.txt", 852),
    "missingModuleNameFaultControl": control("same cursor query without -module-name", "request-interface-accessibilityLabel.yaml", "interface-cursor-output.txt", 852),
    "callSiteCursorInfo": [
        control("accessibilityLabel(content:)", "request-call-accessibilityLabel-1.yaml", "output-call-accessibilityLabel-1.txt"),
        control("sensoryFeedback(trigger:_:)", "request-call-sensoryFeedback-1.yaml", "output-call-sensoryFeedback-1.txt"),
        control("dropDestination(for:action:isTargeted:)", "request-call-dropDestination-1.yaml", "output-call-dropDestination-1.txt"),
        control("dropDestination(for:isEnabled:action:)", "request-call-dropDestination-2.yaml", "output-call-dropDestination-2.txt"),
        control("onDrop(of:isTargeted:perform:) [NSItemProvider]", "request-call-onDrop-1.yaml", "output-call-onDrop-1.txt"),
        control("onDrop(of:isTargeted:perform:) [NSItemProvider, CGPoint]", "request-call-onDrop-2.yaml", "output-call-onDrop-2.txt"),
    ],
    "conditionalBranchControls": {
        "activeTildeSendable": control("MenuButton in selected $TildeSendable branch", "request-active-menu-button.yaml", "active-interface-cursor-output.txt", 376),
        "inactiveTildeSendable": control("MenuButton in inactive #else branch", "request-inactive-menu-button.yaml", "inactive-interface-cursor-output.txt", 394),
        "inlineAlwaysSelectedBranchProbe": {
            "source": "factory/catalogue/compiler-cursor-spike/inline-always-conditional-probe.swift",
            "sourceSha256": "sha256:" + sha(HERE / "inline-always-conditional-probe.swift"),
            "output": "factory/catalogue/compiler-cursor-spike/inline-always-conditional-output.txt",
            "outputSha256": "sha256:" + sha(HERE / "inline-always-conditional-output.txt"),
            "stdout": (HERE / "inline-always-conditional-output.txt").read_text().strip(),
        },
        "inactiveWidgetBundleOverload": {
            "module": "SwiftUI", "interfaceLine": 28491, "name": "buildLimitedAvailability",
            "context": ["WidgetBundleBuilder"], "condition": "compiler(>=5.3) && $InlineAlways",
            "selectedBranch": "InlineAlways", "indexMatchCount": 0,
            "cursorInfo": control("buildLimitedAvailability in inactive #else branch", "request-buildLimitedAvailability.yaml", "buildLimitedAvailability-output.txt", 28491),
        },
    },
}
callsite_controls = summary["controls"]["callSiteCursorInfo"]
for probe in callsite_controls:
    probe["exactInterfaceRowsWithSameUsr"] = [
        {"module": r["module"], "interface": r["interface"], "line": r["line"],
         "name": r["name"], "sourceHash": r["sourceHash"], "entityCount": r["sourcekitEntityCount"],
         "distinctCompilerUsrCount": r["distinctCompilerUsrCount"]}
        for r in rows if any(m["usr"] == probe["usr"] for m in r["indexMatches"])
    ]
compiler_driver_path = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
compiler_path = compiler_driver_path.resolve()
sourcekit_lsp_path = Path(subprocess.check_output(["xcrun", "--find", "sourcekit-lsp"], text=True).strip()).resolve()
sourcekitd_path = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd").resolve()
xcode_version = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
compiler_version = subprocess.check_output([str(compiler_path), "--version"], text=True).strip()
summary["toolchainEvidence"] = {
    "xcodebuildVersion": xcode_version,
    "compiler": {"driverPath": str(compiler_driver_path), "executablePath": str(compiler_path),
                 "version": compiler_version, "sha256": "sha256:" + sha(compiler_path)},
    "sourcekitLsp": {"path": str(sourcekit_lsp_path), "sha256": "sha256:" + sha(sourcekit_lsp_path)},
    "sourcekitd": {"path": str(sourcekitd_path), "sha256": "sha256:" + sha(sourcekitd_path)},
    "sdk": sdk_path, "target": "arm64-apple-macosx27.0",
}
summary["rawGraphInputs"] = [
    {"path": str(path.relative_to(ROOT)), "sha256": "sha256:" + sha(path)}
    for path in raw_graph_paths
]
usr_digest = lambda values: "sha256:" + hashlib.sha256(json.dumps(sorted(values), separators=(",", ":")).encode()).hexdigest()
summary["rawGraphUsrClosure"] = {
    "graphTarget": audit["symbolgraphTarget"], "graphInputDirectory": "factory/out/catalogue/raw",
    "rawGraphUsrCount": len(raw_graph_usrs), "rawGraphUsrSetSha256": usr_digest(raw_graph_usrs),
    "catalogueUsrCount": len(catalogue_usrs), "catalogueUsrSetSha256": usr_digest(catalogue_usrs),
    "setsEqual": raw_graph_usrs == catalogue_usrs,
}
(HERE / "link-evidence.json").write_text(json.dumps(summary, sort_keys=True, separators=(",", ":")) + "\n")
print(json.dumps({"summary": summary["summary"], "exampleRows": [
    {k:r.get(k) for k in ("module", "line", "name", "classification", "indexMatchCount", "indexMatches")} for r in summary["examples"]]}, indent=2))
