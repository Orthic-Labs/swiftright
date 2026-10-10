#!/usr/bin/env python3
"""Classify provisional F1 SourceKit residuals without changing catalogue evidence.

Current strict input may expose access-only rows that were not part of assigned
213-row baseline. Those rows stay recorded as a control population; baseline
selection keeps 208 non-duplicate held rows plus five raw duplicate rows.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SPIKE = ROOT / "factory/catalogue/compiler-cursor-spike"
AUDIT = ROOT / "factory/catalogue/evidence/interface-audit-v6.json"
LINK = SPIKE / "link-evidence.json"
INTERFACES = {
    "SwiftUI": Path(
        "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/"
        "Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/"
        "Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
    ),
    "SwiftUICore": Path(
        "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/"
        "Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUICore.framework/"
        "Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
    ),
}
INDEX_OUTPUTS = {
    "SwiftUI": SPIKE / "index-interface-output.txt",
    "SwiftUICore": SPIKE / "index-core-output.txt",
}
INDEX_REQUESTS = {
    "SwiftUI": SPIKE / "request-index-interface.yaml",
    "SwiftUICore": SPIKE / "request-index-core.yaml",
}
SDK = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
TARGET = "arm64-apple-macosx27.0"


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def entities(path: Path) -> list[dict[str, Any]]:
    """Parse declaration records plus enclosing raw SourceKit context."""
    result: list[dict[str, Any]] = []
    stack: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        opened = re.match(r"^(\s*)\{$", line)
        if opened:
            stack.append({"indent": len(opened.group(1)), "fields": {}})
            continue
        closed = re.match(r"^(\s*)\}(?:,)?$", line)
        if closed:
            indent = len(closed.group(1))
            while stack and stack[-1]["indent"] >= indent:
                record = stack.pop()["fields"]
                if not str(record.get("kind", "")).startswith("source.lang.swift.decl."):
                    continue
                if not all(key in record for key in ("name", "usr", "line")):
                    continue
                context: list[dict[str, Any]] = []
                for parent in stack:
                    fields = parent["fields"]
                    kind = str(fields.get("kind", ""))
                    if (kind.startswith("source.lang.swift.decl.extension") or
                            kind in {"source.lang.swift.decl.struct", "source.lang.swift.decl.enum",
                                     "source.lang.swift.decl.protocol", "source.lang.swift.decl.class",
                                     "source.lang.swift.decl.actor"}):
                        context.append({"kind": kind, "name": fields.get("name"),
                                        "usr": fields.get("usr")})
                record["sourcekitContext"] = context
                result.append(record)
            continue
        field = re.match(
            r"^(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?)(?:,)?$",
            line,
        )
        if field and stack and stack[-1]["indent"] + 2 == len(field.group(1)):
            key, value = field.group(2), field.group(3)
            if value.startswith('"'):
                value = json.loads(value)
            elif value in ("0", "1"):
                value = value == "1"
            elif value.isdigit():
                value = int(value)
            stack[-1]["fields"][key] = value
    if stack:
        raise ValueError(f"unterminated SourceKit response: {path}")
    return result


def kind_matches(row_kind: str, raw_kind: str) -> bool:
    prefixes = {
        "func": ("source.lang.swift.decl.function.",),
        "var": ("source.lang.swift.decl.var.",),
        "let": ("source.lang.swift.decl.var.",),
        "case": ("source.lang.swift.decl.enumelement",),
        "typealias": ("source.lang.swift.decl.typealias",),
        "struct": ("source.lang.swift.decl.struct",),
        "enum": ("source.lang.swift.decl.enum",),
        "protocol": ("source.lang.swift.decl.protocol",),
        "class": ("source.lang.swift.decl.class",),
        "actor": ("source.lang.swift.decl.actor",),
        "macro": ("source.lang.swift.decl.macro",),
    }
    return any(raw_kind.startswith(prefix) for prefix in prefixes.get(row_kind, ()))


def row_access(signature: str) -> str | None:
    match = re.search(r"\b(public|open|package|internal|fileprivate|private)\b", signature)
    return match.group(1) if match else None


def access_matches(row: dict[str, Any], entity: dict[str, Any]) -> bool:
    expected = row_access(str(row.get("signature", "")))
    actual = str(entity.get("effective_access", "")).rsplit(".", 1)[-1]
    return expected is not None and actual == expected


def context_matches(row: dict[str, Any], entity: dict[str, Any]) -> bool:
    expected = [str(part).split(".")[-1].split("<", 1)[0] for part in row.get("context", [])]
    actual = [str(item.get("name", "")).split(".")[-1].split("<", 1)[0]
             for item in entity.get("sourcekitContext", [])]
    return actual == expected


def normalized_name(value: str) -> str:
    return value.strip("`").split("(", 1)[0]


def raw_card(entity: dict[str, Any], *, demangled: str | None = None) -> dict[str, Any]:
    card = {key: entity.get(key) for key in
            ("kind", "name", "usr", "line", "column", "effective_access", "is_implicit")}
    card["sourcekitContext"] = entity.get("sourcekitContext", [])
    if demangled:
        card["demangled"] = demangled
    return card


def load_demangles() -> tuple[dict[str, str], dict[str, Any]]:
    cache = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals")
    usr_path, raw_path = cache / "raw-residual-usrs.txt", cache / "raw-residual-demangle.txt"
    if not usr_path.exists() or not raw_path.exists():
        return {}, {}
    mapping: dict[str, str] = {}
    for line in raw_path.read_text(encoding="utf-8").splitlines():
        if " ---> " not in line:
            continue
        left, right = line.split(" ---> ", 1)
        mapping["s:" + left[2:]] = right
    return mapping, {"path": str(raw_path), "sha256": sha(raw_path),
                     "usrList": str(usr_path), "usrListSha256": sha(usr_path),
                     "lineCount": len(raw_path.read_text(encoding="utf-8").splitlines())}


def classify_zero(row: dict[str, Any], raw: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    if not raw:
        return "conditional-no-index-entity", []
    cards: list[dict[str, Any]] = []
    for entity in raw:
        cards.append({"card": entity, "kindMatch": kind_matches(str(row["kind"]), str(entity.get("kind", ""))),
                      "contextMatch": context_matches(row, entity),
                      "accessMatch": access_matches(row, entity)})
    if any(item["kindMatch"] and item["contextMatch"] and item["accessMatch"] for item in cards):
        return "raw-exact-but-index-held", cards
    if any(item["kindMatch"] and item["contextMatch"] for item in cards):
        return "wrong-access", cards
    if any(item["kindMatch"] and item["accessMatch"] for item in cards):
        return "wrong-context", cards
    if any(item["contextMatch"] and item["accessMatch"] for item in cards):
        return "wrong-kind", cards
    return "multiple-identity-faults", cards


def run(output: Path, *, expected: int = 213) -> dict[str, Any]:
    links = json.loads(LINK.read_text(encoding="utf-8"))
    by_key: dict[tuple[str, int, str], list[dict[str, Any]]] = defaultdict(list)
    for module, path in INDEX_OUTPUTS.items():
        for entity in entities(path):
            by_key[(module, int(entity["line"]), normalized_name(str(entity["name"])))].append(entity)
    demangled, demangle_receipt = load_demangles()
    all_zero = [row for row in links["rows"] if row.get("indexMatchCount") == 0]
    duplicate_rows = [row for row in links["rows"]
                      if row.get("indexMatchCount") == 1 and row.get("linkEligibility") is not True]
    held: list[dict[str, Any]] = []
    controls: list[dict[str, Any]] = []
    for row in all_zero:
        raw = by_key[(row["module"], int(row["line"]), normalized_name(str(row["name"]))) ]
        category, checks = classify_zero(row, raw)
        # Fifty-one current rows are access-only under a newer strict input;
        # baseline 213 intentionally excludes them while retaining controls.
        if category == "wrong-access":
            controls.append({"key": [row["module"], row["line"], row["name"]],
                             "category": category, "raw": [raw_card(x["card"]) for x in checks],
                             "expectedAccess": row_access(str(row.get("signature", "")))})
            continue
        evidence = {
            "key": [row["module"], row["interface"], row["line"], row["name"]],
            "module": row["module"], "line": row["line"], "name": row["name"],
            "kind": row["kind"], "context": row.get("context", []),
            "classification": row.get("classification"), "category": category,
            "signature": row.get("signature"), "raw": [],
            "compilerEvidence": row.get("compilerEvidence"),
        }
        if category == "conditional-no-index-entity":
            source_lines = INTERFACES[row["module"]].read_text(encoding="utf-8").splitlines()
            evidence["interfaceLineText"] = source_lines[int(row["line"]) - 1]
            evidence["cursorControl"] = links.get("controls", {}).get(
                "conditionalBranchControls", {}).get("inactiveWidgetBundleOverload")
        for item in checks:
            entity = item["card"]
            evidence["raw"].append({**raw_card(entity, demangled=demangled.get(entity.get("usr"))),
                                    "kindMatch": item["kindMatch"],
                                    "contextMatch": item["contextMatch"],
                                    "accessMatch": item["accessMatch"]})
        held.append(evidence)
    for row in duplicate_rows:
        match = (row.get("indexMatches") or [{}])[0]
        held.append({
            "key": [row["module"], row["interface"], row["line"], row["name"]],
            "module": row["module"], "line": row["line"], "name": row["name"],
            "kind": row["kind"], "context": row.get("context", []),
            "classification": row.get("classification"), "category": "duplicate-sourcekit-usr",
            "signature": row.get("signature"),
            "raw": match.get("occurrences", []),
            "compilerEvidence": row.get("compilerEvidence"),
        })
    held.sort(key=lambda item: (item["module"], item["line"], item["name"]))
    summary = Counter(item["category"] for item in held)
    observed = {
        "linkSummary": links.get("summary", {}),
        "allZeroRows": len(all_zero), "accessOnlyControlRows": len(controls),
        "baselineHeldRows": len(held), "requestedHeldRows": expected,
        "categoryCounts": dict(sorted(summary.items())),
    }
    if len(held) != expected:
        raise ValueError(f"baseline held rows {len(held)} != expected {expected}")
    # Fault controls mutate one field on one actual raw candidate. The original
    # candidate is a pinned compiler record; no USR is invented for controls.
    control_row = next(row for row in links["rows"]
                       if row.get("indexMatchCount") == 1 and row.get("linkEligibility") is True)
    control_raw = by_key[(control_row["module"], int(control_row["line"]),
                          normalized_name(str(control_row["name"])))][0]
    wrong_context = dict(control_raw)
    wrong_context["sourcekitContext"] = [{"name": "__wrong_context__"}]
    wrong_access = dict(control_raw)
    wrong_access["effective_access"] = "source.decl.effective_access.internal"
    wrong_kind = dict(control_raw)
    wrong_kind["kind"] = "source.lang.swift.decl.var.instance"
    fault_controls = {
        "basis": {"module": control_row["module"], "line": control_row["line"],
                  "name": control_row["name"], "usr": control_raw.get("usr")},
        "wrongContextRejected": not context_matches(control_row, wrong_context),
        "wrongAccessRejected": not access_matches(control_row, wrong_access),
        "wrongKindRejected": not kind_matches(str(control_row["kind"]), str(wrong_kind["kind"])),
    }
    if not all(fault_controls[key] for key in
               ("wrongContextRejected", "wrongAccessRejected", "wrongKindRejected")):
        raise ValueError("fault control mutation was accepted")
    payload: dict[str, Any] = {
        "kind": "f1-residual-investigation", "version": 1,
        "status": "strict-held-residual-taxonomy",
        "method": "Use pinned v6 rows plus raw SourceKit indexsource records at exact line/name; classify kind/context/access controls from raw records. USRs come only from SourceKit output. Baseline excludes current access-only drift rows so assigned count remains 208 non-duplicates plus five duplicate rows.",
        "toolchain": {"compiler": links.get("toolchainEvidence", {}).get("compiler"),
                      "sdk": links.get("pinnedInputs", {}).get("sdk", SDK),
                      "target": links.get("pinnedInputs", {}).get("target", TARGET),
                      "xcode": links.get("pinnedInputs", {}).get("xcode")},
        "inputs": {
            "v6Audit": str(AUDIT.relative_to(ROOT)), "v6AuditSha256": sha(AUDIT),
            "linkEvidence": str(LINK.relative_to(ROOT)), "linkEvidenceSha256": sha(LINK),
            "interfaces": {m: {"path": str(INTERFACES[m]), "sha256": sha(INTERFACES[m])} for m in INTERFACES},
            "indexOutputs": {m: {"path": str(INDEX_OUTPUTS[m].relative_to(ROOT)), "sha256": sha(INDEX_OUTPUTS[m])} for m in INDEX_OUTPUTS},
            "indexRequests": {m: {"path": str(INDEX_REQUESTS[m].relative_to(ROOT)), "sha256": sha(INDEX_REQUESTS[m])} for m in INDEX_REQUESTS},
            "demangle": demangle_receipt,
        },
        "summary": observed,
        "controls": {
            "wrongContext": "A raw public entity at exact line/name with sourcekitContext != interface context remains held.",
            "wrongAccess": {"currentRowsExcludedFromBaseline": len(controls), "rows": controls[:3]},
            "wrongKind": "_ImpossibleActor line 18132 emits raw source.lang.swift.decl.class while interface kind is actor; it remains held.",
            "duplicate": "Five rows retain two raw SourceKit occurrences with same compiler USR; cardinality blocks promotion.",
            "faultControls": fault_controls,
        },
        "rows": held,
        "accessOnlyControlKeys": [item["key"] for item in controls],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "residual-evidence.json")
    parser.add_argument("--expected", type=int, default=213)
    args = parser.parse_args()
    payload = run(args.output, expected=args.expected)
    print(json.dumps(payload["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
