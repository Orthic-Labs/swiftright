#!/usr/bin/env python3
"""Pure assembler for source-bound tuple12 Mac F1 x20 evidence.

Reads retained raw/events/trace/log files & emits one new report. It never
launches native code, signs, changes TCC, deletes inputs, or edits inputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

HEX64 = re.compile(r"^[0-9a-f]{64}$", re.I)
HEX40 = re.compile(r"^[0-9a-f]{40}$", re.I)
RUN = re.compile(r"^mac-(raw|ev|trace)-n([1-9]|1[0-9]|20)\.(json|jsonl)$")
IDS = ["initial", "focus_row5", "type_abc", "engine_insert_above", "type_d"]
ACT = ["launch-and-snapshot", "focus row 5 field", "type abc", "engine inserts row at index 0", "type d"]
ROW5 = "row/F0000001-0000-4000-8000-000000000005"
ROW99 = "row/F0000001-0000-4000-8000-000000000099"


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def existing(path: Path, label: str) -> Path:
    p = path.expanduser()
    if not p.is_absolute():
        raise ValueError(f"{label} must be absolute: {p}")
    cur = Path(p.anchor)
    for part in p.parts[1:]:
        cur /= part
        if cur.exists() and cur.is_symlink():
            raise ValueError(f"{label} contains symlink: {cur}")
    if not p.is_file():
        raise ValueError(f"{label} missing: {p}")
    return p


def directory(path: Path, label: str) -> Path:
    p = path.expanduser()
    if not p.is_absolute():
        raise ValueError(f"{label} must be absolute: {p}")
    if p.exists() and p.is_symlink():
        raise ValueError(f"{label} is symlink: {p}")
    if not p.is_dir():
        raise ValueError(f"{label} missing: {p}")
    return p


def obj(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def plan_join(repo: Path, packet: dict[str, Any]) -> dict[str, Any]:
    plans = packet["macPlans"]
    step_path = existing(repo / plans["stepsPath"], "steps plan")
    stim_path = existing(repo / plans["stimulusPath"], "stimulus plan")
    if digest(step_path) != plans["stepsSha256"]:
        raise ValueError("steps plan SHA-256 mismatch")
    if digest(stim_path) != plans["stimulusSha256"]:
        raise ValueError("stimulus plan SHA-256 mismatch")
    stimulus = obj(stim_path)
    steps = obj(step_path)
    expected = stimulus.get("steps")
    actual = steps.get("steps")
    if not isinstance(expected, list) or [x.get("id") for x in expected] != IDS:
        raise ValueError("stimulus step IDs mismatch")
    if [x.get("logicalAction") for x in expected] != ACT:
        raise ValueError("stimulus logical actions mismatch")
    if [x.get("id") for x in actual or []] != IDS or [x.get("logicalAction") for x in actual or []] != ACT:
        raise ValueError("Mac step plan does not join stimulus")
    if steps.get("launchArgs") != ["--fixture", "F1"] or stimulus.get("fixtureId") != "F1":
        raise ValueError("F1 fixture launch join mismatch")
    return {"steps": step_path, "stimulus": stim_path,
            "stimulusSha256": plans["stimulusSha256"], "stepsSha256": plans["stepsSha256"]}


def receipt_join(repo: Path, packet: dict[str, Any]) -> dict[str, Any]:
    rec = packet["recorder"]
    sign = existing(repo / rec["signReceiptPath"], "sign receipt")
    signing = obj(sign)
    if signing.get("identity") != rec["identity"]:
        raise ValueError("sign receipt identity mismatch")
    files = signing.get("files")
    if not isinstance(files, list) or len(files) != 1 or files[0].get("codesign") != "strict-valid":
        raise ValueError("sign receipt does not prove strict validity")
    if files[0].get("identity") != rec["identity"] or files[0].get("timestampPresent") is not True:
        raise ValueError("sign receipt timestamp/identity mismatch")
    fixture = existing(repo / packet["macFixture"]["path"], "Mac FixtureApp")
    if digest(fixture) != packet["macFixture"]["sha256"] or fixture.stat().st_size != packet["macFixture"]["bytes"]:
        raise ValueError("Mac FixtureApp hash/size mismatch")
    manifest = existing(repo / packet["sourceManifestPath"], "Mac source manifest")
    if digest(manifest) != packet["sourceManifestSha256"]:
        raise ValueError("Mac source manifest hash mismatch")
    return {"signReceipt": {"path": str(sign), "sha256": digest(sign)},
            "fixture": {"path": str(fixture), "sha256": digest(fixture), "bytes": fixture.stat().st_size},
            "sourceManifest": {"path": str(manifest), "sha256": digest(manifest)}}


def capture_join(path: Path, packet: dict[str, Any]) -> dict[str, Any]:
    """Check fresh-run native input receipt; packet remains usable for review."""
    cap = obj(existing(path, "capture receipt"))
    inputs = {x.get("label"): x for x in cap.get("nativeInputs", []) if isinstance(x, dict)}
    expected = {
        "FixtureApp": (packet["macFixture"]["sha256"], packet["macFixture"]["bytes"]),
        "F1MacRecord": (packet["recorder"]["binarySha256"], packet["recorder"]["bytes"]),
        "F1Assemble": (packet["assembler"]["binarySha256"], packet["assembler"]["bytes"]),
    }
    for label, (sha, size) in expected.items():
        row = inputs.get(label)
        if not isinstance(row, dict) or row.get("sha256", "").lower() != sha.lower() or row.get("bytes") != size:
            raise ValueError(f"capture receipt {label} hash/size mismatch")
    if cap.get("sourceCommit") != "0e201571e4320a3b6ccce14313fd2ad67e523904":
        raise ValueError("capture receipt source commit mismatch")
    return {"path": str(path), "sha256": digest(path), "sourceCommit": cap["sourceCommit"], "inputs": expected}


def run_check(case: Path, plan_hash: str, run: int, flat: bool) -> tuple[dict[str, Any], list[str]]:
    failures: list[str] = []
    suffix = f"-n{run}" if flat else ""
    raw_path = case / f"mac-raw{suffix}.json"
    ev_path = case / f"mac-ev{suffix}.jsonl"
    trace_path = case / f"mac-trace{suffix}.json"
    log_path = case / f"mac-rec{suffix}.log"
    for p in (raw_path, ev_path, trace_path, log_path):
        if not p.is_file() or p.is_symlink(): failures.append(f"missing:{p.name}")
    if failures: return {"case": case.name}, failures
    try:
        raw, trace = obj(raw_path), obj(trace_path)
        events = [json.loads(line) for line in ev_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"case": case.name}, [f"read:{exc}"]
    if raw.get("allOK") is not True: failures.append("raw-allOK")
    if raw.get("platform", {}).get("os") != "macos": failures.append("raw-platform")
    if raw.get("pid", 0) <= 0: failures.append("raw-pid")
    raw_steps = raw.get("steps", [])
    if [x.get("id") for x in raw_steps] != IDS or [x.get("logicalAction") for x in raw_steps] != ACT: failures.append("raw-steps")
    if trace.get("schemaVersion") != "sr0-o.trace/v0" or trace.get("fixtureId") != "F1": failures.append("trace-header")
    if trace.get("sourceHash") != f"sha256:{plan_hash}": failures.append("trace-source-hash")
    if trace.get("platform", {}).get("os") != "macos": failures.append("trace-platform")
    trace_steps = trace.get("steps", [])
    if [x.get("id") for x in trace_steps] != IDS or [x.get("logicalAction") for x in trace_steps] != ACT: failures.append("trace-steps")
    observations = trace.get("observations", [])
    if len(observations) != 5: failures.append("trace-observation-count")
    expected_model = {"initial": (ROW5, "Row 5"), "focus_row5": (ROW5, "Row 5"),
                      "type_abc": (ROW5, "Row 5abc"), "engine_insert_above": (ROW99, "Engine 0"),
                      "type_d": (ROW5, "Row 5abcd")}
    for obs in observations:
        step = obs.get("stepId")
        if step not in expected_model: failures.append(f"unknown-step:{step}"); continue
        key, value = expected_model[step]
        if obs.get("model", {}).get(key) != value: failures.append(f"model:{step}")
        if step != "initial" and obs.get("focusedNodeId") != ROW5 + "/field": failures.append(f"focus:{step}")
    if not events: failures.append("events-empty")
    if any(e.get("fixture") != "F1" for e in events if isinstance(e, dict)): failures.append("event-fixture")
    if "steps=5 ok=true" not in log_path.read_text(encoding="utf-8"): failures.append("recorder-log")
    return {"case": f"n{run}", "rawSha256": digest(raw_path), "eventsSha256": digest(ev_path),
            "traceSha256": digest(trace_path), "logSha256": digest(log_path)}, failures


def collect(root: Path, plan_hash: str) -> dict[str, Any]:
    flat = (root / "mac-raw-n1.json").is_file()
    cases = []
    for n in range(1, 21):
        d = root if flat else root / f"n{n}"
        if (d / (f"mac-raw-n{n}.json" if flat else "mac-raw.json")).is_file() and not d.is_symlink(): cases.append((n, d))
    rows, failures = [], []
    for n, case in cases:
        row, errors = run_check(case, plan_hash, n, flat); rows.append(row)
        if errors: failures.append({"case": f"n{n}", "failures": errors})
    if len(cases) != 20: failures.append({"root": ".", "failures": [f"observed-runs={len(cases)} required=20"]})
    passed = len(rows) - len(failures)
    return {"status": "qualified" if len(cases) == 20 and not failures else "incomplete",
            "requiredRuns": 20, "observedRuns": len(cases), "passedRuns": passed,
            "runs": rows, "failures": failures}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, required=True)
    ap.add_argument("--root", type=Path, required=True, help="fresh F1 output containing n1..n20 directories")
    ap.add_argument("--capture-receipt", type=Path, required=True)
    ap.add_argument("--packet", type=Path, default=Path(__file__).with_name("tuple12-mac-f1-packet.json"))
    ap.add_argument("--out", type=Path)
    ns = ap.parse_args()
    try:
        repo, root = directory(ns.repo, "repo"), directory(ns.root, "capture root")
        packet_path = existing(ns.packet, "source packet")
        packet = obj(packet_path)
        if packet.get("kind") != "sr0-tuple12-mac-f1-source-packet-v1": raise ValueError("packet kind mismatch")
        if not HEX40.fullmatch(packet["candidate"]["sourceCommit"]): raise ValueError("candidate source commit malformed")
        plan = plan_join(repo, packet)
        joins = receipt_join(repo, packet)
        capture = capture_join(ns.capture_receipt, packet)
        report = collect(root, plan["stimulusSha256"])
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"ASSEMBLY_FAIL {exc}", file=sys.stderr); return 2
    report.update({"kind": "sr0-tuple12-mac-f1-report-v1", "fixture": "F1",
                   "candidate": packet["candidate"], "macPlans": packet["macPlans"],
                   "recorder": packet["recorder"], "joins": {**joins, "capture": capture},
                   "fullMatrix": packet["recorder"]["generalized16"],
                   "admission": "F1-only; full 16-config matrix held pending generalized signer no-prompt proof"})
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if ns.out:
        out = ns.out.expanduser()
        if not out.is_absolute() or out.exists() or out.is_symlink(): raise ValueError("output must be fresh absolute non-symlink")
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("x", encoding="utf-8", newline="") as stream: stream.write(encoded)
    print(encoded, end="")
    return 0 if report["status"] == "qualified" else 1


if __name__ == "__main__": raise SystemExit(main())
