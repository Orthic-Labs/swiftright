"""Build additive F12 v5 source-bound evidence from frozen v4 rows.

This packet records exact current Tauri/React/Rust source anchors.  It never
creates an SDK registry link or changes any v4 resolution.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
V4 = ROOT / "factory/shell/extended-demand-mapping-v4/mapping-v4.json"
SOURCE_MANIFEST = HERE / "evidence/source-snapshot-manifest.json"

UNMAPPED = [
    "007", "008", "010", "011", "013", "014", "015", "016", "017", "019",
    "024", "026", "027", "029", "030", "031", "032", "034", "036", "039",
    "040", "044", "046", "050", "052", "053", "056", "057", "059",
]
AMBIGUOUS = ["001", "002", "045"]
RESIDUAL = {f"f12-extended-{n}" for n in UNMAPPED + AMBIGUOUS}

# Line ranges are intentionally narrow.  They prove source ownership/use only;
# they do not imply SwiftUI identity, native capability, or full demand closure.
ANCHORS = {
    "007": ("settings-panel", [233, 241], "search input and change handler"),
    "008": ("command-palette", [38, 60], "exit transition, outside dismiss, focus"),
    "010": ("pdf-viewer", [280, 290], "PDF canvas creation/render; wrong journey for generic image transform"),
    "011": ("palette", [69, 114], "modal dismiss, focus trap, Escape close"),
    "015": ("app-lifecycle", [41, 56], "second-instance argv path routing"),
    "016": ("logs", [58, 94], "diagnostics gate and event write"),
    "019": ("app-lifecycle", [67, 84], "open-document window restoration and route"),
    "024": ("media-player", [186, 196], "HTML media error-code classification"),
    "026": ("pdf-viewer", [402, 405], "PDF find input and actions"),
    "027": ("settings-panel", [252, 268], "settings navigation arrow focus"),
    "029": ("shortcuts", [189, 230], "keyboard event routing and listener attach"),
    "030": ("layout", [282, 296], "shell roving navigation focus"),
    "031": ("layout", [282, 296], "shell roving navigation focus"),
    "032": ("shortcuts", [146, 225], "shortcut sequence dispatch"),
    "034": ("legal-gate", [487, 543], "radio and checkbox eligibility controls"),
    "036": ("palette", [69, 114], "modal focus trap and dismissal"),
    "044": ("app-dialogs", [113, 153], "close/quit confirmation callbacks"),
    "045": ("legal-gate", [487, 543], "radio and checkbox HTML controls; candidate selection remains ambiguous"),
    "046": ("shortcuts", [263, 299], "rebind conflict detection and overrides"),
    "050": ("shortcuts", [142, 225], "sequence timeout and retry"),
    "052": ("pdf-viewer", [400, 424], "PDF outline/pages sidebar"),
    "053": ("layout", [282, 296], "navigation selection and roving focus"),
    "056": ("palette", [118, 139], "combobox text entry and keyboard selection"),
    "057": ("media-player", [728, 745], "media time range control"),
    "059": ("settings-panel", [309, 315], "settings error alert and dismiss"),
}
SECONDARY = {
    "008": ("palette", [87, 94], "post-close delayed command"),
    "011": ("command-palette", [117, 160], "dialog focus and key handling"),
    "026": ("find-bar", [67, 117], "find focus, Escape, debounce"),
    "027": ("find-bar", [67, 79], "focus reassertion"),
    "034": ("legal-gate", [535, 543], "agreement checkbox"),
    "036": ("app-dialogs", [108, 112], "dialog composition"),
    "056": ("command-palette", [142, 160], "command palette text entry"),
    "059": ("media-player", [834, 862], "media error fallback"),
}

PARTIAL_REASONS = {
    "007": "HTML input is source-bound; no exact SwiftUI declaration or control-family closure.",
    "008": "React exit/dismiss path is source-bound; animation and all interaction variants remain unclosed.",
    "010": "Observed canvas is PDF rendering; generic image-transform demand remains wrong-journey held.",
    "011": "React palette modal/focus path is source-bound; no SDK/native identity follows.",
    "015": "Tauri second-instance path routing is source-bound; deep-link grammar/host contract remains open.",
    "016": "Rust diagnostics gate/write path is source-bound; platform log contract remains open.",
    "019": "Tauri open-document restoration is source-bound; document/session persistence remains open.",
    "024": "Media error-code switch is source-bound; full cross-provider error taxonomy remains open.",
    "026": "PDF find input is source-bound; IME/composition behavior is not proven by these lines.",
    "027": "Arrow navigation/focus is source-bound; IME behavior remains unproven.",
    "029": "Shortcut registry handles keyboard events; host/native routing remains open.",
    "030": "Shell nav roving focus is source-bound; complete keyboard navigation contract remains open.",
    "031": "Shell nav roving focus is source-bound; selection/virtualization contract remains open.",
    "032": "Shortcut sequence dispatch is source-bound; transport/native shortcut semantics remain open.",
    "034": "HTML eligibility controls are source-bound; SwiftUI style/control identity remains ambiguous.",
    "036": "React modal composition is source-bound; restoration semantics remain open.",
    "044": "Close/quit callbacks are source-bound; OS quit behavior remains open.",
    "046": "Rebind/conflict implementation is source-bound; persisted/native conflict behavior remains open.",
    "050": "Sequence timeout implementation is source-bound; timing contract remains open.",
    "052": "PDF outline/pages panel is source-bound; generic sidebar demand remains open.",
    "053": "Shell nav selection/focus is source-bound; full sidebar state contract remains open.",
    "056": "Combobox text input is source-bound; IME composition semantics remain open.",
    "057": "Media range/time control is source-bound; animation/progress contract remains open.",
    "059": "Error alert/fallback paths are source-bound; validation taxonomy remains open.",
}


def load(path: Path):
    return json.loads(path.read_text())


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_rows():
    manifest = load(SOURCE_MANIFEST)
    out = {}
    for item in manifest["sources"]:
        p = HERE / "evidence" / "source-snapshots" / Path(item["snapshotPath"]).name
        data = p.read_bytes()
        if len(data) != item["bytes"] or sha256_bytes(data) != item["sha256"]:
            raise ValueError(f"source snapshot changed: {item['id']}")
        out[item["id"]] = {**item, "snapshotPath": str(p.relative_to(HERE))}
    return out


def anchor(source_id, lines, text):
    return {"sourceId": source_id, "lines": lines, "anchor": text}


def validate_packet(packet, sources):
    """Strict offline guard used by replay & fault controls."""
    if packet.get("denominator", {}).get("extendedDemandRows") != 107:
        raise ValueError("denominator drift")
    rows = packet.get("rows")
    if not isinstance(rows, list) or len(rows) != 107:
        raise ValueError("row cardinality drift")
    keys = [r.get("rowKey") for r in rows]
    if len(set(keys)) != 107 or not RESIDUAL.issubset(keys):
        raise ValueError("row identity drift")
    for row in rows:
        ev = row.get("v5Evidence")
        if not ev:
            continue
        if ev.get("registryPromotion") is not False or ev.get("fullDemandResolved") is not False:
            raise ValueError(f"promotion/full-resolution gate: {row.get('rowKey')}")
        if row["rowKey"] not in RESIDUAL:
            raise ValueError("non-residual v5 evidence")
        for item in ev.get("sourceEvidence", []):
            sid = item.get("sourceId")
            if sid not in sources:
                raise ValueError(f"unknown source: {sid}")
            lines = item.get("lines")
            if not isinstance(lines, list) or len(lines) != 2 or not all(isinstance(x, int) and x > 0 for x in lines) or lines[0] > lines[1]:
                raise ValueError("invalid source line range")
            src = sources[sid]
            if lines[1] > len((HERE / "evidence" / "source-snapshots" / Path(src["snapshotPath"]).name).read_text().splitlines()):
                raise ValueError("source line outside snapshot")
            for k in ("originalPath", "snapshotPath", "sha256", "bytes"):
                if item.get(k) != src[k]:
                    raise ValueError(f"source binding drift: {sid}:{k}")


def main():
    v4 = load(V4)
    if v4.get("denominator", {}).get("extendedDemandRows") != 107 or len(v4.get("rows", [])) != 107:
        raise ValueError("v4 denominator/row count changed")
    rows = {r["rowKey"]: r for r in v4["rows"]}
    if not RESIDUAL.issubset(rows):
        raise ValueError("residual row set missing from v4")
    sources = source_rows()
    result = copy.deepcopy(v4)
    result["version"] = "extended-demand-mapping-v5"
    result["status"] = "source-bound-observation-only"
    result["v5Evidence"] = {
        "residualRows": sorted(RESIDUAL),
        "registryPromotion": False,
        "newFullDemandResolutions": 0,
        "sourceManifestSha256": sha256_bytes(SOURCE_MANIFEST.read_bytes()),
        "v4MappingSha256": sha256_bytes(V4.read_bytes()),
    }
    for row in result["rows"]:
        key = row["rowKey"]
        if key not in RESIDUAL:
            continue
        short = key.rsplit("-", 1)[-1]
        records = []
        if short in ANCHORS:
            sid, lines, text = ANCHORS[short]
            records.append(anchor(sid, lines, text))
        if short in SECONDARY:
            sid, lines, text = SECONDARY[short]
            records.append(anchor(sid, lines, text))
        disposition = "ambiguous-source-bound-held" if short in AMBIGUOUS else ("partial-source-bound-held" if records else "unresolved-held")
        row["v5Evidence"] = {
            "disposition": disposition,
            "sourceBound": bool(records),
            "sourceEvidence": records,
            "registryPromotion": False,
            "fullDemandResolved": False,
            "reason": PARTIAL_REASONS.get(short, "No exact current source declaration or host adapter establishes this demand.") if short not in AMBIGUOUS else "Multiple catalogue candidates remain; source controls do not select one declaration.",
        }
    # Resolve source IDs to immutable manifest details after row construction.
    for row in result["rows"]:
        ev = row.get("v5Evidence")
        if not ev:
            continue
        for item in ev["sourceEvidence"]:
            source = sources[item["sourceId"]]
            item.update({"originalPath": source["originalPath"], "bytes": source["bytes"], "sha256": source["sha256"], "snapshotPath": source["snapshotPath"]})
    validate_packet(result, sources)
    out = HERE / "mapping-v5.json"
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    dispositions = {
        "kind": "v5-residual-dispositions",
        "denominator": 107,
        "residualCount": len(RESIDUAL),
        "rows": [
            {"rowKey": r["rowKey"], "demand": r["demand"], "v4Disposition": r.get("disposition", r.get("status")), "v5": r["v5Evidence"]}
            for r in result["rows"] if r["rowKey"] in RESIDUAL
        ],
        "registryMappedRows": 0,
        "newFullDemandResolutions": 0,
    }
    (HERE / "evidence" / "unresolved-dispositions-v5.json").write_text(json.dumps(dispositions, indent=2, sort_keys=True) + "\n")
    return result


if __name__ == "__main__":
    main()
