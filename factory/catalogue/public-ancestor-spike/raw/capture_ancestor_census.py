#!/usr/bin/env python3
"""Capture a source-bound public-ancestor census; no eligibility decisions."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[4]
RAW = Path(__file__).resolve().parent
V12 = ROOT / "factory/catalogue/evidence/interface-audit-v12-candidate.json"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
CATALOGUE = ROOT / "factory/catalogue/evidence/catalogue.json"
CATALOGUE_SOURCE = ROOT / "factory/catalogue/catalogue.py"
PARSER = ROOT / "factory/catalogue/module-provenance-spike/exact_validator.py"
LEXICAL_PARSER = ROOT / "factory/catalogue/public-ancestor-spike/lexical_model.py"
PARSER_SHA = "sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5"
LEXICAL_PARSER_SHA = "sha256:88c8ee0f71e18288f5502df757f55879cf16b1a470732c75f999618d0ab04f63"
V12_SHA = "sha256:6f0384e8dfaa1bb21f96c3153cb02425912b6425cfdd534eb01a7f2ab71e1d13"
V12_AUDIT = "sha256:b9b89111ab874ea006f0c65cc2cc8f0ef127c27a36402282c134c76be7a90d7e"
V12_SOURCE_SHA = "sha256:ab4b9fa8e6bbeb7fef9c52d13b6f0ec9e40e64a998d405d323a880ab6b48ed11"
V12_TEST_SHA = "sha256:c01451f57308cc6398052e8c66539c06bf693fda6bd2bdfb589fd5a1418a8ba8"
LINK_SHA = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
ACCESS = {"public", "open", "package", "internal", "fileprivate", "private"}
MODIFIERS = ("nonisolated", "static", "class", "final", "mutating", "nonmutating", "override",
             "prefix", "postfix", "infix", "indirect", "lazy", "weak", "unowned", "isolated",
             "distributed", "consuming", "borrowing", "sending", "async", "throws", "rethrows",
             "unsafe", "noncopyable")
KINDS = ("func", "var", "let", "subscript", "init", "deinit", "struct", "class", "enum",
         "protocol", "actor", "typealias", "associatedtype", "operator", "macro", "case")
DECL_START = re.compile(
    r"\b(?:(public|open|package|internal|fileprivate|private)\s+)?"
    r"(?:(?:" + "|".join(MODIFIERS) + r")\s+)*"
    r"(" + "|".join(KINDS) + r")\s+?(`[^`]+`|\$?[A-Za-z_][A-Za-z_0-9]*|[+*/=<>!&|^~%-]+)?"
)
ACCESS_TOKEN = re.compile(r"\b(public|open|package|internal|fileprivate|private)\b")
NOMINAL = re.compile(r"\b(struct|class|enum|protocol|actor)\s+(`?[A-Za-z_][A-Za-z_0-9]*`?)")
EXTENSION = re.compile(r"\bextension\s+([^{}]+?)(?:\s+where\s+[^{}]+)?\s*\{")
ATTR = re.compile(r"@_?[A-Za-z][A-Za-z0-9_]*(?:\([^)]*\))?")


def sha_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha_file(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def require(ok: bool, why: str) -> None:
    if not ok:
        raise ValueError(why)


def load_helper():
    require(sha_file(PARSER) == PARSER_SHA, "pinned lexical/compiler parser changed")
    spec = importlib.util.spec_from_file_location("_f1_ancestor_census_parser", PARSER)
    require(spec is not None and spec.loader is not None, "cannot load pinned source model")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_lexical_parser():
    require(sha_file(LEXICAL_PARSER) == LEXICAL_PARSER_SHA, "pinned lexical census parser changed")
    spec = importlib.util.spec_from_file_location("_f1_public_ancestor_lexical", LEXICAL_PARSER)
    require(spec is not None and spec.loader is not None, "cannot load lexical census parser")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def access_of(text: str) -> dict[str, Any]:
    tokens = ACCESS_TOKEN.findall(text)
    return {"explicitAccess": tokens[-1] if tokens else None,
            "accessEvidence": "explicit-token" if tokens else "unspecified-in-source"}


def preceding_attributes(lines: list[str], model: dict[int, dict[str, Any]], number: int) -> list[dict[str, Any]]:
    result = []
    cursor = number - 1
    while cursor > 0 and lines[cursor - 1].strip().startswith("@"):
        if model[cursor]["scopes"] != model[number]["scopes"] or model[cursor]["conditions"] != model[number]["conditions"]:
            break
        result.insert(0, {"line": cursor, "text": lines[cursor - 1].strip()})
        cursor -= 1
    return result


def nominal_identity(scopes: list[dict[str, Any]], source_module: str) -> tuple[list[str], str | None, str]:
    path: list[str] = []
    owner_module: str | None = None
    reasons = []
    for scope in scopes:
        if scope["kind"] == "extension":
            raw = scope["target"]
            parts = raw.split(".")
            if parts and parts[0] in {"SwiftUI", "SwiftUICore"}:
                owner_module = parts.pop(0)
            else:
                owner_module = None
                reasons.append("unqualified-extension-target-origin-unresolved")
            path = parts if owner_module else path + [raw]
        else:
            path.append(scope["name"])
            if owner_module is None:
                owner_module = source_module
    if owner_module is None:
        reasons.append("owner-module-not-exactly-qualified")
    return path, owner_module, ";".join(dict.fromkeys(reasons)) or "source-qualified-or-declared"


def parse_access_header(text: str, kind: str, scope: dict[str, Any]) -> dict[str, Any]:
    access = access_of(text)
    if scope["kind"] == "extension":
        match = EXTENSION.search(text)
        if match is None:
            target = scope["target"]
            parse_status = "scope-target-from-pinned-parser-header-unverified"
        else:
            target = match[1].strip()
            target = re.split(r"\s+where\s+", target, maxsplit=1)[0].strip()
            # A single top-level colon begins an inheritance/conformance clause;
            # the double colon used in Swift module-qualified names is preserved.
            depth = 0
            cut = None
            for index, char in enumerate(target):
                if char in "<([":
                    depth += 1
                elif char in ">)]":
                    depth = max(0, depth - 1)
                elif char == ":" and depth == 0 and not (
                    (index and target[index - 1] == ":") or
                    (index + 1 < len(target) and target[index + 1] == ":")
                ):
                    cut = index
                    break
            if cut is not None:
                target = target[:cut].strip()
            parse_status = "source-header-target-exact"
        qualified = target.split(".")
        module = qualified[0] if qualified and qualified[0] in {"SwiftUI", "SwiftUICore"} else None
        path = qualified[1:] if module else qualified
        return {**access, "ownerKind": "extension", "targetSpelling": target,
                "targetModuleSpelling": module, "targetTypePathSpelling": path,
                "moduleResolution": "explicit-module-qualifier" if module else "unqualified-origin-unresolved",
                "parseStatus": parse_status}
    match = NOMINAL.search(text)
    if match is None:
        return {**access, "ownerKind": kind, "name": scope.get("name"), "module": None,
                "moduleResolution": "source-owner-declaration-not-parsed", "parseStatus": "unresolved"}
    return {**access, "ownerKind": match[1], "name": match[2].strip("`"),
            "module": None, "moduleResolution": "nominal-origin-requires-source-declaration-proof",
            "parseStatus": "source-header-nominal-name-exact"}


def declaration_starts(source: str, source_module: str, interface_name: str, source_hash: str,
                       model: dict[int, dict[str, Any]], index_entities: list[dict[str, Any]]) -> list[dict[str, Any]]:
    lines = source.splitlines()
    indexed_by_line: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for entity in index_entities:
        if isinstance(entity.get("line"), int):
            indexed_by_line[entity["line"]].append(entity)

    scope_headers: dict[int, dict[str, Any]] = {}
    for number, line in enumerate(lines, 1):
        snapshot = model[number]
        for scope in snapshot["scopes"]:
            scope_headers.setdefault(scope["line"], copy.deepcopy(scope))
    owners: dict[int, dict[str, Any]] = {}
    for number, scope in scope_headers.items():
        line = lines[number - 1]
        header = parse_access_header(line, scope["kind"], scope)
        attrs = preceding_attributes(lines, model, number)
        owners[number] = {
            "line": number, "kind": scope["kind"], "sourceText": line,
            "scopeDepth": scope["depth"], **header, "attributes": attrs,
            "conditionalStack": copy.deepcopy(model[number]["conditions"]),
            "sameLineCompilerEntities": copy.deepcopy(indexed_by_line.get(number, [])),
        }

    lexical_parser = load_lexical_parser()
    parsed_source = lexical_parser.model(source, source_module)
    starts = []
    for declaration in parsed_source["declarations"]:
            number = declaration["line"]
            line = lines[number - 1]
            clean = re.sub(r"//.*$", "", line)
            kind, name, access = declaration["kind"], declaration["name"], declaration["explicitAccess"]
            scope_refs = copy.deepcopy(model[number]["scopes"])
            scope_records = [copy.deepcopy(owners.get(scope["line"], {
                "line": scope["line"], "kind": scope["kind"], "sourceText": lines[scope["line"]-1],
                **parse_access_header(lines[scope["line"]-1], scope["kind"], scope),
                "parseStatus": "owner-record-fallback",
            })) for scope in scope_refs]
            owner_path, owner_module, module_status = nominal_identity(scope_refs, source_module)
            attrs = preceding_attributes(lines, model, number)
            attrs.extend({"line": number, "text": x} for x in ATTR.findall(clean))
            same_line = copy.deepcopy(indexed_by_line.get(number, []))
            ancestors_kinds = [scope["kind"] for scope in scope_refs]
            implicit_rules = []
            if "protocol" in ancestors_kinds and access is None:
                implicit_rules.append("possible-protocol-requirement-default-public")
            if kind == "case" and "enum" in ancestors_kinds and access is None:
                implicit_rules.append("possible-enum-case-default-public")
            case_names = []
            if kind == "case":
                case_match = re.search(r"\bcase\b", clean)
                case_tail = clean[case_match.end():].strip() if case_match else ""
                # Preserve each top-level enum case label; payload syntax is retained verbatim.
                token = re.compile(r"(?<![A-Za-z0-9_])(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)")
                case_names = [m.group(1).strip("`") for m in token.finditer(case_tail)]
            starts.append({
                "sourceModule": source_module, "interface": interface_name, "sourceHash": source_hash,
                "line": number, "kind": kind, "name": name, "explicitAccess": access,
                "accessEvidence": "explicit-token" if access else "unspecified-in-source",
                "sourceText": line, "attributes": attrs,
                "conditionalStack": copy.deepcopy(model[number]["conditions"]),
                "lexicalAncestors": scope_records, "ownerPathSpelling": owner_path,
                "ownerModuleSpelling": owner_module, "ownerModuleResolution": module_status,
                "implicitPublicRuleCandidates": implicit_rules,
                "enumCaseNameCandidates": case_names,
                "sameLineCompilerEntityCount": len(same_line),
                "sameLineCompilerEntities": same_line,
                "sourceLineDeclarationOrdinal": sum(1 for prior in starts if prior["line"] == number),
                "lexicalParserScopeLines": declaration["scopeLines"],
                "lexicalParserInsideFunction": declaration["insideFunction"],
                "declarationOrigin": "pinned-source-lexical-parser",
            })
    return starts


def all_owner_records(source: str, source_module: str, model: dict[int, dict[str, Any]],
                      index_entities: list[dict[str, Any]]) -> list[dict[str, Any]]:
    lines = source.splitlines()
    by_line: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for entity in index_entities:
        if isinstance(entity.get("line"), int):
            by_line[entity["line"]].append(entity)
    scopes: dict[int, dict[str, Any]] = {}
    for snapshot in model.values():
        for scope in snapshot["scopes"]:
            scopes.setdefault(scope["line"], copy.deepcopy(scope))
    out = []
    for line_no, scope in sorted(scopes.items()):
        text = lines[line_no - 1]
        attrs = preceding_attributes(lines, model, line_no)
        header = parse_access_header(text, scope["kind"], scope)
        path, module, status = nominal_identity(model[line_no]["scopes"], source_module)
        out.append({
            "sourceModule": source_module, "sourceInterfaceLine": line_no, "kind": scope["kind"],
            "sourceText": text, **header, "attributes": attrs,
            "conditionalStack": copy.deepcopy(model[line_no]["conditions"]),
            "lexicalAncestors": copy.deepcopy(model[line_no]["scopes"]),
            "ownerPathSpelling": path, "ownerModuleSpelling": module,
            "ownerModuleResolution": status,
            "sameLineCompilerEntities": copy.deepcopy(by_line.get(line_no, [])),
        })
    return out


def compact_census(payload: dict[str, Any]) -> dict[str, Any]:
    """Deduplicate source lines/entities and replace repeated objects with stable refs."""
    starts = payload["sourceDeclarationStarts"]
    owners = payload["lexicalOwnerRecords"]
    rows = payload["rows"]
    interfaces = payload["pinnedInputs"]["interfaces"]
    module_interfaces = {item["module"]: Path(item["path"]).name for item in interfaces}

    # Raw entity table is reconstructed from immutable pinned index output. Keep identity,
    # effective access and full context once, rather than copying it into every row.
    helper = load_helper()
    entity_table: list[dict[str, Any]] = []
    entity_contexts: list[list[dict[str, Any]]] = []
    context_index: dict[str, int] = {}
    entity_index_by_key: dict[tuple[str, str, int, int], int] = {}
    for item in interfaces:
        raw = (ROOT / item["rawSourceKitOutputPath"]).read_text(encoding="utf-8")
        for entity in helper.entities(raw):
            key = (item["module"], entity["usr"], entity["line"], entity["column"])
            entity_index_by_key[key] = len(entity_table)
            context = entity.pop("sourcekitContext", [])
            encoded_context = json.dumps(context, sort_keys=True, separators=(",", ":"))
            if encoded_context not in context_index:
                context_index[encoded_context] = len(entity_contexts)
                entity_contexts.append(context)
            entity_table.append({"module": item["module"], **entity,
                                 "sourcekitContextRef": context_index[encoded_context]})

    # A line is stored once, with source hash tying it to the pinned SDK interface.
    source_lines: dict[str, dict[str, Any]] = {}
    def line_ref(module: str, line: int, text: str) -> str:
        ref = f"{module}:{module_interfaces[module]}:{line}"
        source_lines[ref] = {"module": module, "interface": module_interfaces[module],
                             "line": line, "text": text}
        return ref

    start_indices_by_line: dict[tuple[str, int], list[int]] = defaultdict(list)
    for index, start in enumerate(starts):
        module = start["sourceModule"]
        start_indices_by_line[(module, start["line"])].append(index)
        entities = start.pop("sameLineCompilerEntities")
        start["sameLineCompilerEntityRefs"] = [
            entity_index_by_key[(module, entity["usr"], entity["line"], entity["column"])]
            for entity in entities
        ]
        line = start.pop("line")
        start["sourceLineRef"] = line_ref(module, line, start.pop("sourceText"))
        start["attributeLineRefs"] = [line_ref(module, a["line"], a["text"]) for a in start.pop("attributes")]
        start["lexicalAncestorLines"] = [scope["line"] for scope in start.pop("lexicalAncestors")]

    for owner in owners:
        module = owner["sourceModule"]
        entities = owner.pop("sameLineCompilerEntities")
        owner["sameLineCompilerEntityRefs"] = [
            entity_index_by_key[(module, entity["usr"], entity["line"], entity["column"])]
            for entity in entities
        ]
        line = owner.pop("sourceInterfaceLine")
        owner["sourceLineRef"] = line_ref(module, line, owner.pop("sourceText"))
        owner["attributeLineRefs"] = [line_ref(module, a["line"], a["text"]) for a in owner.pop("attributes")]
        owner["lexicalAncestorLines"] = [scope["line"] for scope in owner.pop("lexicalAncestors")]

    for row in rows:
        module, interface, line, _ = row["rowKey"]
        entities = row.pop("sameLineCompilerEntities")
        row["sameLineCompilerEntityRefs"] = [
            entity_index_by_key[(module, entity["usr"], entity["line"], entity["column"])]
            for entity in entities
        ]
        row["sourceLineRef"] = line_ref(module, line, row.pop("sourceLine"))
        row.pop("sourcePath", None)
        row.pop("sourceSha256", None)
        row.pop("compilerIndexPath", None)
        row.pop("compilerIndexSha256", None)
        row.pop("compilerRequestPath", None)
        row.pop("compilerRequestSha256", None)
        row.pop("v12Signature", None)
        row.pop("v12Context", None)
        row.pop("v12Conditions", None)
        model = row.pop("sourceSourceModel")
        row["lexicalAncestorLines"] = [scope["line"] for scope in model["scopes"]]
        row["conditionalStack"] = model["conditions"]
        row.pop("v12SourceKitEvidence", None)
        row.pop("allSameLineSourceDeclarationStarts", None)
        row["sourceDeclarationStartIndices"] = start_indices_by_line[(module, line)]

    for owner in payload["crossModuleExtensions"]:
        owner["ownerRecordIndex"] = next(
            i for i, record in enumerate(owners)
            if record["sourceModule"] == owner["sourceModule"]
            and record["sourceLineRef"] == f"{owner['sourceModule']}:{module_interfaces[owner['sourceModule']]}:{owner['sourceInterfaceLine']}"
        )
        for key in ("sourceText", "attributes", "conditionalStack", "lexicalAncestors",
                    "ownerPathSpelling", "ownerModuleSpelling", "ownerModuleResolution",
                    "sameLineCompilerEntities"):
            owner.pop(key, None)

    for item in payload["unparsedScopeLookingHeaders"]:
        module, line = item["sourceModule"], item["line"]
        item["sourceLineRef"] = line_ref(module, line, item.pop("sourceText"))

    payload["pinnedInputs"]["rawInterfaceTextPolicy"] = (
        "source line text is stored once in sourceLines; complete source bytes are pinned by sourceSha256 and external immutable SDK path"
    )
    payload["sourceLines"] = source_lines
    payload["compilerIndexEntities"] = entity_table
    payload["compilerIndexContexts"] = entity_contexts
    payload["summary"]["compilerIndexEntityTableRows"] = len(entity_table)
    payload["summary"]["sourceLineTextRows"] = len(source_lines)
    return payload


def capture() -> dict[str, Any]:
    require(sha_file(V12) == V12_SHA, "v12 audit bytes differ from reviewed snapshot")
    v12 = json.loads(V12.read_text(encoding="utf-8"))
    require(v12["auditHash"] == V12_AUDIT, "v12 canonical audit differs from reviewed snapshot")
    require(sha_file(LINK) == LINK_SHA, "immutable 836 bytes differ")
    link = json.loads(LINK.read_text(encoding="utf-8"))
    require(sha_file(PARSER) == PARSER_SHA, "compiler parser hash differs")
    helper = load_helper()
    source = CATALOGUE_SOURCE.read_text(encoding="utf-8")
    catalogue_source_hash = sha_file(CATALOGUE_SOURCE)
    require("def _interface_declarations" in source and "DECL = re.compile" in source,
            "pinned catalogue parser source lacks known declaration extractor")

    rows_by_interface: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in v12["declarations"]:
        rows_by_interface[(row["module"], row["interface"])].append(row)

    raw_interfaces = []
    start_inventory = []
    owner_records = []
    row_census = []
    unknown_scopes = []
    module_index_counts = {}
    toolchain = link["toolchainEvidence"]
    for descriptor in link["interfaces"]:
        module, path_text = descriptor["module"], descriptor["path"]
        interface_path = Path(path_text)
        source_hash = helper.digest(interface_path.read_bytes())
        require(source_hash == descriptor["sha256"], "pinned interface source hash mismatch: " + module)
        interface_raw = interface_path.read_bytes()
        raw = interface_raw.decode("utf-8", errors="strict")
        model = helper.source_model(raw)
        output_path = ROOT / descriptor["indexOutput"]
        request_path = ROOT / descriptor["indexRequest"]
        require(sha_file(output_path) == descriptor["indexOutputSha256"], "pinned SourceKit output changed: " + module)
        require(sha_file(request_path) == descriptor["indexRequestSha256"], "pinned SourceKit request changed: " + module)
        index_raw = output_path.read_text(encoding="utf-8")
        entities = helper.entities(index_raw)
        require(len(entities) == descriptor["declEntityCount"], "SourceKit entity denominator mismatch: " + module)
        module_index_counts[module] = len(entities)
        raw_interfaces.append({
            "module": module, "path": str(interface_path), "sourceSha256": source_hash,
            "target": descriptor["requestIdentity"]["target"],
            "sdk": descriptor["requestIdentity"]["sdk"],
            "sourceLineCount": len(raw.splitlines()),
            "requestPath": descriptor["indexRequest"], "requestSha256": descriptor["indexRequestSha256"],
            "requestIdentity": descriptor["requestIdentity"],
            "rawSourceKitOutputPath": descriptor["indexOutput"],
            "rawSourceKitOutputSha256": descriptor["indexOutputSha256"],
            "parsedSourceKitDeclarationEntityCount": len(entities),
        })
        starts = declaration_starts(raw, module, interface_path.name, source_hash, model, entities)
        rowgroup = rows_by_interface[(module, interface_path.name)]
        # Preserve any v12 exact declaration line/signature the lexical parser did not
        # recognize (for example operator declarations). These are explicitly marked
        # as audit-anchored supplements, not independent parser discoveries.
        for row in rowgroup:
            same_name = [s for s in starts if s["line"] == row["line"] and s["name"] == row["name"]]
            if same_name:
                continue
            number = row["line"]
            source_line = raw.splitlines()[number - 1]
            scopes = copy.deepcopy(model[number]["scopes"])
            ancestor_records = []
            for scope in scopes:
                header_line = raw.splitlines()[scope["line"] - 1]
                ancestor_records.append({"line": scope["line"], "kind": scope["kind"],
                                         "sourceText": header_line,
                                         **parse_access_header(header_line, scope["kind"], scope)})
            owner_path, owner_module, module_status = nominal_identity(scopes, module)
            starts.append({
                "sourceModule": module, "interface": interface_path.name, "sourceHash": source_hash,
                "line": number, "kind": row["kind"], "name": row["name"],
                "explicitAccess": access_of(source_line)["explicitAccess"],
                "accessEvidence": access_of(source_line)["accessEvidence"],
                "sourceText": source_line,
                "attributes": [{"line": a["line"], "text": a["value"]} for a in row.get("attributes", [])],
                "conditionalStack": copy.deepcopy(model[number]["conditions"]),
                "lexicalAncestors": ancestor_records, "ownerPathSpelling": owner_path,
                "ownerModuleSpelling": owner_module, "ownerModuleResolution": module_status,
                "implicitPublicRuleCandidates": ["possible-protocol-requirement-default-public"]
                    if row["kind"] in {"func", "var", "associatedtype", "subscript"}
                    and any(s["kind"] == "protocol" for s in scopes) else [],
                "enumCaseNameCandidates": [row["name"]] if row["kind"] == "case" else [],
                "sameLineCompilerEntityCount": len([e for e in entities if e.get("line") == number]),
                "sameLineCompilerEntities": copy.deepcopy([e for e in entities if e.get("line") == number]),
                "sourceLineDeclarationOrdinal": sum(1 for prior in starts if prior["line"] == number),
                "lexicalParserScopeLines": [s["line"] for s in scopes],
                "lexicalParserInsideFunction": False,
                "declarationOrigin": "v12-exact-row-anchor-unparsed-source-construct",
                "v12RowKey": [module, interface_path.name, number, row["name"]],
            })
        start_inventory.extend(starts)
        owner_records.extend(all_owner_records(raw, module, model, entities))
        row_by_line: dict[int, list[dict[str, Any]]] = defaultdict(list)
        for row in rowgroup:
            row_by_line[row["line"]].append(row)
        start_by_line: dict[int, list[dict[str, Any]]] = defaultdict(list)
        for start in starts:
            start_by_line[start["line"]].append(start)
        for row in rowgroup:
            same_line = copy.deepcopy(indexed_entities := [e for e in entities if e.get("line") == row["line"]])
            source_line = raw.splitlines()[row["line"] - 1]
            source_snapshot = model[row["line"]]
            if not same_line:
                join_reason = "no-SourceKit-declaration-entity-at-source-line"
            elif not any(e.get("name") == row["name"] or e.get("name", "").startswith(row["name"] + "(") for e in same_line):
                join_reason = "same-line-SourceKit-entities-have-no-exact-name-match"
            else:
                join_reason = "same-line-sourcekit-candidates-retained-no-access-conclusion"
            row_census.append({
                "rowKey": [module, interface_path.name, row["line"], row["name"]],
                "v12Classification": row["classification"],
                "v12Signature": row["signature"], "v12Context": row["context"],
                "v12Conditions": row["conditions"], "v12SourceKitEvidence": row.get("sourceKitEvidence"),
                "sourceModule": module, "sourcePath": str(interface_path), "sourceSha256": source_hash,
                "sourceLine": source_line, "sourceSourceModel": source_snapshot,
                "allSameLineSourceDeclarationStarts": copy.deepcopy(start_by_line.get(row["line"], [])),
                "sameLineCompilerEntityCount": len(same_line), "sameLineCompilerEntities": same_line,
                "compilerIndexPath": descriptor["indexOutput"],
                "compilerIndexSha256": descriptor["indexOutputSha256"],
                "compilerRequestPath": descriptor["indexRequest"],
                "compilerRequestSha256": descriptor["indexRequestSha256"],
                "joinAssessment": join_reason,
            })
        owner_line_set = {owner["sourceInterfaceLine"] for owner in owner_records if owner["sourceModule"] == module}
        for number, line in enumerate(raw.splitlines(), 1):
            txt = re.sub(r"//.*$", "", line).strip()
            if txt.startswith(("extension ", "public extension ", "internal extension ", "private extension ",
                               "fileprivate extension ", "package extension ", "struct ", "public struct ",
                               "class ", "public class ", "enum ", "public enum ", "protocol ", "public protocol ",
                               "actor ", "public actor ")) and number not in owner_line_set:
                reason = ("single-line-empty-extension-not-an-enclosing-scope"
                          if re.search(r"\{\s*\}\s*$", line) else
                          "scope-looking-header-not-represented-in-pinned-source-model")
                unknown_scopes.append({"sourceModule": module, "line": number, "sourceText": line,
                                       "conditions": model[number]["conditions"], "reason": reason})

    require(len(row_census) == len(v12["declarations"]) == 12635, "v12 declaration row denominator changed")
    require(len({tuple(row["rowKey"]) for row in row_census}) == len(row_census), "duplicate v12 row key")
    v12_keys = {tuple((row["module"], row["interface"], row["line"], row["name"])) for row in v12["declarations"]}
    census_keys = {tuple(row["rowKey"]) for row in row_census}
    require(v12_keys == census_keys, "v12 declaration key set does not reconcile to census")
    all_rows_per_v12 = defaultdict(list)
    for row in row_census:
        all_rows_per_v12[tuple(row["rowKey"])].append(row)

    graph_refs = [{"path": item["path"], "sha256": item["sha256"], "module": item.get("module"),
                   "filename": Path(item["path"]).name}
                  for item in link["rawGraphInputs"]]
    for item in graph_refs:
        require(sha_file(ROOT / item["path"]) == item["sha256"], "pinned raw graph changed: " + item["path"])
    catalogue_rows = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    graph_symbols = catalogue_rows["symbols"]
    require(len(graph_symbols) == 108272, "pinned merged catalogue symbol denominator changed")

    row_keys_by_extension: dict[tuple[str, int], list[list[Any]]] = defaultdict(list)
    for row in row_census:
        for scope in row["sourceSourceModel"]["scopes"]:
            if scope["kind"] == "extension":
                row_keys_by_extension[(row["sourceModule"], scope["line"])].append(row["rowKey"])
    cross_module_extensions = []
    for owner in owner_records:
        target_module = owner.get("targetModuleSpelling")
        if owner["kind"] == "extension" and target_module and target_module != owner["sourceModule"]:
            cross_module_extensions.append({
                **owner,
                "sourceMemberV12Rows": sorted(row_keys_by_extension.get((owner["sourceModule"], owner["sourceInterfaceLine"]), [])),
                "classification": "cross-module-nominal-origin-eligibility-requires-independent-proof",
            })

    access_counts = Counter(item["explicitAccess"] or "unspecified" for item in start_inventory)
    scope_counts = Counter(item["kind"] for item in owner_records)
    row_ancestor_counts = Counter(len(item["sourceSourceModel"]["scopes"]) for item in row_census)
    unresolved_owner_rows = [item for item in row_census if "unqualified" in item.get("sourceSourceModel", {}).get("scopes", [{}])[-1].get("kind", "")] if False else []
    counts = Counter(row["joinAssessment"] for row in row_census)
    payload = {
        "kind": "f1-public-ancestor-raw-census", "version": 1,
        "status": "raw-census-no-eligibility-decisions",
        "method": "Source lexical declaration-start census across both pinned arm64e SwiftUI/SwiftUICore interfaces using the separately pinned lexical_model parser; every v12 declaration row missed by that parser is added as a distinctly labeled exact row/source-line supplement. Lexical scope snapshots use pinned exact_validator.source_model. Raw same-line SourceKit entities are referenced by table index. This capture makes no access or public-ancestor eligibility decision and does not certify parser completeness.",
        "pinnedInputs": {
            "v12Candidate": {"path": "factory/catalogue/evidence/interface-audit-v12-candidate.json", "sha256": V12_SHA, "auditHash": V12_AUDIT},
            "v12Consumer": {"path": "factory/catalogue/audit_v12.py", "sha256": V12_SOURCE_SHA},
            "v12Test": {"path": "factory/catalogue/test_audit_v12.py", "sha256": V12_TEST_SHA},
            "immutable836": {"path": "factory/catalogue/compiler-cursor-spike/link-evidence.json", "sha256": LINK_SHA},
            "sourceModelParser": {"path": "factory/catalogue/module-provenance-spike/exact_validator.py", "sha256": PARSER_SHA},
            "lexicalDeclarationParser": {"path": "factory/catalogue/public-ancestor-spike/lexical_model.py",
                                          "sha256": LEXICAL_PARSER_SHA,
                                          "role": "enumerates source lexical declaration starts; no access eligibility conclusion"},
            "declarationExtractor": {"path": "factory/catalogue/catalogue.py", "sha256": catalogue_source_hash,
                                     "pattern": DECL_START.pattern, "modifiers": list(MODIFIERS), "kinds": list(KINDS)},
            "mergedCatalogue": {"path": "factory/catalogue/evidence/catalogue.json", "sha256": sha_file(CATALOGUE), "symbolCount": len(graph_symbols)},
            "toolchain": {"compiler": toolchain["compiler"], "sourcekitd": toolchain["sourcekitd"],
                          "sourcekitLsp": toolchain["sourcekitLsp"], "target": toolchain["target"],
                          "sdk": toolchain["sdk"], "xcodeVersion": toolchain.get("xcodeVersion")},
            "rawGraphs": graph_refs,
            "interfaces": raw_interfaces,
        },
        "summary": {
            "v12DeclarationRows": len(row_census), "sourceDeclarationStartsAcrossBothInterfaces": len(start_inventory),
            "sourceDeclarationStartsFromPinnedLexicalParser": sum(
                item["declarationOrigin"] == "pinned-source-lexical-parser" for item in start_inventory),
            "v12RowsSupplementedBecauseLexicalParserMissedSourceForm": sum(
                item["declarationOrigin"] == "v12-exact-row-anchor-unparsed-source-construct" for item in start_inventory),
            "lexicalOwnerScopeRecords": len(owner_records), "sourceKitParsedDeclarationEntities": sum(module_index_counts.values()),
            "sourceDeclarationStartsByModule": dict(Counter(row["sourceModule"] for row in start_inventory)),
            "sourceDeclarationStartsByExplicitAccess": dict(sorted(access_counts.items())),
            "lexicalOwnerRecordsByKind": dict(sorted(scope_counts.items())),
            "v12RowsByLexicalAncestorDepth": dict(sorted((str(k), v) for k,v in row_ancestor_counts.items())),
            "sameLineCompilerJoinAssessments": dict(sorted(counts.items())),
            "crossModuleExtensionOwnerRows": len(cross_module_extensions),
            "unparsedScopeLookingHeaders": len(unknown_scopes),
            "publicAncestorEligibility": "not-classified-by-capture",
            "sourceOriginResolution": "explicit-source-spelling-only; unqualified owners unresolved",
        },
        "sourceDeclarationStarts": start_inventory,
        "lexicalOwnerRecords": owner_records,
        "rows": row_census,
        "crossModuleExtensions": cross_module_extensions,
        "unparsedScopeLookingHeaders": unknown_scopes,
    }
    return payload


def main() -> None:
    result = compact_census(capture())
    result["censusHash"] = "sha256:" + hashlib.sha256(
        json.dumps(result, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    out = RAW / "ancestor-census-v1.json"
    out.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"path": str(out.relative_to(ROOT)), "v12Rows": result["summary"]["v12DeclarationRows"],
                      "sourceDeclarationStarts": result["summary"]["sourceDeclarationStartsAcrossBothInterfaces"],
                      "lexicalOwners": result["summary"]["lexicalOwnerScopeRecords"],
                      "crossModuleExtensions": result["summary"]["crossModuleExtensionOwnerRows"],
                      "censusHash": result["censusHash"]}, sort_keys=True))


if __name__ == "__main__":
    main()
