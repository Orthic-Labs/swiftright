"""Bounded source controls for fresh common.schema verifier."""
from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

MAX_JSON_BYTES = 1 * 1024 * 1024


def args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--tuple", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--root-nonce", required=True)
    p.add_argument("--source-hash", required=True)
    p.add_argument("--expected-tuple-id", required=True)
    p.add_argument("--source-binding-file", required=True)
    p.add_argument("--source-archive-file", required=True)
    return p.parse_args()


def bounded_bytes(path: Path) -> bytes:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode) or info.st_size > MAX_JSON_BYTES:
        raise ValueError(f"unsafe JSON fixture: {path}")
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(descriptor, "rb", closefd=True) as stream:
        data = stream.read(MAX_JSON_BYTES + 1)
    if len(data) > MAX_JSON_BYTES:
        raise ValueError(f"JSON fixture exceeds budget: {path}")
    return data


def invoke(ns: argparse.Namespace, tuple_path: Path, source_hash: str, archive_path: str | None = None) -> subprocess.CompletedProcess[str]:
    verifier = Path(__file__).with_name("verify-common-schema-r11.py")
    command = [
        sys.executable,
        str(verifier),
        "--tuple", str(tuple_path),
        "--schema", ns.schema,
        "--root-nonce", ns.root_nonce,
        "--source-hash", source_hash,
        "--expected-tuple-id", ns.expected_tuple_id,
        "--source-binding-file", ns.source_binding_file,
        "--source-archive-file", archive_path or ns.source_archive_file,
    ]
    return subprocess.run(command, capture_output=True, text=True, timeout=10, check=False)


def main() -> int:
    ns = args()
    source = json.loads(bounded_bytes(Path(ns.tuple)).decode("utf-8"))
    baseline = invoke(ns, Path(ns.tuple), ns.source_hash)
    if baseline.returncode != 0:
        print(json.dumps({"status": "blocked", "reason": baseline.stdout.strip()}))
        return 2
    cases: list[tuple[str, dict | None, str, str | None]] = []
    wrong_id = json.loads(json.dumps(source))
    wrong_id["candidateID"] = "sr1-source-bound-r11-mac20-host-000000000000-20261011"
    cases.append(("wrong-tuple-id", wrong_id, ns.source_hash, None))
    wrong_ref = json.loads(json.dumps(source))
    wrong_ref["sourceInputs"]["sourceBinding"]["sha256"] = "sha256:" + ("0" * 64)
    cases.append(("wrong-source-binding-ref", wrong_ref, ns.source_hash, None))
    cases.append(("wrong-source-hash", source, "sha256:" + ("0" * 64), None))
    wrong_mac = json.loads(json.dumps(source))
    wrong_mac["tuple"]["hostHashes"]["macos"] = "sha256:" + ("0" * 64)
    cases.append(("wrong-mac-host-hash", wrong_mac, ns.source_hash, None))
    wrong_windows = json.loads(json.dumps(source))
    wrong_windows["tuple"]["hostHashes"]["windows"] = "sha256:" + ("0" * 64)
    cases.append(("wrong-windows-host-hash", wrong_windows, ns.source_hash, None))
    results = []
    with tempfile.TemporaryDirectory(prefix="mac-schema-r11-controls-") as temp:
        bad_archive = Path(temp) / "wrong-source-archive.json"
        bad_archive.write_bytes(bounded_bytes(Path(ns.source_archive_file)) + b"\n")
        cases.append(("wrong-source-archive", source, ns.source_hash, str(bad_archive)))
        for name, document, source_hash, archive_path in cases:
            path = Path(temp) / (name + ".json")
            path.write_text(json.dumps(document), encoding="utf-8")
            result = invoke(ns, path, source_hash, archive_path)
            results.append({"name": name, "rejected": result.returncode != 0, "nativeWindowActions": 0})
            if result.returncode == 0:
                print(json.dumps({"status": "failed", "case": name}))
                return 2
    print(json.dumps({"status": "passed-source-only", "baselineAccepted": True, "faultControls": results, "nativeWindowActions": 0, "compilerActions": 0, "guiActions": 0, "remoteActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
