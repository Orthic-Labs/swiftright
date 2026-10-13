#!/usr/bin/env python3
"""Bounded Mac-side materializer for one sealed Windows r13 run.

Only paths named by export-manifest.json are admitted.  It copies bytes through
streaming handles, derives PresentMon console bytes by exact stdout+stderr
concatenation, & derives release build.json from genuine build inputs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
import tempfile
from pathlib import Path


MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 32 * 1024 * 1024
MAX_JSON = 2 * 1024 * 1024
BUF = 64 * 1024
PARSER_SHA = "35330066332c30e96d5e3a6232a0188889760ad73b7d4c04f1d9fb9f178b535a"
EXE_SHA = "7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c"
DLL_SHA = "7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2"
SOURCE_MANIFEST_SHA = "26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468"
BUILD_RECEIPT_SHA = "14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579"


class Hold(RuntimeError):
    pass


def fail(message: str) -> None:
    raise Hold(message)


def full_hash(path: Path, limit: int | None = None) -> tuple[int, str]:
    st = safe_leaf(path, limit)
    total = 0
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            block = source.read(BUF)
            if not block:
                break
            total += len(block)
            if limit is not None and total > limit:
                fail(f"file exceeds bound: {path}")
            digest.update(block)
    if total != st.st_size:
        fail(f"file changed during read: {path}")
    return total, digest.hexdigest()


def safe_leaf(path: Path, limit: int | None = None) -> os.stat_result:
    """Reject symlink leaves & every symlink parent before any read."""
    path = path.absolute()
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        try:
            st = os.lstat(current)
        except FileNotFoundError:
            fail(f"missing input: {path}")
        if stat.S_ISLNK(st.st_mode):
            fail(f"symlink input rejected: {path}")
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode):
        fail(f"regular file required: {path}")
    if limit is not None and st.st_size > limit:
        fail(f"file exceeds bound: {path}")
    return st


def read_json(path: Path, limit: int = MAX_JSON):
    size, _ = full_hash(path, limit)
    if size > limit:
        fail(f"JSON exceeds bound: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON {path}: {exc}")


def relative_manifest_path(value: object) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        fail("manifest path must be nonempty forward-slash relative text")
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        fail(f"unsafe manifest path: {value}")
    return value


def copy_stream(source: Path, destination: Path, expected_bytes: int, expected_sha: str) -> dict:
    size, digest = full_hash(source, MAX_FILE)
    if size != expected_bytes or digest != expected_sha:
        fail(f"source identity mismatch: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        fail(f"fresh output required: {destination}")
    copied = 0
    hasher = hashlib.sha256()
    fd, temporary = tempfile.mkstemp(prefix=".r13-", dir=str(destination.parent))
    try:
        with os.fdopen(fd, "wb") as out, source.open("rb") as inp:
            while True:
                block = inp.read(BUF)
                if not block:
                    break
                copied += len(block)
                if copied > MAX_FILE:
                    fail(f"copy exceeds file bound: {source}")
                out.write(block)
                hasher.update(block)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, destination)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    if copied != expected_bytes or hasher.hexdigest() != expected_sha:
        fail(f"destination identity mismatch: {destination}")
    return {
        "sourcePath": str(source),
        "destination": str(destination),
        "bytes": copied,
        "sha256": expected_sha,
    }


def write_bytes(destination: Path, chunks: list[Path]) -> dict:
    if destination.exists() or destination.is_symlink():
        fail(f"fresh output required: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    digest = hashlib.sha256()
    fd, temporary = tempfile.mkstemp(prefix=".r13-console-", dir=str(destination.parent))
    try:
        with os.fdopen(fd, "wb") as out:
            for source in chunks:
                safe_leaf(source, MAX_FILE)
                with source.open("rb") as inp:
                    while True:
                        block = inp.read(BUF)
                        if not block:
                            break
                        total += len(block)
                        if total > MAX_FILE:
                            fail("derived PresentMon console exceeds file bound")
                        out.write(block)
                        digest.update(block)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, destination)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    return {"destination": str(destination), "bytes": total, "sha256": digest.hexdigest()}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root", required=True, type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--build-json", required=True, type=Path)
    parser.add_argument("--build-receipt", required=True, type=Path)
    parser.add_argument("--parser", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--parser-sha256", default=PARSER_SHA)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    archive = args.archive_root.absolute()
    manifest_path = (args.manifest or archive / "export-manifest.json").absolute()
    output = args.output_root.absolute()
    receipt_path = args.receipt.absolute()
    if output.exists() or output.is_symlink():
        fail(f"output root must be fresh: {output}")
    if receipt_path.exists() or receipt_path.is_symlink():
        fail(f"receipt must be fresh: {receipt_path}")
    if receipt_path == output or output in receipt_path.parents:
        fail("receipt must be outside output root")
    manifest_size, manifest_sha = full_hash(manifest_path, MAX_JSON)
    manifest = read_json(manifest_path)
    files = manifest.get("files") if isinstance(manifest, dict) else None
    if not isinstance(files, list) or not files:
        fail("export manifest files missing")
    entries: dict[str, dict] = {}
    for row in files:
        if not isinstance(row, dict):
            fail("manifest entry is not object")
        rel = relative_manifest_path(row.get("path"))
        if rel in entries:
            fail(f"duplicate manifest path: {rel}")
        size = row.get("bytes")
        sha = row.get("sha256")
        if not isinstance(size, int) or size < 0 or size > MAX_FILE:
            fail(f"invalid manifest byte bound: {rel}")
        if not isinstance(sha, str) or len(sha) != 64 or any(c not in "0123456789abcdefABCDEF" for c in sha):
            fail(f"invalid manifest SHA: {rel}")
        source = archive / rel
        safe_leaf(source, MAX_FILE)
        entries[rel] = {"path": source, "bytes": size, "sha256": sha.lower()}

    required = [
        "run/result-workload.txt", "run/presentmon.csv",
        "run/presentmon.stdout.txt", "run/presentmon.stderr.txt",
        "run/r1/activity.csv", "run/r1/bridge_input.csv", "run/r1/counters.csv",
        "run/r1/fg_events.csv", "run/r1/frames.csv", "run/r1/inject.csv",
        "run/r1/inputs.csv", "run/r1/integrity.json", "run/r1/mainactor.csv",
        "run/r1/meta.json", "run/r1/modules.txt", "run/r1/overhead_probe.csv",
        "run/r1/render-frames.csv", "run/r1/stderr.txt", "run/r1/stdout.txt",
        "run/r1/ticks.csv",
    ]
    for rel in required:
        if rel not in entries:
            fail(f"required sealed parser input missing: {rel}")
    selected = [entries[rel] for rel in required]
    source_total = sum(int(row["bytes"]) for row in selected)
    if source_total > MAX_TOTAL:
        fail(f"selected archive bytes exceed aggregate bound: {source_total}")

    parser_size, parser_sha = full_hash(args.parser.absolute(), MAX_FILE)
    if parser_sha != args.parser_sha256.lower():
        fail("frozen analyzer hash mismatch")
    build = read_json(args.build_json.absolute())
    build_size, build_sha = full_hash(args.build_json.absolute(), MAX_JSON)
    build_receipt = read_json(args.build_receipt.absolute())
    build_receipt_size, build_receipt_sha = full_hash(args.build_receipt.absolute(), MAX_JSON)
    if build_receipt_sha != BUILD_RECEIPT_SHA:
        fail("genuine build receipt hash mismatch")
    if not isinstance(build, dict) or not isinstance(build_receipt, dict):
        fail("build inputs must be JSON objects")
    if build_receipt.get("kind") != "root-sr0-workload-windows-build-v1":
        fail("unexpected build receipt kind")
    if build_receipt.get("exitCode") != 0 or build_receipt.get("compilerKernelHandleRetained") is not True:
        fail("build receipt is not retained successful build")
    if build_receipt.get("sourceFilesVerified") != 54 or build_receipt.get("manifestOK") is not True:
        fail("build receipt source/manifest proof mismatch")
    receipt_exe = build_receipt.get("exe", {})
    receipt_dll = build_receipt.get("renderer", {})
    if receipt_exe.get("sha256") != EXE_SHA or receipt_dll.get("sha256") != DLL_SHA:
        fail("build receipt artifact identity mismatch")
    if build.get("exe_sha256") != EXE_SHA or build.get("dllSha256", build.get("dll_sha256")) != DLL_SHA:
        fail("build JSON artifact identity mismatch")
    if build.get("sourceManifestSha256") != SOURCE_MANIFEST_SHA:
        fail("build JSON source manifest mismatch")
    derived_build = dict(build)
    derived_build["configuration"] = "release"
    derived_build["derivation"] = "configuration derived from sealed release build receipt"

    output.mkdir(parents=True)
    copied = []
    try:
        for row in selected:
            rel = next(key for key, value in entries.items() if value is row)
            destination_rel = rel.removeprefix("run/")
            copied.append(copy_stream(row["path"], output / destination_rel, row["bytes"], row["sha256"]))
        build_out = output / "build.json"
        build_out.parent.mkdir(parents=True, exist_ok=True)
        with build_out.open("x", encoding="utf-8") as stream:
            json.dump(derived_build, stream, indent=2, sort_keys=True)
            stream.write("\n")
        build_out_size, build_out_sha = full_hash(build_out, MAX_JSON)
        console_sources = [entries["run/presentmon.stdout.txt"], entries["run/presentmon.stderr.txt"]]
        console = write_bytes(output / "presentmon.console.txt", [x["path"] for x in console_sources])
        receipt = {
            "kind": "sr0-r13-offline-analysis-inputs-v2",
            "status": "materialized-byte-preserving",
            "qualificationHeld": True,
            "qualificationClaim": False,
            "nativeActions": 0,
            "archiveRoot": str(archive),
            "archiveManifest": {"path": str(manifest_path), "bytes": manifest_size, "sha256": manifest_sha},
            "selectedArchiveBytes": source_total,
            "outputRoot": str(output),
            "parser": {"path": str(args.parser.absolute()), "bytes": parser_size, "sha256": parser_sha},
            "build": {
                "sourceJson": {"path": str(args.build_json.absolute()), "bytes": build_size, "sha256": build_sha},
                "sourceReceipt": {"path": str(args.build_receipt.absolute()), "bytes": build_receipt_size, "sha256": build_receipt_sha},
                "derivedOutput": {"path": str(build_out), "bytes": build_out_size, "sha256": build_out_sha},
                "configuration": "release",
            },
            "entries": copied,
            "console": {
                **console,
                "order": ["run/presentmon.stdout.txt", "run/presentmon.stderr.txt"],
                "syntheticBytesAdded": 0,
                "source": [
                    {"path": str(x["path"]), "bytes": x["bytes"], "sha256": x["sha256"]}
                    for x in console_sources
                ],
            },
            "rawPreserved": True,
            "hold": "strict display parser/qualification remains held",
        }
        receipt_path.parent.mkdir(parents=True, exist_ok=True)
        with receipt_path.open("x", encoding="utf-8") as stream:
            json.dump(receipt, stream, indent=2, sort_keys=True)
            stream.write("\n")
    except Exception:
        # Authored output is fresh-only; leave no misleading receipt on failure.
        raise
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Hold as exc:
        print(f"HOLD: {exc}", file=sys.stderr)
        raise SystemExit(2)
