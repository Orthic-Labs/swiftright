"""Strict source/case-bound F9 observation helpers for three next cases.

This module compares only exact accessibility labels/roles when both sides
exist. Provider pixels and clock records remain raw, provider-scoped evidence.
No qualification or parity decision is made here.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


CASES = {
    "swiftui.padding-frame": {
        "caseId": "swiftui.padding-frame.recipe/case/8805e6d0729b052d",
        "caseSha256": "58a7c081166141df0b496c4b9ccd0043731d03048993f27842b171387d5c4d5b",
        "sourceSha256": "b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b",
        "macRoot": "factory/native/macos/evidence/20261010-primary-next-five/swiftui.padding-frame.recipe_case_8805e6d0729b052d",
        "windowsRoot": "factory/native/windows/round1-native-v3/single-padding-frame-r1",
    },
    "swiftui.preference-key": {
        "caseId": "swiftui.preference-key.recipe/case/66b6b44aaff817d6",
        "caseSha256": "b2292465cf5f9857b92345a973fc413611365606aec12c9dc435f14ed62bc96d",
        "sourceSha256": "e104e949a6e0f8c6e9e41a6d2d7815a112a40e19d5919b82d2074fd7f5bf9c1f",
        "macRoot": "factory/native/macos/evidence/20261010-corrected-primary/swiftui.preference-key.recipe_case_66b6b44aaff817d6",
        "windowsRoot": "factory/native/windows/round1-native-v3/single-preference-key-r1",
    },
    "swiftui.scroll-view": {
        "caseId": "swiftui.scroll-view.recipe/case/6716afb4fb55269b",
        "caseSha256": "56c2625f63e7e633c18ea0cdfca37545748f1d098622391e3c270be07895dc98",
        "sourceSha256": "cd6615468e11e0137c6e1c9ada25c0cdf2f5a0f4c33668ec63161674b743a2c4",
        "macRoot": "factory/native/macos/evidence/20261010-primary-next-five/swiftui.scroll-view.recipe_case_6716afb4fb55269b",
        "windowsRoot": "factory/native/windows/round1-native-v4/single-scroll-r1",
    },
}

ROLE_MAP = {"AXStaticText": "ControlType.Text"}
INPUT_MANIFEST_SHA256 = "7ac004e1aa4e250e14b5b604eaffc450defa366addcc10608a828b61cb3d79d1"


class ObservationError(ValueError):
    pass


def sha256(raw: bytes) -> str:
    if not isinstance(raw, bytes):
        raise ObservationError("raw input must be bytes")
    return hashlib.sha256(raw).hexdigest()


def _decode(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ObservationError(f"invalid JSON input: {label}") from exc


def _payloads(manifest_bytes: bytes, payloads: dict[str, bytes]) -> dict[str, dict]:
    if sha256(manifest_bytes) != INPUT_MANIFEST_SHA256:
        raise ObservationError("source input manifest hash mismatch")
    manifest = _decode(manifest_bytes, "source input manifest")
    if (not isinstance(manifest, dict) or manifest.get("schema") != "paired-next-observation-input-manifest-v1"
            or manifest.get("status") != "frozen-single-windows-observations-vs-mac-20-run-candidate"
            or type(manifest.get("caseCount")) is not int or manifest["caseCount"] != 3
            or manifest.get("cases") != _expected_cases()):
        raise ObservationError("source input manifest identity mismatch")
    rows = manifest.get("inputs")
    if not isinstance(rows, list) or not rows:
        raise ObservationError("source input manifest empty")
    refs: dict[str, dict] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ObservationError("malformed source input row")
        path, digest, size, channel = row.get("path"), row.get("sha256"), row.get("bytes"), row.get("channel")
        if (not isinstance(path, str) or not path.startswith("factory/") or ".." in Path(path).parts
                or not isinstance(digest, str) or len(digest) != 64
                or type(size) is not int or size < 0 or not isinstance(channel, str) or not channel):
            raise ObservationError("malformed source input reference")
        if path in refs:
            raise ObservationError("duplicate source input path")
        refs[path] = row
    if set(payloads) != set(refs):
        raise ObservationError("raw payload set does not match frozen manifest")
    for path, row in refs.items():
        raw = payloads[path]
        if not isinstance(raw, bytes) or len(raw) != row["bytes"] or sha256(raw) != row["sha256"]:
            raise ObservationError(f"source bytes changed: {path}")
    return {"manifest": manifest, "refs": refs}


def _expected_cases() -> dict[str, dict[str, str]]:
    return {
        block: {
            "caseId": value["caseId"], "caseSha256": value["caseSha256"],
            "sourceSha256": value["sourceSha256"], "macRoot": value["macRoot"],
            "windowsRoot": value["windowsRoot"],
        }
        for block, value in CASES.items()
    }


def load_pinned_inputs(repo_root: Path) -> tuple[bytes, dict[str, bytes]]:
    manifest_path = repo_root / "factory/pipeline/paired-next-observations-v1/source-inputs-v1.json"
    manifest_bytes = manifest_path.read_bytes()
    if sha256(manifest_bytes) != INPUT_MANIFEST_SHA256:
        raise ObservationError("source input manifest bytes changed")
    manifest = _decode(manifest_bytes, "source input manifest")
    payloads = {row["path"]: (repo_root / row["path"]).read_bytes() for row in manifest["inputs"]}
    _payloads(manifest_bytes, payloads)
    return manifest_bytes, payloads


def _object(payloads: dict[str, bytes], path: str) -> Any:
    try:
        return _decode(payloads[path], path)
    except KeyError as exc:
        raise ObservationError(f"required source input missing: {path}") from exc


def _walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def validate_identity(block: str, *, case_id: Any, case_sha256: Any, source_sha256: Any) -> None:
    expected = CASES.get(block)
    if expected is None:
        raise ObservationError("unknown next-case block")
    if (case_id != expected["caseId"] or case_sha256 != expected["caseSha256"]
            or source_sha256 != expected["sourceSha256"]):
        raise ObservationError("source/case identity mismatch")


def mac_accessibility(raw: Any, *, block: str, case_id: str, source_sha256: str,
                      owner_hash: str) -> list[dict[str, str]]:
    expected = CASES.get(block)
    if expected is None:
        raise ObservationError("unknown next-case block")
    if (not isinstance(raw, dict) or raw.get("status") != "OBSERVED"
            or raw.get("permissionRequests") is not False or raw.get("mode") != "fresh-external-ax"):
        raise ObservationError("Mac AX input is not an exact no-prompt observation")
    if (source_sha256 != expected["sourceSha256"] or case_id != expected["caseId"]
            or raw.get("ownerHash") != owner_hash or not isinstance(owner_hash, str)
            or not owner_hash.startswith("sha256:") or len(owner_hash) != 71):
        raise ObservationError("Mac AX source/case/owner identity mismatch")
    steps = raw.get("steps")
    if not isinstance(steps, list) or len(steps) != 1:
        raise ObservationError("Mac AX snapshot step count mismatch")
    tree = steps[0].get("tree") if isinstance(steps[0], dict) else None
    if not isinstance(tree, dict):
        raise ObservationError("Mac AX snapshot tree missing")
    window_title = raw.get("windowTitle")
    if window_title != "SwiftRightFactory-" + case_id:
        raise ObservationError("Mac AX window title does not bind exact case")
    values: list[dict[str, str]] = []
    for node in _walk(tree):
        if node.get("role") != "AXStaticText":
            continue
        value = node.get("value")
        if not isinstance(value, str):
            raise ObservationError("Mac static text lacks string value")
        # Window title is host chrome, excluded only by exact equality with
        # owner-supplied windowTitle; all other labels remain in source order.
        if value == window_title:
            continue
        values.append({"role": "AXStaticText", "value": value})
    if type(raw.get("pid")) is not int or type(raw.get("clientPID")) is not int:
        raise ObservationError("Mac AX owner/client PID missing or malformed")
    if not values:
        raise ObservationError("Mac AX content text is empty")
    return values


def windows_accessibility(raw: Any, *, block: str, case_id: str, case_sha256: str,
                          source_sha256: str) -> list[dict[str, Any]]:
    validate_identity(block, case_id=case_id, case_sha256=case_sha256,
                      source_sha256=source_sha256)
    if not isinstance(raw, dict):
        raise ObservationError("Windows UIA input is not an object")
    windows = [node for node in _walk(raw) if node.get("controlType") == "ControlType.Window"]
    if len(windows) != 1 or type(windows[0].get("enabled")) is not bool:
        raise ObservationError("Windows UIA window identity/access is malformed")
    values = []
    for node in _walk(windows[0]):
        if node.get("controlType") != "ControlType.Text":
            continue
        name = node.get("name")
        if not isinstance(name, str):
            raise ObservationError("Windows UIA text lacks string name")
        values.append({"role": "ControlType.Text", "value": name})
    if not values:
        raise ObservationError("Windows UIA content text is empty")
    return values


def compare_accessibility(mac_values: list[dict[str, str]],
                          windows_values: list[dict[str, Any]]) -> dict[str, Any]:
    mapped = []
    for item in mac_values:
        role = ROLE_MAP.get(item.get("role"))
        if role is None:
            raise ObservationError("Mac role has no explicit cross-provider mapping")
        mapped.append({"role": role, "value": item["value"]})
    same = mapped == windows_values
    return {
        "comparison": "exact-role-and-label-sequence",
        "roleMap": dict(ROLE_MAP),
        "macMappedValues": mapped,
        "windowsValues": windows_values,
        "exactSequenceMatch": same,
        "interpretation": "observed-match" if same else "observed-difference",
        "qualification": "not-claimed",
    }


def mac_run_observation(*, block: str, summary: Any, run_summary: Any,
                       raw_ax: Any, raw_ax_bytes: bytes, capture: Any,
                       capture_bytes: bytes, clock: Any) -> dict[str, Any]:
    expected = CASES.get(block)
    if expected is None:
        raise ObservationError("unknown next-case block")
    if not isinstance(summary, dict) or not isinstance(run_summary, dict):
        raise ObservationError("Mac summary records missing")
    if (summary.get("case", {}).get("id") != expected["caseId"]
            or summary.get("case", {}).get("hash") != "sha256:" + expected["caseSha256"]
            or summary.get("provenance", {}).get("sourceHash") != "sha256:" + expected["sourceSha256"]
            or summary.get("probeManifest", {}).get("sourceHash") != "sha256:" + expected["sourceSha256"]
            or summary.get("acceptance") != "not-promoted"):
        raise ObservationError("Mac summary is not exact source/case candidate")
    run_no = run_summary.get("run")
    if type(run_no) is not int or run_no < 1:
        raise ObservationError("Mac run index malformed")
    if (run_summary.get("externalAXRawHash") != "sha256:" + sha256(raw_ax_bytes)
            or run_summary.get("captureHash") != "sha256:" + sha256(capture_bytes)):
        raise ObservationError("Mac raw AX/capture bytes disagree with run summary")
    if (not isinstance(capture, dict) or capture.get("case", {}).get("id") != expected["caseId"]
            or capture.get("case", {}).get("hash") != "sha256:" + expected["caseSha256"]
            or capture.get("meta", {}).get("run") != run_no):
        raise ObservationError("Mac capture case/run identity mismatch")
    owner_hash = run_summary.get("ownerHash") or summary.get("binaryHash")
    values = mac_accessibility(raw_ax, block=block, case_id=expected["caseId"],
                               source_sha256=expected["sourceSha256"], owner_hash=owner_hash)
    timing = retain_raw_timing(mac_clock=clock, windows_observation={})
    return {
        "run": run_no,
        "labels": values,
        "ownerPid": raw_ax.get("pid"),
        "clientPid": raw_ax.get("clientPID"),
        "paint": {
            "status": run_summary.get("compositorPaint"),
            "compositorPngSha256": str(run_summary.get("compositorPngHash", "")).removeprefix("sha256:"),
            "rawCompositorSha256": str(run_summary.get("compositorRawHash", "")).removeprefix("sha256:"),
            "scope": run_summary.get("compositorScope"),
            "captureImages": capture.get("images"),
        },
        "timing": timing,
    }


def retain_raw_timing(*, mac_clock: Any, windows_observation: Any,
                      windows_task_result: Any | None = None) -> dict[str, Any]:
    """Retain clocks verbatim; do not compare unlike clock domains."""
    if not isinstance(mac_clock, dict):
        raise ObservationError("Mac clock receipt missing")
    start, end = mac_clock.get("startNs"), mac_clock.get("endNs")
    if type(start) is not int or type(end) is not int or end < start:
        raise ObservationError("Mac raw clock bounds malformed")
    if mac_clock.get("clockId") != "macos.dispatch.uptime":
        raise ObservationError("Mac clock source changed")
    win = windows_observation if isinstance(windows_observation, dict) else {}
    task = windows_task_result if isinstance(windows_task_result, dict) else {}
    # Compile timestamps are explicitly separated from UI runtime. Capture
    # packets may add their own raw timing records in later versioned inputs.
    return {
        "macRawClock": dict(mac_clock),
        "macElapsedNsWithinClock": end - start,
        "windowsRawCompileTiming": {
            key: win.get(key) for key in ("startedAt", "processStartedAt", "finishedAt") if key in win
        },
        "windowsRawTaskTiming": {
            key: task.get(key) for key in ("startedAt", "finishedAt") if key in task
        },
        "crossPlatformTimingComparison": "unavailable-different-clock-scopes",
    }


def windows_paint_observation(*, block: str, plan: Any, native: Any,
                              observation: Any, uia: Any, pixels: Any,
                              printwindow: bytes, printwindow_repeat: bytes,
                              screen: bytes, screen_repeat: bytes) -> dict[str, Any]:
    expected = CASES.get(block)
    if expected is None:
        raise ObservationError("unknown next-case block")
    for row, label in ((plan, "plan"), (native, "native observation")):
        if not isinstance(row, dict):
            raise ObservationError(f"Windows {label} missing")
        case = row.get("case")
        validate_identity(block, case_id=case.get("id") if isinstance(case, dict) else None,
                          case_sha256=(case.get("hash", "").removeprefix("sha256:")
                                       if isinstance(case, dict) else None),
                          source_sha256=str(row.get("sourceHash", "")).removeprefix("sha256:"))
    if (plan.get("kind") != "windows-observational-plan"
            or native.get("hostValid") is not True
            or type(native.get("index")) is not int or native.get("index") != 1
            or native.get("nativeParity") != "hold"
            or native.get("occlusionQualified") is not False
            or native.get("captureMethod") != "UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen"
            or native.get("frozenTupleBound") is not False
            or native.get("closureBinding") is not None):
        raise ObservationError("Windows packet is not held source-bound observation")
    if (not isinstance(observation, dict) or type(observation.get("exitCode")) is not int
            or observation.get("exitCode") != 0 or observation.get("timedOut") is not False):
        raise ObservationError("Windows owned process did not complete successfully")
    if observation.get("sourceHash") != "sha256:" + expected["sourceSha256"]:
        raise ObservationError("Windows process receipt source mismatch")
    semantic = windows_accessibility(uia, block=block, case_id=expected["caseId"],
                                     case_sha256=expected["caseSha256"],
                                     source_sha256=expected["sourceSha256"])
    if not isinstance(pixels, dict) or pixels.get("kind") != "factory-background-pixel-observation":
        raise ObservationError("Windows pixel receipt missing")
    for key in ("width", "height", "dpi"):
        if type(pixels.get(key)) is not int or pixels[key] <= 0:
            raise ObservationError(f"Windows pixel {key} is not a positive integer")
    samples = pixels.get("samples")
    if not isinstance(samples, list):
        raise ObservationError("Windows pixel sample list missing")
    pw = [s for s in samples if isinstance(s, dict) and s.get("method") == "printwindow"]
    repeat = [s for s in samples if isinstance(s, dict) and s.get("method") == "printwindow" and s.get("repeat") == 2]
    screen_samples = [s for s in samples if isinstance(s, dict) and s.get("method") == "screen"]
    screen_repeat_row = [s for s in screen_samples if s.get("repeat") == 2]
    if len(pw) != 2 or len(repeat) != 1 or len(screen_samples) != 2 or len(screen_repeat_row) != 1:
        raise ObservationError("Windows PrintWindow/screen primary/repeat sample count mismatch")
    file_hash, repeat_hash = sha256(printwindow), sha256(printwindow_repeat)
    screen_hash, screen_repeat_hash = sha256(screen), sha256(screen_repeat)
    if (type(pw[0].get("repeat")) is not int or pw[0].get("repeat") != 1
            or type(repeat[0].get("repeat")) is not int or repeat[0].get("repeat") != 2
            or pw[0].get("sha256") != file_hash
            or repeat[0].get("sha256") != repeat_hash
            or screen_samples[0].get("repeat") != 1
            or screen_samples[0].get("sha256") != screen_hash
            or screen_repeat_row[0].get("sha256") != screen_repeat_hash
            or screen_hash != screen_repeat_hash or pixels.get("screenRepeatStable") is not True
            or pixels.get("printWindowRepeatStable") is not True or file_hash != repeat_hash):
        raise ObservationError("PrintWindow bytes do not match exact raw receipt/repeat")
    return {
        "identity": {"block": block, "caseId": expected["caseId"],
                     "caseSha256": expected["caseSha256"], "sourceSha256": expected["sourceSha256"]},
        "uia": semantic,
        "printWindow": {
            "provider": "Windows PrintWindow",
            "widthPx": pixels.get("width"), "heightPx": pixels.get("height"),
            "dpi": pixels.get("dpi"), "flags": pixels.get("printWindowFlagNames"),
            "primarySha256": file_hash, "repeatSha256": repeat_hash,
            "sameProviderRepeatExact": file_hash == repeat_hash,
            "screenPrimarySha256": screen_hash, "screenRepeatSha256": screen_repeat_hash,
            "sameScreenRepeatExact": screen_hash == screen_repeat_hash,
            "crossProviderPixelComparison": "not-performed",
        },
        "qualification": {
            "nativeParity": "held", "controlledOcclusion": "not-qualified",
            "frozenTupleBound": False, "acceptedGolden": False,
        },
    }


def build_report(manifest_bytes: bytes, payloads: dict[str, bytes]) -> dict[str, Any]:
    checked = _payloads(manifest_bytes, payloads)
    manifest, refs = checked["manifest"], checked["refs"]
    cases: dict[str, Any] = {}
    for block, expected in CASES.items():
        info = manifest["cases"][block]
        mac_root, win_root = info["macRoot"], info["windowsRoot"]
        summary = _object(payloads, mac_root + "/summary.json")
        if (summary.get("kind") != "macos-host-capture-candidate"
                or summary.get("candidateOnly") is not True
                or summary.get("independentProcessesPerRun") is not True
                or len(summary.get("runs", [])) != 20):
            raise ObservationError(f"Mac source batch is not 20 independent runs: {block}")
        mac_runs = []
        owner_pids, client_pids = set(), set()
        for index in range(1, 21):
            run_summary = [row for row in summary["runs"] if row.get("run") == index]
            if len(run_summary) != 1:
                raise ObservationError(f"Mac summary run index missing/duplicate: {block}/{index}")
            run_summary = run_summary[0]
            base = f"{mac_root}/run-{index:03d}"
            raw_ax_path, capture_path = base + "/external-ax.raw.json", base + "/capture.json"
            clock_path, paint_raw_path = base + "/clock.json", base + "/compositor.raw.json"
            paint_png_path = base + "/compositor.png"
            capture = _object(payloads, capture_path)
            raw_ax = _object(payloads, raw_ax_path)
            clock = _object(payloads, clock_path)
            mac = mac_run_observation(block=block, summary=summary, run_summary=run_summary,
                                     raw_ax=raw_ax, raw_ax_bytes=payloads[raw_ax_path],
                                     capture=capture, capture_bytes=payloads[capture_path], clock=clock)
            if mac["ownerPid"] in owner_pids or mac["clientPid"] in client_pids:
                raise ObservationError(f"Mac AX process reused in batch: {block}")
            owner_pids.add(mac["ownerPid"])
            client_pids.add(mac["clientPid"])
            paint_raw = _object(payloads, paint_raw_path)
            compositor_images = [image for image in capture.get("images", [])
                                 if isinstance(image, dict) and image.get("id") == "macos.compositor"]
            if (len(compositor_images) != 1
                    or compositor_images[0].get("hash") != "sha256:" + sha256(payloads[paint_png_path])
                    or paint_raw.get("status") != "OBSERVED"
                    or paint_raw.get("permissionRequests") is not False
                    or paint_raw.get("windowTitle") != "SwiftRightFactory-" + expected["caseId"]):
                raise ObservationError(f"Mac compositor raw capture did not join exact PNG/case: {block}/{index}")
            mac["paint"].update({
                "compositorPngRawSha256": sha256(payloads[paint_png_path]),
                "compositorRawInputSha256": sha256(payloads[paint_raw_path]),
                "compositorWidthPx": compositor_images[0].get("widthPx"),
                "compositorHeightPx": compositor_images[0].get("heightPx"),
            })
            mac["rawInputs"] = {name: refs[path]["sha256"] for name, path in {
                "externalAX": raw_ax_path, "capture": capture_path, "clock": clock_path,
                "compositorRaw": paint_raw_path, "compositorPng": paint_png_path,
            }.items()}
            mac_runs.append(mac)

        plan = _object(payloads, win_root + "/replays/run-001/plan.json")
        native = _object(payloads, win_root + "/replays/run-001/native-observation.json")
        compile_obs = _object(payloads, win_root + "/replays/run-001/observation.json")
        task = _object(payloads, win_root + "/replays/run-001/task-result.json")
        native_root = win_root + "/replays/run-001/native-01"
        if native.get("compileReceiptHash") != sha256(payloads[win_root + "/replays/run-001/observation.json"]):
            raise ObservationError(f"Windows native capture compile receipt hash mismatch: {block}")
        native_files = native.get("files")
        if not isinstance(native_files, list) or not native_files:
            raise ObservationError(f"Windows native file inventory missing: {block}")
        native_file_map: dict[str, str] = {}
        for row in native_files:
            if not isinstance(row, dict) or not isinstance(row.get("path"), str):
                raise ObservationError(f"Windows native file inventory malformed: {block}")
            path = row["path"]
            if path in native_file_map or not isinstance(row.get("sha256"), str):
                raise ObservationError(f"Windows native file inventory duplicate/malformed: {block}")
            native_file_map[path] = row["sha256"]
            if path not in payloads or sha256(payloads[path]) != row["sha256"]:
                # Native paths are relative to native-01; source manifest uses
                # repository paths, so resolve exact leaf below.
                full_path = native_root + "/" + path
                if full_path not in payloads or sha256(payloads[full_path]) != row["sha256"]:
                    raise ObservationError(f"Windows native file hash receipt mismatch: {block}/{path}")
        expected_native_files = {
            "capture-outcome.json", "host.stderr.txt", "host.stdout.txt", "launch-observation.json",
            "native.pixels.json", "native.printwindow.png", "native.printwindow.repeat.png",
            "native.screen.png", "native.screen.repeat.png", "native.uia.json", "owned-process.json",
        }
        if set(native_file_map) != expected_native_files:
            raise ObservationError(f"Windows native file inventory set changed: {block}")
        if native.get("exeSha256") != compile_obs.get("exeSha256"):
            raise ObservationError(f"Windows executable hash lineage mismatch: {block}")
        owner = _object(payloads, native_root + "/owned-process.json")
        pixels_obj = _object(payloads, native_root + "/native.pixels.json")
        if (owner.get("pid") != pixels_obj.get("pid") or owner.get("path") != compile_obs.get("exePath")
                or pixels_obj.get("printWindowFlagNames") is None):
            raise ObservationError(f"Windows owner/pixel/compile identity mismatch: {block}")
        windows = windows_paint_observation(
            block=block, plan=plan, native=native, observation=compile_obs,
            uia=_object(payloads, native_root + "/native.uia.json"),
            pixels=pixels_obj,
            printwindow=payloads[native_root + "/native.printwindow.png"],
            printwindow_repeat=payloads[native_root + "/native.printwindow.repeat.png"],
            screen=payloads[native_root + "/native.screen.png"],
            screen_repeat=payloads[native_root + "/native.screen.repeat.png"])
        comparisons = [compare_accessibility(row["labels"], windows["uia"])
                       for row in mac_runs]
        cases[block] = {
            "identity": {"caseId": expected["caseId"], "caseSha256": expected["caseSha256"],
                         "sourceSha256": expected["sourceSha256"]},
            "macOS": {"runs": 20, "channel": "external AX + compositor paint",
                      "runObservations": mac_runs},
            "windows": {"runs": 1, "channel": "UIA + PrintWindow",
                        "sourcePacket": "fresh-single-observation", "observation": windows,
                        "compileTimingRaw": {key: compile_obs.get(key) for key in
                                             ("startedAt", "processStartedAt", "finishedAt") if key in compile_obs},
                        "taskResultRaw": task},
            "accessibilityComparisons": comparisons,
            "timingDisposition": "raw-clock-values-retained; no cross-platform timing comparison",
            "pixelDisposition": "raw provider outputs retained; no coordinate or pixel normalization",
            "inputPaths": sorted(path for path in refs if path.startswith(mac_root + "/")
                                  or path.startswith(win_root + "/")),
        }
    return {
        "schema": "paired-next-observational-report-v1",
        "status": "source-bound-observation-only",
        "inputManifestSha256": INPUT_MANIFEST_SHA256,
        "caseCount": 3,
        "cases": cases,
        "qualification": {
            "acceptedGoldenCount": 0, "nativeParity": "held",
            "timingParity": "held", "pixelParity": "held",
            "controlledOcclusion": "not-qualified", "hitTesting": "not-attempted",
            "providerReadback": "unavailable", "semanticPromotion": "not-requested",
        },
        "denominators": {"MacRunsPerCase": 20, "WindowsRunsPerCase": 1},
    }
