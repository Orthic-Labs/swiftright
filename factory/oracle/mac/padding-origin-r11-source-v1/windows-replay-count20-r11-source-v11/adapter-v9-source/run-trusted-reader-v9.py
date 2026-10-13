#!/usr/bin/env python3
"""Verify fresh Windows20 proof bytes through production ArchiveByteReader."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from bounded_io_v9 import ARCHIVE_FILE_LIMIT, ARCHIVE_TOTAL_LIMIT, bounded_json, beneath, output_path, regular_file, safe_relative, stream_copy_verified, verify_ref
from factory.core.artifacts import canonical_hash
from factory.gate.windows_exit_admission import verify_windows_exit_admission
from factory.pipeline.archive_reader import ArchiveByteReader

FRESH_TUPLE_ID = "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011"
FRESH_CASE_ID = "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9"
FRESH_SOURCE_HASH = "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b"


def validate_plan(bundle: dict, plan: dict) -> None:
    if bundle.get("status") != "proofs-attached" or plan.get("count") != 20 or len(bundle.get("captures", [])) != 20:
        raise ValueError("fresh Count20 proof bundle required")
    tuple_doc = plan.get("tuple")
    if not isinstance(tuple_doc, dict) or tuple_doc.get("id") != FRESH_TUPLE_ID or tuple_doc.get("caseID") != FRESH_CASE_ID or tuple_doc.get("sourceHash") != FRESH_SOURCE_HASH:
        raise ValueError("fresh tuple/case/source binding required")
    expected = tuple_doc
    cr = re.compile(plan["captureIdentity"]["capturePattern"])
    ir = re.compile(plan["captureIdentity"]["imagePattern"])
    ids, images = set(), set()
    for row in bundle["captures"]:
        cid, iid = row.get("id"), (row.get("images") or [{}])[0].get("id")
        if not isinstance(cid, str) or not cr.fullmatch(cid) or cid in ids:
            raise ValueError("fresh capture ID provenance mismatch")
        if not isinstance(iid, str) or not ir.fullmatch(iid) or iid in images:
            raise ValueError("fresh image ID provenance mismatch")
        ids.add(cid)
        images.add(iid)
        if row.get("case", {}).get("id") != expected["caseID"] or row.get("case", {}).get("hash") != expected["caseHash"]:
            raise ValueError("fresh case binding mismatch")
        if (row.get("provenance") or {}).get("sourceHash") != expected["sourceHash"]:
            raise ValueError("fresh source provenance mismatch")
        proof = row.get("meta", {}).get("conditions", {}).get("windowsExitProof")
        if not isinstance(proof, dict) or not isinstance(proof.get("files"), dict) or len(proof["files"]) != 13:
            raise ValueError("all 13 Windows proof roles required")
    if len(ids) != 20 or len(images) != 20:
        raise ValueError("fresh capture/image IDs must be distinct")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proof-bundle", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    bundle, plan = bounded_json(args.proof_bundle), bounded_json(args.plan)
    validate_plan(bundle, plan)
    bindings = bundle.get("archiveBindings", {})
    if not isinstance(bindings, dict) or len(bindings) != 20:
        raise ValueError("exact 20 archive binding rows required")
    if args.archive_root.exists() or args.archive_root.is_symlink():
        raise ValueError("archive root must be fresh")
    args.archive_root.parent.mkdir(parents=True, exist_ok=True)
    args.archive_root.mkdir()
    maps, rows = {}, []
    total_bytes = 0
    for ordinal, capture in enumerate(bundle["captures"], 1):
        source_rows = bindings.get(str(ordinal))
        if not isinstance(source_rows, dict) or not source_rows:
            raise ValueError("archive bindings missing:" + str(ordinal))
        key = canonical_hash(capture).removeprefix("sha256:")
        dest = args.archive_root / ("capture-" + key)
        safe_relative("capture-" + key)
        dest.mkdir()
        for rel, entry in source_rows.items():
            safe_relative(rel)
            if not isinstance(entry, dict) or not isinstance(entry.get("sourcePath"), str):
                raise ValueError("source binding descriptor invalid:" + rel)
            src = Path(entry["sourcePath"])
            actual, size = verify_ref(src, entry, max_bytes=ARCHIVE_FILE_LIMIT)
            total_bytes += size
            if total_bytes > ARCHIVE_TOTAL_LIMIT:
                raise ValueError("archive operation exceeds total byte limit")
            target = beneath(dest, rel)
            stream_copy_verified(src, target, expected_bytes=size, expected_sha256=entry["sha256"], max_bytes=ARCHIVE_FILE_LIMIT)
            if actual != entry["sha256"]:
                raise ValueError("source binding hash drift:" + rel)
        maps[key] = dest
        reader = ArchiveByteReader(windows_archives=maps)
        rows.append(verify_windows_exit_admission(capture, read_bytes=lambda path, c=capture: reader(capture=c, reference=path)))
    if not all(row.get("status") == "pass" for row in rows):
        raise ValueError("production reader rejected proof bundle")
    out = {"schema": "windows-exit-proof-trusted-reader-count20-v9", "status": "reader-verified", "count": 20, "rows": rows, "nativeActions": 0, "lockActions": 0, "qualification": "windows-origin-proof-reader-verified; parity/golden/freeze-held"}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": out["status"], "count": 20, "passed": len(rows), "nativeActions": 0, "lockActions": 0}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
