#!/usr/bin/env python3
"""Capture exact SwiftUI -> SwiftUICore external-owner raw facts.

This file records source, SourceKit, and symbol-graph facts only. It makes no
public-ancestor or promotion decision.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
CENSUS = ROOT / "factory/catalogue/public-ancestor-spike/raw/ancestor-census-v1.json"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
PARSER = ROOT / "factory/catalogue/module-provenance-spike/exact_validator.py"
OUTPUT = HERE / "external-owner-evidence.json"
EXPECTED_LINK_SHA = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_CENSUS_SHA = "sha256:ba84859f8387d3c1361b3287a5adf458fd256ffb8c8d900c72997cf43cdaf174"
EXPECTED_TARGETS = {
    "AttributedTextFormatting", "Color", "ControlSize", "CustomHoverEffect",
    "DynamicViewContent", "EdgeInsets", "EmptyModifier", "EmptyView",
    "EnvironmentValues", "ForEach", "Gesture", "Group", "HoverEffectContent",
    "Image", "ImageRenderer", "LayoutSubview", "ModifiedContent", "SectionConfiguration",
    "Shape", "ShapeStyle", "Subview", "Text", "Text.LineStyle", "TimelineSchedule",
    "Transaction", "TupleContent", "View", "ViewBuilder", "ViewModifier",
    "_AppearanceActionModifier", "_AsyncValueActionModifier", "_BenchmarkHost",
    "_ConditionalContent", "_EnvironmentKeyTransformModifier", "_EnvironmentKeyWritingModifier",
    "_PreferenceTransformModifier", "_PreferenceWritingModifier", "_TestApp", "_ValueActionModifier",
}
NOMINAL_RE = re.compile(r"\b(struct|class|enum|protocol|actor)\s+(`?[A-Za-z_][A-Za-z_0-9]*`?)")
EXTENSION_RE = re.compile(r"\bextension\s+([A-Za-z_][A-Za-z_0-9:.]*)[^\{]*\{")
ACCESS_RE = re.compile(r"\b(public|open|package|internal|fileprivate|private)\b")


def digest(data: bytes | str) -> str:
    if isinstance(data, str):
        data = data.encode()
    return "sha256:" + hashlib.sha256(data).hexdigest()


def digest_path(path: Path) -> str:
    return digest(path.read_bytes())


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError("unable to load pinned parser")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def brace_ranges(lines: list[str]) -> list[dict[str, Any]]:
    """Record exact source extension ranges, including SwiftUICore:: targets."""
    ranges: list[dict[str, Any]] = []
    depth = 0
    active: list[dict[str, Any]] = []
    for number, line in enumerate(lines, 1):
        header = EXTENSION_RE.search(line)
        if header:
            record = {
                "line": number,
                "target": header.group(1),
                "sourceText": line,
                "startDepth": depth,
                "endLine": None,
            }
            active.append(record)
        # Interface headers contain no string literals with braces. Preserve exact depth.
        depth += line.count("{") - line.count("}")
        while active and depth <= active[-1]["startDepth"]:
            active[-1]["endLine"] = number
            ranges.append(active.pop())
        require(depth >= 0, "negative SDK brace depth")
    require(depth == 0 and not active, "unbalanced SDK extension source")
    return ranges


def target_path_for_line(
    line_number: int,
    name: str,
    model: dict[int, dict[str, Any]],
    extension_ranges: list[dict[str, Any]],
) -> tuple[str, ...]:
    scopes = model[line_number]["scopes"]
    path: list[str] = []
    for scope in scopes:
        if scope["kind"] in {"struct", "class", "enum", "protocol", "actor"}:
            path.append(scope["name"])
    if not path:
        enclosing = [r for r in extension_ranges if r["line"] < line_number <= (r["endLine"] or 0)]
        if enclosing:
            target = enclosing[-1]["target"]
            if target.startswith("SwiftUICore::"):
                path.extend(target.removeprefix("SwiftUICore::").split("::"))
            elif target.startswith("SwiftUICore."):
                path.extend(target.removeprefix("SwiftUICore.").split("."))
    path.append(name)
    return tuple(path)


def nominal_records(
    source: str,
    module: str,
    model: dict[int, dict[str, Any]],
    entities: list[dict[str, Any]],
    target_paths: set[tuple[str, ...]],
) -> dict[tuple[str, ...], list[dict[str, Any]]]:
    lines = source.splitlines()
    ranges = brace_ranges(lines)
    by_line: dict[int, list[dict[str, Any]]] = {}
    for entity in entities:
        if isinstance(entity.get("line"), int):
            by_line.setdefault(entity["line"], []).append({"module": module, **entity})
    found: dict[tuple[str, ...], list[dict[str, Any]]] = {key: [] for key in target_paths}
    for number, line in enumerate(lines, 1):
        match = NOMINAL_RE.search(line)
        if not match or "{" not in line:
            continue
        name = match.group(2).strip("`")
        path = target_path_for_line(number, name, model, ranges)
        if path not in target_paths:
            continue
        kind = match.group(1)
        prefix = line[: match.start()]
        access_tokens = ACCESS_RE.findall(prefix)
        record = {
            "module": module,
            "path": list(path),
            "line": number,
            "kind": kind,
            "name": name,
            "access": access_tokens[-1] if access_tokens else None,
            "sourceText": line,
            "conditions": model[number]["conditions"],
            "rawEntities": by_line.get(number, []),
            "ownerEntityStatus": "present" if by_line.get(number) else "missing-in-pinned-index",
            "ownerChain": [],
        }
        for scope in model[number]["scopes"]:
            if scope["kind"] in {"struct", "class", "enum", "protocol", "actor"}:
                record["ownerChain"].append({
                    "module": module, "kind": scope["kind"], "name": scope["name"],
                    "line": scope["line"],
                })
        enclosing = [r for r in ranges if r["line"] < number <= (r["endLine"] or 0)]
        if enclosing and not record["ownerChain"]:
            owner = enclosing[-1]
            if owner["target"].startswith("SwiftUICore"):
                record["ownerChain"].append({
                    "module": module, "kind": "extension", "target": owner["target"],
                    "line": owner["line"], "sourceText": owner["sourceText"],
                })
        record["ownerChain"].append({
            "module": module, "kind": kind, "name": name, "line": number,
        })
        found[path].append(record)
    return found


def graph_matches(graph: dict[str, Any], target: tuple[str, ...]) -> list[dict[str, Any]]:
    return [item for item in graph.get("symbols", []) if item.get("pathComponents") == list(target)]


def descriptor(path: Path, relative: bool = True) -> dict[str, str]:
    return {"path": str(path.relative_to(ROOT) if relative and path.is_relative_to(ROOT) else path),
            "sha256": digest_path(path)}


def capture() -> dict[str, Any]:
    require(digest_path(LINK) == EXPECTED_LINK_SHA, "immutable 836 changed")
    link = json.loads(LINK.read_text(encoding="utf-8"))
    census_bytes = CENSUS.read_bytes()
    census_sha = digest(census_bytes)
    require(census_sha == EXPECTED_CENSUS_SHA, "frozen census bytes changed")
    census = json.loads(census_bytes)
    parser_hash = digest_path(PARSER)
    helper = load_module(PARSER, "_external_owner_exact_parser")
    require(census["summary"]["crossModuleExtensionOwnerRows"] == 541, "unexpected external extension denominator")
    cross = census["crossModuleExtensions"]
    targets = {tuple(item["targetTypePathSpelling"]) for item in cross}
    require({".".join(item) for item in targets} == EXPECTED_TARGETS, "target path set changed")

    interfaces = {item["module"]: item for item in link["interfaces"]}
    swiftui = interfaces["SwiftUI"]
    core = interfaces["SwiftUICore"]
    swiftui_source = Path(swiftui["path"])
    core_source = Path(core["path"])
    require(digest_path(swiftui_source) == swiftui["sha256"], "SwiftUI source pin changed")
    require(digest_path(core_source) == core["sha256"], "SwiftUICore source pin changed")
    swiftui_index_path = ROOT / swiftui["indexOutput"]
    core_index_path = ROOT / core["indexOutput"]
    swiftui_request_path = ROOT / swiftui["indexRequest"]
    core_request_path = ROOT / core["indexRequest"]
    for item, path, key in (
        (swiftui, swiftui_index_path, "indexOutputSha256"),
        (core, core_index_path, "indexOutputSha256"),
        (swiftui, swiftui_request_path, "indexRequestSha256"),
        (core, core_request_path, "indexRequestSha256"),
    ):
        require(digest_path(path) == item[key], "pinned SourceKit input changed: " + str(path))

    swiftui_entities = helper.entities(swiftui_index_path.read_text(encoding="utf-8"))
    core_entities = helper.entities(core_index_path.read_text(encoding="utf-8"))
    index_entities = census["compilerIndexEntities"]
    index_contexts = census["compilerIndexContexts"]
    require(len(index_entities) == len(swiftui_entities) + len(core_entities), "census SourceKit entity denominator mismatch")

    def raw_entities(module: str, refs: list[int]) -> list[dict[str, Any]]:
        result = []
        for ref in refs:
            item = dict(index_entities[ref])
            require(item.get("module") == module, "cross-module SourceKit entity reference")
            context_ref = item.pop("sourcekitContextRef", None)
            item["sourcekitContext"] = index_contexts[context_ref] if context_ref is not None else []
            result.append(item)
        return result

    core_source_text = core_source.read_text(encoding="utf-8")
    core_model = helper.source_model(core_source_text)
    target_records = nominal_records(core_source_text, "SwiftUICore", core_model, core_entities, targets)
    require(all(target_records[target] for target in targets), "one or more target nominal records missing")

    graph_path = next(Path(item["path"]) for item in link["rawGraphInputs"]
                      if item["path"] == "factory/out/catalogue/raw/swiftuicore/SwiftUICore.symbols.json")
    require(digest_path(ROOT / graph_path) == next(item["sha256"] for item in link["rawGraphInputs"] if item["path"] == str(graph_path)), "SwiftUICore graph pin changed")
    graph = json.loads((ROOT / graph_path).read_text(encoding="utf-8"))
    rows_by_key = {tuple(item["rowKey"]): item for item in census["rows"]}
    source_lines = census["sourceLines"]
    extensions = []
    for owner in cross:
        owner_record = census["lexicalOwnerRecords"][owner["ownerRecordIndex"]]
        owner_source_line = source_lines[owner_record["sourceLineRef"]]
        header_entities = raw_entities(owner["sourceModule"], owner_record["sameLineCompilerEntityRefs"])
        members = []
        for row_key in owner["sourceMemberV12Rows"]:
            row = rows_by_key[tuple(row_key)]
            members.append({
                "key": row["rowKey"], "line": row["rowKey"][2], "name": row["rowKey"][3],
                "sourceText": source_lines[row["sourceLineRef"]]["text"],
                "conditions": row["conditionalStack"],
                "rawEntities": raw_entities(row["sourceModule"], row["sameLineCompilerEntityRefs"]),
            })
        target = tuple(owner["targetTypePathSpelling"])
        extensions.append({
            "sourceModule": owner["sourceModule"],
            "sourcePath": swiftui["path"],
            "sourceLine": owner["sourceInterfaceLine"],
            "sourceText": owner_source_line["text"],
            "targetModule": owner["targetModuleSpelling"],
            "targetPath": list(target),
            "conditions": owner_record["conditionalStack"],
            "rawExtensionEntities": header_entities,
            "extensionEntityStatus": "present" if header_entities else "missing-in-pinned-index",
            "memberRows": members,
            "nominalOwnerRecords": target_records[target],
            "graphMatches": graph_matches(graph, target),
            "classification": "raw-external-owner-facts-no-eligibility-decision",
        })
    toolchain = link["toolchainEvidence"]
    payload = {
        "kind": "f1-public-ancestor-external-owner-raw-capture",
        "version": 1,
        "status": "raw-facts-no-eligibility-decisions",
        "scope": "SwiftUI source extensions with explicitly qualified SwiftUICore nominal targets",
        "counts": {
            "crossModuleExtensionHeaders": len(extensions),
            "extensionHeadersWithV12MemberRows": sum(bool(x["memberRows"]) for x in extensions),
            "uniqueTargetPaths": len(targets),
            "nominalTargetRecordCount": sum(len(v) for v in target_records.values()),
            "graphPresentTargetPaths": sum(bool(graph_matches(graph, t)) for t in targets),
            "graphAbsentTargetPaths": sum(not graph_matches(graph, t) for t in targets),
        },
        "pins": {
            "immutable836": descriptor(LINK),
            "census": {"path": str(CENSUS.relative_to(ROOT)), "sha256": census_sha},
            "sourceParser": descriptor(PARSER),
            "swiftuiInterface": {"path": swiftui["path"], "sha256": swiftui["sha256"],
                                  "sourceKitRequest": descriptor(swiftui_request_path),
                                  "sourceKitOutput": descriptor(swiftui_index_path)},
            "swiftuiCoreInterface": {"path": core["path"], "sha256": core["sha256"],
                                      "sourceKitRequest": descriptor(core_request_path),
                                      "sourceKitOutput": descriptor(core_index_path)},
            "swiftuiCoreSymbolGraph": descriptor(ROOT / graph_path),
            "toolchain": toolchain,
            "target": toolchain["target"],
        },
        "rawStreamFacts": {
            "swiftuiSourceKitEntityCount": len(swiftui_entities),
            "swiftuiCoreSourceKitEntityCount": len(core_entities),
            "swiftuiRequestBytes": swiftui_request_path.read_text(encoding="utf-8"),
            "swiftuiCoreRequestBytes": core_request_path.read_text(encoding="utf-8"),
            "swiftuiIndexOutputSha256": digest_path(swiftui_index_path),
            "swiftuiCoreIndexOutputSha256": digest_path(core_index_path),
            "swiftuiCoreGraphSymbolCount": len(graph["symbols"]),
        },
        "targetPaths": sorted(".".join(target) for target in targets),
        "extensions": extensions,
    }
    require(digest_path(CENSUS) == census_sha, "census changed during capture")
    payload["captureSha256"] = digest(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return payload


if __name__ == "__main__":
    result = capture()
    OUTPUT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"path": str(OUTPUT.relative_to(ROOT)), "counts": result["counts"],
                      "captureSha256": result["captureSha256"]}, sort_keys=True))
