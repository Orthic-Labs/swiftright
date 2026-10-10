"""Build a narrowly scoped, SDK-backed SwiftUI signature/USR reference."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from factory.core import artifacts

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "factory/catalogue/evidence"
RAW = ROOT / "factory/out/catalogue/raw"
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")

# Entries are keyed by symbol-graph path context. `View.scaledToFit` is called on
# Image through protocol conformance; retaining View as defining context matters.
GROUPS = {
    "shapes": {"Rectangle", "RoundedRectangle", "Circle"},
    "zstack": {"ZStack"},
    "overlay": {"View"},
    "image-sizing": {"Image", "View"},
    "font": {"Font"},
    "line-limit": {"View"},
    "layout-geometry": {"Layout"},
    "scroll-view": {"ScrollView"},
    "frame-padding": {"View"},
    "preference-key": {"PreferenceKey"},
    "labels-hidden": {"View"},
}
METHODS = {
    "shapes": {"Rectangle": {"init", "path"}, "RoundedRectangle": {"init", "path", "cornerSize", "style"}, "Circle": {"init", "path"}},
    "zstack": {"ZStack": {"init"}},
    "overlay": {"View": {"overlay"}},
    "image-sizing": {"Image": {"resizable"}, "View": {"scaledToFit"}},
    "font": {"Font": {"system", "custom"}},
    "line-limit": {"View": {"lineLimit"}},
    "layout-geometry": {"Layout": {"sizeThatFits", "placeSubviews", "explicitAlignment"}},
    "scroll-view": {"ScrollView": {"init", "axes"}},
    "frame-padding": {"View": {"frame", "padding"}},
    "preference-key": {"PreferenceKey": {"defaultValue", "reduce"}},
    "labels-hidden": {"View": {"labelsHidden"}},
}


def _base(path_component: str) -> str:
    return path_component.split("(", 1)[0]


def build_reference() -> dict[str, Any]:
    catalogue_path = EVIDENCE / "catalogue.json"
    audit_path = EVIDENCE / "interface-audit-v5.json"
    extraction_path = EVIDENCE / "extraction-summary.json"
    catalogue = json.loads(catalogue_path.read_text())
    audit = json.loads(audit_path.read_text())
    extraction = json.loads(extraction_path.read_text())
    graph_files = sorted(RAW.glob("**/*.symbols.json"))
    graph_hashes: dict[str, str] = {}
    symbols: dict[str, dict[str, Any]] = {}
    symbol_graphs: dict[str, set[str]] = {}
    for graph_path in graph_files:
        graph = json.loads(graph_path.read_text())
        graph_name = graph_path.name
        graph_hashes[graph_name] = artifacts.file_hash(graph_path)
        for symbol in graph.get("symbols", []):
            usr = symbol.get("identifier", {}).get("precise")
            if not usr:
                continue
            symbols.setdefault(usr, symbol)
            symbol_graphs.setdefault(usr, set()).add(graph_name)

    audit_by_usr: dict[str, list[dict[str, Any]]] = {}
    audit_candidates_by_usr: dict[str, list[dict[str, Any]]] = {}
    for row in audit["declarations"]:
        usr = row.get("symbol", {}).get("usr")
        if usr:
            audit_by_usr.setdefault(usr, []).append(row)
        for candidate in row.get("candidates", []):
            candidate_usr = candidate.get("usr")
            if candidate_usr:
                audit_candidates_by_usr.setdefault(candidate_usr, []).append(row)

    grouped: dict[str, list[dict[str, Any]]] = {}
    for group, contexts in GROUPS.items():
        methods = METHODS[group]
        entries: dict[str, dict[str, Any]] = {}
        for usr, symbol in symbols.items():
            parts = symbol.get("pathComponents", [])
            if len(parts) < 2 or parts[0] not in contexts or _base(parts[-1]) not in methods.get(parts[0], set()):
                continue
            item = {
                "context": parts[0],
                "pathComponents": parts,
                "usr": usr,
                "precise": usr,
                "declarationFragments": symbol.get("declarationFragments", []),
                "graphFiles": sorted(symbol_graphs.get(usr, set())),
                "interfaceEvidence": [
                    {"interface": row["interface"], "line": row["line"], "classification": row["classification"],
                     "signature": row.get("signature"), "conditions": row.get("conditions", []),
                     "targetExclusion": row.get("targetExclusion"), "attributes": row.get("attributes", [])}
                    for row in audit_by_usr.get(usr, [])
                ],
                "interfaceCandidateEvidence": [
                    {"interface": row["interface"], "line": row["line"], "classification": row["classification"],
                     "signature": row.get("signature"), "conditions": row.get("conditions", []),
                     "candidateCount": row.get("candidateCount"), "targetExclusion": row.get("targetExclusion"),
                     "attributes": row.get("attributes", [])}
                    for row in audit_candidates_by_usr.get(usr, [])
                ],
            }
            entries[usr] = item
        grouped[group] = sorted(entries.values(), key=lambda item: (item["context"], item["pathComponents"], item["usr"]))

    interfaces = []
    for module in ("SwiftUI", "SwiftUICore"):
        path = SDK / f"System/Library/Frameworks/{module}.framework/Versions/A/Modules/{module}.swiftmodule/arm64e-apple-macos.swiftinterface"
        interfaces.append({"module": module, "target": "arm64e-apple-macos", "path": str(path), "sha256": artifacts.file_hash(path)})
    payload = {
        "kind": "swiftui-sdk-signature-reference",
        "version": 1,
        "status": "scoped-source-backed-reference",
        "scope": "Requested SwiftUI factory/layout APIs only; this artifact does not claim SDK API completeness.",
        "toolchain": extraction["toolchain"],
        "catalogue": {"path": str(catalogue_path.relative_to(ROOT)), "sha256": artifacts.file_hash(catalogue_path),
                      "symbolCount": len(catalogue["symbols"]), "target": catalogue["symbolGraph"]["target"]},
        "interfaces": interfaces,
        "symbolGraphs": [{"file": name, "sha256": digest} for name, digest in sorted(graph_hashes.items())],
        "groups": grouped,
        "summary": {"groupCount": len(grouped), "groupsWithCandidates": sum(bool(rows) for rows in grouped.values()),
                    "distinctUsrCount": len({row["usr"] for rows in grouped.values() for row in rows}),
                    "resolvedInterfaceUsrCount": len({row["usr"] for rows in grouped.values() for row in rows if row["interfaceEvidence"]}),
                    "unresolvedInterfaceMappingCount": sum(not row["interfaceEvidence"] for rows in grouped.values() for row in rows),
                    "auditStatus": audit["status"], "auditHash": audit["auditHash"]},
    }
    payload["provenance"] = artifacts.provenance(
        source="SwiftUI & SwiftUICore SDK signature cross-reference",
        inputs=[{"path": str(path), "hash": artifacts.file_hash(path)} for path in
                [catalogue_path, audit_path, extraction_path, *graph_files, *(Path(row["path"]) for row in interfaces)]],
        producer="factory.catalogue/signature-reference-1",
        created_at=catalogue.get("provenance", {}).get("createdAt"),
    )
    payload["referenceHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    artifacts.write_artifact(EVIDENCE / "sdk-signature-reference.json", build_reference())


if __name__ == "__main__":
    main()
