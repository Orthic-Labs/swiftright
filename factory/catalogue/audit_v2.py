"""Context and signature reconciliation for Swift SDK interfaces."""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from factory.core import artifacts
from .catalogue import HIDDEN_ATTRIBUTES, _interface_target, sha_file

_DECL = re.compile(r"\b(public|open)\s+(?:(?:nonisolated|static|class|final|mutating|nonmutating|override|prefix|postfix|infix|indirect|lazy|weak|unowned|isolated|distributed|consuming|borrowing|sending|async|throws|rethrows|package|deprecated)\s+)*(func|var|let|subscript|init|deinit|struct|class|enum|protocol|actor|typealias|associatedtype|operator|macro|case)\s+?([A-Za-z_][A-Za-z_0-9]*)?")
_EXT = re.compile(r"\bextension\s+([^\{]+)\{")
_NOMINAL = re.compile(r"\b(public|open)\s+(?:nonisolated\s+)?(struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z_0-9]*)")
_MODULES = {"SwiftUI", "SwiftUICore", "Swift", "Foundation", "AppKit", "CoreGraphics", "CoreFoundation", "Combine", "UniformTypeIdentifiers", "Observation", "OSLog", "CoreData", "CoreMedia"}
_MODULE_QUALIFIER = re.compile(r"\b(?:" + "|".join(re.escape(module) for module in sorted(_MODULES, key=len, reverse=True)) + r")(?:::|\.)")
_TARGET_UNAVAILABLE = re.compile(r"@available\(\s*(?:\*|macOS)\s*,\s*unavailable\s*\)")
_OPERATOR_NAME = re.compile(r"^[!$%&*+\-./:<=>?@\\^|~]+$")


def _balanced_braces(line: str) -> tuple[int, int]:
    clean = re.sub(r'"(?:\\.|[^"\\])*"', '""', line.split("//", 1)[0])
    return clean.count("{"), clean.count("}")


def _scope_target(text: str) -> tuple[str, ...]:
    text = text.split(" where ", 1)[0].strip()
    text = text.split(" : ", 1)[0].strip()
    # Generic arguments belong to constraints, not nominal path identity.
    text = re.sub(r"<.*$", "", text)
    names = re.findall(r"[A-Za-z_][A-Za-z_0-9]*", text)
    return tuple(names[1:] if names and names[0] in _MODULES else names)


def _split_top_level(text: str, delimiter: str = ",") -> list[str]:
    result: list[str] = []
    start = 0
    depths = {"(": 0, "<": 0, "[": 0, "{": 0}
    pairs = {")": "(", ">": "<", "]": "[", "}": "{"}
    for i, char in enumerate(text):
        if char in depths:
            depths[char] += 1
        elif char in pairs:
            depths[pairs[char]] = max(0, depths[pairs[char]] - 1)
        elif char == delimiter and not any(depths.values()):
            result.append(text[start:i].strip())
            start = i + 1
    result.append(text[start:].strip())
    return result if result != [""] else []


def _normalize_type(value: str) -> str:
    value = _MODULE_QUALIFIER.sub("", value)
    # SymbolGraph parameter fragments omit `@escaping`; compare underlying
    # closure types while retaining type-level attributes such as @Sendable.
    value = re.sub(r"@escaping\s*", "", value)
    value = re.sub(r"\s+", "", value)
    value = re.sub(r"=.+$", "", value)
    return value


def _where_constraints(declaration: str) -> tuple[str, ...] | None:
    """Return normalized, unordered generic constraints when present.

    Constraint order is semantically irrelevant. A missing ``where`` clause is
    distinct from a clause that could not be parsed, so callers never use a
    partial constraint parse to disambiguate overloads.
    """
    match = re.search(r"\bwhere\s+(.+?)(?:\s*\{\s*)?$", declaration)
    if not match:
        return ()
    values = _split_top_level(match.group(1))
    if not values:
        return None
    return tuple(sorted(re.sub(r"\s+", "", _MODULE_QUALIFIER.sub("", value)) for value in values))


def _return_type(declaration: str) -> str | None:
    match = re.search(r"->\s*(.+?)(?:\s+where\s+.+|\s*\{\s*)?$", declaration)
    return _normalize_type(match.group(1).strip()) if match else None


def _argument_signature(text: str, *, allow_unlabeled: bool = False) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
    params: list[str] = []
    types: list[str] = []
    for part in _split_top_level(text):
        colon = -1
        depths = {"(": 0, "<": 0, "[": 0, "{": 0}
        pairs = {")": "(", ">": "<", "]": "[", "}": "{"}
        for i, char in enumerate(part):
            if char in depths:
                depths[char] += 1
            elif char in pairs:
                depths[pairs[char]] = max(0, depths[pairs[char]] - 1)
            elif char == ":" and not any(depths.values()):
                colon = i
                break
        if colon < 0:
            if allow_unlabeled and part:
                params.append("_")
                types.append(_normalize_type(part))
                continue
            return None
        before, type_text = part[:colon].strip(), part[colon + 1 :].strip()
        # Attributes and parameter modifiers precede external/internal labels.
        before = re.sub(r"@[A-Za-z_][\w]*(?:\([^)]*\))?", " ", before)
        before = re.sub(r"\b(inout|isolated|borrowing|consuming|sending|__shared|__owned)\b", " ", before)
        words = re.findall(r"[A-Za-z_][A-Za-z_0-9]*|_", before)
        if not words:
            return None
        label = words[0]
        params.append(label)
        type_text = re.split(r"\s*=\s*", type_text, maxsplit=1)[0]
        types.append(_normalize_type(type_text))
    return tuple(params), tuple(types)


def _interface_rows(path: Path) -> list[dict[str, Any]]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    rows: list[dict[str, Any]] = []
    attributes: list[dict[str, Any]] = []
    conditions: list[str] = []
    scopes: list[tuple[int, tuple[str, ...], str, list[dict[str, Any]]]] = []
    depth = 0
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#if "):
            conditions.append(stripped[4:].strip())
        elif stripped.startswith("#elseif ") and conditions:
            conditions[-1] = stripped[8:].strip()
        elif stripped == "#else" and conditions:
            conditions[-1] = "else(" + conditions[-1] + ")"
        elif stripped == "#endif" and conditions:
            conditions.pop()

        if stripped.startswith("@"):
            attributes.append({"line": number, "value": stripped})
        match = _DECL.search(stripped)
        if match:
            kind, name = match.group(2), match.group(3) or match.group(2)
            if kind == "func" and not match.group(3):
                operator_name = re.search(r"\bfunc\s+([^\s(]+)", stripped)
                if operator_name:
                    name = operator_name.group(1)
            context = tuple(part for _, names, _, _ in scopes for part in names)
            inline_attributes = [{"line": number, "value": value} for value in re.findall(r"@_?[A-Za-z][A-Za-z0-9_]*(?:\([^)]*\))?", stripped)]
            inherited_attributes = [entry for scope in scopes for entry in scope[3]]
            all_attrs = list({(entry["line"], entry["value"]): entry for entry in inherited_attributes + attributes[-12:] + inline_attributes}.values())
            hidden = next((reason for pattern, reason in HIDDEN_ATTRIBUTES if any(pattern.search(attr["value"]) for attr in all_attrs)), None)
            unavailable = any(_TARGET_UNAVAILABLE.search(attr["value"]) for attr in all_attrs)
            signature = stripped
            signature_complete = True
            labels: tuple[str, ...] = ()
            types: tuple[str, ...] = ()
            if kind in {"func", "init", "subscript"}:
                paren = signature.find("(", match.end())
                if paren >= 0:
                    level = 0
                    close = None
                    for i in range(paren, len(signature)):
                        level += (signature[i] == "(") - (signature[i] == ")")
                        if level == 0:
                            close = i
                            break
                    if close is None:
                        signature_complete = False
                    else:
                        parsed = _argument_signature(signature[paren + 1 : close])
                        if parsed is None:
                            signature_complete = False
                        else:
                            labels, types = parsed
                else:
                    signature_complete = False
            constraints = _where_constraints(signature)
            return_type = _return_type(signature) if kind in {"func", "init", "subscript"} else None
            if not stripped.startswith("//"):
                rows.append({"interface": path.name, "module": "SwiftUICore" if "SwiftUICore.framework" in str(path) else "SwiftUI", "line": number, "kind": kind, "name": name, "context": list(context), "labels": list(labels), "parameterTypes": list(types), "returnType": return_type, "whereConstraints": list(constraints) if constraints is not None else None, "signature": signature[:1000], "signatureComplete": signature_complete, "attributes": all_attrs, "conditions": list(conditions), "classification": "hidden-attribute" if hidden else ("excluded-target-availability" if unavailable else "unresolved"), "hiddenReason": hidden, "targetExclusion": "macOS unavailable attribute" if unavailable else None})
        elif stripped.startswith("case ") and any(scope[2] == "enum" for scope in scopes):
            context = tuple(part for _, names, _, _ in scopes for part in names)
            inherited_attributes = [entry for scope in scopes for entry in scope[3]]
            all_attrs = list({(entry["line"], entry["value"]): entry for entry in inherited_attributes + attributes[-12:]}.values())
            hidden = next((reason for pattern, reason in HIDDEN_ATTRIBUTES if any(pattern.search(attr["value"]) for attr in all_attrs)), None)
            unavailable = any(_TARGET_UNAVAILABLE.search(attr["value"]) for attr in all_attrs)
            for part in _split_top_level(stripped[5:]):
                case = re.match(r"([A-Za-z_][A-Za-z_0-9]*)(?:\((.*)\))?", part)
                if not case:
                    continue
                parsed = _argument_signature(case.group(2), allow_unlabeled=True) if case.group(2) is not None else ((), ())
                labels, types = parsed if parsed is not None else ((), ())
                rows.append({"interface": path.name, "module": "SwiftUICore" if "SwiftUICore.framework" in str(path) else "SwiftUI", "line": number, "kind": "case", "name": case.group(1), "context": list(context), "labels": list(labels), "parameterTypes": list(types), "signature": part[:1000], "signatureComplete": parsed is not None, "attributes": all_attrs, "conditions": list(conditions), "classification": "hidden-attribute" if hidden else ("excluded-target-availability" if unavailable else "unresolved"), "hiddenReason": hidden, "targetExclusion": "macOS unavailable attribute" if unavailable else None})
        # Push nominal or extension context only after recording its own declaration.
        ext = _EXT.search(stripped)
        nominal = _NOMINAL.search(stripped)
        opens, closes = _balanced_braces(stripped)
        inline_attributes = [{"line": number, "value": value} for value in re.findall(r"@_?[A-Za-z][A-Za-z0-9_]*(?:\([^)]*\))?", stripped)]
        scope_attributes = [entry for scope in scopes for entry in scope[3]]
        pushed_attributes = list({(entry["line"], entry["value"]): entry for entry in scope_attributes + attributes[-12:] + inline_attributes}.values())
        if opens and ext:
            scopes.append((depth + opens, _scope_target(ext.group(1)), "extension", pushed_attributes))
        elif opens and nominal:
            scopes.append((depth + opens, (nominal.group(3),), nominal.group(2), pushed_attributes))
        depth += opens - closes
        scopes = [scope for scope in scopes if scope[0] <= depth]
        if match or (stripped and not stripped.startswith("//") and not stripped.startswith("@")):
            attributes = []
    return rows


def _graph_kind_family(kind: str) -> str:
    if kind in {"func", "operator"}:
        return "callable"
    if kind in {"init", "subscript"}:
        return kind
    if kind in {"var", "let"}:
        return "property"
    return kind


def _symbol_family(identifier: str) -> str:
    kind = identifier.removeprefix("swift.")
    if kind in {"method", "type.method", "func", "func.op"}:
        return "callable"
    if kind in {"init"}:
        return "init"
    if kind in {"subscript", "type.subscript"}:
        return "subscript"
    if kind in {"property", "type.property"}:
        return "property"
    if kind == "enum.case":
        return "case"
    return kind


def _symbol_labels(component: str) -> tuple[str, ...] | None:
    match = re.search(r"\((.*)\)$", component)
    if not match:
        return ()
    parts = _split_top_level(match.group(1), ":")
    return tuple(part for part in parts if part)


def _symbol_types(symbol: dict[str, Any]) -> tuple[str, ...] | None:
    result = []
    for parameter in symbol.get("functionSignature", {}).get("parameters", []):
        fragments = parameter.get("declarationFragments", [])
        text = "".join(fragment.get("spelling", "") for fragment in fragments)
        colon = text.find(":")
        if colon < 0:
            return None
        result.append(_normalize_type(text[colon + 1 :]))
    return tuple(result)


def _load_index(graph_paths: Iterable[Path]) -> tuple[dict[tuple[Any, ...], list[dict[str, Any]]], set[str], dict[str, Any]]:
    index: dict[tuple[Any, ...], list[dict[str, Any]]] = defaultdict(list)
    all_usrs: set[str] = set()
    counts = []
    for path in sorted(map(Path, graph_paths)):
        graph = json.loads(path.read_text(encoding="utf-8"))
        graph_module = graph.get("module", {}).get("name", path.name.split("@")[0])
        counts.append({"file": path.name, "module": graph_module, "symbols": len(graph.get("symbols", [])), "sha256": sha_file(path)})
        for symbol in graph.get("symbols", []):
            usr = symbol.get("identifier", {}).get("precise")
            components = symbol.get("pathComponents", [])
            if not usr or not components:
                continue
            all_usrs.add(usr)
            component = components[-1]
            name = component.split("(", 1)[0]
            declaration = "".join(fragment.get("spelling", "") for fragment in symbol.get("declarationFragments", []))
            returns = symbol.get("functionSignature", {}).get("returns", [])
            return_type = _normalize_type("".join(fragment.get("spelling", "") for fragment in returns)) if returns else _return_type(declaration)
            item = {"usr": usr, "pathComponents": components, "kind": symbol.get("kind", {}).get("identifier", ""), "family": _symbol_family(symbol.get("kind", {}).get("identifier", "")), "labels": _symbol_labels(component), "types": _symbol_types(symbol), "returnType": return_type, "whereConstraints": _where_constraints(declaration), "accessLevel": symbol.get("accessLevel"), "graph": path.name}
            key = (tuple(components[:-1]), name, item["family"])
            index[key].append(item)
    return index, all_usrs, {"graphs": counts, "graphSymbolCount": sum(item["symbols"] for item in counts), "graphUsrCount": len(all_usrs)}


def audit_v2(interface_paths: Iterable[Path], graph_paths: Iterable[Path], *, symbolgraph_target: str | None = None, comparison_graph_paths: Iterable[Path] = (), version: int = 2) -> dict[str, Any]:
    index, usrs, graph_summary = _load_index(graph_paths)
    rows: list[dict[str, Any]] = []
    interface_hashes = []
    for path in sorted(map(Path, interface_paths)):
        module = "SwiftUICore" if "SwiftUICore.framework" in str(path) else "SwiftUI"
        interface_hashes.append({"file": path.name, "module": module, "target": _interface_target(path), "sha256": sha_file(path)})
        for row in _interface_rows(path):
            if row["classification"] in {"hidden-attribute", "excluded-target-availability"}:
                rows.append(row)
                continue
            family = _graph_kind_family(row["kind"])
            key = (tuple(row["context"]), row["name"], family)
            candidates = index.get(key, [])
            # Context tails accommodate interface qualification differences, but never fall back to global name-only matches.
            if not candidates and row["context"]:
                for size in range(len(row["context"]) - 1, 0, -1):
                    candidates = index.get((tuple(row["context"][-size:]), row["name"], family), [])
                    if candidates:
                        break
            if row["kind"] in {"func", "init", "subscript", "case"} and row["signatureComplete"]:
                # Swift operator operands have no external labels. Interfaces
                # show local names (a:, b:), while symbolgraph spells `_`.
                operator = row["kind"] == "func" and bool(_OPERATOR_NAME.fullmatch(row["name"]))
                if not operator:
                    candidates = [c for c in candidates if c["labels"] == tuple(row["labels"])]
                typed = [c for c in candidates if c["types"] is not None and c["types"] == tuple(row["parameterTypes"])] if row["kind"] != "case" else []
                if typed:
                    candidates = typed
            if row.get("whereConstraints"):
                candidates = [c for c in candidates if c["whereConstraints"] == tuple(row["whereConstraints"])]
            if row.get("returnType"):
                returned = [c for c in candidates if c["returnType"] == row["returnType"]]
                if returned:
                    candidates = returned
            unique = {candidate["usr"]: candidate for candidate in candidates if candidate.get("accessLevel") in {"public", "open"}}
            if len(unique) == 1 and row["signatureComplete"]:
                match = next(iter(unique.values()))
                row["classification"] = "matched-context-signature"
                row["symbol"] = {"usr": match["usr"], "pathComponents": match["pathComponents"], "graph": match["graph"]}
            elif len(unique) > 1:
                row["classification"] = "ambiguous-context-signature"
                row["candidates"] = [{"usr": candidate["usr"], "pathComponents": candidate["pathComponents"]} for candidate in sorted(unique.values(), key=lambda item: item["usr"])[:20]]
                row["candidateCount"] = len(unique)
            elif row["conditions"]:
                row["classification"] = "unresolved-conditional"
            else:
                row["classification"] = "unexplained"
            row["hiddenReason"] = None
            rows.append(row)

    comparison = None
    comparison_paths = list(map(Path, comparison_graph_paths))
    if comparison_paths:
        _, comparison_usrs, comparison_summary = _load_index(comparison_paths)
        comparison = {"arm64Graph": comparison_summary, "arm64eGraph": graph_summary, "usrIntersection": len(comparison_usrs & usrs), "arm64Only": len(comparison_usrs - usrs), "arm64eOnly": len(usrs - comparison_usrs)}
    by_status: dict[str, int] = defaultdict(int)
    for row in rows:
        by_status[row["classification"]] += 1
    status = "complete" if not any(name in by_status for name in ("unexplained", "unresolved-conditional", "ambiguous-context-signature")) else "incomplete-context-signature-audit"
    payload = {"kind": "swift-interface-audit", "version": version, "status": status,
        "method": "Matches interface declarations by enclosing nominal/extension path, declaration kind, external labels, normalized parameter & return types (including SDK module qualification), and normalized generic where constraints to public symbolgraph USRs. Operator operands are matched by exact operand types because Swift operators have no external labels. Conditional, ambiguous, hidden-attribute, and unexplained rows retain source line, signature, conditions, and attributes. No global name-only fallback is used.",
        "interfaces": interface_hashes, "symbolgraphTarget": symbolgraph_target,
        "summary": {"publicDeclarationStarts": len(rows), "byClassification": dict(sorted(by_status.items())), "interfaceTargets": sorted({item["target"] for item in interface_hashes if item["target"]}), "graphSymbolCount": graph_summary["graphSymbolCount"], "graphUsrCount": graph_summary["graphUsrCount"], "targetComparison": comparison},
        "symbolGraphs": graph_summary["graphs"], "declarations": rows}
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def audit_v3(interface_paths: Iterable[Path], graph_paths: Iterable[Path], *, symbolgraph_target: str | None = None, comparison_graph_paths: Iterable[Path] = ()) -> dict[str, Any]:
    """Versioned follow-up audit retaining v2 snapshots unchanged on disk."""
    return audit_v2(interface_paths, graph_paths, symbolgraph_target=symbolgraph_target, comparison_graph_paths=comparison_graph_paths, version=3)


def audit_v4(interface_paths: Iterable[Path], graph_paths: Iterable[Path], *, symbolgraph_target: str | None = None, comparison_graph_paths: Iterable[Path] = ()) -> dict[str, Any]:
    """Versioned audit with complete known SDK module qualifier normalization."""
    return audit_v2(interface_paths, graph_paths, symbolgraph_target=symbolgraph_target, comparison_graph_paths=comparison_graph_paths, version=4)
