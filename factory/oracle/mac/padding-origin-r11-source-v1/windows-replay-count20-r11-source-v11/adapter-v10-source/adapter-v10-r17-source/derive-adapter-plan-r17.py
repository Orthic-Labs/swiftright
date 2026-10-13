#!/usr/bin/env python3
"""Derive fresh adapter plan from measured r17 issued metadata bytes."""
from __future__ import annotations
import argparse, copy, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "adapter-v9-source"))
from bounded_io_v9 import bounded_json, beneath, output_path, stream_hash  # noqa: E402

RUN_RE = re.compile(r"^[0-9a-f]{32}$")
CAPTURE_RE = re.compile(r"^capture/[0-9a-f]{32}$")
IMAGE_RE = re.compile(r"^image/[0-9a-f]{32}$")


def rel_path(repo: Path, value: Path) -> str:
    if value.is_absolute() or ":" in value.as_posix() or "\\" in value.as_posix():
        raise ValueError("path must be repository-relative")
    beneath(repo, value.as_posix())
    return value.as_posix()


def derive(args) -> dict:
    repo = args.repo.absolute()
    base_rel = rel_path(repo, args.base_plan)
    issued_rel = rel_path(repo, args.issued_metadata)
    base = bounded_json(beneath(repo, base_rel))
    issued_path = beneath(repo, issued_rel)
    issued = bounded_json(issued_path)
    issued_sha, issued_bytes = stream_hash(issued_path, max_bytes=2 * 1024 * 1024)
    if base.get("kind") != "factory-fresh-r11-count20-adapter-plan-v1" or base.get("count") != 20:
        raise ValueError("Count20 base adapter plan required")
    tuple_doc = base.get("tuple")
    if not isinstance(tuple_doc, dict) or issued.get("sourceHash") != tuple_doc.get("sourceHash"):
        raise ValueError("issued source hash does not match base tuple")
    if issued.get("expectedCount") != 20 or issued.get("frozenTupleBound") is not False:
        raise ValueError("issued Count20 boundary mismatch")
    run_id = issued.get("runID")
    if not isinstance(run_id, str) or not RUN_RE.fullmatch(run_id):
        raise ValueError("issued runID malformed")
    if issued.get("case", {}).get("id") != tuple_doc.get("caseID") or issued.get("case", {}).get("hash") != tuple_doc.get("caseHash"):
        raise ValueError("issued case identity mismatch")
    captures = issued.get("captures")
    if not isinstance(captures, list) or len(captures) != 20:
        raise ValueError("issued capture cardinality mismatch")
    capture_ids, image_ids = set(), set()
    for row in captures:
        capture_id, image_id = row.get("captureID"), row.get("imageID")
        if not isinstance(capture_id, str) or not CAPTURE_RE.fullmatch(capture_id) or capture_id in capture_ids:
            raise ValueError("issued capture provenance mismatch")
        if not isinstance(image_id, str) or not IMAGE_RE.fullmatch(image_id) or image_id in image_ids:
            raise ValueError("issued image provenance mismatch")
        if (row.get("provenance") or {}).get("sourceHash") != tuple_doc.get("sourceHash"):
            raise ValueError("issued capture source provenance mismatch")
        capture_ids.add(capture_id)
        image_ids.add(image_id)
    output = copy.deepcopy(base)
    output["kind"] = "factory-fresh-r11-count20-adapter-plan-r17"
    output["version"] = "r17"
    output["status"] = "issued-source-bound-native-pending"
    output["issuedLineage"] = {"runID": run_id, "issuedMetadataSha256": issued_sha}
    output["issuedMetadataRef"] = {"path": issued_rel, "sha256": issued_sha, "bytes": issued_bytes}
    output["captureIdentity"]["issuedRunID"] = run_id
    output["captureIdentity"]["issuedCaptureIDs"] = sorted(capture_ids)
    output["captureIdentity"]["issuedImageIDs"] = sorted(image_ids)
    output["qualification"] = "hold-until-r17-task-memory-proof-and-trusted-reader"
    return output


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-plan", required=True, type=Path)
    ap.add_argument("--issued-metadata", required=True, type=Path)
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    try:
        output = derive(args)
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": output["status"], "runID": output["issuedLineage"]["runID"], "issuedMetadataSha256": output["issuedLineage"]["issuedMetadataSha256"], "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
