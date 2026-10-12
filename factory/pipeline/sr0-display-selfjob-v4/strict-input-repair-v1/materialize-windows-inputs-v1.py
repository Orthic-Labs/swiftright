#!/usr/bin/env python3
"""Bounded local materializer for archived Windows SR0 strict inputs.

No process/native/compiler work. Raw rows stay byte-identical; derived files only
supply analyzer namespace inputs absent from exported Windows archive.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re
from pathlib import Path

FILE_CAPS = {
    "result-workload.txt": 2 * 1024 * 1024,
    "presentmon.csv": 64 * 1024 * 1024,
    "presentmon.stdout.txt": 8 * 1024 * 1024,
    "presentmon.stderr.txt": 8 * 1024 * 1024,
}
TRACE_NAMES = (
    "meta.json", "integrity.json", "inputs.csv", "frames.csv",
    "bridge_input.csv", "ticks.csv", "mainactor.csv", "inject.csv",
    "overhead_probe.csv",
)
TRACE_CAP = 32 * 1024 * 1024
JSON_CAP = 2 * 1024 * 1024
TOTAL_CAP = 128 * 1024 * 1024

def fail(message: str) -> None:
    raise SystemExit(message)

def regular(path: Path, cap: int) -> Path:
    if not path.is_file() or path.is_symlink():
        fail(f"input must be regular non-symlink file: {path}")
    if path.stat().st_size > cap:
        fail(f"input exceeds bound: {path}")
    return path

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def read_json(path: Path) -> dict:
    path = regular(path, JSON_CAP)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON input {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"JSON input must be object: {path}")
    return value

def fresh_bytes(path: Path, data: bytes) -> None:
    if path.exists() or path.is_symlink():
        fail(f"fresh output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with temp.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()

def fresh_json(path: Path, value: dict) -> None:
    fresh_bytes(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())

def copy_fresh(src: Path, dst: Path, cap: int, total: list[int]) -> dict:
    src = regular(src, cap)
    size = src.stat().st_size
    if total[0] + size > TOTAL_CAP:
        fail("derived namespace exceeds 128MiB total")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        fail(f"fresh output exists: {dst}")
    temp = dst.with_name(f".{dst.name}.{os.getpid()}.tmp")
    digest = hashlib.sha256()
    try:
        with src.open("rb") as inp, temp.open("xb") as out:
            while chunk := inp.read(1024 * 1024):
                digest.update(chunk)
                out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temp, dst)
    finally:
        if temp.exists():
            temp.unlink()
    total[0] += size
    return {"source": str(src), "path": str(dst), "bytes": size, "sha256": digest.hexdigest()}

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw-root", required=True)
    ap.add_argument("--build-path", required=True)
    ap.add_argument("--incremental-path", required=True)
    ap.add_argument("--output-root", required=True)
    ap.add_argument("--receipt", required=True)
    ns = ap.parse_args()
    supplied_raw = Path(ns.raw_root)
    supplied_build = Path(ns.build_path)
    supplied_inc = Path(ns.incremental_path)
    supplied_out = Path(ns.output_root)
    supplied_receipt = Path(ns.receipt)
    if any(path.is_symlink() for path in (supplied_raw, supplied_build, supplied_inc, supplied_out, supplied_receipt)):
        fail("raw, input, & output paths must not be symlinks")
    raw = supplied_raw.resolve()
    build_path = supplied_build.resolve()
    inc_path = supplied_inc.resolve()
    out = supplied_out.resolve()
    receipt_path = supplied_receipt.resolve()
    if not raw.is_dir():
        fail(f"raw root must be directory: {raw}")
    if out.exists():
        fail(f"output root must be fresh: {out}")
    out.mkdir(parents=True)
    total = [0]
    files = {}
    for name, cap in FILE_CAPS.items():
        files[name] = copy_fresh(raw / name, out / name, cap, total)
    console = bytearray()
    for name in ("presentmon.stdout.txt", "presentmon.stderr.txt"):
        # Re-apply per-stream bound before deriving console namespace; avoid an
        # unbounded read after the initial raw copy.
        data = regular(raw / name, FILE_CAPS[name]).read_bytes()
        console.extend(data)
        if name == "presentmon.stdout.txt" and console and not console.endswith(b"\n"):
            console.extend(b"\r\n")
    console_path = out / "presentmon.console.txt"
    fresh_bytes(console_path, bytes(console))
    files["presentmon.console.txt"] = {
        "source": [str(raw / "presentmon.stdout.txt"), str(raw / "presentmon.stderr.txt")],
        "path": str(console_path),
        "bytes": console_path.stat().st_size,
        "sha256": sha256(console_path),
    }
    build = read_json(build_path)
    inc = read_json(inc_path)
    exe_sha = str(build.get("exe_sha256") or build.get("exeSha256") or "").lower()
    dll_sha = str(build.get("dll_sha256") or build.get("dllSha256") or "").lower()
    manifest_sha = str(build.get("sourceManifestSha256") or "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", exe_sha) or not re.fullmatch(r"[0-9a-f]{64}", dll_sha):
        fail("build artifact hashes missing")
    if not re.fullmatch(r"[0-9a-f]{64}", manifest_sha):
        fail("build source manifest hash missing")
    if str(inc.get("source_manifest_sha256", "")).lower() != manifest_sha:
        fail("incremental/source manifest mismatch")
    source_file_sha = str(inc.get("source_file_sha256", "")).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", source_file_sha):
        fail("incremental source hash missing")
    identity = regular(raw / "result-workload.txt", FILE_CAPS["result-workload.txt"]).read_text(
        encoding="utf-8", errors="strict"
    )
    match = re.search(r"(?m)^exe=.*?exe_sha256=([0-9a-fA-F]{64})\s.*?dll_sha256=([0-9a-fA-F]{64})\s", identity)
    if not match or match.group(1).lower() != exe_sha or match.group(2).lower() != dll_sha:
        fail("build artifact identity differs from captured workload")
    derived_build = dict(build)
    derived_build.update({
        "configuration": "release",
        "exe_sha256": exe_sha,
        "dll_sha256": dll_sha,
        "sourceManifestSha256": manifest_sha,
        "source": "explicit-build-receipt",
        "sourcePath": str(build_path),
        "sourceSha256": sha256(build_path),
        "adapterDerived": True,
    })
    build_out = out / "build.json"
    fresh_json(build_out, derived_build)
    inc_out = out / "incremental.json"
    inc_meta = copy_fresh(inc_path, inc_out, JSON_CAP, total)
    for name in TRACE_NAMES:
        files[f"r1/{name}"] = copy_fresh(raw / "r1" / name, out / "r1" / name, TRACE_CAP, total)
    pid_exit = re.findall(r"(?m)^pid_exit run=\S+ pid=\d+ handle=[1-9]\d+ .* exit=-?\d+", identity)
    if not pid_exit:
        fail("raw result has no retained-handle pid_exit record")
    receipt = {
        "kind": "sr0-display-strict-input-repair-windows-python-v1",
        "status": "materialized-held",
        "qualificationHeld": True,
        "qualificationHoldReason": "strict display/capture metrics remain frozen",
        "rawRoot": str(raw),
        "outputRoot": str(out),
        "rawPreserved": True,
        "parityClaim": False,
        "optionalHandleTailPreserved": True,
        "pidExitRecords": len(pid_exit),
        "buildInput": str(build_path),
        "buildInputSha256": sha256(build_path),
        "incrementalInput": str(inc_path),
        "incrementalInputSha256": sha256(inc_path),
        "sourceManifestSha256": manifest_sha,
        "sourceFileSha256": source_file_sha,
        "derivedBuildSha256": sha256(build_out),
        "files": files,
        "incrementalOutput": inc_meta,
        "totalDerivedBytes": total[0],
        "displayQualification": "held",
        "holds": [
            "derived console/build/incremental inputs only; raw evidence unchanged",
            "strict report display/capture/timing failures remain applicable",
        ],
    }
    fresh_json(receipt_path, receipt)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

