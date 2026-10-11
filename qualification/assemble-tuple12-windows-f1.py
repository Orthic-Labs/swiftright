#!/usr/bin/env python3
"""Pure source-bound assembler for tuple12 Windows F1 receipts.

This module only reads retained output and optionally creates one new report with
CreateNew semantics. It never launches Windows, changes tasks, or mutates input.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

SHA256 = re.compile(r"^[0-9a-f]{64}$", re.I)
SHA1 = re.compile(r"^[0-9a-f]{40}$", re.I)
CASE = re.compile(r"^F1-r([1-9][0-9]*)-([0-9a-f]{32})$")


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def local_path_without_reparse(path: Path) -> Path:
    """Resolve existing local path while rejecting symlink/reparse components."""
    candidate = path.expanduser()
    if not candidate.is_absolute():
        raise ValueError(f"path is not absolute: {path}")
    current = Path(candidate.anchor)
    for part in candidate.parts[1:]:
        current /= part
        if current.exists() and current.is_symlink():
            raise ValueError(f"reparse/symlink path rejected: {current}")
    return candidate


def bound_path(value: str, name: str) -> dict[str, str]:
    """Record local or remote absolute source path without claiming remote bytes."""
    if not value:
        raise ValueError(f"{name} is empty")
    windows_absolute = bool(re.match(r"^[A-Za-z]:[\\/]", value))
    posix_absolute = value.startswith("/")
    if not (windows_absolute or posix_absolute):
        raise ValueError(f"{name} must be absolute: {value}")
    local = Path(value) if posix_absolute else None
    exists = False
    if local is not None and local.exists():
        local_path_without_reparse(local)
        exists = True
    return {"path": value, "binding": "local-bytes" if exists else "receipt-bound"}


def marker_ok(text: str, exe: str, dll: str) -> tuple[bool, list[str]]:
    required = [
        "renderer_ready_event=True",
        "SR0_NOACTIVATE guard=installed",
        "SR0_RENDERER_READY file=created",
        "record=renderer-ready",
        "phase=first-ready",
        "source=Bridge.onReady",
        "renderer_window_revalidate=PASS",
        "WindowMetrics phase=startup",
        "client_ok=True",
        "same_process=True",
        "run_summary keymode=char delivery=targeted fg_changes=0",
        "SELFTEST F1: PASS (17/17",
        "ASSERT F1 focus-stays-row5: PASS",
        "ASSERT F1 row5-text: PASS",
        "ASSERT F1 ax-focus-delivered: PASS",
        "setfocus_attempt[Row 5]=0 noactivate=True",
        "provider_focus[Row 5]=False",
        "focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus",
        "driver_abort=none",
        "driver_close_ready_file=True",
        "close_window=WM_CLOSE posted=True",
        "same_hwnd=True",
        "same_handle=True",
        "exit=0",
        f"ARTIFACTS exe={exe.lower()} renderer={dll.lower()}",
    ]
    missing = [needle for needle in required if needle.lower() not in text.lower()]
    guard = text.lower().find("sr0_noactivate guard=installed")
    ready = text.lower().find("sr0_renderer_ready file=created")
    if guard < 0 or ready <= guard:
        missing.append("guard-before-renderer-ready")
    return not missing, missing


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def receipt_ok(receipt: dict[str, Any], expected: dict[str, str], trace: str) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if receipt.get("status") != "passed":
        failures.append(f"receipt-status={receipt.get('status')}")
    for field in ("workerExitCode", "driverExitCode", "childExitCode"):
        if receipt.get(field) != 0:
            failures.append(f"{field}={receipt.get(field)!r}")
    for field in ("driverKernel", "childKernel"):
        kernel = receipt.get(field)
        if not isinstance(kernel, dict) or kernel.get("terminal") is not True or kernel.get("getExitCode") is not True:
            failures.append(f"{field}-terminal-proof")
    for field in ("driverHandle", "childHandle"):
        handle = receipt.get(field)
        if not isinstance(handle, dict) or handle.get("retained") is not True:
            failures.append(f"{field}-retained-proof")
    driver = receipt.get("driverScript")
    exe = receipt.get("exe")
    renderer = receipt.get("renderer")
    if not isinstance(driver, dict) or driver.get("sha256", "").lower() != expected["driver"]:
        failures.append("driver-hash")
    if not isinstance(exe, dict) or exe.get("sha256", "").lower() != expected["exe"]:
        failures.append("exe-hash")
    if not isinstance(renderer, dict) or renderer.get("sha256", "").lower() != expected["renderer"]:
        failures.append("renderer-hash")
    trace_ok, trace_failures = marker_ok(trace, expected["exe"], expected["renderer"])
    if not trace_ok:
        failures.extend(f"trace:{item}" for item in trace_failures)
    return not failures, failures


def collect(root: Path, expected: dict[str, str], required_runs: int) -> dict[str, Any]:
    root = local_path_without_reparse(root)
    if not root.is_dir():
        raise ValueError(f"input root is not a directory: {root}")
    cases: list[tuple[int, Path]] = []
    for item in sorted(root.iterdir()):
        if not item.is_dir() or item.is_symlink():
            continue
        match = CASE.fullmatch(item.name)
        if match:
            cases.append((int(match.group(1)), item))
    failures: list[dict[str, Any]] = []
    receipts: list[dict[str, Any]] = []
    seen_runs: set[int] = set()
    for run, case in cases:
        entry: dict[str, Any] = {"run": run, "case": case.name}
        if run in seen_runs:
            entry["failures"] = ["duplicate-run-number"]
            failures.append(entry)
            continue
        seen_runs.add(run)
        receipt_paths = sorted((case / "receipts").glob("worker-*.json"))
        trace_paths = sorted(case.rglob("driver-trace.txt"))
        problems: list[str] = []
        if len(receipt_paths) != 1:
            problems.append(f"receipt-count={len(receipt_paths)}")
        if len(trace_paths) != 1:
            problems.append(f"trace-count={len(trace_paths)}")
        receipt: dict[str, Any] | None = None
        if len(receipt_paths) == 1:
            try:
                receipt = read_json(receipt_paths[0])
            except (OSError, ValueError, json.JSONDecodeError) as exc:
                problems.append(f"receipt-read={exc}")
        trace = ""
        if len(trace_paths) == 1:
            try:
                trace = trace_paths[0].read_text(encoding="utf-8")
            except OSError as exc:
                problems.append(f"trace-read={exc}")
        if receipt is not None and not problems:
            ok, receipt_failures = receipt_ok(receipt, expected, trace)
            if not ok:
                problems.extend(receipt_failures)
        if problems:
            entry["failures"] = problems
            if receipt_paths:
                entry["receipt"] = receipt_paths[0].relative_to(root).as_posix()
            failures.append(entry)
            continue
        assert receipt is not None and len(trace_paths) == 1
        receipts.append({
            "run": run,
            "case": case.name,
            "receipt": receipt_paths[0].relative_to(root).as_posix(),
            "receiptSha256": digest(receipt_paths[0]),
            "trace": trace_paths[0].relative_to(root).as_posix(),
            "traceSha256": digest(trace_paths[0]),
        })
    if len(cases) != required_runs:
        failures.append({"root": ".", "failures": [f"observed-case-count={len(cases)} required={required_runs}"]})
    status = "qualified" if len(cases) == required_runs and len(receipts) == required_runs and not failures else "incomplete"
    return {
        "status": status,
        "requiredRuns": required_runs,
        "observedRuns": len(cases),
        "passedRuns": len(receipts),
        "receipts": receipts,
        "failures": failures,
    }


def fault_controls(text: str, expected: dict[str, str]) -> dict[str, bool]:
    """Mutation controls prove key admission gates reject one fault each."""
    controls = {
        "missing-17-assertions": ("SELFTEST F1: PASS (17/17", "SELFTEST F1: PASS (16/17"),
        "wrong-node": ("ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 focus-stays-row3: PASS"),
        "activation": ("SR0_NOACTIVATE guard=installed", "SR0_NOACTIVATE guard=missing"),
        "input-abort": ("driver_abort=none", "driver_abort=foreground-lost"),
        "setfocus-attempt": ("setfocus_attempt[Row 5]=0 noactivate=True", "setfocus_attempt[Row 5]=0 noactivate=False"),
    }
    result: dict[str, bool] = {}
    for name, (old, new) in controls.items():
        if old.lower() not in text.lower():
            result[name] = False
            continue
        mutated = text.replace(old, new, 1)
        result[name] = not marker_ok(mutated, expected["exe"], expected["renderer"])[0]
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--runs", type=int, default=20)
    parser.add_argument("--expected-exe", required=True)
    parser.add_argument("--expected-renderer", required=True)
    parser.add_argument("--expected-driver", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-manifest-sha256", required=True)
    parser.add_argument("--base-path", required=True)
    parser.add_argument("--driver-path", required=True)
    parser.add_argument("--worker-path", required=True)
    parser.add_argument("--coordinator-path", required=True)
    parser.add_argument("--fault-controls", action="store_true")
    ns = parser.parse_args()
    if ns.runs != 20:
        parser.error("F1 assembler requires exactly 20 runs")
    expected = {"exe": ns.expected_exe.lower(), "renderer": ns.expected_renderer.lower(), "driver": ns.expected_driver.lower()}
    if any(not SHA256.fullmatch(value) for value in expected.values()):
        parser.error("artifact pins must be SHA-256")
    if not SHA1.fullmatch(ns.source_commit):
        parser.error("source commit must be 40-hex")
    if not SHA256.fullmatch(ns.source_manifest_sha256):
        parser.error("source manifest must be SHA-256")
    try:
        source_paths = {name: bound_path(value, name) for name, value in {
            "base": ns.base_path, "driver": ns.driver_path,
            "worker": ns.worker_path, "coordinator": ns.coordinator_path,
        }.items()}
        report = collect(ns.root, expected, ns.runs)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ASSEMBLY_FAIL {exc}", file=sys.stderr)
        return 2
    report.update({
        "kind": "sr0-tuple12-windows-f1-report-v1",
        "fixture": "F1",
        "source": {
            "commit": ns.source_commit.lower(),
            "manifestSha256": ns.source_manifest_sha256.lower(),
            "paths": source_paths,
            "binding": "receipt-bound",
        },
        "artifacts": expected,
        "admission": "qualified-only-when-20-passed-receipts",
    })
    if ns.fault_controls:
        traces = sorted(ns.root.rglob("driver-trace.txt"))
        if len(traces) == 1:
            text = traces[0].read_text(encoding="utf-8")
            report["faultControls"] = fault_controls(text, expected)
        else:
            report["faultControls"] = {"status": "not-run", "traceCount": len(traces)}
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if ns.out:
        out = local_path_without_reparse(ns.out)
        if out.exists():
            raise SystemExit(f"ASSEMBLY_FAIL output exists: {out}")
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("x", encoding="utf-8", newline="") as stream:
            stream.write(encoded)
    print(encoded, end="")
    return 0 if report["status"] == "qualified" else 1


if __name__ == "__main__":
    raise SystemExit(main())
