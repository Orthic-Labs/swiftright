#!/usr/bin/env python3
"""Source controls for Rectangle normalizer joins; writes no captures."""
from __future__ import annotations

import argparse
import copy
from pathlib import Path

from normalize_rectangle_runs_r1 import load_json, normalize_one, validate_inputs


def expect_reject(label, callback):
    try:
        callback()
    except Exception:
        return {"name": label, "rejected": True}
    raise AssertionError(f"fault accepted: {label}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--case", type=Path, required=True)
    args = parser.parse_args()
    summary = load_json(args.summary)
    manifest = load_json(args.manifest)
    case = load_json(args.case)
    validate_inputs(summary, manifest, case)
    rows = summary["runs"]
    channels = summary.get("channels") or {}
    rejected = []

    wrong_host = copy.deepcopy(summary)
    wrong_host["binaryHash"] = "sha256:" + "0" * 64
    rejected.append(expect_reject("summary-binary-host-join", lambda: validate_inputs(wrong_host, manifest, case)))

    wrong_tuple = copy.deepcopy(case)
    wrong_tuple["tuple"]["hostHashes"]["macos"] = "sha256:" + "1" * 64
    rejected.append(expect_reject("tuple-host-join", lambda: validate_inputs(summary, manifest, wrong_tuple)))

    wrong_source = copy.deepcopy(summary)
    wrong_source["sourceHash"] = "sha256:" + "2" * 64
    rejected.append(expect_reject("source-hash-join", lambda: validate_inputs(wrong_source, manifest, case)))

    run_dir = args.summary.parent / f"run-{rows[0]['run']:03d}"
    wrong_pid = copy.deepcopy(rows[0])
    wrong_pid["instrumented"]["pid"] += 1
    rejected.append(expect_reject("instrumented-pid-join", lambda: normalize_one(run_dir, wrong_pid, manifest, case, channels, summary["binaryHash"])))

    wrong_raw = copy.deepcopy(rows[0])
    wrong_raw["instrumented"]["rawHash"] = "sha256:" + "3" * 64
    rejected.append(expect_reject("instrumented-raw-hash-join", lambda: normalize_one(run_dir, wrong_raw, manifest, case, channels, summary["binaryHash"])))

    print({"status": "SOURCE_CONTROLS_DEFINED", "baseline": "validate_inputs", "faultControls": rejected})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
