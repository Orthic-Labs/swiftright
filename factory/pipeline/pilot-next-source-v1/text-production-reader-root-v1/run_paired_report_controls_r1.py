#!/usr/bin/env python3
"""Production paired-report verifier controls; raw evidence stays read-only."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import shutil
from pathlib import Path
from typing import Any, Callable

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("text_reader_materializer", HERE / "materialize_text_reader_r1.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("materializer import unavailable")
MATERIALIZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MATERIALIZER)

MAX_JSON = MATERIALIZER.MAX_JSON


def write_case(path: Path, report: dict[str, Any]) -> None:
    raw = (json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if len(raw) > MAX_JSON:
        raise RuntimeError("mutated report exceeded bounded JSON budget")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def invoke(path: Path, windows_root: Path, expected: str | None) -> dict[str, Any]:
    try:
        result = MATERIALIZER.validate_paired_report(path, windows_root)
    except MATERIALIZER.Hold as exc:
        if expected is None:
            raise RuntimeError(f"unexpected rejection: {exc}") from exc
        if expected not in str(exc):
            raise RuntimeError(f"wrong rejection, expected {expected!r}, got {exc!s}") from exc
        return {"status": "rejected", "reason": str(exc)}
    if expected is not None:
        raise RuntimeError(f"fault admitted: expected {expected!r}")
    return {"status": "accepted", "summary": result}


def mutate(report: dict[str, Any], name: str) -> tuple[dict[str, Any], str]:
    value = copy.deepcopy(report)
    if name == "wrong-case":
        value["mac"]["case"]["id"] = "mutated-case"
        return value, "paired macos identity mismatch"
    if name == "wrong-tuple":
        value["mac"]["tuple"]["id"] = "mutated-tuple"
        return value, "paired macos identity mismatch"
    if name == "wrong-source":
        value["mac"]["sourceHash"] = "sha256:" + "0" * 64
        return value, "paired macos identity mismatch"
    if name == "raw-hash":
        value["windows"]["rows"][0]["raw"][0]["sha256"] = "sha256:" + "0" * 64
        return value, "Windows row 1 raw 0 reference hash/bytes drift"
    if name == "exit-role":
        value["mac"]["rows"][0]["terminal"]["exitProof"]["host"]["exitCode"] = 1
        return value, "paired Mac row 1 host exit proof mismatch"
    if name == "pid":
        value["mac"]["rows"][0]["terminal"]["exitProof"]["host"]["pid"] = 0
        return value, "paired Mac row 1 host exit proof mismatch"
    if name == "terminal":
        value["windows"]["rows"][0]["terminal"]["kernelWait"] = 258
        return value, "paired Windows row 1 terminal proof mismatch"
    if name == "missing-ordinal":
        value["mac"]["rows"][1]["ordinal"] = None
        return value, "paired Mac row 2 identity mismatch"
    if name == "duplicate-run":
        value["windows"]["rows"][1]["sourceRun"] = "native-01"
        return value, "paired Windows row 2 identity mismatch"
    if name == "qualified":
        value["qualification"] = True
        return value, "paired report must remain unqualified/parity-held"
    if name == "parity":
        value["parity"] = "qualified"
        return value, "paired report must remain unqualified/parity-held"
    if name == "png-repeatability":
        value["semantic"]["repeatability"]["windowsScreenExactRepeat"] = False
        return value, "paired image repeatability claim mismatch"
    raise ValueError(name)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--windows-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = MATERIALIZER.read_json(args.report.resolve(strict=True))
    if not isinstance(report, dict):
        raise RuntimeError("paired report object required")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise RuntimeError("controls output must be fresh")
    output.mkdir(parents=True, exist_ok=True)
    baseline = invoke(args.report.resolve(strict=True), args.windows_root.resolve(strict=True), None)
    cases: list[dict[str, Any]] = []
    for name in ("wrong-case", "wrong-tuple", "wrong-source", "raw-hash", "exit-role", "pid", "terminal", "missing-ordinal", "duplicate-run", "qualified", "parity", "png-repeatability"):
        mutated, expected = mutate(report, name)
        path = output / "mutations" / name / "report.json"
        write_case(path, mutated)
        cases.append({"name": name, **invoke(path, args.windows_root.resolve(strict=True), expected)})
    result = {"schema": "factory-text-paired-report-controls-r1", "status": "SOURCE_CONTROLS_PASS", "nativeActions": 0, "baseline": baseline, "cases": cases, "rawEvidenceMutated": False}
    write_case(output / "paired-report-controls.json", result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
