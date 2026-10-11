#!/usr/bin/env python3
"""Verify fresh Windows20 proof bytes through production ArchiveByteReader."""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "adapter-v9-source"))
REPO = next((parent for parent in HERE.parents if (parent / "factory").is_dir()), None)
if REPO is None:
    raise SystemExit("HOLD: repository root unavailable")
sys.path.insert(0, str(REPO))
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
    ordered_pairs = None
    # Plan's sorted convenience arrays are not row provenance.  Caller must
    # supply ordered issued pairs through v12 input map; reader joins by run.
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
        if not isinstance(proof, dict) or proof.get("version") != 1 or not isinstance(proof.get("files"), dict) or set(proof["files"]) != {"outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr"}:
            raise ValueError("all 13 Windows proof roles required")
        if (proof.get("activeProcessCount") != 1 or proof.get("activeCountQualification") != "self-only-after-child-terminal"
                or proof.get("liveChildCount") != 0 or proof.get("externalTaskTerminal") is not True
                or proof.get("wholeBatchExitConfirmed") is not True or proof.get("lockReleased") is not True):
            raise ValueError("self-only active-process proof missing for capture")
    if len(ids) != 20 or len(images) != 20:
        raise ValueError("fresh capture/image IDs must be distinct")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proof-bundle", required=True, type=Path)
    ap.add_argument("--input-map", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--input-archive-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    bundle, plan, input_map = bounded_json(args.proof_bundle), bounded_json(args.plan), bounded_json(args.input_map)
    lineage = input_map.get("lineage") or {}
    if not isinstance(lineage.get("runID"), str) or not isinstance(lineage.get("issuedPairs"), list) or len(lineage["issuedPairs"]) != 20:
        raise ValueError("v12 ordered issued lineage required")
    validate_plan(bundle, plan)
    if bundle.get("schema") == "factory-native-count20-r17-adapter-proof-v12" and bundle.get("readyForTrustedReader") is not True:
        raise ValueError("self-only active-process cleanup admission required before trusted reader")
    admission = bundle.get("cleanupAdmission") or {}
    if (admission.get("activeProcessCount") != 1 or admission.get("selfOnlyAccepted") is not True or admission.get("liveChildRejected") is not True
            or admission.get("externalTaskTerminal") is not True or admission.get("wholeBatchExitConfirmed") is not True
            or admission.get("lockReleased") is not True or admission.get("cleanupErrors") != []):
        raise ValueError("self-only active-process cleanup admission is incomplete")
    bindings = bundle.get("archiveBindings", {})
    if not isinstance(bindings, dict) or len(bindings) != 20:
        raise ValueError("exact 20 archive binding rows required")
    if args.archive_root.exists() or args.archive_root.is_symlink():
        raise ValueError("archive root must be fresh")
    args.archive_root.parent.mkdir(parents=True, exist_ok=True)
    args.archive_root.mkdir()
    maps, rows = {}, []
    total_bytes = 0
    blob_root = args.archive_root / "_blobs"
    blob_root.mkdir()
    for ordinal, capture in enumerate(bundle["captures"], 1):
        pair = lineage["issuedPairs"][ordinal - 1]
        if capture.get("id") != pair.get("captureID") or (capture.get("images") or [{}])[0].get("id") != pair.get("imageID"):
            raise ValueError("measured capture/image pair order mismatch")
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
            blob_name = entry["sha256"].removeprefix("sha256:")
            if not re.fullmatch(r"[0-9a-f]{64}", blob_name):
                raise ValueError("source binding hash invalid:" + rel)
            blob = blob_root / blob_name
            if blob.exists() or blob.is_symlink():
                if blob.is_symlink():
                    raise ValueError("dedupe blob must not be symlinked:" + blob_name)
                verify_ref(blob, {"bytes": size, "sha256": entry["sha256"]}, max_bytes=ARCHIVE_FILE_LIMIT)
            else:
                if total_bytes + size > ARCHIVE_TOTAL_LIMIT:
                    raise ValueError("unique archive bytes exceed bounded total limit")
                stream_copy_verified(src, blob, expected_bytes=size, expected_sha256=entry["sha256"], max_bytes=ARCHIVE_FILE_LIMIT)
                total_bytes += size
            target = beneath(dest, rel)
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() or target.is_symlink():
                raise ValueError("capture archive destination must be fresh:" + rel)
            try:
                os.link(blob, target)
            except OSError as exc:
                raise ValueError("dedupe hardlink unavailable; refusing duplicate archive copy:" + rel) from exc
            if actual != entry["sha256"]:
                raise ValueError("source binding hash drift:" + rel)
        maps[key] = dest
        reader = ArchiveByteReader(windows_archives=maps)
        rows.append(verify_windows_exit_admission(capture, read_bytes=lambda path, c=capture: reader(capture=c, reference=path)))
    all_pass = all(row.get("status") == "pass" for row in rows)
    reader_status = "reader-verified" if all_pass else "reader-observed-rejections"
    qualification = ("windows-origin-proof-reader-verified; parity/golden/freeze-held"
                     if all_pass else "windows-origin-proof-reader-observed-rejections; protected admission held")
    out = {"schema": "windows-exit-proof-trusted-reader-count20-v12", "status": reader_status, "count": 20, "rows": rows, "issuedLineage": {"runID": lineage["runID"], "issuedMetadataSha256": lineage.get("issuedMetadataSha256"), "orderedPairs": lineage["issuedPairs"]}, "memoryReceipt": input_map.get("lineage", {}).get("memoryReceipt"), "nativeActions": 0, "lockActions": 0, "qualification": qualification}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": out["status"], "count": 20, "passed": sum(row.get("status") == "pass" for row in rows), "blocked": sum(row.get("status") != "pass" for row in rows), "runID": lineage["runID"], "nativeActions": 0, "lockActions": 0}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
