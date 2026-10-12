#!/usr/bin/env python3
"""Bounded, source-bound Text pair diagnostic.

This consumes an explicit adapter manifest built from measured Mac AX/compositor
& Windows UIA/PrintWindow archives. It never rewrites raw observations, infers
provider parity, or launches native work.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import struct
import sys
import zlib
from pathlib import Path
from typing import Any

MAX_JSON = 2 * 1024 * 1024
MAX_EVIDENCE = 64 * 1024 * 1024
MAX_IMAGE = 8 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_PIXELS = 4_000_000
CHUNK = 1024 * 1024
TEXT_CASE_PREFIX = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light."
TEXT_RECIPE = "sha256:ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d"
TEXT_SOURCE = "sha256:4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e"
TEXT_RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"


class Reject(ValueError):
    pass


def fail(reason: str) -> None:
    raise Reject(reason)


def regular(path: Path, limit: int) -> os.stat_result:
    """Stat before opening; reject symlink components & oversized files."""
    try:
        st = path.lstat()
    except OSError as exc:
        fail(f"missing ref: {path}: {exc}")
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        fail(f"bounded regular file required: {path}")
    probe = path
    while probe != probe.parent:
        try:
            if probe.is_symlink():
                fail(f"symlink component rejected: {probe}")
        except OSError as exc:
            fail(f"path check failed: {probe}: {exc}")
        probe = probe.parent
    return st


def digest(path: Path, limit: int = MAX_EVIDENCE) -> tuple[str, int]:
    st = regular(path, limit)
    h = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while True:
            buf = stream.read(CHUNK)
            if not buf:
                break
            total += len(buf)
            h.update(buf)
    if total != st.st_size:
        fail(f"file changed while hashing: {path}")
    return "sha256:" + h.hexdigest(), total


def load_json(path: Path, expected_hash: str | None = None, expected_bytes: int | None = None) -> Any:
    st = regular(path, MAX_JSON)
    if expected_bytes is not None and st.st_size != int(expected_bytes):
        fail(f"JSON byte join mismatch: {path}")
    actual, _ = digest(path, MAX_JSON)
    if expected_hash is not None and actual != expected_hash:
        fail(f"JSON hash join mismatch: {path}")
    with path.open("rb") as stream:
        raw = stream.read(MAX_JSON + 1)
    if len(raw) > MAX_JSON:
        fail(f"JSON budget exceeded: {path}")
    try:
        return json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON: {path}: {exc}")


def ref_obj(value: Any, name: str) -> tuple[Path, str, int]:
    if not isinstance(value, dict):
        fail(f"{name} ref must be object")
    path = value.get("path")
    sha = value.get("sha256")
    size = value.get("bytes")
    if not isinstance(path, str) or not isinstance(sha, str) or not isinstance(size, int):
        fail(f"{name} ref requires path/sha256/bytes")
    if not sha.startswith("sha256:") or len(sha) != 71:
        fail(f"{name} hash malformed")
    if size < 0:
        fail(f"{name} byte count malformed")
    return Path(path), sha, size


def verify_ref(value: Any, name: str, limit: int = MAX_EVIDENCE) -> tuple[Path, str, int]:
    path, expected, size = ref_obj(value, name)
    actual, actual_size = digest(path, limit)
    if actual_size != size or actual != expected:
        fail(f"{name} bytes/hash mismatch")
    return path, actual, actual_size


def unwrap(doc: Any, key: str) -> dict[str, Any]:
    if not isinstance(doc, dict):
        fail(f"{key} document must be object")
    inner = doc.get(key)
    return inner if isinstance(inner, dict) else doc


def field(doc: dict[str, Any], *paths: tuple[str, ...]) -> Any:
    for path in paths:
        cur: Any = doc
        for part in path:
            if not isinstance(cur, dict) or part not in cur:
                cur = None
                break
            cur = cur[part]
        if cur is not None:
            return cur
    return None


def ensure_hash(value: Any, name: str) -> str:
    if not isinstance(value, str) or not value.startswith("sha256:") or len(value) != 71:
        fail(f"{name} must be sha256:<64 hex>")
    return value


def identity_from_raw(doc: Any, name: str) -> dict[str, Any]:
    if not isinstance(doc, dict):
        fail(f"{name} raw observation must be JSON object")
    ident = doc.get("identity") if isinstance(doc.get("identity"), dict) else doc
    required = ("caseID", "caseHash", "tupleID", "tupleHash", "sourceHash", "recipeHash")
    out: dict[str, Any] = {}
    for key in required:
        value = ident.get(key)
        if not isinstance(value, str) or not value:
            fail(f"{name} raw identity missing {key}")
        out[key] = value
    return out


def png_summary(path: Path) -> dict[str, Any]:
    """Decode bounded non-interlaced 8-bit PNG rows & retain scalar evidence."""
    st = regular(path, MAX_IMAGE)
    if st.st_size < 33:
        fail(f"PNG too short: {path}")
    compressed = bytearray()
    width = height = depth = color = interlace = None
    with path.open("rb") as stream:
        if stream.read(8) != b"\x89PNG\r\n\x1a\n":
            fail(f"PNG signature mismatch: {path}")
        while True:
            header = stream.read(8)
            if len(header) != 8:
                fail(f"PNG truncated: {path}")
            length, kind = struct.unpack(">I4s", header)
            if length > MAX_IMAGE or length + len(compressed) > MAX_IMAGE:
                fail(f"PNG chunk budget exceeded: {path}")
            payload = stream.read(length)
            crc = stream.read(4)
            if len(payload) != length or len(crc) != 4:
                fail(f"PNG chunk truncated: {path}")
            if kind == b"IHDR":
                if length != 13:
                    fail("PNG IHDR malformed")
                width, height, depth, color, comp, filt, interlace = struct.unpack(">IIBBBBB", payload)
                if depth != 8 or comp != 0 or filt != 0 or interlace != 0 or color not in (0, 2, 4, 6):
                    fail("PNG requires non-interlaced 8-bit supported color type")
                if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
                    fail("PNG pixel budget exceeded")
            elif kind == b"IDAT":
                compressed.extend(payload)
            elif kind == b"IEND":
                break
    if width is None or height is None or color is None:
        fail("PNG missing IHDR")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    row_bytes = width * channels
    expected = height * (row_bytes + 1)
    if expected > MAX_IMAGE * 8:
        fail("PNG decompressed budget exceeded")
    try:
        raw = zlib.decompress(bytes(compressed), bufsize=expected)
    except zlib.error as exc:
        fail(f"PNG IDAT decode failed: {exc}")
    if len(raw) != expected:
        fail("PNG scanline length mismatch")
    digest_rows = hashlib.sha256()
    histogram: dict[str, int] = {}
    overflow = 0
    bbox = [width, height, -1, -1]
    previous = bytearray(row_bytes)
    offset = 0
    for _y in range(height):
        filt = raw[offset]
        encoded = raw[offset + 1 : offset + 1 + row_bytes]
        offset += row_bytes + 1
        row = bytearray(row_bytes)
        for i, value in enumerate(encoded):
            left = row[i - channels] if i >= channels else 0
            up = previous[i]
            up_left = previous[i - channels] if i >= channels else 0
            if filt == 0:
                row[i] = value
            elif filt == 1:
                row[i] = (value + left) & 255
            elif filt == 2:
                row[i] = (value + up) & 255
            elif filt == 3:
                row[i] = (value + ((left + up) // 2)) & 255
            elif filt == 4:
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                row[i] = (value + (left if pa <= pb and pa <= pc else up if pb <= pc else up_left)) & 255
            else:
                fail("PNG filter unsupported")
        digest_rows.update(row)
        for x in range(width):
            base = x * channels
            if channels == 1:
                rgba = (row[base], row[base], row[base], 255)
            elif channels == 2:
                rgba = (row[base], row[base], row[base], row[base + 1])
            elif channels == 3:
                rgba = (row[base], row[base + 1], row[base + 2], 255)
            else:
                rgba = tuple(row[base : base + 4])
            key = ",".join(str(v) for v in rgba)
            if key in histogram or len(histogram) < 64:
                histogram[key] = histogram.get(key, 0) + 1
            else:
                overflow += 1
            if rgba[3] and rgba[:3] != (255, 255, 255):
                bbox[0] = min(bbox[0], x); bbox[1] = min(bbox[1], _y)
                bbox[2] = max(bbox[2], x); bbox[3] = max(bbox[3], _y)
        previous = row
    return {"widthPx": width, "heightPx": height, "pixelCount": width * height,
            "rowDigest": "sha256:" + digest_rows.hexdigest(), "colorHistogram": histogram,
            "histogramOverflowPixels": overflow, "inkBBoxPx": None if bbox[2] < 0 else bbox}


def verify_metric(path_value: Any, raw_ref: Any, name: str, expected: dict[str, Any]) -> tuple[dict[str, Any], int]:
    path, sha, size = verify_ref(path_value, name)
    metric = load_json(path, sha, size)
    if metric.get("kind") != "factory-text-observed-metrics-v1":
        fail(f"{name} kind mismatch")
    source_ref = metric.get("rawRef")
    raw_path, raw_sha, raw_size = ref_obj(raw_ref, name + " raw")
    if not isinstance(source_ref, dict) or source_ref.get("path") != str(raw_path) or source_ref.get("sha256") != raw_sha or int(source_ref.get("bytes", -1)) != raw_size:
        fail(f"{name} raw lineage mismatch")
    identity = metric.get("identity")
    if identity != expected:
        fail(f"{name} metric identity mismatch")
    for key in ("contentViewportDip", "compositorFramePx", "titlebarPx", "placementDip", "clip", "font", "wrap"):
        if key not in metric:
            fail(f"{name} metric missing {key}")
    return metric, size


def validate(doc: dict[str, Any], verify_bytes: bool = True) -> dict[str, Any]:
    if doc.get("kind") != "factory-text-paired20-input-v1" or doc.get("count") != 20:
        fail("paired20 input kind/count mismatch")
    contract = doc.get("contract")
    if not isinstance(contract, dict) or contract.get("candidate") != "swiftui.text.layout.baseline.pilot-next":
        fail("Text contract candidate mismatch")
    if contract.get("casePrefix") != TEXT_CASE_PREFIX or contract.get("recipeHash") != TEXT_RECIPE or contract.get("sourceHash") != TEXT_SOURCE or contract.get("runtimeSourceCommit") != TEXT_RUNTIME:
        fail("Text contract source/case/recipe mismatch")
    if contract.get("contentViewportDip") != {"width": 120, "height": 48} or contract.get("compositorTitlebarPx") != 32:
        fail("Text viewport/titlebar contract mismatch")
    refs = doc.get("canonicalRefs")
    if not isinstance(refs, dict):
        fail("canonicalRefs required")
    canonical: dict[str, Any] = {}
    total = 0
    for name in ("case", "tuple", "source", "recipe"):
        path, sha, size = ref_obj(refs.get(name), name)
        if verify_bytes:
            canonical[name] = load_json(path, sha, size)
            total += size
        else:
            canonical[name] = {}
    if total > MAX_TOTAL:
        fail("canonical evidence total budget exceeded")
    case = unwrap(canonical["case"], "case")
    tuple_doc = unwrap(canonical["tuple"], "tuple")
    source = unwrap(canonical["source"], "source")
    recipe = unwrap(canonical["recipe"], "recipe")
    case_id = field(case, ("id",), ("case", "id")); case_hash = field(case, ("hash",), ("case", "hash"))
    tuple_id = field(tuple_doc, ("id",), ("tuple", "id")); tuple_hash = field(tuple_doc, ("hash",), ("tuple", "hash"))
    source_hash = field(source, ("sourceHash",), ("witness", "sourceHash"))
    recipe_hash = field(recipe, ("hash",), ("recipe", "hash"))
    if not isinstance(case_id, str) or not case_id.startswith(TEXT_CASE_PREFIX) or not isinstance(case_hash, str): fail("canonical case mismatch")
    if not isinstance(tuple_id, str) or not isinstance(tuple_hash, str): fail("canonical tuple mismatch")
    if source_hash != TEXT_SOURCE or recipe_hash != TEXT_RECIPE: fail("canonical source/recipe mismatch")
    expected = {"caseID": case_id, "caseHash": case_hash, "tupleID": tuple_id, "tupleHash": tuple_hash, "sourceHash": source_hash, "recipeHash": recipe_hash}
    rows = doc.get("rows")
    if not isinstance(rows, list) or len(rows) != 20:
        fail("exactly 20 pair rows required")
    seen: set[str] = set()
    reports = []
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict) or row.get("run") != index:
            fail(f"row {index} ordering mismatch")
        for id_name, prefix in (("captureID", "capture/"), ("imageID", "image/")):
            ident = row.get(id_name)
            if not isinstance(ident, str) or not ident.startswith(prefix) or len(ident) != len(prefix) + 32 or ident in seen:
                fail(f"row {index} {id_name} invalid or duplicate")
            seen.add(ident)
        joins = row.get("joins")
        if joins != expected:
            fail(f"row {index} identity join mismatch")
        pair_reports = {}
        for platform in ("mac", "windows"):
            side = row.get(platform)
            if not isinstance(side, dict): fail(f"row {index} {platform} side missing")
            raw_path, raw_sha, raw_size = verify_ref(side.get("raw"), f"row {index} {platform} raw")
            total += raw_size
            if total > MAX_TOTAL: fail("pair evidence total budget exceeded")
            raw = load_json(raw_path, raw_sha, raw_size)
            if identity_from_raw(raw, f"row {index} {platform} raw") != expected:
                fail(f"row {index} {platform} raw identity mismatch")
            metrics, metric_size = verify_metric(side.get("metrics"), side.get("raw"), f"row {index} {platform} metrics", expected)
            total += metric_size
            if total > MAX_TOTAL: fail("pair evidence total budget exceeded")
            pixels_path, pixels_sha, pixels_size = verify_ref(side.get("pixels"), f"row {index} {platform} pixels", MAX_IMAGE)
            total += pixels_size
            if total > MAX_TOTAL: fail("pair evidence total budget exceeded")
            pixels = png_summary(pixels_path)
            pair_reports[platform] = {"metrics": metrics, "pixels": pixels, "rawRef": {"path": str(raw_path), "sha256": raw_sha, "bytes": raw_size}, "pixelsRef": {"path": str(pixels_path), "sha256": pixels_sha, "bytes": pixels_size}}
        for platform in ("mac", "windows"):
            m = pair_reports[platform]["metrics"]
            if m["contentViewportDip"] != {"width": 120, "height": 48} or m["titlebarPx"] != 32:
                fail(f"row {index} {platform} viewport/titlebar mismatch")
            if not isinstance(m["compositorFramePx"], dict) or not isinstance(m["font"], dict) or not isinstance(m["wrap"], dict):
                fail(f"row {index} {platform} scalar metrics malformed")
            requested_font = {"family": "system", "size": 24, "weight": "regular", "design": "default"}
            if m["font"].get("requested") != requested_font and m["font"] != requested_font:
                fail(f"row {index} {platform} requested font mismatch")
            wrap = m["wrap"]
            if wrap.get("text") != "Aa" or not isinstance(wrap.get("lineCount"), int) or wrap["lineCount"] < 1:
                fail(f"row {index} {platform} wrap metric mismatch")
        macm, winm = pair_reports["mac"]["metrics"], pair_reports["windows"]["metrics"]
        reports.append({"run": index, "captureID": row["captureID"], "imageID": row["imageID"],
                        "contentViewport": {"mac": macm["contentViewportDip"], "windows": winm["contentViewportDip"], "status": "observed-exact-120x48"},
                        "compositor": {"mac": macm["compositorFramePx"], "windows": winm["compositorFramePx"], "titlebarPx": {"mac": macm["titlebarPx"], "windows": winm["titlebarPx"]}, "status": "platform-observation"},
                        "font": {"mac": macm["font"], "windows": winm["font"], "equal": macm["font"] == winm["font"]},
                        "wrap": {"mac": macm["wrap"], "windows": winm["wrap"], "equal": macm["wrap"] == winm["wrap"]},
                        "pixels": {"mac": pair_reports["mac"]["pixels"], "windows": pair_reports["windows"]["pixels"], "status": "scalar-diagnostic-only"}})
    return {"kind": "factory-text-paired20-diagnostic-v1", "status": "observed-diagnostic", "count": 20, "identity": expected, "rawEvidenceRewritten": False, "parity": "held", "rows": reports}


def run_controls(doc: dict[str, Any]) -> dict[str, Any]:
    mutations = [
        ("case-id", ("rows", 0, "joins", "caseID"), "bad-case"),
        ("case-hash", ("rows", 0, "joins", "caseHash"), "sha256:" + "0" * 64),
        ("tuple-id", ("rows", 0, "joins", "tupleID"), "bad-tuple"),
        ("tuple-hash", ("rows", 0, "joins", "tupleHash"), "sha256:" + "0" * 64),
        ("source-hash", ("rows", 0, "joins", "sourceHash"), "sha256:" + "0" * 64),
        ("recipe-hash", ("rows", 0, "joins", "recipeHash"), "sha256:" + "0" * 64),
        ("capture-id", ("rows", 1, "captureID"), doc["rows"][0]["captureID"]),
        ("image-id", ("rows", 1, "imageID"), doc["rows"][0]["imageID"]),
        ("run-order", ("rows", 0, "run"), 2),
        ("missing-row", ("rows",), doc["rows"][:-1]),
        ("raw-bytes", ("rows", 0, "mac", "raw", "bytes"), int(doc["rows"][0]["mac"]["raw"]["bytes"]) + 1),
        ("raw-hash", ("rows", 0, "windows", "raw", "sha256"), "sha256:" + "0" * 64),
        ("metric-lineage", ("rows", 0, "mac", "metrics", "sha256"), "sha256:" + "0" * 64),
        ("content-width", ("contract", "contentViewportDip", "width"), 121),
        ("titlebar", ("contract", "compositorTitlebarPx"), 31),
        ("pixel-ref", ("rows", 0, "windows", "pixels", "sha256"), "sha256:" + "0" * 64),
    ]
    outcomes = []
    for name, path, value in mutations:
        mutant = copy.deepcopy(doc)
        cur: Any = mutant
        if len(path) == 1:
            mutant[path[0]] = value
        else:
            for part in path[:-1]: cur = cur[part]
            cur[path[-1]] = value
        try:
            validate(mutant, verify_bytes=True)
        except Reject as exc:
            outcomes.append({"name": name, "rejected": True, "reason": str(exc)})
        else:
            outcomes.append({"name": name, "rejected": False, "reason": "fault escaped"})
    return {"kind": "factory-text-paired20-controls-v1", "count": len(outcomes), "allRejected": all(x["rejected"] for x in outcomes), "outcomes": outcomes}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pair-manifest", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    ap.add_argument("--controls", action="store_true")
    args = ap.parse_args()
    manifest = load_json(args.pair_manifest)
    if not isinstance(manifest, dict): fail("pair manifest must be object")
    result = run_controls(manifest) if args.controls else validate(manifest)
    encoded = json.dumps(result, sort_keys=True, indent=2) + "\n"
    if args.output:
        if args.output.exists(): fail("output must be fresh")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(encoded)
    else:
        sys.stdout.write(encoded)
    return 0 if (not args.controls or result.get("allRejected")) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Reject as exc:
        print(json.dumps({"kind": "factory-text-paired20-rejection-v1", "status": "held", "reason": str(exc)}, sort_keys=True), file=sys.stderr)
        raise SystemExit(2)
