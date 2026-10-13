#!/usr/bin/env python3
"""Strict, read-only assembler for one tuple12 Workload lifecycle packet.

It emits ``incomplete`` for any failed or missing gate and never rewrites inputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

SHA256 = re.compile(r"^[0-9a-f]{64}$", re.I)
EXE = "7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c"
DLL = "7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2"
EXPECTED = ("orchestratorTerminal", "streamsDrained", "taskQuiescent", "runProof",
            "semanticRunProof", "presentMonProof", "presentMonSessionAbsent",
            "cleanupProof", "presentMonRelease", "lockReleased")


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def no_reparse(path: Path) -> Path:
    path = path.expanduser()
    if not path.is_absolute():
        raise ValueError(f"path is not absolute: {path}")
    cur = Path(path.anchor)
    for part in path.parts[1:]:
        cur /= part
        if cur.exists() and cur.is_symlink():
            raise ValueError(f"reparse/symlink path rejected: {cur}")
    return path


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--receipt", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--expected-exe", default=EXE)
    ap.add_argument("--expected-dll", default=DLL)
    args = ap.parse_args()
    failures: list[str] = []
    root = no_reparse(args.root)
    receipt_path = no_reparse(args.receipt)
    out = no_reparse(args.out)
    files = {
        "receipt": receipt_path,
        "result": root / "runs/result-workload.txt",
        "orchestrator": root / "runs/orchestrator.log",
        "build": root / "runs/build.json",
        "report": root / "runs/report/report.json",
        "console": root / "runs/presentmon.console.txt",
        "csv": root / "runs/presentmon.csv",
    }
    for name, path in files.items():
        if not path.is_file() or path.is_symlink():
            failures.append(f"{name}-missing-or-reparse")
    receipt: dict[str, Any] = {}
    report: dict[str, Any] = {}
    build: dict[str, Any] = {}
    for key, target in (("receipt", "receipt"), ("report", "report"), ("build", "build")):
        path = files[target]
        if path.is_file() and not path.is_symlink():
            try:
                value = read_json(path)
                if key == "receipt": receipt = value
                elif key == "report": report = value
                else: build = value
            except (OSError, ValueError, json.JSONDecodeError) as exc:
                failures.append(f"{key}-read={exc}")
    if receipt.get("kind") != "sr0-tuple12-workload-coordinator-v5":
        failures.append("receipt-kind")
    if receipt.get("status") != "passed":
        failures.append(f"receipt-status={receipt.get('status')!r}")
    for field in EXPECTED:
        if receipt.get(field) is not True:
            failures.append(f"receipt-{field}")
    for field in ("orchestratorExit", "startedWorkers", "startedSamplers"):
        want = {"orchestratorExit": 0, "startedWorkers": 3, "startedSamplers": 3}[field]
        if receipt.get(field) != want:
            failures.append(f"receipt-{field}={receipt.get(field)!r}")
    if str(receipt.get("expectedExe", "")).lower() != args.expected_exe.lower():
        failures.append("receipt-exe-pin")
    if str(receipt.get("expectedDll", "")).lower() != args.expected_dll.lower():
        failures.append("receipt-dll-pin")
    if build.get("configuration") != "release":
        failures.append("build-configuration-release")
    if str(build.get("exe_sha256", "")).lower() != args.expected_exe.lower():
        failures.append("build-exe-pin")
    if str(build.get("dll_sha256", build.get("dllSha256", ""))).lower() != args.expected_dll.lower():
        failures.append("build-dll-pin")
    if report.get("overall") != "PASS" or report.get("refusal_reasons"):
        failures.append("analysis-report-not-pass")
    result = files["result"].read_text(encoding="utf-8", errors="replace") if files["result"].is_file() else ""
    if len(re.findall(r"^=== RUN [A-Za-z0-9._-]+ start=", result, re.M)) != 3:
        failures.append("result-three-runs")
    if "background_noactivate" not in result or "host_startup_guard" not in result:
        failures.append("result-noactivate-proof")
    if "finished=" not in result:
        failures.append("result-finished")
    files_out = {name: {"path": str(path), "sha256": digest(path)} for name, path in files.items() if path.is_file()}
    assembled = {"kind": "sr0-tuple12-workload-assembly-v1", "status": "qualified" if not failures else "incomplete",
                 "root": str(root), "receipt": receipt.get("receipt"), "expectedExe": args.expected_exe.lower(),
                 "expectedDll": args.expected_dll.lower(), "failures": failures, "files": files_out}
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(assembled, indent=2) + "\n").encode("utf-8")
    with out.open("xb") as stream:
        stream.write(payload)
    print(json.dumps(assembled, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
