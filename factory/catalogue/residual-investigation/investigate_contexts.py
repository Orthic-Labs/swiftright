#!/usr/bin/env python3
"""Bounded evidence for finalized F1 enclosing-context holds.

This report is observational.  No context normalization here is used to
promote catalogue rows.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SPIKE = ROOT / "factory/catalogue/compiler-cursor-spike"
LINK = SPIKE / "link-evidence.json"
AUDIT = ROOT / "factory/catalogue/evidence/interface-audit-v6.json"
DEMANGLE = ROOT / "factory/catalogue/evidence/sourcekit-usr-demangle-v7-final.json"


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


def split_top_level(value: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    for index, char in enumerate(value):
        if char in "<([":
            depth += 1
        elif char in ">)]":
            depth -= 1
        elif char == "." and depth == 0:
            parts.append(value[start:index])
            start = index + 1
    parts.append(value[start:])
    return [part for part in parts if part]


def demangled_owner_components(demangled: str, name: str) -> list[str]:
    """Extract owner path for comparison only.

    This uses exact row name, balanced delimiters, and explicit module-token
    removal.  It is not a linkage rule.
    """
    modules = {"Swift", "SwiftUI", "SwiftUICore", "Foundation", "__C"}
    value = re.sub(
        r"^(?:static |class |mutating |nonmutating |prefix |postfix |final )+",
        "",
        demangled,
    )
    value = re.sub(r"^\(extension in [^)]+\):", "", value)
    marker = "." + name
    position = value.rfind(marker)
    if position < 0:
        raise ValueError(f"demangle has no exact member marker {marker!r}: {demangled}")
    path = split_top_level(value[:position])
    while path and path[0] not in modules:
        path.pop(0)
    result: list[str] = []
    for part in path:
        part = re.sub(r"<.*$", "", part).strip()
        if part and part not in modules:
            result.append(part)
    return result


def run(output: Path) -> dict[str, Any]:
    inv = load_investigator()
    links = json.loads(LINK.read_text(encoding="utf-8"))
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    demangles = json.loads(DEMANGLE.read_text(encoding="utf-8"))["demangledByUsr"]

    rows = [
        row for row in links["rows"]
        if row.get("linkHoldReason") == "enclosing-context-mismatch"
    ]
    if len(rows) != 206:
        raise ValueError(f"expected 206 finalized context holds, got {len(rows)}")

    raw_by_key: dict[tuple[str, int, str], list[dict[str, Any]]] = collections.defaultdict(list)
    for module, path in inv.INDEX_OUTPUTS.items():
        for entity in inv.entities(path):
            key = (module, int(entity["line"]), inv.normalized_name(str(entity["name"])))
            raw_by_key[key].append(entity)
    audit_by_key = {
        (item["module"], int(item["line"]), inv.normalized_name(str(item["name"]))): item
        for item in audit["declarations"]
    }

    evidence_rows: list[dict[str, Any]] = []
    counts = collections.Counter()
    for row in rows:
        key = (row["module"], int(row["line"]), inv.normalized_name(str(row["name"])))
        entities = raw_by_key.get(key, [])
        if len(entities) != 1:
            raise ValueError(f"raw SourceKit cardinality for {key}: {len(entities)}")
        entity = entities[0]
        audit_row = audit_by_key[key]
        usr = entity.get("usr")
        demangled = demangles.get(usr)
        if not usr or demangled is None:
            raise ValueError(f"missing exact final demangle for {key}: {usr}")
        expected_context = [str(value) for value in row.get("context", [])]
        raw_context = [str(item.get("name")) for item in entity.get("sourcekitContext", [])]
        owner = demangled_owner_components(demangled, str(row["name"]))
        module_tokens = {"Swift", "SwiftUI", "SwiftUICore", "Foundation", "__C"}
        semantic_context = [value for value in expected_context if value not in module_tokens]
        if owner != semantic_context:
            raise ValueError(
                f"owner/context comparison failed for {key}: {owner!r} != {semantic_context!r}"
            )
        raw_relation = "empty" if not raw_context else "immediate-suffix"
        if raw_context and raw_context != expected_context[-len(raw_context):]:
            raise ValueError(f"raw context is not exact suffix for {key}")
        context_match = inv.context_matches(row, entity)
        kind_match = inv.kind_matches(str(row["kind"]), str(entity.get("kind", "")))
        access_match = inv.access_matches(row, entity)
        if context_match or not kind_match or not access_match:
            raise ValueError(f"strict gate controls unexpected for {key}")
        scope_rows = audit_row.get("v6Evidence", {}).get("enclosingScopes", [])
        counts[f"rawContext:{raw_relation}"] += 1
        counts["demangleExtensionMarker:" + str("(extension in " in demangled)] += 1
        counts[f"enclosingScopeDepth:{len(scope_rows)}"] += 1
        evidence_rows.append(
            {
                "key": [row["module"], row["interface"], row["line"], row["name"]],
                "module": row["module"],
                "line": row["line"],
                "name": row["name"],
                "interfaceKind": row["kind"],
                "interfaceContext": expected_context,
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
                "demangled": demangled,
                "comparison": {
                    "rawContextRelation": raw_relation,
                    "ownerComponentsAfterExplicitModuleRemoval": owner,
                    "interfaceContextAfterExplicitModuleRemoval": semantic_context,
                    "ownerSemanticContextExact": True,
                    "kindMatch": kind_match,
                    "accessMatch": access_match,
                    "strictContextMatch": context_match,
                    "demangleExtensionMarker": "(extension in " in demangled,
                },
            }
        )
    evidence_rows.sort(key=lambda item: (item["module"], item["line"], item["name"]))

    # Synthetic controls mutate only pinned raw records; they never create USRs.
    control = evidence_rows[0]
    control_row = next(
        row for row in rows
        if [row["module"], row["interface"], row["line"], row["name"]] == control["key"]
    )
    raw_entity = raw_by_key[(control["module"], control["line"], control["name"])][0]
    expected = control_row["context"]
    accepted_if_context_repaired = dict(raw_entity)
    accepted_if_context_repaired["sourcekitContext"] = [{"name": value} for value in expected]
    rejected_wrong_context = dict(raw_entity)
    rejected_wrong_context["sourcekitContext"] = [{"name": "__wrong_context__"}]
    controls = {
        "basis": {
            "key": control["key"],
            "usr": raw_entity["usr"],
            "rawRecordSource": "pinned SourceKit index output",
        },
        "all206KindMatch": all(item["comparison"]["kindMatch"] for item in evidence_rows),
        "all206AccessMatch": all(item["comparison"]["accessMatch"] for item in evidence_rows),
        "all206StrictContextRejected": all(
            not item["comparison"]["strictContextMatch"] for item in evidence_rows
        ),
        "contextRepairWouldPassContextGate": inv.context_matches(
            control_row, accepted_if_context_repaired
        ),
        "wrongContextMutationRejected": not inv.context_matches(
            control_row, rejected_wrong_context
        ),
    }
    if not all(controls.values()):
        raise ValueError(f"fault controls failed: {controls}")

    payload = {
        "kind": "f1-context-mismatch-investigation",
        "version": 1,
        "status": "strict-held-context-taxonomy",
        "method": (
            "Finalized rows with linkHoldReason=enclosing-context-mismatch were joined "
            "by exact module/line/name to one raw SourceKit entity. Kind/access were "
            "checked with existing strict predicates. Final compiler demangles were "
            "joined by exact raw USR. Owner comparison removes only explicit module "
            "qualification tokens and is observational, never a promotion rule."
        ),
        "inputs": {
            "linkEvidence": str(LINK.relative_to(ROOT)),
            "linkEvidenceSha256": sha(LINK),
            "v6Audit": str(AUDIT.relative_to(ROOT)),
            "v6AuditSha256": sha(AUDIT),
            "finalDemangle": str(DEMANGLE.relative_to(ROOT)),
            "finalDemangleSha256": sha(DEMANGLE),
            "rawIndexOutputs": {
                module: {
                    "path": str(path.relative_to(ROOT)),
                    "sha256": sha(path),
                }
                for module, path in inv.INDEX_OUTPUTS.items()
            },
            "rawIndexRequests": {
                module: {
                    "path": str(path.relative_to(ROOT)),
                    "sha256": sha(path),
                }
                for module, path in inv.INDEX_REQUESTS.items()
            },
        },
        "summary": {
            "finalLinkHeldByContext": len(evidence_rows),
            "rawSourceKitEntityCardinality": {"one": len(evidence_rows)},
            "rawContextRelation": {
                relation.split(":", 1)[1]: value
                for relation, value in counts.items()
                if relation.startswith("rawContext:")
            },
            "demangleExtensionMarker": {
                marker.split(":", 1)[1]: value
                for marker, value in counts.items()
                if marker.startswith("demangleExtensionMarker:")
            },
            "enclosingScopeDepth": {
                depth.split(":", 1)[1]: value
                for depth, value in counts.items()
                if depth.startswith("enclosingScopeDepth:")
            },
            "kindMatch": len(evidence_rows),
            "accessMatch": len(evidence_rows),
            "strictContextMatch": 0,
            "ownerSemanticContextExact": len(evidence_rows),
            "genuineOwnerMismatch": 0,
            "missingFinalDemangle": 0,
        },
        "taxonomy": [
            {
                "id": "raw-context-empty",
                "count": counts["rawContext:empty"],
                "evidence": "Raw SourceKit entity has no enclosing context; final demangle carries extension owner marker or nominal owner.",
            },
            {
                "id": "raw-context-immediate-suffix",
                "count": counts["rawContext:immediate-suffix"],
                "evidence": "Raw SourceKit context equals exact immediate suffix of interface context; outer lexical scopes are absent.",
            },
            {
                "id": "compiler-owner-exact-after-module-qualification",
                "count": len(evidence_rows),
                "evidence": "Final demangled owner components equal interface context after removing only explicit module tokens; comparison is review evidence, not relaxed matching.",
            },
            {
                "id": "genuine-owner-mismatch",
                "count": 0,
                "evidence": "No exact raw-USR demangle disagrees with interface lexical owner under recorded comparison.",
            },
        ],
        "resolutionCandidates": [
            {
                "id": "demangle-confirmed-context-recovery",
                "count": len(evidence_rows),
                "status": "review-only",
                "requiredEvidence": [
                    "retain exact raw line/name/kind/access joins",
                    "retain exact raw USR demangle join",
                    "treat empty/suffix SourceKit context as an explicit compiler context encoding",
                    "add independent SourceKit cursor/range control before any promotion",
                ],
                "currentLinkPromotion": 0,
            }
        ],
        "controls": controls,
        "rows": evidence_rows,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "context-mismatch-evidence.json")
    args = parser.parse_args()
    payload = run(args.output)
    print(json.dumps(payload["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
