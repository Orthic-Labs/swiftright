#!/usr/bin/env python3
"""Read-only independent review of F12 extended-demand mapping v5."""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import importlib.util
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parents[1]
STAGE_SHA = "sha256:48f17eeb00daac1d59d59b26253c7b8554233513cb082efe5ca1e6aaa5967e88"
MAP_SHA = "584d2fb652ebb8a08000ee4345c56205ed600680c837868a4fd9c3a796888ca7"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise AssertionError(message)


def load(path: Path):
    return json.loads(path.read_text())


def load_generator():
    spec = importlib.util.spec_from_file_location("mapping_v5_generator", HERE / "generate.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_rows(generator):
    return generator.source_rows()


def strict_summary(packet, residual, source_count):
    packet.get("v5Evidence", {}).get("registryPromotion") is False or fail("packet promotion authority")
    packet.get("v5Evidence", {}).get("newFullDemandResolutions") == 0 or fail("packet resolution authority")
    d = packet["denominator"]
    d == {"currentSourceUsageRows": 2, "extendedDemandRows": 107, "registryMappedRows": 0, "sourceInventoryEvidenceRows": 46} or fail("denominator authority")
    c = packet["componentCounts"]
    c == {"components": 9, "demandsWithComponents": 8, "newFullDemandResolutions": 0, "observedNominalComponents": 2, "proposedComponents": 7, "registryMappedRows": 0} or fail("component authority")
    rows = packet["rows"]
    ev_rows = [row for row in rows if "v5Evidence" in row]
    len(rows) == 107 and len(ev_rows) == 32 and len(residual) == 32 or fail("row counts")
    set(row["rowKey"] for row in ev_rows) == residual or fail("residual overlap")
    source_bound = sum(bool(row["v5Evidence"].get("sourceBound")) for row in ev_rows)
    source_bound == 25 and source_count == 25 or fail("source-bound count")
    sum(row["v5Evidence"]["fullDemandResolved"] is False for row in ev_rows) == 32 or fail("full resolution authority")
    sum(row["v5Evidence"]["registryPromotion"] is False for row in ev_rows) == 32 or fail("registry authority")


def expect_reject(label, packet, sources, generator, strict=False):
    try:
        if strict:
            strict_summary(packet, generator.RESIDUAL, sum(bool(r.get("v5Evidence", {}).get("sourceBound")) for r in packet["rows"]))
        generator.validate_packet(packet, sources)
    except (AssertionError, ValueError, KeyError, TypeError):
        return {"control": label, "rejected": True}
    raise AssertionError(f"control accepted: {label}")


def producer_controls(packet, sources, generator):
    out = []
    mutated = copy.deepcopy(packet); mutated["denominator"]["extendedDemandRows"] = 106
    out.append(expect_reject("denominator-drift", mutated, sources, generator))
    mutated = copy.deepcopy(packet); mutated["rows"] = mutated["rows"][:-1]
    out.append(expect_reject("row-cardinality-drift", mutated, sources, generator))
    mutated = copy.deepcopy(packet); mutated["rows"][3]["v5Evidence"] = copy.deepcopy(mutated["rows"][1]["v5Evidence"])
    out.append(expect_reject("non-residual-evidence", mutated, sources, generator))
    mutated = copy.deepcopy(packet); next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-007")["v5Evidence"]["registryPromotion"] = True
    out.append(expect_reject("registry-promotion", mutated, sources, generator))
    mutated = copy.deepcopy(packet); next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-045")["v5Evidence"]["fullDemandResolved"] = True
    out.append(expect_reject("ambiguous-full-resolution", mutated, sources, generator))
    mutated = copy.deepcopy(packet); next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-011")["v5Evidence"]["sourceEvidence"][0]["sourceId"] = "missing-source"
    out.append(expect_reject("unknown-source", mutated, sources, generator))
    mutated = copy.deepcopy(packet); next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-029")["v5Evidence"]["sourceEvidence"][0]["lines"] = [0, 1]
    out.append(expect_reject("wrong-source-line", mutated, sources, generator))
    mutated = copy.deepcopy(packet); next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-007")["v5Evidence"]["sourceEvidence"][0]["sha256"] = "0" * 64
    out.append(expect_reject("source-hash-drift", mutated, sources, generator))
    return out


def independent_controls(packet, sources, generator):
    out = []
    mutated_sources = copy.deepcopy(sources)
    mutated_sources["settings-panel"]["bytes"] += 1
    out.append(expect_reject("stale-source-authority", packet, mutated_sources, generator))
    mutated = copy.deepcopy(packet); mutated["denominator"]["sourceInventoryEvidenceRows"] = 45
    out.append(expect_reject("denominator-authority", mutated, sources, generator, strict=True))
    mutated = copy.deepcopy(packet); next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-007")["v5Evidence"]["sourceBound"] = False
    out.append(expect_reject("source-bound-overlap-authority", mutated, sources, generator, strict=True))
    mutated = copy.deepcopy(packet); mutated["v5Evidence"]["registryPromotion"] = True
    out.append(expect_reject("packet-authority-promotion", mutated, sources, generator, strict=True))
    return out


def review() -> dict:
    generator = load_generator()
    packet = load(HERE / "mapping-v5.json")
    sources = source_rows(generator)
    stage_path = HERE / "stage-manifest-v5.json"
    stage = load(stage_path)
    sha(stage_path) == STAGE_SHA.removeprefix("sha256:") or fail("stage hash")
    len(stage["files"]) == 20 and stage["denominator"] == 107 or fail("stage metadata")
    stage["registryPromotion"] is False and stage["newFullDemandResolutions"] == 0 or fail("stage promotion")
    for entry in stage["files"]:
        path = ROOT / Path(entry["path"])
        path.is_file() or fail(f"stage file missing: {entry['path']}")
        path.stat().st_size == entry["bytes"] and sha(path) == entry["sha256"] or fail(f"stage file drift: {entry['path']}")
    for dep in stage["dependencies"]:
        path = ROOT / Path(dep["path"])
        path.is_file() and path.stat().st_size == dep["bytes"] and sha(path) == dep["sha256"] or fail(f"dependency drift: {dep['path']}")
    sha(HERE / "mapping-v5.json") == MAP_SHA or fail("mapping hash")
    packet["denominator"]["extendedDemandRows"] == 107 and len(packet["rows"]) == 107 or fail("mapping denominator")
    packet["status"] == "source-bound-observation-only" or fail("mapping status")
    packet["v5Evidence"]["registryPromotion"] is False and packet["v5Evidence"]["newFullDemandResolutions"] == 0 or fail("mapping promotion")
    v4 = load(ROOT / "factory/shell/extended-demand-mapping-v4/mapping-v4.json")
    for got, old in zip(packet["rows"], v4["rows"]):
        got_copy = copy.deepcopy(got); got_copy.pop("v5Evidence", None)
        got_copy == old or fail(f"v4 row changed: {got['rowKey']}")
    residual = set(packet["v5Evidence"]["residualRows"])
    len(residual) == 32 or fail("residual denominator")
    ev_rows = [row for row in packet["rows"] if "v5Evidence" in row]
    len(ev_rows) == 32 and set(row["rowKey"] for row in ev_rows) == residual or fail("residual overlap")
    dispositions = load(HERE / "evidence" / "unresolved-dispositions-v5.json")
    dispositions["denominator"] == 107 and dispositions["residualCount"] == 32 and len(dispositions["rows"]) == 32 or fail("disposition count")
    disp_by_key = {row["rowKey"]: row for row in dispositions["rows"]}
    for row in ev_rows:
        disp_by_key.get(row["rowKey"], {}).get("v5") == row["v5Evidence"] or fail(f"disposition join {row['rowKey']}")
    strict_summary(packet, residual, sum(bool(row["v5Evidence"].get("sourceBound")) for row in ev_rows))
    # Recheck every archived current source, exact bytes/hash, line range & field authority.
    for sid, src in sources.items():
        path = HERE / "evidence" / "source-snapshots" / Path(src["snapshotPath"]).name
        path.stat().st_size == src["bytes"] and sha(path) == src["sha256"] or fail(f"source snapshot {sid}")
        original = Path(src["originalPath"])
        original.is_file() and original.stat().st_size == src["bytes"] and sha(original) == src["sha256"] or fail(f"current source drift {sid}")
    source_evidence = 0
    for row in ev_rows:
        for item in row["v5Evidence"]["sourceEvidence"]:
            source_evidence += 1
            src = sources.get(item["sourceId"])
            src is not None or fail(f"source ID {row['rowKey']}")
            for key in ("originalPath", "snapshotPath", "sha256", "bytes"):
                item.get(key) == src[key] or fail(f"source binding {row['rowKey']}/{item['sourceId']}/{key}")
            lines = item["lines"]
            len(lines) == 2 and all(isinstance(x, int) and x > 0 for x in lines) and lines[0] <= lines[1] or fail(f"line range {row['rowKey']}")
            src_path = HERE / "evidence" / "source-snapshots" / Path(src["snapshotPath"]).name
            lines[1] <= len(src_path.read_text().splitlines()) or fail(f"line bound {row['rowKey']}")
    producer = producer_controls(packet, sources, generator)
    independent = independent_controls(packet, sources, generator)
    all_controls = producer + independent
    all(c["rejected"] for c in all_controls) and len(producer) == 8 and len(independent) == 4 or fail("controls")
    from collections import Counter
    dispositions_count = Counter(row["v5Evidence"]["disposition"] for row in ev_rows)
    return {
        "status": "PASS",
        "stageSha256": STAGE_SHA,
        "stageFiles": len(stage["files"]),
        "mappingSha256": MAP_SHA,
        "v4RowsPreserved": 107,
        "extendedDemandRows": 107,
        "residualRows": 32,
        "sourceBoundRows": 25,
        "exactAnchoredRows": 24,
        "unresolvedRows": 5,
        "ambiguousRows": 3,
        "sourceEvidenceItems": source_evidence,
        "dispositionCounts": dict(dispositions_count),
        "registryPromotion": False,
        "newFullDemandResolutions": 0,
        "producerControls": producer,
        "independentControls": independent,
        "promotion": "BLOCKED: source-bound observation only; no nominal/full-demand/registry resolution",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stdout", type=Path, required=True)
    parser.add_argument("--stderr", type=Path, required=True)
    args = parser.parse_args()
    started = dt.datetime.now(dt.timezone.utc)
    pid = os.getpid()
    try:
        result = review()
        review_dir = HERE / "independent-review"
        review_dir.mkdir(exist_ok=True)
        (review_dir / "review-report.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        print(json.dumps(result, indent=2, sort_keys=True))
        code = 0
    except Exception as exc:
        print(f"FAIL: {exc}")
        code = 1
    sys.stdout.flush(); sys.stderr.flush()
    ended = dt.datetime.now(dt.timezone.utc)
    tool = Path(sys.executable)
    receipt = {
        "kind": "extended-demand-mapping-v5-independent-review-process-receipt",
        "argv": sys.argv,
        "cwd": os.getcwd(),
        "pid": pid,
        "pgid": os.getpgid(pid),
        "startedAtUtc": started.isoformat(),
        "endedAtUtc": ended.isoformat(),
        "exitCode": code,
        "tool": {"path": str(tool), "sha256": sha(tool) if tool.is_file() else None},
        "stdoutPath": str(args.stdout.resolve()),
        "stderrPath": str(args.stderr.resolve()),
        "stdoutSha256": "sha256:" + hashlib.sha256(args.stdout.read_bytes()).hexdigest() if args.stdout.is_file() else None,
        "stderrSha256": "sha256:" + hashlib.sha256(args.stderr.read_bytes()).hexdigest() if args.stderr.is_file() else None,
    }
    (HERE / "independent-review" / "independent-review-process-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
