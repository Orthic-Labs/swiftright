#!/usr/bin/env python3
"""Pair fresh Mac20 & reader-verified Windows20 through production comparator."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from factory.comparison.comparator import ComparisonError, compare_case
from bounded_io_v9 import ARCHIVE_FILE_LIMIT, bounded_json, output_path, verify_ref

FRESH_TUPLE_ID = "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011"
FRESH_CASE_ID = "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9"
FRESH_SOURCE_HASH = "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b"
FRESH_MAC_HOST = "sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777"
FRESH_WINDOWS_HOST = "sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a"


def require_fresh_plan(plan: dict) -> dict:
    if plan.get("count") != 20 or plan.get("status") != "pending-windows-native-archive":
        raise ValueError("fresh Count20 plan required")
    tuple_doc = plan.get("tuple")
    expected = {"id": FRESH_TUPLE_ID, "caseID": FRESH_CASE_ID, "sourceHash": FRESH_SOURCE_HASH, "macHostHash": FRESH_MAC_HOST, "windowsHostHash": FRESH_WINDOWS_HOST}
    if not isinstance(tuple_doc, dict) or any(tuple_doc.get(key) != value for key, value in expected.items()):
        raise ValueError("fresh tuple/source/host binding mismatch")
    if tuple_doc.get("caseHash") != "sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de":
        raise ValueError("fresh case hash binding mismatch")
    identity = plan.get("captureIdentity")
    if not isinstance(identity, dict) or identity.get("expectedCount") != 20 or identity.get("producer") != "factory-prelaunch-capture-metadata-v2":
        raise ValueError("fresh capture identity contract missing")
    return tuple_doc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--mac-refs", required=True, type=Path)
    ap.add_argument("--mac-report", required=True, type=Path)
    ap.add_argument("--windows-captures", required=True, type=Path)
    ap.add_argument("--reader-report", required=True, type=Path)
    ap.add_argument("--case", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    plan = bounded_json(args.plan)
    refs = bounded_json(args.mac_refs)
    mac_report = bounded_json(args.mac_report)
    windows = bounded_json(args.windows_captures)
    reader = bounded_json(args.reader_report)
    case = bounded_json(args.case)
    expected = require_fresh_plan(plan)
    if reader.get("status") != "reader-verified" or reader.get("count") != 20:
        raise ValueError("fresh reader/count20 admission required")
    if mac_report.get("status") in {"qualified", "parity-passed", "golden-frozen"}:
        raise ValueError("Mac report must remain observation-only")
    rows = refs.get("macCaptures")
    if not isinstance(rows, list) or len(rows) != 20:
        raise ValueError("fresh Mac20 refs required")
    mac = []
    for ordinal, row in enumerate(rows, 1):
        if not isinstance(row, dict) or not isinstance(row.get("path"), str) or not Path(row["path"]).is_absolute():
            raise ValueError(f"Mac ref path invalid:{ordinal}")
        path = Path(row["path"])
        verify_ref(path, row, max_bytes=ARCHIVE_FILE_LIMIT)
        value = bounded_json(path)
        if value.get("meta", {}).get("run") != ordinal:
            raise ValueError(f"Mac run order mismatch:{ordinal}")
        mac.append(value)
    win = windows.get("captures")
    if not isinstance(win, list) or len(win) != 20:
        raise ValueError("fresh Windows20 captures required")
    cr = re.compile(plan["captureIdentity"]["capturePattern"])
    ir = re.compile(plan["captureIdentity"]["imagePattern"])
    capture_ids, image_ids = set(), set()
    for value in win:
        cid = value.get("id")
        iid = (value.get("images") or [{}])[0].get("id")
        if not cr.fullmatch(str(cid)) or cid in capture_ids:
            raise ValueError("Windows capture provenance ID mismatch")
        if not ir.fullmatch(str(iid)) or iid in image_ids:
            raise ValueError("Windows image provenance ID mismatch")
        capture_ids.add(cid)
        image_ids.add(iid)
        if value.get("case", {}).get("id") != expected["caseID"] or value.get("case", {}).get("hash") != expected["caseHash"]:
            raise ValueError("Windows case join mismatch")
        if (value.get("provenance") or {}).get("sourceHash") != expected["sourceHash"]:
            raise ValueError("Windows source join mismatch")
    if len(capture_ids) != 20 or len(image_ids) != 20:
        raise ValueError("fresh capture/image IDs must be distinct")
    if not isinstance(case, dict) or case.get("id") not in (None, expected["caseID"]):
        raise ValueError("fresh comparator case mismatch")
    try:
        comparison = compare_case(case, mac + win, acceptance_config={}, holds=["fresh paired parity/golden/freeze held"])
        comparison_failed = False
    except ComparisonError as exc:
        comparison = {"status": "blocked", "reason": "canonical tuple/case admission rejected", "error": str(exc), "parity": "held", "goldens": 0, "promotion": "held"}
        comparison_failed = True
    status = "paired-comparison-blocked" if comparison_failed else "paired-comparison-observed"
    out = {
        "schema": "paired-padding-f10-comparison-diagnostic-v9",
        "status": status,
        "candidateOnly": True,
        "freshTupleID": expected["id"],
        "freshCaseID": expected["caseID"],
        "reader": {"macRuns": 20, "windowsReaderVerified": 20},
        "comparisonAdmission": {"status": "blocked" if comparison_failed else "observed", "error": comparison.get("error", "")},
        "comparison": comparison,
        "parity": {"status": "held", "goldens": 0, "promotion": "held"},
        "effects": {"nativeWindowActions": 0, "compilerActions": 0, "remoteActions": 0, "lockActions": 0, "sourceMutations": 0},
    }
    output_path(args.output)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": status, "macRuns": 20, "windowsReaderVerified": 20, "nativeParity": "held"}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
