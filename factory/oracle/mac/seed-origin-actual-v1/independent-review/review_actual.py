#!/usr/bin/env python3
"""Independent offline review of fresh Mac seed-origin actual-v1 evidence.

No compiler, capture host, GUI, network, or source producer is invoked here.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

SCRATCH = "/Users/adrdsouza/Library/Caches/SwiftRightFactory/seed-origin-actual-v1-20261011/"
ZERO = "sha256:" + "0" * 64


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def fail(msg: str) -> None:
    raise AssertionError(msg)


def data(path: Path):
    return json.loads(path.read_text())


def canonical_sha(path: Path) -> str:
    value = data(path)
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def assert_internal(path: str, label: str) -> None:
    path.startswith(SCRATCH) or fail(f"{label} leaves internal scratch: {path}")


def assert_no_prompt(value, label: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() == "permissionrequests" and child is not False:
                fail(f"{label} permissionRequests={child!r}")
            assert_no_prompt(child, f"{label}/{key}")
    elif isinstance(value, list):
        for i, child in enumerate(value):
            assert_no_prompt(child, f"{label}/{i}")


def load_verifier(root: Path):
    spec = importlib.util.spec_from_file_location("actual_v1_verify", root / "verify_actual.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def replace_json(path: Path, value) -> None:
    # Replay tree uses hardlinks; unlink before writing so producer evidence stays untouched.
    path.unlink()
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")


def replay_controls(root: Path) -> dict[str, str]:
    verifier = load_verifier(root)
    controls: dict[str, str] = {}
    with tempfile.TemporaryDirectory(prefix="seed-origin-actual-v1-review-") as td:
        replay = Path(td) / "capture"
        shutil.copytree(root, replay, copy_function=os.link)
        controls["positive"] = "PASS" if verifier.validate(replay)["runs"] == 100 else "FAIL"

        def rejected(name: str, mutate) -> None:
            mutate(replay)
            try:
                verifier.validate(replay)
            except Exception:
                controls[name] = "PASS"
            else:
                controls[name] = "FAIL"

        rejected("missing-run", lambda d: _drop_run(d))
        # Each mutation starts from already-mutated metadata only after prior rejection.
        # Restore replay by rebuilding hardlinks, preserving bounded six-control scope.
        shutil.rmtree(replay)
        shutil.copytree(root, replay, copy_function=os.link)
        rejected("pid-pgid-mismatch", lambda d: _pid_mismatch(d))
        shutil.rmtree(replay)
        shutil.copytree(root, replay, copy_function=os.link)
        rejected("source-drift", lambda d: _source_drift(d))
        shutil.rmtree(replay)
        shutil.copytree(root, replay, copy_function=os.link)
        rejected("tool-drift", lambda d: _tool_drift(d))
        shutil.rmtree(replay)
        shutil.copytree(root, replay, copy_function=os.link)
        rejected("ax-binary-join", lambda d: _ax_binary_join(d))
    return controls


def _lineage(d: Path) -> dict:
    return data(d / "lineage.json")


def _drop_run(d: Path) -> None:
    p = d / "lineage.json"
    x = _lineage(d)
    x["cases"][0]["runs"].pop()
    replace_json(p, x)


def _pid_mismatch(d: Path) -> None:
    cid = _lineage(d)["cases"][0]["caseId"]
    p = d / cid / "compiler-receipt.json"
    x = data(p)
    x["compiler"]["pgid"] += 1
    replace_json(p, x)


def _source_drift(d: Path) -> None:
    p = d / "lineage.json"
    x = _lineage(d)
    x["cases"][0]["sourceBindings"][0]["sourceAfter"]["sha256"] = ZERO
    replace_json(p, x)


def _tool_drift(d: Path) -> None:
    cid = _lineage(d)["cases"][0]["caseId"]
    p = d / cid / "compiler-receipt.json"
    x = data(p)
    x["compiler"]["realToolAfter"]["sha256"] = ZERO
    replace_json(p, x)


def _ax_binary_join(d: Path) -> None:
    p = d / "ax-compiler-receipt.json"
    x = data(p)
    x["compiler"]["outputBinary"]["sha256"] = ZERO
    replace_json(p, x)


def review(root: Path) -> dict:
    root = root.resolve()
    lineage = data(root / "lineage.json")
    lineage["candidateOnly"] is True or fail("candidateOnly missing")
    lineage["captureRun"] is True or fail("captureRun missing")
    lineage["status"] == "CAPTURED_CANDIDATE_NOT_PROMOTED" or fail("promotion status")
    lineage["caseCount"] == 5 and lineage["runsPerCase"] == 20 and lineage["totalRuns"] == 100 or fail("denominator")

    stage_path = root / "stage-manifest.json"
    stage = data(stage_path)
    sha(stage_path) == "sha256:419f334b675f6d19de5db82a4636bf6360c97100834f123cad95cb6b9bb8f832" or fail("stage pin")
    len(stage["entries"]) == 2109 or fail("stage count")
    amap = data(root / "archive-map.json")
    amap["files"] and len(amap["files"]) == 2108 or fail("archive map count")
    for entry in amap["files"]:
        path = root / entry["path"]
        path.is_file() or fail(f"archive missing {entry['path']}")
        path.stat().st_size == entry["bytes"] or fail(f"archive bytes {entry['path']}")
        sha(path) == entry["sha256"] or fail(f"archive hash {entry['path']}")

    pins = data(root / "input-snapshot" / "input-pins.json")
    pins["seed"] == lineage["seed"] == 14577611000270672472 or fail("seed")
    pin_by_case = {row["caseID"]: row for row in pins["rows"]}
    len(pin_by_case) == 5 or fail("input pin count")
    capture_index = data(root / "capture-index.json")
    capture_index["candidateOnly"] is True or fail("capture candidate flag")
    index_by_case = {row["case"]["id"]: row for row in capture_index["results"]}
    len(index_by_case) == 5 or fail("capture index count")

    raw_counts = {"plain": 0, "instrumented": 0, "compositor": 0, "externalAX": 0}
    unique_process_rows = 0
    held = {}
    for case in lineage["cases"]:
        cid = case["caseId"]
        row = pin_by_case.get(cid) or fail(f"missing input pin {cid}")
        case["runCount"] == 20 and len(case["runs"]) == 20 or fail(f"run count {cid}")
        row["seed"] == lineage["seed"] or fail(f"seed {cid}")
        case["manifestSha256"] == row["manifest"]["sha256"] or fail(f"manifest hash {cid}")
        case["sourceInputSha256"] == row["source"]["sha256"] or fail(f"source input hash {cid}")
        # Recheck staged source/case/recipe bytes & canonical pins, matching seeded Win5 inputs.
        for k in ("source", "case", "recipe"):
            rel = row[k]["path"].replace("inputs/", "")
            path = root / "input-snapshot" / rel
            path.is_file() or fail(f"input missing {cid}/{k}")
            path.stat().st_size == row[k]["bytes"] or fail(f"input bytes {cid}/{k}")
            if k == "source":
                sha(path) == row[k]["sha256"] or fail(f"source bytes hash {cid}")
            else:
                sha(path) == row[k]["rawSha256"] or fail(f"raw hash {cid}/{k}")
                canonical_sha(path) == row[k]["canonicalSha256"] or fail(f"canonical hash {cid}/{k}")

        receipt_path = root / case["compilerReceiptPath"]
        receipt = data(receipt_path)
        c = receipt["compiler"]
        receipt["status"] == "SUCCESS" and receipt["sourceDrift"] is False or fail(f"receipt {cid}")
        c["exitCode"] == 0 and c["timedOut"] is False and c["pgid"] == c["pid"] and c["ownedProcessGroup"] is True or fail(f"process {cid}")
        case["compilerPid"] == c["pid"] and case["compilerPgid"] == c["pgid"] or fail(f"lineage process join {cid}")
        c["argv"][0] == "/usr/bin/xcrun" and c["argv"][1] == "swiftc" and c["logicalCompilerName"] == "swiftc" or fail(f"compiler argv {cid}")
        c["realToolBefore"] == c["realToolAfter"] and c["realToolDrift"] is False or fail(f"tool drift {cid}")
        case["compilerReceiptSha256"] == sha(receipt_path) or fail(f"receipt hash {cid}")
        assert_internal(c["cwd"], f"cwd {cid}")
        assert_internal(c["outputBinary"]["path"], f"binary output {cid}")
        for arg in c["argv"][5:]:
            assert_internal(arg, f"compiler source/output argv {cid}")
        for stream in ("stdoutPath", "stderrPath"):
            path = Path(c[stream]); path.is_file() or fail(f"stream {cid}/{stream}")
            sha(path) == c[stream.replace("Path", "Hash")] or fail(f"stream hash {cid}/{stream}")
        binary = root / case["binaryPath"]
        binary.is_file() and sha(binary) == case["binarySha256"] == c["outputBinary"]["sha256"] or fail(f"binary {cid}")
        for binding in case["sourceBindings"]:
            source = root / binding["archivePath"]
            source.is_file() and sha(source) == binding["archiveSha256"] == binding["sourceBefore"]["sha256"] == binding["sourceAfter"]["sha256"] or fail(f"source {cid}/{binding['name']}")
            assert_internal(binding["sourceBefore"]["path"], f"source before {cid}/{binding['name']}")
            assert_internal(binding["sourceAfter"]["path"], f"source after {cid}/{binding['name']}")
            binding["unchanged"] is True or fail(f"source unchanged {cid}/{binding['name']}")
        idx = index_by_case[cid]
        idx["status"] == "CANDIDATE_CAPTURED" or fail(f"index status {cid}")
        held[cid] = {k: v for k, v in idx["channels"].items() if "HELD" in v or "NOT_ATTEMPTED" in v}
        for run in case["runs"]:
            n = run["run"]
            run_dir = root / cid / f"run-{n:03d}"
            run_dir.is_dir() or fail(f"run directory {cid}/{n}")
            raws = {}
            for mode in ("plain", "instrumented"):
                path = run_dir / f"{mode}.raw.json"; raw = data(path)
                sha(path) == run[f"{mode}RawHash"] or fail(f"{mode} hash {cid}/{n}")
                raw["pid"] > 0 and raw["status"] in ("OBSERVED", "UNOBSERVED") or fail(f"{mode} process {cid}/{n}")
                raw_counts[mode] += 1; raws[mode] = raw
                assert_no_prompt(raw, f"{cid}/{n}/{mode}")
            for mode in ("compositor", "externalAX"):
                path = run_dir / ("compositor.raw.json" if mode == "compositor" else "external-ax.raw.json")
                raw = data(path); sha(path) == run[f"{mode}RawHash"] or fail(f"{mode} hash {cid}/{n}")
                raw["pid"] > 0 and raw["status"] in ("OBSERVED", "UNOBSERVED") or fail(f"{mode} process {cid}/{n}")
                raw_counts[mode] += 1; raws[mode] = raw
                assert_no_prompt(raw, f"{cid}/{n}/{mode}")
            pids = [raw["pid"] for raw in raws.values()]
            len(set(pids)) == 4 or fail(f"duplicate channel pid {cid}/{n}")
            unique_process_rows += 1
            capture = run_dir / "capture.json"; cap = data(capture)
            sha(capture) == run["captureHash"] or fail(f"capture hash {cid}/{n}")
            cap["meta"]["conditions"]["candidateOnly"] is True or fail(f"capture candidate {cid}/{n}")
            cap["meta"]["conditions"]["observationalOnly"] is True or fail(f"capture observational {cid}/{n}")
            cap["case"]["hash"] == row["case"]["canonicalSha256"] or fail(f"capture case hash {cid}/{n}")
            window = data(run_dir / "owned-window-process.json")
            assert_internal(window["executable"], f"window executable {cid}/{n}")
            window["processGroupOwned"] is True or fail(f"window group {cid}/{n}")
            window["binaryHash"] == case["binarySha256"] or fail(f"window binary join {cid}/{n}")
            client = window["client"]
            assert_internal(client["executable"], f"AX executable {cid}/{n}")
            client["binaryHash"] == lineage["auxiliaryAX"]["binarySha256"] or fail(f"AX binary join {cid}/{n}")
            client["permissionRequests"] is False or fail(f"AX prompt {cid}/{n}")

    ax = lineage["auxiliaryAX"]
    ax_receipt = root / ax["receiptPath"]; ar = data(ax_receipt); ac = ar["compiler"]
    ar["status"] == "SUCCESS" and ac["exitCode"] == 0 and ac["timedOut"] is False and ac["pgid"] == ac["pid"] or fail("AX compiler status")
    ac["argv"][0:2] == ["/usr/bin/xcrun", "swiftc"] or fail("AX compiler argv")
    assert_internal(ac["cwd"], "AX cwd"); assert_internal(ac["outputBinary"]["path"], "AX binary")
    ax_source = root / ax["sourceArchivePath"]; ax_binary = root / ax["binaryArchivePath"]
    ax_source.is_file() and sha(ax_source) == ax["sourceSha256"] == ac["sourceBefore"]["AXClient.swift"]["sha256"] == ac["sourceAfter"]["AXClient.swift"]["sha256"] or fail("AX source join")
    ax_binary.is_file() and sha(ax_binary) == ax["binarySha256"] == ac["outputBinary"]["sha256"] or fail("AX binary join")
    for stream in ("stdoutPath", "stderrPath"):
        path = Path(ac[stream]); path.is_file() or fail(f"AX stream {stream}")
        sha(path) == ac[stream.replace("Path", "Hash")] or fail(f"AX stream hash {stream}")
    fresh = data(root / "fresh-ax-client.json"); fresh["externalAX"] == "AVAILABLE" and fresh["permissionRequests"] is False or fail("fresh AX preflight")
    fresh["compilerStatus"] == "SUCCESS" and fresh["compilerExitCode"] == 0 or fail("fresh AX compile")
    assert_internal(fresh["executable"], "fresh AX executable")
    recorder = data(root / "recorder-capabilities.json")
    recorder["permissionRequests"] is False and recorder["externalAX"] == "HELD" or fail("recorder prompt/state")
    assert_internal(recorder["copiedExecutable"], "recorder executable")

    controls = replay_controls(root)
    all_pass = all(value == "PASS" for value in controls.values())
    all_pass or fail(f"replay controls {controls}")
    return {
        "status": "PASS",
        "stageSha256": sha(stage_path),
        "stageFiles": len(stage["entries"]),
        "archiveFiles": len(amap["files"]),
        "cases": 5,
        "runs": 100,
        "channelRows": raw_counts,
        "uniqueChannelProcessRows": unique_process_rows,
        "compilerPids": sorted(case["compilerPid"] for case in lineage["cases"]),
        "auxiliaryCompilerPid": ax["compilerPid"],
        "sourceInputPins": 5,
        "candidateOnly": True,
        "scrollOffscreen": "HELD",
        "customLayoutExternalAX": "HELD",
        "replayControls": controls,
        "promotion": "BLOCKED: candidateOnly evidence; no parity claim",
        "heldChannels": held,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--stdout", type=Path, required=True)
    parser.add_argument("--stderr", type=Path, required=True)
    args = parser.parse_args()
    started = dt.datetime.now(dt.timezone.utc)
    pid = os.getpid()
    try:
        result = review(args.root)
        review_dir = args.root / "independent-review"
        review_dir.mkdir(exist_ok=True)
        (review_dir / "review-report.json").write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
        print(json.dumps(result, sort_keys=True, indent=2))
        exit_code = 0
    except Exception as exc:
        print(f"FAIL: {exc}")
        exit_code = 1
    sys.stdout.flush(); sys.stderr.flush()
    ended = dt.datetime.now(dt.timezone.utc)
    tool = Path(sys.executable)
    receipt = {
        "kind": "seed-origin-actual-v1-independent-review-process-receipt",
        "argv": sys.argv,
        "cwd": os.getcwd(),
        "pid": pid,
        "pgid": os.getpgid(pid),
        "startedAtUtc": started.isoformat(),
        "endedAtUtc": ended.isoformat(),
        "exitCode": exit_code,
        "tool": {"path": str(tool), "sha256": sha(tool) if tool.is_file() else None},
        "stdoutPath": str(args.stdout.resolve()),
        "stderrPath": str(args.stderr.resolve()),
    }
    receipt["stdoutSha256"] = sha(args.stdout) if args.stdout.is_file() else None
    receipt["stderrSha256"] = sha(args.stderr) if args.stderr.is_file() else None
    review_dir = args.root / "independent-review"
    review_dir.mkdir(exist_ok=True)
    (review_dir / "independent-review-process-receipt.json").write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
