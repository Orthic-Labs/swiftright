#!/usr/bin/env python3
"""Bounded, raw-only adapter for Text paint paired observations.

This module deliberately refuses to infer missing Windows20 receipts.  It is
also used by controls, so controls exercise production validation rather than
an independent mirror predicate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
from typing import Any, Iterable

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 128 * 1024 * 1024
SHA = "sha256:"
CASE_ID = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418"
CASE_HASH = SHA + "29807aa918aa7c2c1c4a4705eb324b0020f29060be7359d4923694aeb5d437ad"
TUPLE_ID = "sr1-text-paint-v2-r11-paired20-20261012"
WIN_HOST_HASH = SHA + "33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7"
MAC_HOST_HASH = SHA + "fb2757beded3e6d1d4d650b508ed28f2080f0168d56948f7a1dac2bc897db84c"
RENDERER_HASH = SHA + "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
SOURCE_HASH = SHA + "4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e"
SOURCE_BYTES = 403
PLAN_HASH = "de8660b0c55a717d52171ec476b833881919696f434c3ceba077ba3b77fbc642"
COMPILE_RECEIPT_HASH = "bef8851cef48e96889bb46f8e66d85cff7f9f0f8f19e34c65d3d09c38036010b"
EXE_HASH = "33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7"
SERIALIZER_HASH = "952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba"
RUNTIME_COMMIT = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"


class Hold(Exception):
    pass


class Bounded:
    def __init__(self) -> None:
        self.total = 0

    def path(self, root: Path, relative: str) -> Path:
        p = Path(relative)
        if p.is_absolute() or ".." in p.parts:
            raise Hold(f"unsafe relative path: {relative}")
        cur = root
        for part in p.parts:
            cur = cur / part
            if cur.is_symlink():
                raise Hold(f"symlink path component: {relative}")
        return cur

    def bytes(self, path: Path, limit: int = MAX_FILE) -> bytes:
        try:
            st = path.stat()
        except OSError as e:
            raise Hold(f"unreadable input {path}: {e}") from e
        if not path.is_file() or path.is_symlink():
            raise Hold(f"input is not regular: {path}")
        if st.st_size > limit:
            raise Hold(f"input exceeds {limit} bytes: {path}")
        self.total += st.st_size
        if self.total > MAX_TOTAL:
            raise Hold("aggregate input exceeds 128MiB")
        out = bytearray()
        with path.open("rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    return bytes(out)
                out.extend(chunk)

    def json(self, path: Path) -> Any:
        try:
            # Windows transport receipts may carry UTF-8 BOM.  Decode it at
            # the JSON boundary only; file_ref still hashes original bytes.
            return json.loads(self.bytes(path, MAX_JSON).decode("utf-8-sig"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            raise Hold(f"invalid JSON: {path}: {e}") from e

    def file_ref(self, root: Path, relative: str, limit: int = MAX_FILE) -> dict[str, Any]:
        path = self.path(root, relative)
        try:
            st = path.stat()
        except OSError as e:
            raise Hold(f"missing raw file {relative}: {e}") from e
        if not path.is_file() or path.is_symlink():
            raise Hold(f"raw file is not regular: {relative}")
        if st.st_size > limit:
            raise Hold(f"raw file exceeds {limit} bytes: {relative}")
        self.total += st.st_size
        if self.total > MAX_TOTAL:
            raise Hold("aggregate raw bytes exceeds 128MiB")
        digest = hashlib.sha256()
        with path.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                digest.update(chunk)
        return {"path": relative, "bytes": st.st_size, "sha256": SHA + digest.hexdigest()}


def need(obj: dict[str, Any], key: str, where: str) -> Any:
    if key not in obj:
        raise Hold(f"{where} missing {key}")
    return obj[key]


def same_identity(left: dict[str, Any], right: dict[str, Any], label: str) -> None:
    for key in ("id", "hash"):
        if left.get(key) != right.get(key):
            raise Hold(f"{label}.{key} mismatch")


def validate_source_graph(graph_root: Path, b: Bounded, expected_count: int) -> dict[str, Any]:
    """Validate admitted producer graph rows before consuming native archive."""
    stage = b.json(b.path(graph_root, "stage-manifest.json"))
    rows = stage.get("files")
    if not isinstance(rows, list) or not rows or len(rows) > 256:
        raise Hold("source graph stage manifest invalid")
    seen: set[str] = set(); total = 0
    for row in rows:
        rel = row.get("path") if isinstance(row, dict) else None
        if not isinstance(rel, str) or rel in seen:
            raise Hold("source graph duplicate row")
        seen.add(rel)
        p = b.path(graph_root, rel)
        ref = b.file_ref(graph_root, rel, MAX_FILE)
        if row.get("bytes") != ref["bytes"] or row.get("sha256") != ref["sha256"].removeprefix(SHA):
            raise Hold(f"source graph row drift: {rel}")
        total += ref["bytes"]
    if total > MAX_TOTAL:
        raise Hold("source graph exceeds aggregate bound")
    si = b.json(b.path(graph_root, "admission/source-inputs.json"))
    if si.get("count") != expected_count:
        raise Hold(f"source graph count mismatch: {si.get('count')}")
    for key, expected in (("caseID", CASE_ID), ("caseHash", CASE_HASH),
                          ("tupleID", TUPLE_ID), ("sourceHash", SOURCE_HASH),
                          ("runtimeSourceCommit", RUNTIME_COMMIT),
                          ("exeHash", EXE_HASH), ("rendererSha256", RENDERER_HASH.removeprefix(SHA)),
                          ("serializerControlSha256", SERIALIZER_HASH)):
        value = si.get(key)
        if key == "caseHash" and value is None:
            value = si.get("caseCanonicalHash")
        if value != expected:
            raise Hold(f"source graph {key} mismatch")
    if si.get("planHash") != PLAN_HASH or si.get("compileReceiptHash") != COMPILE_RECEIPT_HASH:
        raise Hold("source graph measured plan/receipt hash mismatch")
    tuple_doc = b.json(b.path(graph_root, "admission/candidate-tuple.json"))
    td = tuple_doc.get("tuple", tuple_doc)
    same_identity(tuple_doc.get("case", {}), {"id": CASE_ID, "hash": CASE_HASH}, "source graph case")
    if td.get("id") != TUPLE_ID or td.get("runtimeCommit") != RUNTIME_COMMIT:
        raise Hold("source graph tuple identity mismatch")
    if td.get("hostHashes", {}).get("windows") != WIN_HOST_HASH or td.get("hostHashes", {}).get("macos") != MAC_HOST_HASH:
        raise Hold("source graph host tuple mismatch")
    if td.get("rendererHash") != RENDERER_HASH:
        raise Hold("source graph renderer tuple mismatch")
    return {"count": expected_count, "fileCount": len(rows), "bytes": total,
            "sourceInputsHash": hashlib.sha256(json.dumps(si, sort_keys=True).encode()).hexdigest()}


def validate_mac_provenance(summary: dict[str, Any], capture: dict[str, Any]) -> str:
    """Join Mac capture provenance to measured Witness.swift bytes.

    Per-run capture.provenance.sourceHash is producer provenance and may vary
    by capture.  Shared source identity comes from compilerReceipt's measured
    sourceAfter Witness.swift row, which must equal Windows source binding.
    """
    compiler = summary.get("compilerReceipt", {}).get("compiler", {})
    before = compiler.get("sourceBefore", {}).get("Witness.swift")
    after = compiler.get("sourceAfter", {}).get("Witness.swift")
    if not isinstance(before, dict) or not isinstance(after, dict):
        raise Hold("Mac compiler receipt missing Witness.swift source provenance")
    if before != after:
        raise Hold("Mac compiler Witness.swift source drift")
    source_hash = after.get("sha256")
    source_bytes = after.get("bytes")
    if source_hash != SOURCE_HASH or source_bytes != SOURCE_BYTES:
        raise Hold("Mac Witness.swift source provenance does not match admitted source")
    provenance = capture.get("provenance")
    if not isinstance(provenance, dict):
        raise Hold("Mac capture missing provenance")
    inputs = provenance.get("inputs")
    if not isinstance(inputs, list) or not inputs:
        raise Hold("Mac capture provenance missing binary input")
    if provenance.get("producer") != "factory/native/macos":
        raise Hold("Mac capture provenance producer mismatch")
    if not any(isinstance(item, dict) and item.get("hash") == MAC_HOST_HASH for item in inputs):
        raise Hold("Mac capture provenance missing measured host input")
    return source_hash


def _find_ax_text(node: Any) -> dict[str, Any] | None:
    if isinstance(node, dict):
        role = node.get("role")
        value = node.get("value")
        if role in ("AXStaticText", "AXTextField") and isinstance(value, str):
            return {"role": role, "value": value, "frame": node.get("frame")}
        tree = node.get("tree")
        if tree is not None:
            found = _find_ax_text(tree)
            if found is not None:
                return found
        for child in node.get("children", []):
            found = _find_ax_text(child)
            if found is not None:
                return found
    elif isinstance(node, list):
        for child in node:
            found = _find_ax_text(child)
            if found is not None:
                return found
    return None


def _number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise Hold(f"{label} is not numeric")
    result = float(value)
    if not math.isfinite(result):
        raise Hold(f"{label} is not finite")
    return result


def derive_mac_text_geometry(node: dict[str, Any]) -> dict[str, Any]:
    """Preserve AX screen-point frame & derive text dimensions in points/DIP."""
    frame = node.get("frame")
    if not isinstance(frame, dict):
        raise Hold("Mac AX text node missing frame")
    x = _number(frame.get("x"), "Mac AX frame.x")
    y = _number(frame.get("y"), "Mac AX frame.y")
    width = _number(frame.get("w"), "Mac AX frame.w")
    height = _number(frame.get("h"), "Mac AX frame.h")
    if width < 0 or height < 0:
        raise Hold("Mac AX text frame has negative dimensions")
    return {
        "coordinateSpace": "AXScreenPoints",
        "rawFrame": dict(frame),
        "originScreenPoints": {"x": x, "y": y},
        "dimensionsDip": {"width": width, "height": height},
        "scale": 1.0,
    }


def _find_uia_text(node: Any) -> dict[str, Any] | None:
    if isinstance(node, dict):
        if node.get("controlType") == "ControlType.Text":
            value = node.get("name", node.get("value"))
            return {"controlType": node.get("controlType"), "value": value, "bounds": node.get("bounds")}
        for child in node.get("children", []):
            found = _find_uia_text(child)
            if found is not None:
                return found
    elif isinstance(node, list):
        for child in node:
            found = _find_uia_text(child)
            if found is not None:
                return found
    return None


def derive_windows_text_geometry(node: dict[str, Any], dpi: Any) -> dict[str, Any]:
    """Preserve UIA screen-pixel bounds & derive client-scale dimensions/DIP."""
    bounds = node.get("bounds")
    if not isinstance(bounds, list) or len(bounds) != 4:
        raise Hold("Windows UIA text node missing four-element bounds")
    values = [_number(value, f"Windows UIA bounds[{index}]") for index, value in enumerate(bounds)]
    x, y, width_px, height_px = values
    dpi_value = _number(dpi, "Windows pixel dpi")
    if dpi_value <= 0 or width_px < 0 or height_px < 0:
        raise Hold("Windows UIA bounds/dpi are invalid")
    scale = dpi_value / 96.0
    return {
        "coordinateSpace": "UIAScreenPixels",
        "rawBounds": list(bounds),
        "originScreenPixels": {"x": x, "y": y},
        "dimensionsDip": {"width": width_px / scale, "height": height_px / scale},
        "scale": scale,
        "dpi": dpi_value,
    }


def mac_terminal_observation_hold(owned: dict[str, Any]) -> str | None:
    """Validate only fields actually supplied by Mac producer receipt.

    Mac producer uses owned-window-process.json, not Windows job receipts.  A
    missing native exit/cleanup record remains an explicit hold; it is never
    synthesized from compiler exit fields.
    """
    if owned.get("retainedProcessHandle") is not True:
        return "Mac original process retained-handle evidence missing"
    if "exitCode" not in owned:
        return "Mac original-process exit/cleanup evidence absent"
    exit_code = owned.get("exitCode")
    if exit_code != 0:
        return f"Mac original-process exit code nonzero: {exit_code}"
    cleanup = owned.get("cleanup")
    if not isinstance(cleanup, dict) or cleanup.get("completed") is not True:
        return "Mac original-process cleanup evidence absent"
    return None


def semantic_compare(mac: dict[str, Any], win: dict[str, Any]) -> dict[str, Any]:
    """Report observed semantic fields without normalizing host differences."""
    mac_rows = mac["rows"]
    win_rows = win["rows"]
    mac_text = [row["semantic"]["text"] for row in mac_rows]
    win_text = [row["semantic"]["text"] for row in win_rows]
    mac_viewport = [row["semantic"]["viewportDip"] for row in mac_rows]
    win_viewport = [row["semantic"]["viewportDip"] for row in win_rows]
    mac_plain = [row["semantic"]["plainHash"] for row in mac_rows]
    win_print = [row["semantic"]["printWindowHash"] for row in win_rows]
    win_screen = [row["semantic"]["screenHash"] for row in win_rows]
    mac_bounds_raw = [row["semantic"]["textNode"] for row in mac_rows]
    win_bounds_raw = [row["semantic"]["textNode"] for row in win_rows]
    mac_bounds_dip = [row["semantic"]["textNodeDip"] for row in mac_rows]
    win_bounds_dip = [row["semantic"]["textNodeDip"] for row in win_rows]
    mac_dimensions = [item["dimensionsDip"] for item in mac_bounds_dip]
    win_dimensions = [item["dimensionsDip"] for item in win_bounds_dip]
    text_agreement = len(set(mac_text)) == 1 and len(set(win_text)) == 1 and mac_text[0] == win_text[0]
    viewport_agreement = all(left == right for left, right in zip(mac_viewport, win_viewport))
    return {
        "textContent": {"mac": mac_text, "windows": win_text, "exactAgreement": text_agreement},
        "wrapping": {
            "mac": [row["semantic"]["axRaw"] for row in mac_rows],
            "windows": [row["semantic"]["uiaRaw"] for row in win_rows],
            "exactAgreement": None,
            "status": "held-no-cross-host-line-break-field",
        },
        "textBounds": {
            "macRaw": mac_bounds_raw,
            "windowsRaw": win_bounds_raw,
            "macDip": mac_bounds_dip,
            "windowsDip": win_bounds_dip,
            "macDimensionsDip": mac_dimensions,
            "windowsDimensionsDip": win_dimensions,
            "exactAgreement": mac_dimensions == win_dimensions,
            "comparison": "dimensions-only; screen origins remain raw per host",
        },
        "viewport": {"macDip": mac_viewport, "windowsDip": win_viewport, "exactAgreement": viewport_agreement},
        "defaultPaint": {
            "mac": [row["semantic"]["paint"] for row in mac_rows],
            "windows": None,
            "exactAgreement": None,
            "status": "held-windows-paint-field-unavailable",
        },
        "repeatability": {
            "macPlainHashes": sorted(set(mac_plain)),
            "windowsPrintWindowHashes": sorted(set(win_print)),
            "windowsScreenHashes": sorted(set(win_screen)),
            "macPlainExactRepeat": len(set(mac_plain)) == 1,
            "windowsPrintWindowExactRepeat": len(set(win_print)) == 1,
            "windowsScreenExactRepeat": len(set(win_screen)) == 1,
        },
        "status": "observed-diagnostic",
        "qualification": "held",
    }


def mac_adapter(root: Path, b: Bounded) -> dict[str, Any]:
    index = b.json(b.path(root, "capture-index.json"))
    results = need(index, "results", "Mac capture-index")
    if not isinstance(results, list) or len(results) != 1:
        raise Hold("Mac capture-index must contain exactly one result")
    case = need(results[0], "case", "Mac capture-index result")
    same_identity(case, {"id": CASE_ID, "hash": CASE_HASH}, "Mac case")
    case_dir = b.path(root, CASE_ID)
    summary = b.json(case_dir / "summary.json")
    same_identity(need(summary, "case", "Mac summary"), case, "Mac summary case")
    runs = need(summary, "runs", "Mac summary")
    if not isinstance(runs, list) or len(runs) != 20:
        raise Hold("Mac summary must contain 20 runs")
    first_capture: dict[str, Any] | None = None
    rows: list[dict[str, Any]] = []
    for ordinal in range(1, 21):
        entry = runs[ordinal - 1]
        if not isinstance(entry, dict) or entry.get("run") != ordinal:
            raise Hold(f"Mac run ordinal mismatch at {ordinal}")
        rel = f"{CASE_ID}/run-{ordinal:03d}"
        capture = b.json(b.path(root, f"{rel}/capture.json"))
        same_identity(need(capture, "case", f"Mac run {ordinal}"), case, f"Mac run {ordinal} case")
        if capture.get("run") not in (None, ordinal) and capture.get("meta", {}).get("run") != ordinal:
            raise Hold(f"Mac run {ordinal} capture ordinal mismatch")
        tuple_doc = need(capture, "tuple", f"Mac run {ordinal}")
        capture_provenance = capture.get("provenance")
        if not isinstance(capture_provenance, dict) or not isinstance(capture_provenance.get("sourceHash"), str):
            raise Hold(f"Mac run {ordinal} missing provenance")
        if not capture_provenance["sourceHash"].startswith(SHA):
            raise Hold(f"Mac run {ordinal} provenance source hash is malformed")
        if capture_provenance.get("producer") != "factory/native/macos":
            raise Hold(f"Mac run {ordinal} provenance producer mismatch")
        capture_inputs = capture_provenance.get("inputs")
        if not isinstance(capture_inputs, list) or not any(
            isinstance(item, dict) and item.get("hash") == MAC_HOST_HASH for item in capture_inputs
        ):
            raise Hold(f"Mac run {ordinal} provenance missing measured host input")
        if first_capture is None:
            first_capture = capture
        elif tuple_doc != first_capture.get("tuple"):
            raise Hold(f"Mac run {ordinal} tuple drift")
        refs = [
            f"{rel}/capture.json", f"{rel}/plain.raw.json", f"{rel}/instrumented.raw.json",
            f"{rel}/compositor.raw.json", f"{rel}/external-ax.raw.json", f"{rel}/clock.json",
            f"{rel}/owned-window-process.json",
        ]
        raw = [b.file_ref(root, p, MAX_JSON) for p in refs]
        plain_doc = b.json(b.path(root, f"{rel}/plain.raw.json"))
        ax_doc = b.json(b.path(root, f"{rel}/external-ax.raw.json"))
        # Image hashes are semantic references in capture.json.  Hash image bytes
        # only when present; absence stays an explicit hold rather than a fake ref.
        for name in ("plain.png", "instrumented.png", "compositor.png"):
            raw.append(b.file_ref(root, f"{rel}/{name}", MAX_FILE))
        owned = b.json(b.path(root, f"{rel}/owned-window-process.json"))
        case_inputs = capture.get("meta", {}).get("conditions", {}).get("caseInputs", {})
        image = plain_doc.get("image", {})
        ax_text = _find_ax_text(ax_doc.get("steps", []))
        if ax_text is None:
            raise Hold(f"Mac run {ordinal} external AX text node missing")
        ax_geometry = derive_mac_text_geometry(ax_text)
        owned_client = owned.get("client") if isinstance(owned.get("client"), dict) else {}
        terminal_hold = mac_terminal_observation_hold(owned)
        rows.append({
            "ordinal": ordinal,
            "sourceRun": f"run-{ordinal:03d}",
            "captureSemanticHash": entry.get("captureHash"),
            "capture": capture,
            "raw": raw,
            "terminal": {
                "evidenceSource": "owned-window-process.json",
                "retainedProcessHandle": owned.get("retainedProcessHandle"),
                "processGroupOwned": owned.get("processGroupOwned"),
                "pid": owned.get("pid"),
                "executable": owned.get("executable"),
                "windowTitle": owned.get("windowTitle"),
                "client": {
                    "pid": owned_client.get("pid"),
                    "externalAX": owned_client.get("externalAX"),
                    "permissionRequests": owned_client.get("permissionRequests"),
                },
                "terminalHold": terminal_hold,
            },
            "semantic": {
                "text": case_inputs.get("text"),
                "font": plain_doc.get("fontContract"),
                "viewportDip": [image.get("width"), image.get("height")],
                "textNode": ax_text,
                "textNodeDip": ax_geometry,
                "axRaw": ax_text,
                "paint": {"foreground": case_inputs.get("foreground"), "font": case_inputs.get("font")},
                "plainHash": next((i.get("hash") for i in capture.get("images", []) if i.get("id") == "macos.plain"), None),
            },
        })
    assert first_capture is not None
    source_hash = validate_mac_provenance(summary, first_capture)
    if first_capture["tuple"].get("id") != TUPLE_ID:
        raise Hold("Mac tuple id mismatch")
    if first_capture["tuple"].get("rendererHash") != RENDERER_HASH:
        raise Hold("Mac renderer hash mismatch")
    if first_capture.get("meta", {}).get("host", {}).get("hash") != MAC_HOST_HASH:
        raise Hold("Mac capture host hash mismatch")
    compiler_receipt = summary.get("compilerReceipt", {}).get("compiler", {})
    if compiler_receipt.get("outputBinary", {}).get("sha256") != summary.get("binaryHash"):
        raise Hold("Mac compiler output hash is not joined to summary binary")
    if summary.get("binaryHash") != MAC_HOST_HASH:
        raise Hold("Mac summary binary hash does not match measured host")
    return {
        "platform": "macos", "case": case, "tuple": first_capture["tuple"],
        "sourceHash": source_hash,
        "hostHash": first_capture.get("meta", {}).get("host", {}).get("hash"),
        "rendererHash": first_capture["tuple"].get("rendererHash"),
        "recipe": summary.get("probeManifest", {}).get("recipe"),
        "compiler": {"binaryHash": summary.get("binaryHash"), "adapterSourceHash": summary.get("adapterSourceHash")},
        "rows": rows,
        "holds": [],
    }


def validate_windows_control(coordinator: dict[str, Any], task: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Validate actual control/coordinator schema; returns proofs unchanged."""
    if coordinator.get("count") != 20 or task.get("count") != 20:
        raise Hold("Windows coordinator/task-result do not both report count 20")
    if coordinator.get("status") != "completed-source-bound-observation" or task.get("status") != "completed-source-bound-observation":
        raise Hold("Windows coordinator/task-result status is not completed source-bound observation")
    if coordinator.get("wholeBatchExitConfirmed") is not True or coordinator.get("lockReleased") is not True:
        raise Hold("Windows coordinator missing whole-batch exit or lock-release proof")
    if coordinator.get("cleanupErrors") not in ([], None):
        raise Hold("Windows coordinator reports cleanup errors")
    parent = coordinator.get("taskParentProof")
    if not isinstance(parent, dict):
        raise Hold("Windows coordinator missing taskParentProof")
    for key, expected in (("kernelWait", 0), ("kernelExitCode", 0), ("kernelExitCodeSigned", 0), ("dotNetExitCode", 0)):
        if parent.get(key) != expected:
            raise Hold(f"Windows taskParentProof {key} is not zero")
    if parent.get("dotNetExited") is not True or not isinstance(parent.get("retainedHandle"), int):
        raise Hold("Windows taskParentProof lacks retained handle or .NET exit proof")
    memory = task.get("memoryReceipt")
    if not isinstance(memory, dict) or memory.get("status") != "passed":
        raise Hold("Windows task-result missing passed memoryReceipt")
    if memory.get("activeProcessCount") != 1 or memory.get("jobMemoryLimitBytes") != 1073741824 or memory.get("limitFlags") != 512:
        raise Hold("Windows memoryReceipt lacks required 1GiB self-job admission")
    if memory.get("killOnJobClose") is not False:
        raise Hold("Windows memoryReceipt killOnJobClose must be false")
    return parent, memory


def windows_adapter(root: Path, b: Bounded) -> dict[str, Any]:
    # Actual producer schema uses control/coordinator.json + task-result.json.
    # export-manifest.count is file count, so it must never become run count.
    coordinator = b.json(b.path(root, "control/coordinator.json"))
    task = b.json(b.path(root, "control/task-result.json"))
    parent, memory = validate_windows_control(coordinator, task)
    binding = b.json(b.path(root, "admission/candidate-binding.json"))
    candidate = b.json(b.path(root, "admission/candidate-tuple.json"))
    inputs = b.json(b.path(root, "admission/source-inputs.json"))
    plan = b.json(b.path(root, "native/plan.json"))
    obs = b.json(b.path(root, "native/observation.json"))
    same_identity(need(binding, "case", "Windows binding"), {"id": CASE_ID, "hash": CASE_HASH}, "Windows case")
    tuple_doc = need(candidate, "tuple", "Windows candidate tuple")
    if tuple_doc.get("id") != TUPLE_ID:
        raise Hold("Windows tuple id mismatch")
    if tuple_doc.get("hostHashes", {}).get("windows") != WIN_HOST_HASH:
        raise Hold("Windows host hash mismatch")
    if tuple_doc.get("hostHashes", {}).get("macos") != MAC_HOST_HASH:
        raise Hold("Windows tuple Mac host hash mismatch")
    if tuple_doc.get("rendererHash") != RENDERER_HASH:
        raise Hold("Windows tuple renderer hash mismatch")
    if candidate.get("case") != binding.get("case"):
        raise Hold("Windows candidate/binding case drift")
    for key, expected in (("caseID", CASE_ID), ("caseHash", CASE_HASH), ("tupleID", TUPLE_ID)):
        if key in inputs and inputs[key] != expected:
            raise Hold(f"Windows source-input {key} mismatch")
    if plan.get("case") != candidate.get("case") or obs.get("case") != candidate.get("case"):
        raise Hold("Windows plan/observation case drift")
    if obs.get("sourceHash") != binding.get("sourceHash"):
        raise Hold("Windows source hash drift")
    if binding.get("sourceHash") != SOURCE_HASH:
        raise Hold("Windows source hash does not match admitted Text witness")
    if obs.get("compilerHash") != plan.get("compilerHash"):
        raise Hold("Windows compiler hash drift")
    if plan.get("recipe") != candidate.get("recipe", plan.get("recipe")):
        # Candidate tuple roots from r11 do not carry recipe, so this branch
        # only rejects a producer that supplies a contradictory one.
        raise Hold("Windows plan/candidate recipe drift")
    rows: list[dict[str, Any]] = []
    for ordinal in range(1, 21):
        rel = f"native/native-{ordinal:02d}"
        outcome = b.json(b.path(root, f"{rel}/capture-outcome.json"))
        cert = b.json(b.path(root, f"{rel}/final-exit-certificate.json"))
        terminal_worker = b.json(b.path(root, f"{rel}/terminal-worker.json"))
        owned = b.json(b.path(root, f"{rel}/owned-process.json"))
        if outcome.get("case") not in (None, candidate.get("case")):
            raise Hold(f"Windows row {ordinal} case drift")
        if terminal_worker.get("terminalResultConfirmed") is not True:
            raise Hold(f"Windows row {ordinal} terminal worker not confirmed")
        sample = cert.get("sample")
        streams = cert.get("rawStreams")
        if not isinstance(sample, dict) or not isinstance(streams, list) or len(streams) != 2:
            raise Hold(f"Windows row {ordinal} missing terminal certificate streams")
        if sample.get("kernelAfter") != 0 or sample.get("exitCode") != 0 or sample.get("getExitCodeSucceeded") is not True:
            raise Hold(f"Windows row {ordinal} exit certificate is not zero/verified")
        if cert.get("start", {}).get("retainedHandle") is None or owned.get("pid") is None:
            raise Hold(f"Windows row {ordinal} missing original process identity")
        if any(s.get("sealed") is not True or s.get("copyCompleted") is not True or s.get("destinationClosed") is not True for s in streams):
            raise Hold(f"Windows row {ordinal} streams are not sealed")
        raw = []
        for filename in ("capture-outcome.json", "final-exit-certificate.json", "terminal-worker.json", "owned-process.json", "host.stdout.txt", "host.stderr.txt", "native.pixels.json", "native.uia.json", "native.printwindow.png", "native.screen.png"):
            raw.append(b.file_ref(root, f"{rel}/{filename}", MAX_FILE))
        pixels_doc = b.json(b.path(root, f"{rel}/native.pixels.json"))
        uia_doc = b.json(b.path(root, f"{rel}/native.uia.json"))
        dpi = pixels_doc.get("dpi")
        if not isinstance(dpi, (int, float)) or dpi <= 0:
            raise Hold(f"Windows row {ordinal} pixel observation missing positive dpi")
        uia_text = _find_uia_text(uia_doc)
        if uia_text is None:
            raise Hold(f"Windows row {ordinal} UIA text node missing")
        uia_geometry = derive_windows_text_geometry(uia_text, dpi)
        samples = pixels_doc.get("samples")
        if not isinstance(samples, list):
            raise Hold(f"Windows row {ordinal} pixel observation missing samples")
        print_hash = next((s.get("sha256") for s in samples if s.get("method") == "printwindow" and s.get("repeat") == 1), None)
        screen_hash = next((s.get("sha256") for s in samples if s.get("method") == "screen" and s.get("repeat") == 1), None)
        rows.append({"ordinal": ordinal, "sourceRun": f"native-{ordinal:02d}", "raw": raw,
                     "terminal": {"kernelWait": sample.get("kernelAfter"), "exitCode": sample.get("exitCode"),
                                   "originalHandleRetained": True, "streamDrainComplete": all(s.get("copyCompleted") is True for s in streams),
                                   "streamsSealed": all(s.get("sealed") is True for s in streams)},
                     "observation": outcome,
                     "semantic": {
                         "text": uia_text.get("value") if uia_text else None,
                         "viewportDip": [pixels_doc.get("width", 0) * 96 / dpi, pixels_doc.get("height", 0) * 96 / dpi],
                         "textNode": uia_text,
                         "textNodeDip": uia_geometry,
                         "uiaRaw": uia_text,
                         "printWindowHash": print_hash,
                         "screenHash": screen_hash,
                     }})
    return {
        "platform": "windows", "case": candidate["case"], "tuple": tuple_doc,
        "sourceHash": binding.get("sourceHash"), "hostHash": tuple_doc.get("hostHashes", {}).get("windows"),
        "rendererHash": binding.get("renderer", {}).get("sha256"),
        "recipe": plan.get("recipe"),
        "compiler": {"compilerHash": plan.get("compilerHash"), "exeHash": obs.get("exeSha256")},
        "rows": rows, "successfulCount": 20, "successfulCountRef": "control/coordinator.json", "memoryReceipt": memory, "parentProof": parent, "holds": [],
    }


def validate_pair(mac: dict[str, Any], win: dict[str, Any]) -> list[str]:
    holds = list(mac.get("holds", []))
    same_identity(mac["case"], win["case"], "paired case")
    if mac.get("tuple", {}).get("id") != win.get("tuple", {}).get("id"):
        raise Hold("paired tuple id mismatch")
    if mac.get("sourceHash") != win.get("sourceHash"):
        raise Hold("paired source hash mismatch")
    if mac.get("tuple") != win.get("tuple"):
        raise Hold("paired tuple contents mismatch")
    if mac.get("recipe") != win.get("recipe"):
        raise Hold("paired recipe identity mismatch")
    if mac.get("rendererHash") != win.get("rendererHash"):
        raise Hold("paired renderer hash mismatch")
    if mac.get("hostHash") != mac.get("tuple", {}).get("hostHashes", {}).get("macos"):
        holds.append("Mac host hash is absent or not joined to tuple")
    for row in mac["rows"]:
        t = row["terminal"]
        if t.get("terminalHold"):
            holds.append(f"Mac {row['sourceRun']} {t['terminalHold']}")
        if not t.get("evidenceSource") or not t.get("pid") or not t.get("executable"):
            holds.append(f"Mac {row['sourceRun']} missing owned-window process evidence")
    return holds


def compare(mac_root: Path, win_root: Path, count1_graph: Path, count20_graph: Path) -> dict[str, Any]:
    b = Bounded()
    result: dict[str, Any] = {
        "kind": "factory-text-paint-paired20-observed-v1", "status": "blocked",
        "parity": "held", "semantic": "held", "timing": "raw-only",
        "inputs": {"macRoot": str(mac_root), "windowsRoot": str(win_root)}, "holds": [],
    }
    try:
        g1 = validate_source_graph(count1_graph, b, 1)
        g20 = validate_source_graph(count20_graph, b, 20)
        mac = mac_adapter(mac_root, b)
        win = windows_adapter(win_root, b)
        result["mac"] = mac; result["windows"] = win
        result["sourceGraphs"] = {"count1": g1, "count20": g20}
        result["holds"] = validate_pair(mac, win)
        result["semantic"] = semantic_compare(mac, win)
        result["status"] = "observed-diagnostic"
        result["observed"] = {"macCount": len(mac["rows"]), "windowsCount": len(win["rows"]), "rawBytesRead": b.total}
    except Hold as e:
        result["holds"].append(str(e)); result["status"] = "blocked"
        result["observed"] = {"rawBytesRead": b.total}
    return result


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mac-root", type=Path, required=True)
    p.add_argument("--windows-root", type=Path, required=True)
    p.add_argument("--count1-graph", type=Path, required=True)
    p.add_argument("--count20-graph", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    report = compare(args.mac_root, args.windows_root, args.count1_graph, args.count20_graph)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_suffix(args.output.suffix + ".tmp")
    tmp.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, args.output)
    return 0 if report["status"] != "blocked" else 2


if __name__ == "__main__":
    raise SystemExit(main())
