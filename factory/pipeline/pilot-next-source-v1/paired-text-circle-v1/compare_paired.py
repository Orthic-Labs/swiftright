#!/usr/bin/env python3
"""Bounded source-bound Text/Circle pair reader.

Consumes an explicit 20-row archive manifest. It reads sealed raw evidence,
parent certificates, metrics & pixels; it never captures, rewrites raw files,
or promotes parity.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
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
SHA = re.compile(r"^sha256:[0-9a-f]{64}$")
TEXT_PREFIX = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light."
CIRCLE_PREFIX = "swiftui.circle.fixed.recipe.pilot-next.circle-fixed-light."


class Reject(ValueError):
    pass


def reject(message: str) -> None:
    raise Reject(message)


def regular(path: Path, limit: int) -> os.stat_result:
    try:
        st = path.lstat()
    except OSError as exc:
        reject(f"missing ref: {path}: {exc}")
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        reject(f"bounded regular file required: {path}")
    cur = path
    while cur != cur.parent:
        if cur.is_symlink():
            reject(f"symlink component rejected: {cur}")
        cur = cur.parent
    return st


def digest(path: Path, limit: int) -> tuple[str, int]:
    st = regular(path, limit)
    total = 0
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            block = stream.read(CHUNK)
            if not block:
                break
            total += len(block)
            if total > limit:
                reject(f"bounded read exceeded: {path}")
            h.update(block)
    if total != st.st_size:
        reject(f"file changed while hashing: {path}")
    return "sha256:" + h.hexdigest(), total


def load_json_ref(value: Any, name: str, limit: int = MAX_JSON) -> tuple[dict[str, Any], dict[str, Any]]:
    if not isinstance(value, dict):
        reject(f"{name} ref must be object")
    path = value.get("path")
    expected = value.get("sha256")
    size = value.get("bytes")
    if not isinstance(path, str) or not isinstance(expected, str) or not SHA.fullmatch(expected) or type(size) is not int:
        reject(f"{name} ref requires path/sha256/bytes")
    actual, actual_size = digest(Path(path), limit)
    if actual != expected or actual_size != size:
        reject(f"{name} bytes/hash mismatch")
    with Path(path).open("rb") as stream:
        raw = stream.read(limit + 1)
    if len(raw) > limit:
        reject(f"{name} JSON budget exceeded")
    try:
        doc = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        reject(f"{name} invalid JSON: {exc}")
    if not isinstance(doc, dict):
        reject(f"{name} JSON object required")
    return doc, {"path": str(Path(path)), "sha256": actual, "bytes": actual_size}


def load_raw_ref(value: Any, name: str) -> tuple[dict[str, Any], dict[str, Any]]:
    return load_json_ref(value, name, MAX_EVIDENCE)


def identity(doc: dict[str, Any], name: str) -> dict[str, Any]:
    value = doc.get("identity") if isinstance(doc.get("identity"), dict) else doc
    keys = ("caseID", "caseHash", "tupleID", "tupleHash", "sourceHash", "recipeHash")
    out = {key: value.get(key) for key in keys}
    if any(not isinstance(item, str) or not item for item in out.values()):
        reject(f"{name} identity incomplete")
    return out


def file_ref(value: Any, name: str, limit: int = MAX_EVIDENCE) -> dict[str, Any]:
    if not isinstance(value, dict):
        reject(f"{name} file ref required")
    path, expected, size = value.get("path"), value.get("sha256"), value.get("bytes")
    if not isinstance(path, str) or not isinstance(expected, str) or not SHA.fullmatch(expected) or type(size) is not int:
        reject(f"{name} malformed file ref")
    actual, actual_size = digest(Path(path), limit)
    if actual != expected or actual_size != size:
        reject(f"{name} bytes/hash mismatch")
    return {"path": path, "sha256": actual, "bytes": actual_size}


def png_summary(ref: Any, name: str) -> tuple[dict[str, Any], dict[str, Any]]:
    item = file_ref(ref, name, MAX_IMAGE)
    path = Path(item["path"])
    with path.open("rb") as stream:
        if stream.read(8) != b"\x89PNG\r\n\x1a\n":
            reject(f"{name} PNG signature mismatch")
        compressed = bytearray()
        width = height = depth = color = interlace = None
        while True:
            header = stream.read(8)
            if len(header) != 8:
                reject(f"{name} PNG truncated")
            length, kind = struct.unpack(">I4s", header)
            if length > MAX_IMAGE or len(compressed) + length > MAX_IMAGE:
                reject(f"{name} PNG budget exceeded")
            payload = stream.read(length)
            crc = stream.read(4)
            if len(payload) != length or len(crc) != 4:
                reject(f"{name} PNG chunk truncated")
            if kind == b"IHDR":
                if length != 13:
                    reject(f"{name} PNG IHDR malformed")
                width, height, depth, color, comp, filt, interlace = struct.unpack(">IIBBBBB", payload)
                if depth != 8 or comp != 0 or filt != 0 or interlace != 0 or color not in (2, 6):
                    reject(f"{name} requires non-interlaced RGB/RGBA PNG")
                if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
                    reject(f"{name} pixel budget exceeded")
            elif kind == b"IDAT":
                compressed.extend(payload)
            elif kind == b"IEND":
                break
    if width is None or height is None or color is None:
        reject(f"{name} PNG IHDR missing")
    channels = 3 if color == 2 else 4
    row_bytes = width * channels
    expected = height * (row_bytes + 1)
    if expected > MAX_IMAGE * 8:
        reject(f"{name} PNG decoded budget exceeded")
    try:
        raw = zlib.decompress(bytes(compressed), bufsize=expected)
    except zlib.error as exc:
        reject(f"{name} PNG decode failed: {exc}")
    if len(raw) != expected:
        reject(f"{name} PNG row length mismatch")
    histogram: dict[str, int] = {}
    bbox = [width, height, -1, -1]
    previous = bytearray(row_bytes)
    offset = 0
    for y in range(height):
        filt = raw[offset]
        encoded = raw[offset + 1:offset + 1 + row_bytes]
        offset += row_bytes + 1
        row = bytearray(row_bytes)
        for index, value in enumerate(encoded):
            left = row[index - channels] if index >= channels else 0
            up = previous[index]
            up_left = previous[index - channels] if index >= channels else 0
            if filt == 0:
                row[index] = value
            elif filt == 1:
                row[index] = (value + left) & 255
            elif filt == 2:
                row[index] = (value + up) & 255
            elif filt == 3:
                row[index] = (value + ((left + up) // 2)) & 255
            elif filt == 4:
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                row[index] = (value + (left if pa <= pb and pa <= pc else up if pb <= pc else up_left)) & 255
            else:
                reject(f"{name} PNG filter unsupported")
        for x in range(width):
            base = x * channels
            rgba = tuple(row[base:base + channels]) + ((255,) if channels == 3 else ())
            key = ",".join(str(part) for part in rgba)
            if key in histogram or len(histogram) < 64:
                histogram[key] = histogram.get(key, 0) + 1
            if rgba[3] > 0 and rgba[:3] != (255, 255, 255):
                bbox[0], bbox[1] = min(bbox[0], x), min(bbox[1], y)
                bbox[2], bbox[3] = max(bbox[2], x), max(bbox[3], y)
        previous = row
    return {"widthPx": width, "heightPx": height, "pixels": width * height,
            "histogram": histogram,
            "inkBBoxPx": None if bbox[2] < 0 else {"x": bbox[0], "y": bbox[1], "width": bbox[2] - bbox[0] + 1, "height": bbox[3] - bbox[1] + 1}}, item


def require_parent(proof_ref: Any, name: str) -> dict[str, Any]:
    proof, ref = load_json_ref(proof_ref, name)
    if proof.get("originalHandleRetained") is not True or proof.get("ownedExited") is not True:
        reject(f"{name} parent exit certificate incomplete")
    if proof.get("lockReleased") is not True or proof.get("jobActiveCount") != 0:
        reject(f"{name} parent ownership certificate incomplete")
    if proof.get("streamDrainComplete") is not True and proof.get("streamsSealed") is not True:
        reject(f"{name} stream certificate incomplete")
    return {"proof": proof, "ref": ref}


def canonical_identity(refs: dict[str, Any], profile: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if not isinstance(refs, dict):
        reject("canonicalRefs required")
    docs: dict[str, dict[str, Any]] = {}
    refs_out: dict[str, dict[str, Any]] = {}
    for key in ("case", "tuple", "source", "recipe", "compileReceipt"):
        docs[key], refs_out[key] = load_json_ref(refs.get(key), key)
    for key in ("executable", "renderer"):
        refs_out[key] = file_ref(refs.get(key), key, MAX_EVIDENCE)
    case = docs["case"].get("case", docs["case"])
    tup = docs["tuple"].get("tuple", docs["tuple"])
    source = docs["source"].get("source", docs["source"])
    recipe = docs["recipe"].get("recipe", docs["recipe"])
    case_id = case.get("id")
    tuple_id = tup.get("id")
    if not isinstance(case_id, str) or not isinstance(tuple_id, str):
        reject("canonical case/tuple ids missing")
    prefix = TEXT_PREFIX if profile == "text" else CIRCLE_PREFIX
    if not case_id.startswith(prefix):
        reject("canonical case prefix mismatch")
    required = {"caseID": case_id, "tupleID": tuple_id,
                "caseHash": case.get("hash"), "tupleHash": tup.get("hash"),
                "sourceHash": source.get("sourceHash"), "recipeHash": recipe.get("hash"),
                "compileReceiptHash": refs_out["compileReceipt"]["sha256"],
                "executableHash": refs_out["executable"]["sha256"],
                "rendererHash": refs_out["renderer"]["sha256"]}
    if any(not isinstance(value, str) or not value for value in required.values()):
        reject("canonical identity incomplete")
    return required, refs_out


def row_identity(row: dict[str, Any], expected: dict[str, Any], index: int) -> None:
    if row.get("run") != index:
        reject(f"run ordering mismatch at {index}")
    joins = row.get("joins")
    if not isinstance(joins, dict):
        reject(f"run {index} joins missing")
    for key, value in expected.items():
        if joins.get(key) != value:
            reject(f"run {index} identity mismatch: {key}")
    for name, prefix in (("captureID", "capture/"), ("imageID", "image/")):
        value = row.get(name)
        if not isinstance(value, str) or not value.startswith(prefix) or len(value) != len(prefix) + 32:
            reject(f"run {index} {name} invalid")


def validate_side(side: Any, expected: dict[str, Any], profile: str, platform: str, index: int) -> dict[str, Any]:
    if not isinstance(side, dict):
        reject(f"run {index} {platform} side missing")
    raw, raw_ref = load_raw_ref(side.get("raw"), f"run {index} {platform} raw")
    if identity(raw, f"run {index} {platform} raw") != {key: expected[key] for key in ("caseID", "caseHash", "tupleID", "tupleHash", "sourceHash", "recipeHash")}:
        reject(f"run {index} {platform} raw identity mismatch")
    metrics, metric_ref = load_json_ref(side.get("metrics"), f"run {index} {platform} metrics")
    if metrics.get("identity") != identity(raw, "metrics"):
        reject(f"run {index} {platform} metric identity mismatch")
    pixels, pixel_ref = png_summary(side.get("pixels"), f"run {index} {platform} pixels")
    parent = require_parent(side.get("parentProof"), f"run {index} {platform}")
    native_pid = side.get("nativePID")
    if type(native_pid) is not int or native_pid <= 0:
        reject(f"run {index} {platform} nativePID required")
    if parent["proof"].get("processPID") != native_pid:
        reject(f"run {index} {platform} parent PID mismatch")
    raw_pid = raw.get("pid", raw.get("processPID"))
    if raw_pid != native_pid:
        reject(f"run {index} {platform} raw PID mismatch")
    if profile == "text":
        if metrics.get("contentViewportDip") != {"width": 120, "height": 48}:
            reject(f"run {index} {platform} Text viewport mismatch")
        for key in ("font", "wrap", "compositorFramePx", "titlebarPx"):
            if key not in metrics:
                reject(f"run {index} {platform} Text metric missing: {key}")
    else:
        if metrics.get("viewportDip") != {"width": 320, "height": 240}:
            reject(f"run {index} {platform} Circle viewport mismatch")
        if metrics.get("semanticColor") != "system.blue":
            reject(f"run {index} {platform} Circle semantic color mismatch")
        if "frameDip" not in metrics or "placement" not in metrics or "clip" not in metrics:
            reject(f"run {index} {platform} Circle geometry metric missing")
    return {"raw": raw_ref, "metrics": metric_ref, "pixels": pixel_ref,
            "parentProof": parent, "pixelSummary": pixels, "metricsDoc": metrics}


def validate(doc: dict[str, Any]) -> dict[str, Any]:
    if doc.get("kind") != "factory-text-circle-paired20-input-v1" or doc.get("count") != 20:
        reject("paired20 kind/count mismatch")
    profile = doc.get("profile")
    if profile not in ("text", "circle"):
        reject("profile must be text or circle")
    expected, canonical = canonical_identity(doc.get("canonicalRefs"), profile)
    rows = doc.get("rows")
    if not isinstance(rows, list) or len(rows) != 20:
        reject("exactly 20 ordered rows required")
    seen: set[str] = set()
    reports = []
    total = sum(item["bytes"] for item in canonical.values())
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict):
            reject(f"run {index} row missing")
        row_identity(row, expected, index)
        for name in ("captureID", "imageID"):
            if row[name] in seen:
                reject(f"duplicate {name}")
            seen.add(row[name])
        sides = {platform: validate_side(row.get(platform), expected, profile, platform, index) for platform in ("mac", "windows")}
        total += sum(item["raw"]["bytes"] + item["metrics"]["bytes"] + item["pixels"]["bytes"] + item["parentProof"]["ref"]["bytes"] for item in sides.values())
        if total > MAX_TOTAL:
            reject("paired evidence budget exceeded")
        reports.append({"run": index, "captureID": row["captureID"], "imageID": row["imageID"],
                        "metrics": {platform: sides[platform]["metricsDoc"] for platform in sides},
                        "pixels": {platform: sides[platform]["pixelSummary"] for platform in sides},
                        "status": "observed-diagnostic", "semantic": "held", "timing": "raw-only"})
    return {"kind": "factory-text-circle-paired20-report-v1", "profile": profile,
            "status": "observed-diagnostic", "count": 20, "identity": expected,
            "rawEvidenceRewritten": False, "parity": "held", "rows": reports,
            "canonicalRefs": canonical}


def controls(doc: dict[str, Any]) -> dict[str, Any]:
    faults = [
        ("missing-run", lambda d: d["rows"].pop()),
        ("wrong-case", lambda d: d["rows"][0]["joins"].__setitem__("caseID", "wrong")),
        ("wrong-pid", lambda d: d["rows"][0]["mac"].__setitem__("nativePID", d["rows"][0]["mac"]["nativePID"] + 1)),
        ("wrong-parent-proof", lambda d: d["rows"][0]["windows"]["parentProof"].__setitem__("sha256", "sha256:" + "0" * 64)),
        ("wrong-executable-ref", lambda d: d["canonicalRefs"]["executable"].__setitem__("sha256", "sha256:" + "0" * 64)),
        ("wrong-pixel-ref", lambda d: d["rows"][0]["mac"]["pixels"].__setitem__("sha256", "sha256:" + "0" * 64)),
    ]
    outcomes = []
    for name, mutate in faults:
        mutant = copy.deepcopy(doc)
        try:
            mutate(mutant)
            validate(mutant)
        except (Reject, KeyError, TypeError, IndexError) as exc:
            outcomes.append({"name": name, "rejected": True, "reason": str(exc)})
        else:
            outcomes.append({"name": name, "rejected": False, "reason": "fault escaped"})
    return {"kind": "factory-text-circle-paired20-controls-v1", "count": len(outcomes),
            "allRejected": all(item["rejected"] for item in outcomes), "outcomes": outcomes}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--controls", action="store_true")
    args = parser.parse_args()
    try:
        value = json.loads(args.input.read_text(encoding="utf-8-sig"))
        result = controls(value) if args.controls else validate(value)
        payload = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            if args.output.exists():
                reject("output must be fresh")
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open("x", encoding="utf-8", newline="\n") as stream:
                stream.write(payload)
        else:
            print(payload, end="")
        return 0 if not args.controls or result["allRejected"] else 1
    except (OSError, json.JSONDecodeError, Reject) as exc:
        print(json.dumps({"status": "blocked", "reason": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
