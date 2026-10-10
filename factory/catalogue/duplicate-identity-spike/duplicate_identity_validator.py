#!/usr/bin/env python3
"""Fail-closed validator for one exact duplicate SourceKit declaration pair."""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any


EXPECTED_CONDITION = "compiler(>=5.3) && $TildeSendable"
EXPECTED_MODULE = "SwiftUI"
EXPECTED_TARGET = "arm64-apple-macosx27.0"
EXPECTED_SDK = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"


def digest_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def _parse_tree_section(lines: list[str], start: int) -> dict[str, Any] | None:
    roots: list[dict[str, Any]] = []
    stack: list[tuple[int, dict[str, Any]]] = []
    for line in lines[start + 1:]:
        if line.startswith("Demangling for "):
            break
        if line.startswith("$s"):
            break
        if not line.lstrip().startswith("kind="):
            break
        match = re.match(r'^([ ]*)kind=([^,]+?)(?:,\s*text="([^"]*)")?(?:,\s*.*)?$', line)
        if not match:
            return None
        indent, kind, value = len(match.group(1)), match.group(2), match.group(3)
        node = {"kind": kind, "text": value, "children": []}
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if stack:
            stack[-1][1]["children"].append(node)
        else:
            roots.append(node)
        stack.append((indent, node))
    return roots[0] if len(roots) == 1 else None


def parse_demangle_tree(text: str, usr: str) -> dict[str, Any] | None:
    """Parse one target section; reject duplicate sections or malformed trees."""
    marker = "$s" + usr[2:] if usr.startswith("s:") else usr
    header = "Demangling for " + marker
    lines = text.splitlines()
    starts = [index for index, line in enumerate(lines) if line == header]
    if len(starts) != 1:
        return None
    return _parse_tree_section(lines, starts[0])


def _children(node: dict[str, Any], kind: str) -> list[dict[str, Any]]:
    return [child for child in node.get("children", []) if child.get("kind") == kind]


def _request_identity(request_text: str, *, source_path: str, module: str) -> bool:
    def fields(name: str) -> list[str]:
        return re.findall(rf'^\s*key\.{name}: "([^"]*)"\s*,?\s*$', request_text, re.M)

    sourcefiles = fields("sourcefile")
    request_kinds = re.findall(r"^\s*key\.request:\s*([^,\s]+)", request_text, re.M)
    sections = re.findall(r"^\s*key\.compilerargs:", request_text, re.M)
    args_match = re.search(r"key\.compilerargs:\s*\[(.*?)\]", request_text, re.S)
    if len(sourcefiles) != 1 or len(request_kinds) != 1 or len(sections) != 1 or args_match is None:
        return False
    args = [bytes(value, "utf-8").decode("unicode_escape") for value in re.findall(r'"((?:\\.|[^"\\])*)"', args_match.group(1))]
    def value(option: str) -> str | None:
        positions = [index for index, arg in enumerate(args) if arg == option]
        if len(positions) != 1 or positions[0] + 1 >= len(args):
            return None
        return args[positions[0] + 1]
    return (request_kinds[0] == "source.request.indexsource" and sourcefiles[0] == source_path
            and args and args[0] == source_path and value("-sdk") == EXPECTED_SDK
            and value("-target") == EXPECTED_TARGET and value("-module-name") == module)


def _tree_identity(tree: dict[str, Any], *, module: str, scope: str, name: str) -> bool:
    if tree.get("kind") != "Global":
        return False
    variables = _children(tree, "Variable")
    if len(tree.get("children", [])) != 1 or len(variables) != 1:
        return False
    variable = variables[0]
    structures = _children(variable, "Structure")
    identifiers = _children(variable, "Identifier")
    if len(structures) != 1 or len(identifiers) != 1 or identifiers[0].get("text") != name:
        return False
    structure = structures[0]
    modules = _children(structure, "Module")
    scope_ids = _children(structure, "Identifier")
    return (len(modules) == 1 and len(scope_ids) == 1
            and modules[0].get("text") == module and scope_ids[0].get("text") == scope)


def validate_duplicate_identity(
    row: dict[str, Any],
    raw_entities: list[dict[str, Any]],
    raw_records: list[dict[str, Any]],
    *,
    source_text: str,
    source_sha256: str,
    request_text: str,
    request_sha256: str,
    expected_request_sha256: str,
    response_sha256: str,
    expected_response_sha256: str,
    demangle_text: str,
    toolchain: dict[str, Any],
    expected_toolchain: dict[str, Any],
    source_path: str,
) -> dict[str, Any]:
    reasons: list[str] = []
    if row.get("module") != EXPECTED_MODULE:
        reasons.append("module")
    if row.get("sourceHash") != source_sha256:
        reasons.append("source-hash")
    if digest_bytes(source_text.encode("utf-8")) != source_sha256:
        reasons.append("source-bytes")
    if request_sha256 != expected_request_sha256 or not _request_identity(request_text, source_path=source_path, module=EXPECTED_MODULE):
        reasons.append("request")
    if response_sha256 != expected_response_sha256:
        reasons.append("response")
    if toolchain != expected_toolchain:
        reasons.append("toolchain")
    if row.get("kind") != "var" or len(raw_entities) != 2 or len(raw_records) != 2:
        reasons.append("cardinality")
    if len(raw_records) == 2:
        for record in raw_records:
            if digest_bytes(str(record.get("text", "")).encode("utf-8")) != record.get("sha256"):
                reasons.append("record-hash")
        if raw_records[0].get("text") != raw_records[1].get("text"):
            reasons.append("distinct-raw-records")
    if len(raw_entities) == 2 and raw_entities[0] != raw_entities[1]:
        reasons.append("distinct-entities")
    line = row.get("line")
    name = str(row.get("name", ""))
    context = list(row.get("context", []))
    source_lines = source_text.splitlines()
    source_line = source_lines[line - 1] if isinstance(line, int) and 0 < line <= len(source_lines) else ""
    if source_line != row.get("sourceLine"):
        reasons.append("source-line")
    if len(re.findall(rf"\bvar\s+{re.escape(name)}\s*:", source_line)) != 1:
        reasons.append("source-name-cardinality")
    if not re.search(rf"\bvar\s+{re.escape(name)}\s*:", source_line):
        reasons.append("source-name")
    if row.get("activeCondition") != EXPECTED_CONDITION or row.get("activeBranch") is not True:
        reasons.append("source-branch")
    scope_line = row.get("scopeLine")
    scope_name = str(row.get("scopeName", ""))
    scope_text = source_lines[scope_line - 1] if isinstance(scope_line, int) and 0 < scope_line <= len(source_lines) else ""
    if not scope_name or not re.search(rf"\bstruct\s+{re.escape(scope_name)}\b", scope_text):
        reasons.append("source-scope")
    if len(raw_entities) == 2:
        first, second = raw_entities
        for entity in raw_entities:
            if (entity.get("line") != line or entity.get("name") != name
                    or entity.get("kind") != "source.lang.swift.decl.var.instance"
                    or entity.get("effective_access") != "source.decl.effective_access.public"
                    or entity.get("is_implicit") is True
                    or entity.get("sourcekitContext") is None):
                reasons.append("raw-fields")
        actual_context = [item.get("name") for item in first.get("sourcekitContext", [])]
        if actual_context != context:
            reasons.append("raw-context")
        if first.get("usr") != second.get("usr") or not isinstance(first.get("usr"), str) or not first.get("usr"):
            reasons.append("raw-usr")
        tree = parse_demangle_tree(demangle_text, first.get("usr", ""))
        if tree is None or not _tree_identity(tree, module=EXPECTED_MODULE, scope=context[0] if len(context) == 1 else "", name=name):
            reasons.append("usr-tree")
    return {"accepted": not reasons, "reasons": reasons}


def duplicate_identity_accepts(*args: Any, **kwargs: Any) -> bool:
    return bool(validate_duplicate_identity(*args, **kwargs)["accepted"])
