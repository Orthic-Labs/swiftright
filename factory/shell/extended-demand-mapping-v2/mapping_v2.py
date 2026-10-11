"""Current-source bindings for exact F12 extended-demand catalogue references."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
BASE_CANDIDATE_PATH = "factory/shell/extended-demand-mapping-v1/evidence/mapping-candidate.json"
CATALOGUE_PATH = "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json"
BASE_CANDIDATE_SHA256 = "0a55d077c4824f3a8d59a8cb9dd13aa689e4dab50e629680d900b2798361e466"
CATALOGUE_SHA256 = "fd453b6345f83b49931c7194c2e1127538e2de4ceb0de4c25f715ac6d85ac4f2"
SNAPSHOT_MANIFEST_SHA256 = "6131cca4b304c93cd2933fa7d28c0d708e7608d0b4c31fd8659e18368dd3b1b8"

# Byte-exact source lines from EditorScreen.swift. Leading indentation is part of
# each pinned line; no trimming or whitespace normalization is performed.
USAGES = {
    "List/ForEach/onMove": [
        ("SwiftUI.List", "s:7SwiftUI4ListV", "examples/SliceApp/Sources/SliceApp/Shared/EditorScreen.swift", "            List {", "List container"),
        ("SwiftUI.ForEach", "s:7SwiftUI7ForEachV", "examples/SliceApp/Sources/SliceApp/Shared/EditorScreen.swift", "                ForEach($model.rows, id: \\.id) { row in", "ForEach row iteration"),
        ("SwiftUI.DynamicViewContent.onMove(perform:)", "s:7SwiftUI18DynamicViewContentPAAE6onMove7performQry10Foundation8IndexSetV_SitcSg_tF", "examples/SliceApp/Sources/SliceApp/Shared/EditorScreen.swift", "                .onMove { offsets, destination in", "onMove trailing-closure call"),
    ],
    "TextField/FocusState": [
        ("SwiftUI.TextField", "s:7SwiftUI9TextFieldV", "examples/SliceApp/Sources/SliceApp/Shared/EditorScreen.swift", "            TextField(\"Row\", text: Binding(get: { text.wrappedValue }, set: { model.editText(id, $0) }))", "TextField initializer call"),
        ("SwiftUI.FocusState", "s:7SwiftUI10FocusStateV", "examples/SliceApp/Sources/SliceApp/Shared/EditorScreen.swift", "    @FocusState private var focus: UUID?", "FocusState property wrapper"),
    ],
}
EXPECTED_ROWS = {
    "List/ForEach/onMove": "f12-extended-004",
    "TextField/FocusState": "f12-extended-006",
}


class MappingV2Error(ValueError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _json(raw: bytes, name: str) -> Any:
    try:
        return json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MappingV2Error(f"{name} is not valid JSON bytes") from exc


def build_candidate(base_bytes: bytes, catalogue_bytes: bytes, manifest_bytes: bytes,
                    snapshots: dict[str, bytes]) -> dict[str, Any]:
    for name, raw in (("base candidate", base_bytes), ("catalogue", catalogue_bytes), ("snapshot manifest", manifest_bytes)):
        if not isinstance(raw, bytes):
            raise MappingV2Error(f"{name} must be exact bytes")
    if _sha(base_bytes) != BASE_CANDIDATE_SHA256:
        raise MappingV2Error("v1 candidate pin mismatch")
    if _sha(catalogue_bytes) != CATALOGUE_SHA256:
        raise MappingV2Error("F1 catalogue pin mismatch")
    if _sha(manifest_bytes) != SNAPSHOT_MANIFEST_SHA256:
        raise MappingV2Error("current-source snapshot manifest pin mismatch")

    base = _json(base_bytes, "v1 candidate")
    catalogue = _json(catalogue_bytes, "catalogue")
    manifest = _json(manifest_bytes, "snapshot manifest")
    if base.get("denominator", {}).get("extendedDemandRows") != 107 or base.get("denominator", {}).get("registryMappedRows") != 0:
        raise MappingV2Error("v1 denominator or no-promotion invariant changed")
    if len(base.get("rows", [])) != 107:
        raise MappingV2Error("v1 demand rows are incomplete")

    source_by_path: dict[str, tuple[dict[str, Any], bytes]] = {}
    rows = manifest.get("sources")
    if manifest.get("kind") != "f12-extended-demand-current-source-snapshot" or manifest.get("sourceCount") != 2 or not isinstance(rows, list) or len(rows) != 2:
        raise MappingV2Error("current-source snapshot manifest shape changed")
    if not isinstance(snapshots, dict) or set(snapshots) != {row.get("snapshotPath") for row in rows}:
        raise MappingV2Error("current-source snapshot set differs from manifest")
    for row in rows:
        path, snap_path, digest, size = row.get("sourcePath"), row.get("snapshotPath"), row.get("sha256"), row.get("bytes")
        raw = snapshots.get(snap_path)
        if not all(isinstance(x, str) for x in (path, snap_path, digest)) or type(size) is not int or not isinstance(raw, bytes):
            raise MappingV2Error("current-source snapshot record malformed")
        if len(raw) != size or _sha(raw) != digest or path in source_by_path:
            raise MappingV2Error("current-source snapshot bytes do not match manifest")
        source_by_path[path] = (row, raw)

    symbols = catalogue.get("symbols")
    if not isinstance(symbols, list):
        raise MappingV2Error("F1 catalogue symbol list malformed")
    symbol_matches: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for symbol in symbols:
        if isinstance(symbol, dict):
            symbol_matches.setdefault((symbol.get("path"), symbol.get("usr")), []).append(symbol)

    base_rows = {row.get("rowKey"): row for row in base["rows"]}
    if len(base_rows) != 107:
        raise MappingV2Error("v1 row keys are missing or duplicated")
    bound_rows = []
    for label, expected_key in EXPECTED_ROWS.items():
        row = base_rows.get(expected_key)
        if row is None or row.get("demand") != label or row.get("disposition") != "exact-catalogue-reference-only":
            raise MappingV2Error(f"v1 direct-reference row mismatch: {label}")
        if row.get("registryBlockId") is not None:
            raise MappingV2Error("v1 row unexpectedly has registry promotion")
        usages = []
        for path, usr, source_rel, exact_line, role in USAGES[label]:
            source_path = str((ROOT / source_rel).resolve())
            source = source_by_path.get(source_path)
            if source is None:
                raise MappingV2Error("required current source is not in snapshot manifest")
            lines = source[1].decode("utf-8").splitlines()
            line_matches = [i + 1 for i, value in enumerate(lines) if value == exact_line]
            if len(line_matches) != 1:
                raise MappingV2Error(f"byte-exact usage line must occur once: {label}: {role}")
            candidates = symbol_matches.get((path, usr), [])
            if len(candidates) != 1 or candidates[0].get("status") != "inventory":
                raise MappingV2Error(f"F1 catalogue identity no longer resolves uniquely: {path}")
            source_record, raw = source
            usages.append({
                "path": path,
                "usr": usr,
                "catalogueStatus": "inventory",
                "sourcePath": source_record["sourcePath"],
                "sourceSha256": source_record["sha256"],
                "sourceBytes": source_record["bytes"],
                "line": line_matches[0],
                "exactLine": exact_line,
                "usage": role,
            })
        expected_refs = {(x[0], x[1]) for x in USAGES[label]}
        actual_refs = {(x.get("path"), x.get("usr")) for x in row.get("catalogueIdentityReferences", [])}
        if actual_refs != expected_refs:
            raise MappingV2Error("source usage selectors differ from pinned v1 catalogue references")
        bound_rows.append({
            "rowKey": expected_key,
            "demand": label,
            "status": "current-source-usage-confirmed",
            "journeyIds": row.get("journeyIds"),
            "sourceEvidenceIds": row.get("inventoryEvidenceIds"),
            "v1EvidenceFreshness": row.get("inventoryEvidenceFreshness"),
            "v1ReferencesPreserved": row.get("catalogueIdentityReferences"),
            "historicalAnchorDrift": {
                "evidenceId": "slice-model",
                "line": 117,
                "recordedText": "private func persist() {",
                "capturedExactText": "    private func persist() {",
                "recordedSha256MatchesCapturedBytes": True,
                "exactAnchorMatches": False,
                "normalizationApplied": False,
            },
            "currentUsageReferences": usages,
            "registryBlockIds": [],
        })

    if {r["rowKey"] for r in bound_rows} != set(EXPECTED_ROWS.values()):
        raise MappingV2Error("direct-source evidence row coverage changed")
    return {
        "kind": "f12-extended-demand-current-source-bindings",
        "version": 2,
        "status": "source-bound-candidate-no-registry-promotion",
        "baseCandidateSha256": _sha(base_bytes),
        "catalogueSha256": _sha(catalogue_bytes),
        "sourceSnapshotManifestSha256": _sha(manifest_bytes),
        "denominator": {"extendedDemandRows": 107, "sourceBoundDirectReferenceRows": len(bound_rows), "registryMappedRows": 0},
        "rows": bound_rows,
        "preservation": {"allOtherV1RowsUnchanged": True, "v1CandidateIsImmutableInput": True},
    }


def load_inputs() -> tuple[bytes, bytes, bytes, dict[str, bytes]]:
    base = (ROOT / BASE_CANDIDATE_PATH).read_bytes()
    catalogue = (ROOT / CATALOGUE_PATH).read_bytes()
    manifest_path = Path(__file__).resolve().parent / "evidence/source-snapshot-manifest.json"
    manifest = manifest_path.read_bytes()
    parsed = _json(manifest, "snapshot manifest")
    snapshots = {row["snapshotPath"]: (Path(__file__).resolve().parent / row["snapshotPath"]).read_bytes() for row in parsed["sources"]}
    return base, catalogue, manifest, snapshots
