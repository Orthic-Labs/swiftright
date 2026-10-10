#!/usr/bin/env python3
"""Structural compiler-owner bridge for finalized F1 context holds.

The bridge is review evidence only.  It never edits finalized link evidence
or promotes rows in-place.
"""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SPIKE = ROOT / "factory/catalogue/compiler-cursor-spike"
LINK = SPIKE / "link-evidence.json"
AUDIT = ROOT / "factory/catalogue/evidence/interface-audit-v6.json"
DEMANGLE = Path(
    "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/"
    "XcodeDefault.xctoolchain/usr/bin/swift-demangle"
)
EXPANDED = HERE / "swift-demangle-expand-v1.txt"
EXPECTED_LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"


def load_investigator():
    path = HERE / "investigate.py"
    spec = importlib.util.spec_from_file_location("f1_residual_investigate", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def parse_node_tree(section: str) -> tuple[str, dict[str, Any]]:
    lines = section.splitlines()
    match = re.match(r"Demangling for (\$s\S+)$", lines[0])
    if not match:
        raise ValueError(f"bad swift-demangle section header: {lines[0]!r}")
    usr = match.group(1)
    roots: list[dict[str, Any]] = []
    stack: list[tuple[int, dict[str, Any]]] = []
    saw_arrow = False
    for line in lines[1:]:
        if line.startswith("$s"):
            saw_arrow = True
            break
        if line.startswith("<<NULL>>"):
            raise ValueError(f"swift-demangle returned NULL for {usr}")
        if not line.strip():
            continue
        node = re.match(
            r'^(\s*)kind=([^,]+?)(?:,\s*text="([^"]*)")?(?:,\s*.*)?$',
            line,
        )
        if not node:
            raise ValueError(f"unknown swift-demangle node record for {usr}: {line!r}")
        indent = len(node.group(1))
        item: dict[str, Any] = {
            "kind": node.group(2),
            "text": node.group(3),
            "children": [],
        }
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if stack:
            stack[-1][1]["children"].append(item)
        else:
            roots.append(item)
        stack.append((indent, item))
    if len(roots) != 1 or roots[0].get("kind") != "Global":
        raise ValueError(f"missing Global root for {usr}")
    if not saw_arrow:
        raise ValueError(f"missing swift-demangle result line for {usr}")
    return usr, roots[0]


def parse_sections(raw: str) -> dict[str, dict[str, Any]]:
    sections = re.split(r"(?=Demangling for \$s)", raw)
    parsed: dict[str, dict[str, Any]] = {}
    for section in sections:
        if not section.strip():
            continue
        usr, root = parse_node_tree(section)
        if usr in parsed:
            raise ValueError(f"duplicate swift-demangle tree for {usr}")
        parsed[usr] = root
    return parsed


def identifier_paths(
    node: dict[str, Any], target: str, path: tuple[dict[str, Any], ...] = ()
) -> list[tuple[dict[str, Any], ...]]:
    current = path + (node,)
    paths: list[tuple[dict[str, Any], ...]] = []
    declaration_name_kinds = {
        "Identifier",
        "InfixOperator",
        "PrefixOperator",
        "PostfixOperator",
    }
    if node.get("kind") in declaration_name_kinds and node.get("text") == target:
        paths.append(current)
    for child in node.get("children", []):
        paths.extend(identifier_paths(child, target, current))
    return paths


NOMINAL_KINDS = {"Structure", "Enum", "Class", "Protocol", "Actor"}
OWNER_KINDS = NOMINAL_KINDS | {"Extension"}
GENERIC_KINDS = {
    "DependentGenericSignature",
    "DependentGenericConformanceRequirement",
    "DependentGenericSameTypeRequirement",
    "DependentGenericLayoutRequirement",
}


def nominal_extract(node: dict[str, Any]) -> tuple[str | None, list[str], str | None]:
    """Return nominal module, lexical names, nested extension module."""
    module: str | None = None
    extension_module: str | None = None
    chain: list[str] = []
    for child in node.get("children", []):
        if child.get("kind") == "Extension":
            for item in child.get("children", []):
                if item.get("kind") == "Module" and extension_module is None:
                    extension_module = item.get("text")
            for item in child.get("children", []):
                if item.get("kind") in NOMINAL_KINDS:
                    cm, cc, ce = nominal_extract(item)
                    module = module or cm
                    extension_module = extension_module or ce
                    chain.extend(cc)
        elif child.get("kind") in NOMINAL_KINDS:
            cm, cc, ce = nominal_extract(child)
            module = module or cm
            extension_module = extension_module or ce
            chain.extend(cc)
        elif child.get("kind") == "Module" and module is None:
            module = child.get("text")
    for child in node.get("children", []):
        if child.get("kind") == "Identifier":
            chain.append(str(child.get("text")))
            break
    return module, chain, extension_module


def structural_owner(root: dict[str, Any], target: str) -> dict[str, Any]:
    paths = identifier_paths(root, target)
    if not paths:
        raise ValueError(f"no declaration identifier {target}")
    declaration_parent_kinds = NOMINAL_KINDS | {
        "Function", "TypeAlias", "Variable", "Subscript", "Constructor",
        "EnumElement", "InfixOperator", "PrefixOperator", "PostfixOperator",
    }
    def root_declaration(path: tuple[dict[str, Any], ...]) -> dict[str, Any] | None:
        return next(
            (
                item for item in path[1:]
                if item.get("kind") in declaration_parent_kinds
            ),
            None,
        )
    direct_paths = [
        path for path in paths
        if not any(item.get("kind") in GENERIC_KINDS for item in path)
        and root_declaration(path) is not None
        and path[-2] is root_declaration(path)
    ]
    if not direct_paths:
        raise ValueError(f"only generic-reference identifiers for {target}")
    path = min(direct_paths, key=len)
    parent = path[-2]
    owner_nodes: list[dict[str, Any]]
    if parent.get("kind") in NOMINAL_KINDS and len(path) > 3:
        owner_nodes = list(path[2:-1])
    else:
        owner_nodes = [
            child
            for child in parent.get("children", [])
            if child.get("kind") in OWNER_KINDS
        ]
    extension_module: str | None = None
    nominal_module: str | None = None
    chain: list[str] = []
    for node in owner_nodes:
        if node.get("kind") == "Extension":
            for child in node.get("children", []):
                if child.get("kind") == "Module" and extension_module is None:
                    extension_module = child.get("text")
            for child in node.get("children", []):
                if child.get("kind") in NOMINAL_KINDS:
                    module, names, nested_extension = nominal_extract(child)
                    nominal_module = nominal_module or module
                    extension_module = extension_module or nested_extension
                    chain.extend(names)
        elif node.get("kind") in NOMINAL_KINDS:
            module, names, nested_extension = nominal_extract(node)
            nominal_module = nominal_module or module
            extension_module = extension_module or nested_extension
            chain.extend(names)
    generic_reference_count = sum(
        any(item.get("kind") in GENERIC_KINDS for item in path)
        for path in paths
    )
    non_declaration_reference_count = len(paths) - len(direct_paths)
    def has_local_scope(node: dict[str, Any]) -> bool:
        if node.get("kind") in {"Function", "Constructor"}:
            return True
        return any(has_local_scope(child) for child in node.get("children", []))
    # A Function parent is declaration kind for methods.  A nominal target
    # below Function is function-local; multiple Function nodes are likewise
    # nested function ownership.
    function_count = sum(item.get("kind") == "Function" for item in path)
    function_scope = (
        (parent.get("kind") in NOMINAL_KINDS and function_count > 0)
        or function_count > 1
        or any(has_local_scope(node) for node in owner_nodes)
    )
    return {
        "identifierPathKinds": [item.get("kind") for item in path],
        "identifierPathCount": len(paths),
        "genericReferencePathCount": generic_reference_count,
        "nonDeclarationReferencePathCount": non_declaration_reference_count,
        "directDeclarationPathCount": len(direct_paths),
        "ownerNodeKinds": [item.get("kind") for item in owner_nodes],
        "ownerModule": extension_module or nominal_module,
        "nominalModule": nominal_module,
        "extensionModule": extension_module,
        "ownerNames": chain,
        "functionLocalScope": function_scope,
    }


def expected_nominal_module(row: dict[str, Any], scope_rows: list[dict[str, Any]]) -> str:
    """Read nominal module provenance from exact v6 lexical scope target."""
    if not scope_rows:
        raise ValueError(f"missing lexical scope receipt for {row['module']}:{row['line']}")
    target = str(scope_rows[0].get("target") or scope_rows[0].get("declaration") or "")
    # v6 uses `Module::` for cross-module source ownership, while same
    # module SwiftUI overlay scopes use `Module.Type`. Preserve both tokens;
    # compiler nominal module must equal this exact lexical token.
    match = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)::", target)
    if match:
        return match.group(1)
    dotted = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\.", target)
    return dotted.group(1) if dotted else row["module"]


def owner_matches_row(
    row: dict[str, Any], owner: dict[str, Any], expected_module: str,
) -> bool:
    expected_names = [value for value in row["context"] if value != row["module"]]
    return (
        owner.get("ownerModule") == row["module"]
        and owner.get("nominalModule") == expected_module
        and (
            owner.get("extensionModule") is None
            or owner.get("extensionModule") == row["module"]
        )
        and owner.get("ownerNames") == expected_names
        and owner.get("directDeclarationPathCount") == 1
        and not owner.get("functionLocalScope")
    )


def raw_entity_matches(
    row: dict[str, Any], entities: list[dict[str, Any]], inv: Any,
) -> bool:
    """Production raw identity gate; context intentionally stays separate."""
    if len(entities) != 1:
        return False
    entity = entities[0]
    return (
        int(entity.get("line", -1)) == int(row["line"])
        and inv.normalized_name(str(entity.get("name", "")))
        == inv.normalized_name(str(row["name"]))
        and inv.kind_matches(str(row["kind"]), str(entity.get("kind", "")))
        and inv.access_matches(row, entity)
        and str(entity.get("usr", "")).startswith("s:")
    )


def bridge_accepts(
    row: dict[str, Any], entities: list[dict[str, Any]], tree: dict[str, Any],
    scope_rows: list[dict[str, Any]], inv: Any,
) -> bool:
    """Strict bridge validator exercised by evidence & fault controls."""
    if not raw_entity_matches(row, entities, inv):
        return False
    try:
        owner = structural_owner(tree, str(row["name"]))
    except ValueError:
        return False
    return owner_matches_row(row, owner, expected_nominal_module(row, scope_rows))


def walk_nodes(node: dict[str, Any]):
    yield node
    for child in node.get("children", []):
        yield from walk_nodes(child)


def mutate_first_text(node: dict[str, Any], kind: str, old: str, new: str) -> bool:
    for item in walk_nodes(node):
        if item.get("kind") == kind and item.get("text") == old:
            item["text"] = new
            return True
    return False


def mutate_extension_module(node: dict[str, Any], old: str, new: str) -> bool:
    for item in walk_nodes(node):
        if item.get("kind") != "Extension":
            continue
        for child in item.get("children", []):
            if child.get("kind") == "Module" and child.get("text") == old:
                child["text"] = new
                return True
    return False


def mutate_nominal_module(node: dict[str, Any], old: str, new: str) -> bool:
    for item in walk_nodes(node):
        if item.get("kind") not in NOMINAL_KINDS:
            continue
        for child in item.get("children", []):
            if child.get("kind") == "Module" and child.get("text") == old:
                child["text"] = new
                return True
    return False


def mutate_function_local_owner(node: dict[str, Any]) -> bool:
    for item in walk_nodes(node):
        if item.get("kind") not in OWNER_KINDS:
            continue
        item.setdefault("children", []).append(
            {"kind": "Function", "text": None, "children": [
                {"kind": "Identifier", "text": "__local_control__", "children": []}
            ]}
        )
        return True
    return False


def mutate_generic_identifier(node: dict[str, Any], target: str) -> bool:
    for item in walk_nodes(node):
        if item.get("kind") not in GENERIC_KINDS:
            continue
        for child in walk_nodes(item):
            if child.get("kind") == "Identifier":
                child["text"] = target
                return True
    return False


def run(output: Path, expanded_output: Path = EXPANDED) -> dict[str, Any]:
    inv = load_investigator()
    actual_link_sha = sha(LINK)
    if actual_link_sha != EXPECTED_LINK_SHA256:
        raise ValueError(
            f"immutable link evidence changed: expected {EXPECTED_LINK_SHA256}, got {actual_link_sha}"
        )
    links = json.loads(LINK.read_text(encoding="utf-8"))
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    rows = [
        row for row in links["rows"]
        if row.get("linkHoldReason") == "enclosing-context-mismatch"
    ]
    if len(rows) != 206:
        raise ValueError(f"expected 206 finalized context holds, got {len(rows)}")
    raw_by_key: dict[tuple[str, int, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for module, path in inv.INDEX_OUTPUTS.items():
        for entity in inv.entities(path):
            raw_by_key[(module, int(entity["line"]), inv.normalized_name(str(entity["name"])))].append(entity)
    audit_by_key = {
        (item["module"], int(item["line"]), inv.normalized_name(str(item["name"]))): item
        for item in audit["declarations"]
    }
    ordered = sorted(rows, key=lambda row: (row["module"], row["line"], row["name"]))
    entities: list[dict[str, Any]] = []
    usrs: list[str] = []
    scope_by_key: dict[tuple[str, int, str], list[dict[str, Any]]] = {}
    for row in ordered:
        key = (row["module"], int(row["line"]), inv.normalized_name(str(row["name"])))
        exact = raw_by_key.get(key, [])
        if len(exact) != 1:
            raise ValueError(f"raw SourceKit cardinality for {key}: {len(exact)}")
        entity = exact[0]
        if not raw_entity_matches(row, exact, inv):
            raise ValueError(f"raw identity gate failed for {key}")
        usr = entity.get("usr")
        if not usr or not usr.startswith("s:"):
            raise ValueError(f"invalid raw USR for {key}: {usr}")
        scopes = audit_by_key[key].get("v6Evidence", {}).get("enclosingScopes", [])
        if not scopes:
            raise ValueError(f"missing v6 enclosing scope for {key}")
        scope_by_key[key] = scopes
        usrs.append("$s" + usr[2:])
        entities.append(entity)
    expanded_output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(DEMANGLE), "--expand", *usrs]
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    expanded_output.write_text(completed.stdout, encoding="utf-8")
    trees = parse_sections(completed.stdout)
    expected_usrs = set(usrs)
    if set(trees) != expected_usrs:
        missing = sorted(expected_usrs - set(trees))
        extra = sorted(set(trees) - expected_usrs)
        raise ValueError(f"expanded USR set mismatch missing={missing[:3]} extra={extra[:3]}")
    evidence_rows: list[dict[str, Any]] = []
    counts = collections.Counter()
    for row, entity in zip(ordered, entities):
        key = (row["module"], int(row["line"]), inv.normalized_name(str(row["name"])))
        usr = entity["usr"]
        tree = trees.get("$s" + usr[2:])
        if tree is None:
            raise ValueError(f"missing expanded tree for {key}")
        owner = structural_owner(tree, str(row["name"]))
        scope_rows = scope_by_key[key]
        expected_module = expected_nominal_module(row, scope_rows)
        expected_names = [value for value in row["context"] if value != row["module"]]
        raw_context = [str(item.get("name")) for item in entity.get("sourcekitContext", [])]
        raw_relation = "empty" if not raw_context else "immediate-suffix"
        if raw_context and raw_context != row["context"][-len(raw_context):]:
            raise ValueError(f"raw context is not suffix for {key}")
        kind_match = inv.kind_matches(str(row["kind"]), str(entity.get("kind", "")))
        access_match = inv.access_matches(row, entity)
        context_match = inv.context_matches(row, entity)
        structural_exact = owner_matches_row(row, owner, expected_module)
        raw_exact = raw_entity_matches(row, [entity], inv)
        provenance = {
            "expectedNominalModule": expected_module,
            "compilerNominalModule": owner.get("nominalModule"),
            "compilerExtensionModule": owner.get("extensionModule"),
            "sourceModule": row["module"],
            "nominalModuleExact": owner.get("nominalModule") == expected_module,
            "extensionModuleExact": (
                owner.get("extensionModule") is None
                or owner.get("extensionModule") == row["module"]
            ),
        }
        alias_hold = not provenance["nominalModuleExact"]
        proposed = bool(raw_exact and structural_exact and not context_match and kind_match and access_match)
        if alias_hold:
            counts["moduleProvenanceMismatch"] += 1
        if proposed:
            counts["proposedBridgeEligible"] += 1
        counts[f"rawContext:{raw_relation}"] += 1
        counts[f"genericReferencePaths:{owner['genericReferencePathCount']}"] += 1
        counts[f"scopeDepth:{len(scope_rows)}"] += 1
        counts["extensionOwner:" + str(owner["extensionModule"] is not None)] += 1
        evidence_rows.append(
            {
                "key": [row["module"], row["interface"], row["line"], row["name"]],
                "module": row["module"],
                "line": row["line"],
                "name": row["name"],
                "interfaceKind": row["kind"],
                "interfaceContext": row["context"],
                "interfaceEnclosingScopes": scope_rows,
                "raw": {
                    "kind": entity.get("kind"),
                    "name": entity.get("name"),
                    "usr": usr,
                    "line": entity.get("line"),
                    "column": entity.get("column"),
                    "effective_access": entity.get("effective_access"),
                    "is_implicit": entity.get("is_implicit"),
                    "sourcekitContext": entity.get("sourcekitContext", []),
                },
                "compilerOwner": owner,
                "bridge": {
                    "expectedNamesAfterRemovingOnlyRowModuleToken": expected_names,
                    "rawContextRelation": raw_relation,
                    "kindMatch": kind_match,
                    "accessMatch": access_match,
                    "strictContextMatch": context_match,
                    "structuralOwnerExact": structural_exact,
                    "moduleProvenance": provenance,
                    "proposedBridgeEligible": proposed,
                    "holdReason": "unsupported-compiler-module-alias" if alias_hold else None,
                },
            }
        )

    # Controls mutate raw entity/tree inputs & invoke same production validator.
    first_i = next(
        i for i, item in enumerate(evidence_rows)
        if item["bridge"]["proposedBridgeEligible"]
    )
    first_row, first_entity = ordered[first_i], entities[first_i]
    first_key = (first_row["module"], int(first_row["line"]), inv.normalized_name(str(first_row["name"])))
    first_tree = trees["$s" + first_entity["usr"][2:]]
    first_scopes = scope_by_key[first_key]
    if not bridge_accepts(first_row, [first_entity], first_tree, first_scopes, inv):
        raise ValueError(f"accepted control basis failed production validator: {first_key}")
    extension_i = next(
        i for i, item in enumerate(evidence_rows)
        if item["bridge"]["proposedBridgeEligible"]
        and item["line"] == 9901
        and item["name"] == "FontAttribute"
    )
    extension_row, extension_entity = ordered[extension_i], entities[extension_i]
    extension_key = (extension_row["module"], int(extension_row["line"]), inv.normalized_name(str(extension_row["name"])))
    extension_tree = trees["$s" + extension_entity["usr"][2:]]
    extension_scopes = scope_by_key[extension_key]
    if not bridge_accepts(extension_row, [extension_entity], extension_tree, extension_scopes, inv):
        raise ValueError(f"accepted extension control basis failed: {extension_key}")
    wrong_outer_tree = copy.deepcopy(first_tree)
    outer_name = evidence_rows[first_i]["compilerOwner"]["ownerNames"][0]
    if not mutate_first_text(wrong_outer_tree, "Identifier", outer_name, "__wrong_outer__"):
        raise ValueError("outer control mutation did not apply")
    wrong_module_tree = copy.deepcopy(extension_tree)
    if not mutate_nominal_module(wrong_module_tree, str(evidence_rows[extension_i]["compilerOwner"].get("nominalModule")), "__wrong_nominal_module__"):
        raise ValueError("nominal module control mutation did not apply")
    wrong_extension_tree = copy.deepcopy(extension_tree)
    if not mutate_extension_module(wrong_extension_tree, extension_row["module"], "__wrong_extension_module__"):
        raise ValueError("extension module control mutation did not apply")
    function_tree = copy.deepcopy(first_tree)
    function_mutated = mutate_function_local_owner(function_tree)
    repeated_tree = copy.deepcopy(first_tree)
    if not mutate_first_text(repeated_tree, "Identifier", outer_name, str(first_row["name"])):
        raise ValueError("repeated-name control mutation did not apply")
    generic_i = next(i for i, r in enumerate(evidence_rows) if r["compilerOwner"]["genericReferencePathCount"] > 0)
    generic_row, generic_entity = ordered[generic_i], entities[generic_i]
    generic_key = (generic_row["module"], int(generic_row["line"]), inv.normalized_name(str(generic_row["name"])))
    generic_tree = copy.deepcopy(trees["$s" + generic_entity["usr"][2:]])
    generic_mutated = mutate_generic_identifier(generic_tree, str(generic_row["name"]))
    duplicate_entities = [first_entity, copy.deepcopy(first_entity)]
    missing_access = copy.deepcopy(first_entity)
    missing_access["effective_access"] = "source.decl.effective_access.internal"
    actor_kind = copy.deepcopy(first_entity)
    actor_kind["kind"] = "source.lang.swift.decl.class"
    controls = {
        "all206RawEntityCardinalityOne": all(raw_entity_matches(r, [e], inv) for r, e in zip(ordered, entities)),
        "all206KindExact": all(inv.kind_matches(str(r["kind"]), str(e.get("kind", ""))) for r, e in zip(ordered, entities)),
        "all206AccessExact": all(inv.access_matches(r, e) for r, e in zip(ordered, entities)),
        "sameSuffixWrongOuterRejected": not bridge_accepts(first_row, [first_entity], wrong_outer_tree, first_scopes, inv),
        "wrongNominalModuleRejected": not bridge_accepts(extension_row, [extension_entity], wrong_module_tree, extension_scopes, inv),
        "wrongExtensionModuleRejected": not bridge_accepts(extension_row, [extension_entity], wrong_extension_tree, extension_scopes, inv),
        "functionLocalRejected": function_mutated and not bridge_accepts(first_row, [first_entity], function_tree, first_scopes, inv),
        "duplicateRawEntityRejected": not raw_entity_matches(first_row, duplicate_entities, inv),
        "missingAccessRejected": not bridge_accepts(first_row, [missing_access], first_tree, first_scopes, inv),
        "actorKindRejected": not bridge_accepts(first_row, [actor_kind], first_tree, first_scopes, inv),
        # Both generic rows are among 33 held SwiftUICore-qualified SwiftUI
        # aliases, so production validator must keep them held.  Mutation
        # still proves generic references do not alter direct owner path.
        "genericReferencesExcluded": (
            generic_mutated
            and structural_owner(generic_tree, str(generic_row["name"]))["directDeclarationPathCount"] == 1
            and structural_owner(generic_tree, str(generic_row["name"]))["genericReferencePathCount"] >= 2
            and not bridge_accepts(generic_row, [generic_entity], generic_tree, scope_by_key[generic_key], inv)
        ),
        "repeatedDeclNameRejected": not bridge_accepts(first_row, [first_entity], repeated_tree, first_scopes, inv),
    }
    if not all(controls.values()):
        raise ValueError(f"bridge controls failed: {controls}")
    control_details = {
        "sameSuffixWrongOuterRejected": {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "mutation": "owner nominal Identifier text -> __wrong_outer__"},
        "wrongNominalModuleRejected": {"key": evidence_rows[extension_i]["key"], "usr": extension_entity["usr"], "mutation": "owner nominal Module text -> __wrong_nominal_module__"},
        "wrongExtensionModuleRejected": {"key": evidence_rows[extension_i]["key"], "usr": extension_entity["usr"], "mutation": "Extension direct Module text -> __wrong_extension_module__"},
        "functionLocalRejected": {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "mutation": "Function node appended inside owner context branch"},
        "duplicateRawEntityRejected": {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "mutation": "duplicate exact raw entity appended"},
        "missingAccessRejected": {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "mutation": "effective_access -> internal"},
        "actorKindRejected": {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "mutation": "raw kind -> source.lang.swift.decl.class"},
        "genericReferencesExcluded": {"key": evidence_rows[generic_i]["key"], "usr": generic_entity["usr"], "mutation": "generic requirement Identifier text -> declaration name; direct path remains unique"},
        "repeatedDeclNameRejected": {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "mutation": "owner nominal Identifier text -> declaration name"},
    }
    payload = {
        "kind": "f1-context-bridge-investigation",
        "version": 2,
        "status": "review-only-structural-owner-bridge",
        "lineage": {
            "immutableLinkEvidence": "factory/catalogue/compiler-cursor-spike/link-evidence.json",
            "immutableLinkEvidenceSha256": EXPECTED_LINK_SHA256,
            "supersedes": "context-bridge-evidence-v1 review draft",
            "v1FindingsResolved": ["nominal module was masked by extension module", "duplicate USR sections were overwritten", "unknown demangle records were ignored", "fault controls mutated derived values"],
        },
        "method": (
            "For each finalized enclosing-context hold, exact raw SourceKit line/name joins "
            "to one entity. Pinned Xcode swift-demangle --expand node trees reconstruct "
            "independent nominal-module, extension-module, full lexical owner, generic, "
            "and function-local ownership. Duplicate USRs or unknown node records fail "
            "parsing. Explicit SwiftUICore lexical qualifiers whose compiler nominal module "
            "is SwiftUI remain held pending compiler alias evidence."
        ),
        "inputs": {
            "linkEvidence": str(LINK.relative_to(ROOT)),
            "linkEvidenceSha256": sha(LINK),
            "expectedImmutableLinkEvidenceSha256": EXPECTED_LINK_SHA256,
            "bridgeSource": {"path": str(Path(__file__).relative_to(ROOT)), "sha256": sha(Path(__file__))},
            "investigatorSource": {"path": str((HERE / "investigate.py").relative_to(ROOT)), "sha256": sha(HERE / "investigate.py")},
            "v6Audit": str(AUDIT.relative_to(ROOT)),
            "v6AuditSha256": sha(AUDIT),
            "interfaces": {name: {"path": str(path), "sha256": sha(path)} for name, path in inv.INTERFACES.items()},
            "rawIndexOutputs": {
                module: {"path": str(path.relative_to(ROOT)), "sha256": sha(path)}
                for module, path in inv.INDEX_OUTPUTS.items()
            },
            "rawIndexRequests": {
                module: {"path": str(path.relative_to(ROOT)), "sha256": sha(path)}
                for module, path in inv.INDEX_REQUESTS.items()
            },
            "swiftDemangle": {"path": str(DEMANGLE), "sha256": sha(DEMANGLE), "mode": "--expand"},
            "expandedOutput": {"path": str(expanded_output.relative_to(ROOT)), "sha256": sha(expanded_output), "requestedUsrCount": len(usrs)},
        },
        "summary": {
            "finalLinkContextHolds": len(evidence_rows),
            "proposedBridgeEligible": counts["proposedBridgeEligible"],
            "currentLinkPromotion": 0,
            "rawEntityCardinalityOne": len(evidence_rows),
            "structuralOwnerExact": sum(item["bridge"]["structuralOwnerExact"] for item in evidence_rows),
            "rawContextEmpty": counts["rawContext:empty"],
            "rawContextImmediateSuffix": counts["rawContext:immediate-suffix"],
            "genericReferenceRows": sum(item["compilerOwner"]["genericReferencePathCount"] > 0 for item in evidence_rows),
            "repeatedDeclNameRows": sum(item["compilerOwner"]["nonDeclarationReferencePathCount"] > 0 for item in evidence_rows),
            "extensionOwnerRows": counts["extensionOwner:True"],
            "moduleProvenanceMismatch": counts["moduleProvenanceMismatch"],
            "unsupportedCompilerModuleAliasRows": counts["moduleProvenanceMismatch"],
            "scopeDepth": {key.split(":", 1)[1]: value for key, value in counts.items() if key.startswith("scopeDepth:")},
            "genuineStructuralMismatch": len(evidence_rows) - sum(item["bridge"]["structuralOwnerExact"] for item in evidence_rows),
            "missingExpandedTree": 0,
        },
        "resolutionProposal": {
            "id": "f1-bridge-206-v2",
            "status": "review-only",
            "rows": len(evidence_rows),
            "requiredExactChecks": [
                "one raw SourceKit entity at exact module/line/name",
                "raw kind & expected access exact",
                "swift-demangle --expand raw USR tree present & unique",
                "compiler nominal module equals exact lexical target module",
                "compiler extension module equals source module when Extension exists",
                "compiler full nominal path equals interface context after removing only row module token",
                "generic-reference paths excluded by node kind",
                "function-local owner paths rejected",
            ],
            "heldAliasRows": counts["moduleProvenanceMismatch"],
        },
        "controls": controls,
        "controlBases": [
            {"key": evidence_rows[first_i]["key"], "usr": first_entity["usr"], "baselineAccepted": True},
            {"key": evidence_rows[extension_i]["key"], "usr": extension_entity["usr"], "baselineAccepted": True},
        ],
        "controlDetails": control_details,
        "rows": evidence_rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "context-bridge-evidence.json")
    parser.add_argument("--expanded-output", type=Path, default=EXPANDED)
    args = parser.parse_args()
    payload = run(args.output, args.expanded_output)
    print(json.dumps(payload["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
