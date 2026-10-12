#!/usr/bin/env python3
"""Bounded local materializer for archived Mac raw evidence.

It copies explicit raw bytes into fresh namespace, binds explicit build-mac receipt,
& records missing incremental proof without inventing it. It never launches work.
"""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, tempfile
from pathlib import Path

DEFAULT_FILE_CAP = 64 * 1024 * 1024
DEFAULT_TOTAL_CAP = 128 * 1024 * 1024
JSON_CAP = 2 * 1024 * 1024

def fail(msg: str) -> None:
    raise SystemExit(msg)

def regular(path: Path, cap: int) -> Path:
    if not path.is_file() or path.is_symlink():
        fail(f"input must be regular non-symlink file: {path}")
    if path.stat().st_size > cap:
        fail(f"input exceeds bound: {path}")
    return path

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def copy_fresh(src: Path, dst: Path, cap: int, total: list[int], total_cap: int) -> dict:
    src = regular(src, cap)
    n = src.stat().st_size
    if total[0] + n > total_cap:
        fail("raw archive exceeds total bound")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        fail(f"fresh output exists: {dst}")
    tmp = dst.with_name(f".{dst.name}.{os.getpid()}.tmp")
    h = hashlib.sha256()
    try:
        with src.open("rb") as inf, tmp.open("xb") as outf:
            while chunk := inf.read(1024 * 1024):
                h.update(chunk)
                outf.write(chunk)
            outf.flush()
            os.fsync(outf.fileno())
        os.replace(tmp, dst)
    finally:
        if tmp.exists():
            tmp.unlink()
    total[0] += n
    return {"source": str(src), "path": str(dst), "bytes": n, "sha256": h.hexdigest()}

def read_json(path: Path) -> dict:
    path = regular(path, JSON_CAP)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON input {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"JSON input must be object: {path}")
    return value

def write_json_fresh(path: Path, value: dict) -> None:
    if path.exists() or path.is_symlink():
        fail(f"fresh output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        with tmp.open("rb") as f:
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-root", required=True)
    ap.add_argument("--build-path", required=True)
    ap.add_argument("--output-root", required=True)
    ap.add_argument("--receipt", required=True)
    ap.add_argument("--incremental-path")
    ap.add_argument("--max-file-bytes", type=int, default=DEFAULT_FILE_CAP)
    ap.add_argument("--max-total-bytes", type=int, default=DEFAULT_TOTAL_CAP)
    ns = ap.parse_args()
    raw = Path(ns.raw_root).resolve()
    build_path = Path(ns.build_path).resolve()
    out = Path(ns.output_root).resolve()
    receipt_path = Path(ns.receipt).resolve()
    if not raw.is_dir() or raw.is_symlink():
        fail(f"raw root must be directory: {raw}")
    if out.exists():
        fail(f"output root must be fresh: {out}")
    if not (0 < ns.max_file_bytes <= DEFAULT_FILE_CAP):
        fail("file bound must be positive & <=64MiB")
    if not (0 < ns.max_total_bytes <= DEFAULT_TOTAL_CAP):
        fail("total bound must be positive & <=128MiB")
    out.mkdir(parents=True)
    total = [0]
    files = []
    for src in sorted(raw.rglob("*")):
        if src.is_symlink():
            fail(f"raw archive symlink rejected: {src}")
        if src.is_file():
            rel = src.relative_to(raw)
            files.append(copy_fresh(src, out / rel, ns.max_file_bytes, total, ns.max_total_bytes))
    if not files:
        fail("raw archive has no files")
    build = read_json(build_path)
    if build.get("configuration") != "release":
        fail("build-mac receipt is not release")
    build_out = dict(build)
    build_out.update({
        "source": "explicit-build-mac-receipt",
        "sourcePath": str(build_path),
        "sourceSha256": digest(build_path),
        "adapterDerived": True,
    })
    write_json_fresh(out / "build-mac.json", build_out)
    inc = None
    holds = []
    if ns.incremental_path:
        inc_path = Path(ns.incremental_path).resolve()
        inc = read_json(inc_path)
        inc_out = out / "incremental.json"
        write_json_fresh(inc_out, inc)
        inc_meta = {
            "source": str(inc_path),
            "sourceSha256": digest(inc_path),
            "path": str(inc_out),
            "sha256": digest(inc_out),
            "bytes": inc_out.stat().st_size,
        }
    else:
        inc_meta = {"available": False}
        holds.append("no explicit Mac incremental receipt; W7 remains held")
    holds.append("Mac F1/F2 raw archive is preserved; no workload-analysis-v3 run layout is inferred")
    receipt = {
        "kind": "sr0-display-mac-strict-input-repair-v1",
        "status": "materialized-held",
        "qualificationHeld": True,
        "rawRoot": str(raw),
        "outputRoot": str(out),
        "rawPreserved": True,
        "parityClaim": False,
        "files": files,
        "fileCount": len(files),
        "totalRawBytes": total[0],
        "buildMac": {
            "source": str(build_path),
            "sourceSha256": digest(build_path),
            "derivedPath": str(out / "build-mac.json"),
            "derivedSha256": digest(out / "build-mac.json"),
        },
        "incremental": inc_meta,
        "holds": holds,
        "analysisReady": False,
    }
    write_json_fresh(receipt_path, receipt)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

