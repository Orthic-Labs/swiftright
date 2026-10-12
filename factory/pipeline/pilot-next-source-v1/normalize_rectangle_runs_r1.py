#!/usr/bin/env python3
"""Derive fresh Rectangle captures from one sealed 20-run Mac summary."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import time
from datetime import datetime, timezone
from pathlib import Path

from factory.core.artifacts import canonical_hash, validate_artifact, write_artifact

MAX_JSON = 2 * 1024 * 1024
MAX_BINARY = 64 * 1024 * 1024
HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
RUNS = 20


def _regular(path: Path, limit: int) -> int:
    if path.is_symlink():
        raise ValueError(f"symlink rejected: {path}")
    stat = path.stat()
    if not path.is_file() or stat.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return stat.st_size


def load_json(path: Path) -> dict:
    _regular(path, MAX_JSON)
    value = json.loads(path.read_bytes())
    if not isinstance(value, dict):
        raise ValueError(f"object JSON required: {path}")
    return value


def stream_hash(path: Path, limit: int = MAX_BINARY) -> str:
    _regular(path, limit)
    digest = hashlib.sha256()
    deadline = time.monotonic() + 30
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            if time.monotonic() > deadline:
                raise ValueError(f"hash deadline exceeded: {path}")
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def measured(value):
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, list):
        return [measured(item) for item in value]
    if isinstance(value, dict):
        return {key: measured(item) for key, item in value.items()}
    return value


def image_record(run_dir: Path, name: str, raw: dict, expected: str | None) -> dict | None:
    raw_path = run_dir / f"{name}.raw.json"
    png_path = run_dir / f"{name}.png"
    if not raw_path.exists() or not png_path.exists():
        return None
    raw_value = load_json(raw_path)
    actual_raw = stream_hash(raw_path, MAX_JSON)
    if expected and actual_raw != expected:
        raise ValueError(f"{name} raw hash mismatch in {run_dir}")
    if raw_value.get("status") != "OBSERVED":
        return None
    image = raw_value.get("image")
    if not isinstance(image, dict):
        raise ValueError(f"{name} image missing in {run_dir}")
    png_hash = stream_hash(png_path)
    return {
        "id": f"macos.{name}",
        "hash": png_hash,
        "widthPx": image["width"],
        "heightPx": image["height"],
        "captureScale": measured(image["scale"]),
    }


def validate_inputs(summary: dict, manifest: dict, case: dict) -> None:
    if summary.get("kind") != "macos-host-capture-candidate":
        raise ValueError("unexpected Mac summary kind")
    if manifest.get("case", {}).get("id") != case.get("id"):
        raise ValueError("manifest/case ID mismatch")
    if manifest.get("case", {}).get("hash") != canonical_hash(case):
        raise ValueError("manifest/case hash mismatch")
    if summary.get("case") != manifest["case"]:
        raise ValueError("summary/case binding mismatch")
    source_hash = case.get("witness", {}).get("sourceHash")
    if not HASH.fullmatch(str(source_hash)) or summary.get("sourceHash") != source_hash:
        raise ValueError("source hash binding mismatch")
    binary_hash = summary.get("binaryHash")
    if not HASH.fullmatch(str(binary_hash)):
        raise ValueError("binary hash is not measured")
    tuple_value = case.get("tuple")
    if not isinstance(tuple_value, dict) or not HASH.fullmatch(str(tuple_value.get("hostHashes", {}).get("macos"))):
        raise ValueError("Mac host hash missing from tuple")
    if binary_hash != tuple_value["hostHashes"]["macos"]:
        raise ValueError("summary binary hash does not equal tuple Mac host hash")
    if manifest.get("tupleId") != tuple_value.get("id"):
        raise ValueError("manifest/tuple binding mismatch")
    geometry = manifest.get("channels", {}).get("geometry")
    if not isinstance(geometry, list) or len(geometry) != 1 or not geometry[0].get("probeTag"):
        raise ValueError("explicit geometry channel declaration required")
    runs = summary.get("runs")
    if not isinstance(runs, list) or len(runs) != RUNS:
        raise ValueError("exactly 20 summary runs required")
    if [row.get("run") for row in runs] != list(range(1, RUNS + 1)):
        raise ValueError("summary runs must remain ordered 1..20")
    pids = [row.get("instrumented", {}).get("pid") for row in runs]
    if any(not isinstance(pid, int) for pid in pids) or len(set(pids)) != RUNS:
        raise ValueError("instrumented owner PIDs must be distinct across 20 runs")


def normalize_one(run_dir: Path, row: dict, manifest: dict, case: dict, channels: dict, binary_hash: str) -> dict:
    raw_path = run_dir / "instrumented.raw.json"
    raw = load_json(raw_path)
    actual_raw_hash = stream_hash(raw_path, MAX_JSON)
    expected_raw_hash = row.get("instrumented", {}).get("rawHash")
    if actual_raw_hash != expected_raw_hash:
        raise ValueError(f"instrumented raw hash mismatch in run {row['run']}")
    if raw.get("status") != "OBSERVED" or not isinstance(raw.get("pid"), int):
        raise ValueError(f"instrumented observation invalid in run {row['run']}")
    if raw["pid"] != row.get("instrumented", {}).get("pid"):
        raise ValueError(f"instrumented PID mismatch in run {row['run']}")
    if row.get("instrumented", {}).get("status") != "OBSERVED":
        raise ValueError(f"summary instrumented status invalid in run {row['run']}")
    if not isinstance(raw.get("monoStartNs"), int) or not isinstance(raw.get("monoEndNs"), int):
        raise ValueError(f"raw timing missing in run {row['run']}")
    if raw["monoStartNs"] < 0 or raw["monoEndNs"] < raw["monoStartNs"]:
        raise ValueError(f"raw timing range invalid in run {row['run']}")
    clock = {"clockId": "macos.dispatch.uptime", "startNs": raw["monoStartNs"], "endNs": raw["monoEndNs"], "scope": "same-process render interval only"}
    images = []
    for name in ("plain", "instrumented", "compositor"):
        expected = row.get(name, {}).get("rawHash") if name != "compositor" else row.get("compositorRawHash")
        record = image_record(run_dir, name, raw, expected)
        if record:
            expected_png = row.get(name, {}).get("pngHash") if name != "compositor" else row.get("compositorPngHash")
            if expected_png and record["hash"] != expected_png:
                raise ValueError(f"{name} PNG hash mismatch in run {row['run']}")
            images.append(record)
    placements = raw.get("rootLayout", {}).get("placements", [])
    for placement in placements:
        if not isinstance(placement, dict):
            raise ValueError(f"layout placement invalid in run {row['run']}")
        frame = placement.get("frame", placement)
        if not isinstance(frame, dict):
            raise ValueError(f"layout frame missing in run {row['run']}")
        for key in ("x", "y", "width", "height"):
            if key not in frame:
                continue
            value = frame[key]
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError(f"layout frame {key} is not numeric in run {row['run']}")
            if isinstance(value, float) and not math.isfinite(value):
                raise ValueError(f"layout frame {key} is non-finite in run {row['run']}")
            if value < 0:
                raise ValueError(f"layout frame {key} is negative in run {row['run']}")
    layout = []
    if placements:
        layout = [{"probeTag": manifest["channels"]["geometry"][0]["probeTag"], "viewIdentity": manifest["witness"]["id"], "frame": measured(placements[-1])}]
    capture = {
        "kind": "capture", "version": "0.1",
        "id": f"{case['id']}.macos.run-{row['run']:03d}",
        "provenance": {"sourceHash": actual_raw_hash, "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "producer": "factory/pipeline/pilot-next-source-v1/normalize_rectangle_runs_r1", "inputs": [{"id": "macos.capture.binary", "hash": binary_hash}]},
        "case": manifest["case"], "platform": "macos", "tuple": case["tuple"],
        "meta": {"run": row["run"], "host": {"id": "factory.host.macos.measured", "hash": case["tuple"]["hostHashes"]["macos"]}, "conditions": {"candidateOnly": True, "observationalOnly": True, "channelStatus": channels, "clockScope": clock["scope"], "caseInputs": case["inputs"], "shapeAX": "UNAVAILABLE_OR_HELD", "rawHashesValidated": True}, "clock": {"clockId": clock["clockId"], "correlationHash": canonical_hash(clock)}},
        "layout": layout, "ax": [], "events": [{"id": "offscreen.begin", "kind": "capture-render-begin", "timeNs": clock["startNs"], "clockId": clock["clockId"]}, {"id": "offscreen.end", "kind": "capture-render-end", "timeNs": clock["endNs"], "clockId": clock["clockId"]}], "anim": [], "images": images, "text": []
    }
    validate_artifact(capture)
    return capture


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--case", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    summary = load_json(args.summary)
    manifest = load_json(args.manifest)
    case = load_json(args.case)
    validate_inputs(summary, manifest, case)
    source_root = args.summary.parent
    output = args.output.expanduser()
    if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise ValueError("output must be fresh")
    channels = summary.get("channels") or {"offscreenPaint": "OBSERVED", "rootHostGeometry": "OBSERVED", "externalAX": "HELD_OR_UNAVAILABLE", "compositorPaint": "OBSERVED"}
    derived = []
    for row in summary["runs"]:
        run_dir = source_root / f"run-{row['run']:03d}"
        if not run_dir.is_dir() or run_dir.is_symlink():
            raise ValueError(f"missing run directory: {run_dir}")
        capture = normalize_one(run_dir, row, manifest, case, channels, summary["binaryHash"])
        destination = output / "runs" / f"run-{row['run']:03d}" / "capture.json"
        write_artifact(destination, capture)
        derived.append({"run": row["run"], "capture": str(destination.relative_to(output)), "captureHash": canonical_hash(capture), "instrumentedRawHash": row["instrumented"]["rawHash"]})
    report = {"kind": "macos-rectangle-derived-normalization", "version": "0.1", "candidateOnly": True, "observationalOnly": True, "sourceSummary": str(args.summary), "sourceManifest": str(args.manifest), "sourceCase": str(args.case), "case": manifest["case"], "tupleId": case["tuple"]["id"], "runs": derived, "rawSummaryUntouched": True, "status": "DERIVED_NORMALIZED"}
    write_artifact(output / "derived-summary.json", report)
    print(json.dumps({"status": report["status"], "runs": len(derived), "output": str(output)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
