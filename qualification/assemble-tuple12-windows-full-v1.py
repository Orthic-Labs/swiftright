#!/usr/bin/env python3
"""Strict source-bound assembler for tuple12 Windows Full (16 x 20) output.

Reads retained matrix output only.  It never launches jobs or changes input.
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
CONFIGS = (
    ("F1", ""), ("F2", ""),
    ("F3", "list-0s"), ("F3", "list-1s"), ("F3", "list-3s"),
    ("F3", "vstack-1s"), ("F3", "vstack-3s"),
    ("F3", "lazy-1s"), ("F3", "lazy-3s"),
    ("F4", ""), ("F5", ""), ("F6", ""), ("F6", "reduced"),
    ("F7", ""), ("F8", ""), ("F9", ""),
)
EXPECTED_DENOMINATORS = {
    ("F1", ""): 17, ("F2", ""): 13,
    ("F3", "list-0s"): 15, ("F3", "list-1s"): 15,
    ("F3", "list-3s"): 15, ("F3", "vstack-1s"): 15,
    ("F3", "vstack-3s"): 15, ("F3", "lazy-1s"): 15,
    ("F3", "lazy-3s"): 15, ("F4", ""): 12, ("F5", ""): 13,
    ("F6", ""): 16, ("F6", "reduced"): 11,
    ("F7", ""): 20, ("F8", ""): 15, ("F9", ""): 11,
}
DRIVER_HASHES = {"5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4", "0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c"}  # r5, r6 diagnostic
CONFIG_SLUGS = {f"{fixture}{'-' + variant if variant else ''}": (fixture, variant)
                for fixture, variant in CONFIGS}
SLUGS = sorted(CONFIG_SLUGS, key=len, reverse=True)
CASE_RE = re.compile(r"^(?P<slug>.+)-r(?P<run>[1-9][0-9]*)-(?P<guid>[0-9a-f]{32})$", re.I)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def local_path_without_reparse(path: Path) -> Path:
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
    if not value:
        raise ValueError(f"{name} is empty")
    if not (re.match(r"^[A-Za-z]:[\\/]", value) or value.startswith("/")):
        raise ValueError(f"{name} must be absolute: {value}")
    local = Path(value) if value.startswith("/") else None
    exists = False
    if local is not None and local.exists():
        local_path_without_reparse(local)
        exists = True
    return {"path": value, "binding": "local-bytes" if exists else "receipt-bound"}


def _config_label(fixture: str, variant: str) -> str:
    if (fixture, variant) == ("F6", "reduced"): return "F6-reduced"  # product-emitted label
    return f"{fixture}{' ' + variant if variant else ''}"


def native_markers(fixture: str, variant: str) -> list[str]:
    label = _config_label(fixture, variant)
    return [
        f"SELFTEST-STAGES {label}:",
        f"ASSERT {label} script-completed: PASS",
        f"ASSERT {label} renderer-no-violations: PASS",
        f"ASSERT {label} commits-accepted: PASS",
        f"ASSERT {label} no-measure-or-draw-failures: PASS",
    ]


def marker_ok(text: str, fixture: str, variant: str, expected: dict[str, str]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    low = text.lower()
    common = [
        "renderer_ready_event=True", "SR0_NOACTIVATE guard=installed",
        "SR0_RENDERER_READY file=created", "record=renderer-ready",
        "phase=first-ready", "source=Bridge.onReady",
        "renderer_window_revalidate=PASS", "WindowMetrics phase=startup",
        "client_ok=True", "same_process=True",
        "run_summary keymode=char delivery=targeted fg_changes=0",
        f"SELFTEST {_config_label(fixture, variant)}: PASS", "driver_abort=none",
        "driver_close_ready_file=True", "close_window=WM_CLOSE posted=True",
        "same_hwnd=True", "same_handle=True", "exit=0",
        f"ARTIFACTS exe={expected['exe']} renderer={expected['renderer']}",
    ]
    required = common + native_markers(fixture, variant)
    for needle in required:
        if needle.lower() not in low:
            failures.append(needle)
    if fixture == "F1":
        required_f1 = [
            "SELFTEST F1: PASS (17/17", "ASSERT F1 focus-stays-row5: PASS",
            "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS",
            "setfocus_attempt[Row 5]=0 noactivate=True",
            "provider_focus[Row 5]=False",
            "focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus",
        ]
        for needle in required_f1:
            if needle.lower() not in low:
                failures.append(needle)
    label = re.escape(_config_label(fixture, variant))
    verdict = re.search(rf"SELFTEST\s+{label}:\s+PASS\s+\((\d+)/(\d+)\s+asserted", text, re.I)
    expected_denominator = EXPECTED_DENOMINATORS[(fixture, variant)]
    if not verdict:
        failures.append("native-selftest-denominator")
    elif verdict.group(1) != verdict.group(2) or int(verdict.group(2)) != expected_denominator:
        failures.append(f"native-selftest-denominator={verdict.group(1)}/{verdict.group(2)} expected={expected_denominator}")
    guard = low.find("sr0_noactivate guard=installed")
    ready = low.find("sr0_renderer_ready file=created")
    if guard < 0 or ready <= guard:
        failures.append("guard-before-renderer-ready")
    return not failures, failures


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def receipt_ok(receipt: dict[str, Any], expected: dict[str, str], fixture: str, variant: str, trace: str) -> tuple[bool, list[str]]:
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
    if receipt.get("fixture") != fixture or receipt.get("variant", "") != variant:
        failures.append("receipt-config-join")
    driver = receipt.get("driverScript")
    exe = receipt.get("exe")
    renderer = receipt.get("renderer")
    if not isinstance(driver, dict) or driver.get("sha256", "").lower() != expected["driver"]:
        failures.append("driver-hash")
    if not isinstance(exe, dict) or exe.get("sha256", "").lower() != expected["exe"]:
        failures.append("exe-hash")
    if not isinstance(renderer, dict) or renderer.get("sha256", "").lower() != expected["renderer"]:
        failures.append("renderer-hash")
    trace_ok, trace_failures = marker_ok(trace, fixture, variant, expected)
    if not trace_ok:
        failures.extend(f"trace:{item}" for item in trace_failures)
    return not failures, failures


def parse_case(name: str) -> tuple[tuple[str, str], int] | None:
    match = CASE_RE.fullmatch(name)
    if not match:
        return None
    slug = match.group("slug")
    if slug not in CONFIG_SLUGS:
        return None
    return CONFIG_SLUGS[slug], int(match.group("run"))


def collect(root: Path, expected: dict[str, str]) -> dict[str, Any]:
    root = local_path_without_reparse(root)
    if not root.is_dir():
        raise ValueError(f"input root is not a directory: {root}")
    failures: list[dict[str, Any]] = []
    rows: list[dict[str, Any]] = []
    seen: set[tuple[tuple[str, str], int]] = set()
    expected_keys = {(cfg, run) for cfg in CONFIGS for run in range(1, 21)}
    for item in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if item.is_symlink():
            failures.append({"case": item.name, "failures": ["reparse/symlink-case"]})
            continue
        if not item.is_dir():
            failures.append({"case": item.name, "failures": ["unexpected-root-entry"]})
            continue
        parsed = parse_case(item.name)
        if parsed is None:
            failures.append({"case": item.name, "failures": ["unknown-case-name"]})
            continue
        (fixture, variant), run = parsed
        key = ((fixture, variant), run)
        if key in seen:
            failures.append({"case": item.name, "failures": ["duplicate-config-run"]})
            continue
        seen.add(key)
        problems: list[str] = []
        matrix_paths = [p for p in item.glob("matrix-run.json") if p.is_file() and not p.is_symlink()]
        receipt_paths = [p for p in (item / "receipts").glob("worker-*.json") if p.is_file() and not p.is_symlink()] if (item / "receipts").is_dir() else []
        trace_paths = [p for p in item.rglob("driver-trace.txt") if p.is_file() and not p.is_symlink()]
        if len(matrix_paths) != 1: problems.append(f"matrix-count={len(matrix_paths)}")
        if len(receipt_paths) != 1: problems.append(f"receipt-count={len(receipt_paths)}")
        if len(trace_paths) != 1: problems.append(f"trace-count={len(trace_paths)}")
        matrix = receipt = None
        trace = ""
        if len(matrix_paths) == 1:
            try: matrix = read_json(matrix_paths[0])
            except (OSError, ValueError, json.JSONDecodeError) as exc: problems.append(f"matrix-read={exc}")
        if len(receipt_paths) == 1:
            try: receipt = read_json(receipt_paths[0])
            except (OSError, ValueError, json.JSONDecodeError) as exc: problems.append(f"receipt-read={exc}")
        if len(trace_paths) == 1:
            try: trace = trace_paths[0].read_text(encoding="utf-8")
            except OSError as exc: problems.append(f"trace-read={exc}")
        if matrix is not None:
            expected_matrix = {"kind": matrix.get("kind") if matrix.get("kind") in ("sr0-tuple12-matrix-run-v3", "sr0-tuple12-matrix-run-v6") else "sr0-tuple12-matrix-run-v6", "mode": matrix.get("mode") if (matrix.get("mode") in ("Full", "F3List0s") or (matrix.get("mode") == "F6Reduced" and fixture == "F6" and variant == "reduced")) else "Full", "fixture": fixture, "variant": variant, "run": run, "runs": 20, "status": "passed", "driverSha256": expected["driver"], "workerSha256": expected["worker"], "coordinatorSha256": expected["coordinator"], "exeSha256": expected["exe"], "rendererSha256": expected["renderer"], "coordinatorExit": 0, "targetedDelivery": True, "noActivate": True}
            for field, value in expected_matrix.items():
                actual = matrix.get(field)
                if isinstance(value, str): actual = str(actual).lower(); value = value.lower()
                if actual != value: problems.append(f"matrix-{field}={matrix.get(field)!r}")
            worker_receipt = str(matrix.get("workerReceipt", ""))
            if not worker_receipt.lower().endswith(receipt_paths[0].name.lower() if receipt_paths else "\0"):
                problems.append("matrix-worker-receipt-join")
        if receipt is not None and not problems:
            ok, receipt_failures = receipt_ok(receipt, expected, fixture, variant, trace)
            if not ok: problems.extend(receipt_failures)
        row = {"fixture": fixture, "variant": variant, "run": run, "case": item.name}
        if problems:
            row["failures"] = problems; failures.append(row)
        else:
            row.update({"matrix": str(matrix_paths[0].relative_to(root).as_posix()), "matrixSha256": digest(matrix_paths[0]), "receipt": str(receipt_paths[0].relative_to(root).as_posix()), "receiptSha256": digest(receipt_paths[0]), "trace": str(trace_paths[0].relative_to(root).as_posix()), "traceSha256": digest(trace_paths[0])})
            rows.append(row)
    missing = sorted(expected_keys - seen, key=lambda x: (CONFIGS.index(x[0]), x[1]))
    for (fixture, variant), run in missing:
        failures.append({"fixture": fixture, "variant": variant, "run": run, "failures": ["missing-config-run"]})
    status = "qualified" if not failures and len(rows) == 320 else "incomplete"
    return {"status": status, "requiredConfigs": 16, "runsPerConfig": 20, "requiredRuns": 320, "observedRuns": len(seen), "passedRuns": len(rows), "configs": [{"fixture": f, "variant": v, "requiredRuns": 20, "requiredNativeDenominator": EXPECTED_DENOMINATORS[(f, v)]} for f, v in CONFIGS], "runs": sorted(rows, key=lambda x: (CONFIGS.index((x["fixture"], x["variant"])), x["run"])), "failures": failures}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--expected-exe", required=True)
    parser.add_argument("--expected-renderer", required=True)
    parser.add_argument("--expected-driver", required=True)
    parser.add_argument("--expected-worker", required=True)
    parser.add_argument("--expected-coordinator", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-manifest-sha256", required=True)
    parser.add_argument("--base-path", required=True); parser.add_argument("--driver-path", required=True)
    parser.add_argument("--worker-path", required=True); parser.add_argument("--coordinator-path", required=True)
    ns = parser.parse_args()
    expected = {"exe": ns.expected_exe.lower(), "renderer": ns.expected_renderer.lower(), "driver": ns.expected_driver.lower(), "worker": ns.expected_worker.lower(), "coordinator": ns.expected_coordinator.lower()}
    if any(not SHA256.fullmatch(value) for value in expected.values()): parser.error("artifact pins must be SHA-256")
    if expected["driver"] not in DRIVER_HASHES: parser.error("driver pin is not approved (r5/r6)")
    if not SHA1.fullmatch(ns.source_commit): parser.error("source commit must be 40-hex")
    if not SHA256.fullmatch(ns.source_manifest_sha256): parser.error("source manifest must be SHA-256")
    try:
        source_paths = {name: bound_path(value, name) for name, value in {"base": ns.base_path, "driver": ns.driver_path, "worker": ns.worker_path, "coordinator": ns.coordinator_path}.items()}
        report = collect(ns.root, expected)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ASSEMBLY_FAIL {exc}", file=sys.stderr); return 2
    report.update({"kind": "sr0-tuple12-windows-full-report-v1", "source": {"commit": ns.source_commit.lower(), "manifestSha256": ns.source_manifest_sha256.lower(), "paths": source_paths, "binding": "receipt-bound"}, "artifacts": expected, "admission": "qualified-only-when-16-configs-x-20-passed-native-receipts"})
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if ns.out:
        out = local_path_without_reparse(ns.out)
        if out.exists(): raise SystemExit(f"ASSEMBLY_FAIL output exists: {out}")
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("x", encoding="utf-8", newline="") as stream: stream.write(encoded)
    print(encoded, end="")
    return 0 if report["status"] == "qualified" else 1


if __name__ == "__main__":
    raise SystemExit(main())
