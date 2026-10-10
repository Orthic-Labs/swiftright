#!/usr/bin/env python3
"""Fail-closed review validator for the actor-kind edge candidate.

This is an edge-spike validator only. It is callable by tests/evidence and is
not installed into current catalogue adapters.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any


ACTOR_RAW_KIND = "source.lang.swift.decl.class"


def digest_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def parse_demangle_tree(text: str, usr: str) -> dict[str, Any] | None:
    """Read one exact swift-demangle --expand tree from archived stdout."""
    marker = f"Demangling for $s{usr[2:]}" if usr.startswith("s:") else f"Demangling for {usr}"
    lines = text.splitlines()
    starts = [index for index, line in enumerate(lines) if line == marker]
    if len(starts) != 1:
        return None
    start = starts[0]
    roots: list[dict[str, Any]] = []
    stack: list[tuple[int, dict[str, Any]]] = []
    for line in lines[start + 1:]:
        if line.startswith("Demangling for "):
            break
        if line.startswith("$s"):
            break
        if not line.lstrip().startswith("kind="):
            break
        if not line.strip():
            continue
        match = re.match(r'^(\s*)kind=([^,]+?)(?:,\s*text="([^"]*)")?(?:,\s*.*)?$', line)
        if not match:
            return None
        indent, kind, value = len(match.group(1)), match.group(2), match.group(3)
        node: dict[str, Any] = {"kind": kind, "text": value, "children": []}
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if stack:
            stack[-1][1]["children"].append(node)
        else:
            roots.append(node)
        stack.append((indent, node))
    if len(roots) != 1 or roots[0].get("kind") != "Global":
        return None
    root_children = roots[0].get("children", [])
    class_nodes = [item for item in root_children if item.get("kind") == "Class"]
    if len(root_children) != 1 or len(class_nodes) != 1:
        return None
    class_children = class_nodes[0].get("children", [])
    module_nodes = [item for item in class_children if item.get("kind") == "Module"]
    identifier_nodes = [item for item in class_children if item.get("kind") == "Identifier"]
    if (len(class_children) != 2 or len(module_nodes) != 1
            or len(identifier_nodes) != 1):
        return None
    return roots[0]


def _child(node: dict[str, Any], kind: str) -> dict[str, Any] | None:
    return next((item for item in node.get("children", []) if item.get("kind") == kind), None)


def validate_actor_bridge(
    row: dict[str, Any],
    raw_entities: list[dict[str, Any]],
    *,
    interface_text: str,
    interface_sha256: str,
    demangle_text: str,
) -> dict[str, Any]:
    """Validate one actor bridge candidate; every identity gate is required."""
    reasons: list[str] = []
    if row.get("module") != "SwiftUICore":
        reasons.append("module")
    if row.get("kind") != "actor":
        reasons.append("interface-kind")
    if len(raw_entities) != 1:
        reasons.append("raw-cardinality")
    if row.get("sourceHash") != interface_sha256:
        reasons.append("source-hash")
    if digest_bytes(interface_text.encode("utf-8")) != interface_sha256:
        reasons.append("interface-bytes")
    line = int(row.get("line", -1))
    source_lines = interface_text.splitlines()
    source_line = source_lines[line - 1] if 0 < line <= len(source_lines) else ""
    name = str(row.get("name", ""))
    if not re.search(rf"\bactor\s+{re.escape(name)}\b", source_line):
        reasons.append("actor-source-marker")
    if not re.search(rf"\bpublic\s+actor\s+{re.escape(name)}\b", str(row.get("signature", ""))):
        reasons.append("actor-signature-marker")
    if len(raw_entities) == 1:
        entity = raw_entities[0]
        if entity.get("line") != line:
            reasons.append("line")
        if entity.get("name") != name:
            reasons.append("name")
        if entity.get("kind") != ACTOR_RAW_KIND:
            reasons.append("sourcekit-kind")
        if entity.get("effective_access") != "source.decl.effective_access.public":
            reasons.append("access")
        if entity.get("is_implicit") is True:
            reasons.append("implicit")
        context = [str(item.get("name", "")).split(".")[-1].split("<", 1)[0]
                   for item in entity.get("sourcekitContext", [])]
        if context != list(row.get("context", [])):
            reasons.append("context")
        usr = entity.get("usr")
        if not isinstance(usr, str) or not usr:
            reasons.append("usr")
        else:
            tree = parse_demangle_tree(demangle_text, usr)
            if tree is None:
                reasons.append("usr-tree")
            else:
                root_children = tree.get("children", [])
                class_nodes = [item for item in root_children if item.get("kind") == "Class"]
                class_node = class_nodes[0] if len(class_nodes) == 1 else None
                if tree.get("kind") != "Global":
                    reasons.append("usr-root")
                if len(root_children) != 1 or class_node is None:
                    reasons.append("usr-global-children")
                class_children = (class_node or {}).get("children", [])
                module_nodes = [item for item in class_children if item.get("kind") == "Module"]
                identifier_nodes = [item for item in class_children if item.get("kind") == "Identifier"]
                if (len(class_children) != 2 or len(module_nodes) != 1
                        or len(identifier_nodes) != 1):
                    reasons.append("usr-class-children")
                module_node = module_nodes[0] if len(module_nodes) == 1 else None
                identifier_node = identifier_nodes[0] if len(identifier_nodes) == 1 else None
                if module_node is None or module_node.get("text") != row.get("module"):
                    reasons.append("usr-module")
                if identifier_node is None or identifier_node.get("text") != name:
                    reasons.append("usr-name")
    return {"accepted": not reasons, "reasons": reasons}


def actor_bridge_accepts(*args: Any, **kwargs: Any) -> bool:
    """Boolean production-style entrypoint used by evidence controls."""
    return bool(validate_actor_bridge(*args, **kwargs)["accepted"])
