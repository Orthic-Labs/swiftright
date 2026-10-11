#!/usr/bin/env python3
"""Run one structured current/candidate metadata parity diagnostic."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
LOG = OUT / "raw"
BIN = OUT / "binaries"
RECEIPT = OUT / "run-receipt.json"
PROBE = OUT / "MetadataCopyProbe.swift"
CURRENT = ROOT / "factory/native/windows/module-origin-37429120-20261011/runtime/Sources/SwiftRightRuntime"
CANDIDATE = ROOT / "factory/runtime-additions/additive-copy-cost-v1/runtime-candidate-sources/SwiftRightRuntime"


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rel(path: Path) -> str:
    return path.resolve().relative_to(ROOT).as_posix()


def tree_manifest(root: Path) -> dict:
    files = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        files.append({"path": path.relative_to(root).as_posix(), "bytes": path.stat().st_size, "sha256": sha256(path)})
    encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"root": rel(root), "files": files, "manifestSha256": hashlib.sha256(encoded).hexdigest()}


def stream_record(path: Path, data: bytes) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return {"path": rel(path), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def process(label: str, argv: list[str], output_stem: str, executable: Path | None = None) -> dict:
    started = now()
    started_ns = time.time_ns()
    exe = Path(argv[0]).resolve()
    record = {
        "label": label,
        "argv": argv,
        "cwd": str(ROOT),
        "executable": str(exe),
        "executableHashAtStart": sha256(exe) if exe.is_file() else None,
        "startedAt": started,
        "startedUnixNS": started_ns,
    }
    child = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    record["pid"] = child.pid
    stdout, stderr = child.communicate()
    record["endedAt"] = now()
    record["endedUnixNS"] = time.time_ns()
    record["returncode"] = child.returncode
    record["stdout"] = stream_record(LOG / f"{output_stem}.stdout", stdout)
    record["stderr"] = stream_record(LOG / f"{output_stem}.stderr", stderr)
    if executable is not None and executable.is_file():
        record["outputExecutable"] = {"path": rel(executable), "bytes": executable.stat().st_size, "sha256": sha256(executable)}
    return record


def key_values(data: bytes) -> dict[str, str]:
    result = {}
    for line in data.decode("utf-8", errors="strict").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def main() -> int:
    LOG.mkdir(parents=True, exist_ok=True)
    BIN.mkdir(parents=True, exist_ok=True)
    swiftc = Path(shutil.which("swiftc") or "").resolve()
    if not swiftc.is_file():
        raise RuntimeError("swiftc not found")
    version = process("swiftc-version", [str(swiftc), "--version"], "swiftc-version")

    records = [version]
    source_trees = {"current": tree_manifest(CURRENT), "candidate": tree_manifest(CANDIDATE)}
    probes = {}
    for name, source_root in (("current", CURRENT), ("candidate", CANDIDATE)):
        binary = BIN / f"{name}-metadata-copy-probe"
        source_files = [str(path) for path in sorted(source_root.glob("*.swift"))]
        compile_argv = [str(swiftc), "-O", "-module-name", "SwiftRightRuntime", *source_files, str(PROBE), "-o", str(binary)]
        records.append(process(f"{name}-compile", compile_argv, f"{name}-compile"))
        run = process(f"{name}-run", [str(binary)], f"{name}-run", executable=binary)
        records.append(run)
        probes[name] = {"values": key_values((LOG / f"{name}-run.stdout").read_bytes()), "returncode": run["returncode"]}

    parity = probes["current"]["values"] == probes["candidate"]["values"]
    receipt = {
        "schema": "additive-copy-cost-actual-r2-receipt-v1",
        "createdAt": now(),
        "cwd": str(ROOT),
        "host": {"platform": platform.platform(), "machine": platform.machine(), "python": sys.version},
        "tool": {"path": str(swiftc), "sha256": sha256(swiftc), "versionProcess": "swiftc-version", "optimization": "-O", "moduleName": "SwiftRightRuntime"},
        "sourceTrees": source_trees,
        "probeSource": {"path": rel(PROBE), "bytes": PROBE.stat().st_size, "sha256": sha256(PROBE)},
        "binaries": {name: {"path": rel(BIN / f"{name}-metadata-copy-probe"), "sha256": sha256(BIN / f"{name}-metadata-copy-probe")} for name in probes},
        "processes": records,
        "diagnostic": {"current": probes["current"], "candidate": probes["candidate"], "stdoutKeyValueParity": parity},
    }
    RECEIPT.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"receipt": rel(RECEIPT), "stdoutKeyValueParity": parity, "processCount": len(records)}, sort_keys=True))
    return 0 if parity and all(item["returncode"] == 0 for item in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
