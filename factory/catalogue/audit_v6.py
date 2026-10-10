"""Candidate v6 audit: preserve v5 rows and retry exact overloads with robust signature parsing."""
from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

from factory.core import artifacts
from . import audit_v2


def _params(signature: str) -> tuple[tuple[str, ...], tuple[str, ...]] | None:
    """Parse declaration parameter labels/types, including qualified parameter attributes."""
    match = re.search(r"\b(?:func|init|subscript)\s+(?:[^ (]+\s*)?(?:<[^>]*>)?\s*\(", signature)
    if not match:
        return None
    open_paren = signature.find("(", match.start())
    level = 0
    close_paren = None
    for i in range(open_paren, len(signature)):
        level += (signature[i] == "(") - (signature[i] == ")")
        if level == 0:
            close_paren = i
            break
    if close_paren is None:
        return None
    text = signature[open_paren + 1:close_paren]
    labels: list[str] = []
    types: list[str] = []
    for parameter in audit_v2._split_top_level(text):
        colon = -1
        depth = {"(": 0, "<": 0, "[": 0, "{": 0}
        pairs = {")": "(", ">": "<", "]": "[", "}": "{"}
        for idx, char in enumerate(parameter):
            if char in depth:
                depth[char] += 1
            elif char in pairs:
                depth[pairs[char]] = max(0, depth[pairs[char]] - 1)
            elif char == ":" and not any(depth.values()):
                colon = idx
                break
        if colon < 0:
            return None
        before, type_text = parameter[:colon], parameter[colon + 1:]
        before = re.sub(r"@[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*(?:\([^)]*\))?\s*", " ", before)
        before = re.sub(r"\b(inout|isolated|borrowing|consuming|sending|__shared|__owned)\b", " ", before)
        words = re.findall(r"[A-Za-z_][A-Za-z_0-9]*|_", before)
        if not words:
            return None
        labels.append(words[0])
        type_text = re.split(r"\s*=\s*", type_text, maxsplit=1)[0]
        # @escaping is a parameter modifier, while @Sendable/global actor
        # attributes are part of closure type identity and must be retained.
        type_text = re.sub(r"@escaping\s*", "", type_text)
        types.append(audit_v2._normalize_type(type_text))
    return tuple(labels), tuple(types)


def _return(signature: str) -> str | None:
    """Find top-level result arrow, ignoring function arrows inside parameter types."""
    match = re.search(r"\b(?:func|init|subscript)\b", signature)
    if not match:
        return None
    depth = {"(": 0, "<": 0, "[": 0, "{": 0}
    pairs = {")": "(", ">": "<", "]": "[", "}": "{"}
    idx = match.start()
    while idx < len(signature) - 1:
        # `>` in an arrow is not a generic closer. Skip complete nested
        # function arrows before examining bracket depth.
        if signature[idx:idx + 2] == "->":
            if not any(depth.values()):
                value = signature[idx + 2:].strip()
                value = re.split(r"\s+where\s+", value, maxsplit=1)[0]
                value = re.sub(r"\s*\{\s*$", "", value).strip()
                return audit_v2._normalize_type(value)
            idx += 2
            continue
        char = signature[idx]
        if char in depth:
            depth[char] += 1
        elif char in pairs:
            depth[pairs[char]] = max(0, depth[pairs[char]] - 1)
        idx += 1
    return None


def _context_candidates(index: dict[tuple[Any, ...], list[dict[str, Any]]], row: dict[str, Any]) -> list[dict[str, Any]]:
    family = audit_v2._graph_kind_family(row["kind"])
    context = tuple(row.get("context", []))
    candidates = index.get((context, row["name"], family), [])
    return [candidate for candidate in candidates if candidate.get("accessLevel") in {"public", "open"}]


def _candidate_record(candidate: dict[str, Any]) -> dict[str, Any]:
    return {"usr": candidate["usr"], "pathComponents": candidate["pathComponents"],
            "labels": list(candidate["labels"]) if candidate.get("labels") is not None else None,
            "parameterTypes": list(candidate["types"]) if candidate.get("types") is not None else None,
            "returnType": candidate.get("returnType"),
            "whereConstraints": list(candidate["whereConstraints"]) if candidate.get("whereConstraints") is not None else None,
            "graph": candidate.get("graph")}


_SCOPE_NOMINAL = re.compile(r"\b(?:(public|open|internal|fileprivate|private|package)\s+)?(?:nonisolated\s+)?(struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z_0-9]*)")
_SCOPE_EXTENSION = re.compile(r"\b(?:(public|open|internal|fileprivate|private|package)\s+)?extension\s+([^\{]+)\{")


def _line_scopes(path: Path) -> dict[int, list[dict[str, Any]]]:
    """Capture lexical nominal/extension scopes, including internal nominal parents."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    scopes: list[dict[str, Any]] = []
    by_line: dict[int, list[dict[str, Any]]] = {}
    depth = 0
    for number, line in enumerate(lines, 1):
        # Remove comments while preserving quoted text before searching for
        # scope headers; comments must never manufacture access evidence.
        clean = re.sub(r'"(?:\\.|[^"\\])*"|//.*', lambda match: '""' if match.group(0).startswith('"') else "", line).strip()
        stripped = line.strip()
        by_line[number] = [dict(scope) for scope in scopes]
        nominal = _SCOPE_NOMINAL.search(clean)
        extension = _SCOPE_EXTENSION.search(clean)
        opens, closes = clean.count("{"), clean.count("}")
        if opens and extension:
            scopes.append({"kind": "extension", "access": extension.group(1) or "unspecified",
                           "target": extension.group(2).strip(), "line": number, "declaration": clean[:700],
                           "depth": depth + opens})
        elif opens and nominal:
            scopes.append({"kind": nominal.group(2), "access": nominal.group(1) or "internal",
                           "target": nominal.group(3), "line": number, "declaration": clean[:700],
                           "depth": depth + opens})
        depth += opens - closes
        scopes = [scope for scope in scopes if scope["depth"] <= depth]
    return by_line


def _nonpublic_scope(scopes: list[dict[str, Any]]) -> dict[str, Any] | None:
    inaccessible = {"internal", "package", "fileprivate", "private"}
    for scope in scopes:
        if scope["kind"] != "extension" and scope["access"] in inaccessible:
            return scope
        if scope["kind"] == "extension" and scope["access"] in inaccessible:
            return scope
    return None


def _attempt(row: dict[str, Any], index: dict[tuple[Any, ...], list[dict[str, Any]]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    signature = row.get("signature", "")
    if len(signature) >= 1000:
        return [], {"reason": "source-signature-truncated", "candidateCount": 0}
    candidates = _context_candidates(index, row)
    if not candidates:
        return [], {"reason": "no-public-candidate-at-exact-context-and-name", "candidateCount": 0}
    nearby = [_candidate_record(candidate) for candidate in candidates[:8]]
    candidate_count = len(candidates)
    family = audit_v2._graph_kind_family(row["kind"])
    label_match_count: int | None = None
    type_match_count: int | None = None
    constraint_match_count: int | None = None
    return_match_count: int | None = None
    if row["kind"] in {"func", "init", "subscript", "case"}:
        parsed = _params(signature)
        if not parsed:
            return [], {"reason": "interface-parameter-signature-not-parseable", "candidateCount": 0,
                        "contextNameCandidateCount": candidate_count, "nearbyCandidates": nearby}
        labels, types = parsed
        operator = row["kind"] == "func" and bool(audit_v2._OPERATOR_NAME.fullmatch(row["name"]))
        if not operator:
            candidates = [candidate for candidate in candidates if candidate["labels"] == labels]
        label_match_count = len(candidates)
        typed = [candidate for candidate in candidates if candidate.get("types") is not None and candidate["types"] == types]
        if typed:
            candidates = typed
        else:
            candidates = []
        type_match_count = len(candidates)
        result_type = _return(signature)
    else:
        result_type = None
    where = audit_v2._where_constraints(signature)
    if where is None:
        return [], {"reason": "interface-where-constraints-not-parseable", "candidateCount": 0,
                    "contextNameCandidateCount": candidate_count, "nearbyCandidates": nearby,
                    "labelMatchCount": label_match_count, "parameterTypeMatchCount": type_match_count}
    if row["kind"] in {"func", "init", "subscript", "case"}:
        candidates = [candidate for candidate in candidates if candidate.get("whereConstraints") == where]
        constraint_match_count = len(candidates)
    if result_type:
        candidates = [candidate for candidate in candidates if candidate.get("returnType") == result_type]
        return_match_count = len(candidates)
    unique = {candidate["usr"]: candidate for candidate in candidates}
    reason = ("exact-context-signature-and-return-match" if len(unique) == 1 else
              "multiple-signature-compatible-usrs" if len(unique) > 1 else
              "context-name-candidates-fail-exact-signature")
    return list(unique.values()), {"reason": reason, "candidateCount": len(unique),
                                   "contextNameCandidateCount": candidate_count,
                                   "labelMatchCount": label_match_count, "parameterTypeMatchCount": type_match_count,
                                   "constraintMatchCount": constraint_match_count, "returnTypeMatchCount": return_match_count,
                                   "parsedReturnType": result_type,
                                   "candidates": nearby if len(unique) == 0 else [_candidate_record(candidate) for candidate in list(unique.values())[:8]],
                                   "nearbyCandidates": nearby if len(unique) == 0 else []}


def build_audit_v6(v5_path: Path, graph_paths: Iterable[Path], *, evidence_path: str = "evidence/interface-audit-v6.json") -> dict[str, Any]:
    v5 = json.loads(Path(v5_path).read_text())
    index, all_usrs, graph_summary = audit_v2._load_index(graph_paths)
    rows = json.loads(json.dumps(v5["declarations"]))
    v6_matches = 0
    internal_scope_exclusions = 0
    before = Counter(row["classification"] for row in rows)
    extraction = json.loads((Path(v5_path).parent / "extraction-summary.json").read_text())
    sdk = Path(extraction["toolchain"]["sdkPath"])
    interface_paths = {
        module: sdk / f"System/Library/Frameworks/{module}.framework/Versions/A/Modules/{module}.swiftmodule/arm64e-apple-macos.swiftinterface"
        for module in ("SwiftUI", "SwiftUICore")
    }
    scope_cache = {module: _line_scopes(path) for module, path in interface_paths.items()}
    for row in rows:
        original = row["classification"]
        if original not in {"active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained"}:
            continue
        candidates, diagnostic = _attempt(row, index)
        lexical_scopes = scope_cache.get(row.get("module"), {}).get(row.get("line"), [])
        private_scope = _nonpublic_scope(lexical_scopes)
        row["v6Evidence"] = {
            "method": "exact contextual candidate lookup; corrected module-qualified parameter attributes & top-level return-arrow parsing; exact normalized parameter, constraints & return matching",
            **diagnostic,
            "enclosingScopes": lexical_scopes,
        }
        if private_scope:
            row["v6PriorClassification"] = original
            row["classification"] = "excluded-nonpublic-enclosing-context"
            row["v6Evidence"]["reason"] = "declaration-is-nested-under-explicit-nonpublic-scope"
            row["v6Evidence"]["scopeEvidence"] = private_scope
            internal_scope_exclusions += 1
        elif len(candidates) == 1:
            candidate = candidates[0]
            row["v6PriorClassification"] = original
            row["classification"] = "matched-context-signature"
            row["symbol"] = {"usr": candidate["usr"], "pathComponents": candidate["pathComponents"], "graph": candidate["graph"]}
            v6_matches += 1
    counts = Counter(row["classification"] for row in rows)
    remaining = sum(counts[name] for name in ("active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained"))
    residual_reasons = Counter(row.get("v6Evidence", {}).get("reason", "no-v6-attempt") for row in rows
                               if row.get("classification") in {"active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained"})
    excluded_scope_counts = Counter(row.get("v6Evidence", {}).get("scopeEvidence", {}).get("access", "unknown") for row in rows
                                    if row.get("classification") == "excluded-nonpublic-enclosing-context")
    payload: dict[str, Any] = {
        "kind": "swift-interface-audit",
        "version": 6,
        "status": "incomplete-context-signature-audit",
        "method": (v5["method"] + " Candidate v6 retries only prior active-unmapped, ambiguous, & unexplained rows. It repairs module-qualified declaration-attribute label parsing and ignores closure arrows when reading result types; only exact-context/name candidates whose normalized labels, parameter types, generic constraints, and return type agree become matches. Every residual row retains an exact candidate-search reason & any graph candidates; no residual is classified hidden or inactive by inference. The graph target is read from the current extraction-summary input rather than inherited from the parent audit."),
        "parentAudit": {"path": "evidence/interface-audit-v5.json", "auditHash": v5["auditHash"], "status": v5["status"],
                        "symbolgraphTarget": v5.get("symbolgraphTarget")},
        "summary": {"beforeV5ResidualCounts": {key: before[key] for key in ("active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained")},
                    "v6NewMatches": v6_matches,
                    "v6NonpublicEnclosingScopeExclusions": internal_scope_exclusions,
                    "v6NonpublicScopeRowsByAccess": dict(sorted(excluded_scope_counts.items())),
                    "remainingResidualRowsBySearchReason": dict(sorted(residual_reasons.items())),
                    "byClassification": dict(sorted(counts.items())),
                    "remainingActiveUnmappedAmbiguousOrUnexplained": remaining,
                    "graphSymbolCount": graph_summary["graphSymbolCount"], "graphUsrCount": graph_summary["graphUsrCount"],
                    "matchedV6CountsByPriorStatus": dict(sorted(Counter(row["v6PriorClassification"] for row in rows
                                                                         if row.get("classification") == "matched-context-signature" and "v6PriorClassification" in row).items()))},
        "interfaces": v5["interfaces"],
        "symbolGraphs": graph_summary["graphs"],
        "symbolgraphTarget": extraction["toolchain"]["target"],
        "graphTargetEvidence": {
            "source": "evidence/extraction-summary.json",
            "sourceHash": artifacts.file_hash(Path(v5_path).parent / "extraction-summary.json"),
            "target": extraction["toolchain"]["target"],
            "graphInputs": "factory/out/catalogue/raw",
        },
        "compilerConditionalEvidence": v5["compilerConditionalEvidence"],
        "declarations": rows,
    }
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    evidence = root / "factory/catalogue/evidence"
    sdk = Path(json.loads((evidence / "extraction-summary.json").read_text())["toolchain"]["sdkPath"])
    interfaces = [sdk / f"System/Library/Frameworks/{module}.framework/Versions/A/Modules/{module}.swiftmodule/arm64e-apple-macos.swiftinterface"
                  for module in ("SwiftUI", "SwiftUICore")]
    graphs = sorted((root / "factory/out/catalogue/raw").glob("**/*.symbols.json"))
    payload = build_audit_v6(evidence / "interface-audit-v5.json", graphs)
    artifacts.write_artifact(evidence / "interface-audit-v6.json", payload)


if __name__ == "__main__":
    main()
