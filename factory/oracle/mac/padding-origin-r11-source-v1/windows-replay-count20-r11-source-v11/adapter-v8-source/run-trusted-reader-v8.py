#!/usr/bin/env python3
"""Verify fresh Windows20 proof bytes through production ArchiveByteReader."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path
from factory.core.artifacts import canonical_hash
from factory.gate.windows_exit_admission import verify_windows_exit_admission
from factory.pipeline.archive_reader import ArchiveByteReader

def bounded(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > 16 * 1024 * 1024: raise ValueError("bounded JSON required")
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict): raise ValueError("JSON object required")
    return value

def digest(raw: bytes) -> str: return "sha256:" + hashlib.sha256(raw).hexdigest()

def validate_plan(bundle: dict, plan: dict) -> None:
    if bundle.get("status") != "proofs-attached" or plan.get("count") != 20 or len(bundle.get("captures", [])) != 20: raise ValueError("fresh Count20 proof bundle required")
    expected = plan["tuple"]; cr = re.compile(plan["captureIdentity"]["capturePattern"]); ir = re.compile(plan["captureIdentity"]["imagePattern"]); ids = set(); images = set()
    for row in bundle["captures"]:
        cid, iid = row.get("id"), (row.get("images") or [{}])[0].get("id")
        if not isinstance(cid, str) or not cr.fullmatch(cid) or cid in ids: raise ValueError("fresh capture ID provenance mismatch")
        if not isinstance(iid, str) or not ir.fullmatch(iid) or iid in images: raise ValueError("fresh image ID provenance mismatch")
        ids.add(cid); images.add(iid); provenance = row.get("provenance") or {}
        if provenance.get("sourceHash") != expected["sourceHash"]: raise ValueError("fresh source provenance mismatch")
        proof = row.get("meta", {}).get("conditions", {}).get("windowsExitProof")
        if not isinstance(proof, dict) or not isinstance(proof.get("files"), dict) or len(proof["files"]) < 13: raise ValueError("all Windows proof roles required")

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--proof-bundle", required=True, type=Path); ap.add_argument("--plan", required=True, type=Path); ap.add_argument("--archive-root", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists(): raise SystemExit("HOLD: refusing to overwrite output")
    bundle, plan = bounded(args.proof_bundle), bounded(args.plan); validate_plan(bundle, plan); bindings = bundle.get("archiveBindings", {}); maps = {}; rows = []
    for ordinal, capture in enumerate(bundle["captures"], 1):
        source_rows = bindings.get(str(ordinal));
        if not isinstance(source_rows, dict) or not source_rows: raise ValueError("archive bindings missing:" + str(ordinal))
        key = canonical_hash(capture).removeprefix("sha256:"); dest = args.archive_root / ("capture-" + key); dest.mkdir(parents=True, exist_ok=True)
        for rel, entry in source_rows.items():
            src = Path(entry["sourcePath"]).resolve(strict=True); st = src.stat()
            if src.is_symlink() or not src.is_file(): raise ValueError("source binding must be regular file:" + rel)
            digestor = hashlib.sha256(); size = 0
            with src.open("rb") as handle:
                while chunk := handle.read(1024 * 1024): digestor.update(chunk); size += len(chunk)
            if "sha256:" + digestor.hexdigest() != entry.get("sha256") or size != entry.get("bytes"): raise ValueError("source binding drift:" + rel)
            target = dest / rel; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(src.read_bytes())
        maps[key] = dest; reader = ArchiveByteReader(windows_archives=maps); rows.append(verify_windows_exit_admission(capture, read_bytes=lambda path, c=capture: reader(capture=c, reference=path)))
    if not all(row.get("status") == "pass" for row in rows): raise ValueError("production reader rejected proof bundle")
    out = {"schema": "windows-exit-proof-trusted-reader-count20-v8", "status": "reader-verified", "count": 20, "rows": rows, "nativeActions": 0, "lockActions": 0, "qualification": "windows-origin-proof-reader-verified; parity/golden/freeze-held"}
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8"); print(json.dumps({"status": out["status"], "count": 20, "passed": len(rows), "nativeActions": 0, "lockActions": 0})); return 0

if __name__ == "__main__": raise SystemExit(main())
