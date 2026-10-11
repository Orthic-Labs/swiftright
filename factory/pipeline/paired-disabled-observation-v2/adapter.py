"""Source-bound, observational-only report for independent F9 disabled batches."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

MANIFEST_SHA256 = "53e223357633c74d790e8c4af704882ab10d5d8d1727aa6bbc413e1c41d513cb"
CASE_ID = "swiftui.disabled.recipe/case/f113195a59446fc4"
SOURCE_SHA256 = "68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
CASE_SHA256 = "d6a88082e0818e46e4e1ea5e6d45af6edbce63c86fc6b847704c38ad3db9aa99"
PROBE_SHA256 = "5e155ed85464617856bff8796c548a4bca943b0a4e1176425a6f8f3e63a4b27e"
MAC_AX_ROOT = "factory/native/macos/disabled-enabled-observation-v1/evidence"
MAC_PAINT_ROOT = "factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4"
WIN_ROOT = "factory/native/windows/disabled-repeatability-batch-v1/actual-r1"


class ObservationError(ValueError):
    pass


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _json(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ObservationError(f"invalid JSON: {label}") from exc


def _walk(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _inputs(manifest_bytes: bytes, payloads: dict[str, bytes]) -> tuple[dict, dict[str, dict]]:
    if not isinstance(manifest_bytes, bytes) or _sha(manifest_bytes) != MANIFEST_SHA256:
        raise ObservationError("frozen source manifest hash mismatch")
    manifest = _json(manifest_bytes, "input manifest")
    if (manifest.get("kind") != "paired-disabled-observation-v2-input-manifest"
            or manifest.get("version") != 2 or type(manifest.get("version")) is not int
            or manifest.get("caseId") != CASE_ID or manifest.get("sourceSha256") != SOURCE_SHA256):
        raise ObservationError("input manifest identity mismatch")
    rows = manifest.get("inputs")
    if not isinstance(rows, list) or not rows:
        raise ObservationError("input manifest is empty")
    by_path: dict[str, dict] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ObservationError("malformed input row")
        path, channel, digest, size = (row.get("path"), row.get("channel"), row.get("sha256"), row.get("bytes"))
        if (not isinstance(path, str) or not path.startswith("factory/") or ".." in Path(path).parts
                or not isinstance(channel, str) or not channel or not isinstance(digest, str)
                or len(digest) != 64 or type(size) is not int or size < 0):
            raise ObservationError("malformed input reference")
        if path in by_path:
            raise ObservationError("duplicate input path")
        by_path[path] = row
    if set(payloads) != set(by_path):
        raise ObservationError("payload set differs from full frozen source set")
    for path, row in by_path.items():
        raw = payloads[path]
        if not isinstance(raw, bytes) or len(raw) != row["bytes"] or _sha(raw) != row["sha256"]:
            raise ObservationError(f"source bytes mismatch: {path}")
    expected_channels = {"macos-ax-batch", "macos-ax-review", "macos-paint-batch", "windows-repeatability-batch", "windows-review", "shared-source"}
    if {r["channel"] for r in rows} != expected_channels:
        raise ObservationError("source channel set changed")
    return manifest, by_path


def _data(payloads: dict[str, bytes], path: str) -> Any:
    try:
        return _json(payloads[path], path)
    except KeyError as exc:
        raise ObservationError(f"missing source file: {path}") from exc


def _unique_continue(node: Any, role: str, label_key: str) -> dict:
    found = [x for x in _walk(node) if x.get(role) == ("AXButton" if role == "role" else "ControlType.Button")
             and x.get(label_key) == "Continue"]
    if len(found) != 1:
        raise ObservationError(f"{role} Continue target is not unique")
    return found[0]


def build_report(manifest_bytes: bytes, payloads: dict[str, bytes]) -> dict:
    manifest, refs = _inputs(manifest_bytes, payloads)
    def channel(name: str) -> list[dict]:
        return [row for row in manifest["inputs"] if row["channel"] == name]
    def has(path: str) -> dict:
        try:
            return refs[path]
        except KeyError as exc:
            raise ObservationError(f"required evidence missing: {path}") from exc
    case_path = "factory/pipeline/cases/swiftui.disabled.recipe--case--f113195a59446fc4.json"
    source_path = "factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.swift"
    probe_path = "factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.manifest.json"
    case = _data(payloads, case_path)
    probe = _data(payloads, probe_path)
    if _sha(payloads[case_path]) != CASE_SHA256 or _sha(payloads[source_path]) != SOURCE_SHA256 or _sha(payloads[probe_path]) != PROBE_SHA256:
        raise ObservationError("F9 case/source/probe bytes differ from frozen identity")
    if case.get("id") != CASE_ID or case.get("block") != "swiftui.disabled":
        raise ObservationError("F9 case identity mismatch")
    if probe.get("sourceHash") != "sha256:" + SOURCE_SHA256 or probe.get("case", {}).get("hash") != "sha256:" + CASE_SHA256:
        raise ObservationError("probe manifest does not bind source and case")

    ax_report_path = f"{MAC_AX_ROOT}/report.json"
    ax_input_path = f"{MAC_AX_ROOT}/input-manifest.json"
    old_summary_path = f"{MAC_PAINT_ROOT}/summary.json"
    win_analysis_path = "factory/native/windows/disabled-repeatability-batch-v1/analysis.json"
    mac_review_path = "factory/native/macos/disabled-enabled-observation-v1/independent-review/independent-review.json"
    win_review_path = "factory/native/windows/disabled-repeatability-batch-v1/actual-review/report.json"
    ax_report = _data(payloads, ax_report_path)
    ax_input = _data(payloads, ax_input_path)
    paint = _data(payloads, old_summary_path)
    win_analysis = _data(payloads, win_analysis_path)
    mac_review = _data(payloads, mac_review_path)
    win_review = _data(payloads, win_review_path)
    if (ax_report.get("kind") != "disabled-enabled-ax-observation-v1" or ax_report.get("caseId") != CASE_ID
            or ax_report.get("newObservationCount") != 20 or ax_report.get("observedEnabledTrueCount") != 20
            or ax_report.get("permissionRequests") is not False or ax_report.get("noInputInvoked") is not True):
        raise ObservationError("Mac AX-only batch summary is not 20 valid observations")
    if ax_input.get("caseSha256") != CASE_SHA256 or ax_input.get("axClient", {}).get("sourceSha256") != "0ba89941a66465fdfd3f6c7f8b90d4bf049dcbb561a2d2cec846cace349eea51":
        raise ObservationError("Mac AX-only client/case lineage mismatch")
    if (mac_review.get("kind") != "disabled-enabled-ax-independent-review"
            or mac_review.get("observation", {}).get("enabledTrueCount") != 20
            or mac_review.get("observation", {}).get("newRunCount") != 20
            or mac_review.get("observation", {}).get("noInputInvoked") is not True
            or mac_review.get("observation", {}).get("permissionRequests") is not False
            or not all(value is True for value in mac_review.get("checks", {}).values())):
        raise ObservationError("Mac AX independent review receipt does not clear bounded raw joins")
    if (paint.get("kind") != "macos-host-capture-candidate" or paint.get("case", {}).get("id") != CASE_ID
            or paint.get("sourceHash") != "sha256:" + SOURCE_SHA256 or paint.get("independentProcessesPerRun") is not True
            or len(paint.get("runs", [])) != 20):
        raise ObservationError("historical Mac paint batch summary changed")
    if (win_analysis.get("kind") != "windows-disabled-observational-repeatability" or win_analysis.get("runs") != 20
            or win_analysis.get("uniquePids") != 20 or win_analysis.get("caseId") != CASE_ID
            or win_analysis.get("sourceHash") != SOURCE_SHA256 or win_analysis.get("qualifiedWindowsBatches") != 0
            or win_analysis.get("observedSemanticRepeatability") is not True or win_analysis.get("printWindowDistinctHashes") != 1
            or win_analysis.get("qualifiedTiming") != "unavailable" or win_analysis.get("hitTesting") != "not-attempted"
            or win_analysis.get("nativeParity") != "hold"):
        raise ObservationError("Windows batch analysis changed or indicates qualification")
    if (win_review.get("kind") != "independent-disabled-repeatability-actual-review"
            or win_review.get("verdict") != "VERIFIED-BOUNDED-20-RAW-OBSERVATIONS"
            or win_review.get("pins", {}).get("analysis") != refs[win_analysis_path]["sha256"]
            or win_review.get("pins", {}).get("sourceHash") != SOURCE_SHA256
            or win_review.get("pins", {}).get("caseHash") != CASE_SHA256
            or win_review.get("checks", {}).get("runs") != 20
            or win_review.get("checks", {}).get("uniquePids") != 20
            or win_review.get("checks", {}).get("uniqueHwnds") != 20
            or win_review.get("checks", {}).get("locksReleased") is not True
            or win_review.get("checks", {}).get("pixelRepeatsExact") is not True
            or win_review.get("qualification", {}).get("qualifiedWindowsBatches") != 0):
        raise ObservationError("Windows actual-r1 independent review receipt changed")

    mac_ax_runs = []
    mac_ax_pids = set()
    mac_ax_client_pids = set()
    for index in range(1, 21):
        base = f"{MAC_AX_ROOT}/run-{index:03d}"
        raw_path = f"{base}/external-ax.raw.json"
        result_path = f"{base}/result.json"
        owner_path = f"{base}/owner-process.json"
        raw = _data(payloads, raw_path)
        result = _data(payloads, result_path)
        owner = _data(payloads, owner_path)
        summary_rows = [row for row in ax_report.get("results", []) if row.get("run") == index]
        button = _unique_continue(raw, "role", "label")
        attr = button.get("enabledAttribute")
        if (raw.get("kind") != "fresh-external-ax-enabled-observation" or raw.get("status") != "OBSERVED"
                or raw.get("caseId") != CASE_ID or raw.get("sourceSha256") != "sha256:" + SOURCE_SHA256
                or raw.get("permissionRequests") is not False or result.get("run") != index
                or result.get("status") != "OBSERVED" or result.get("ownerExitCode") != 0
                or len(summary_rows) != 1 or summary_rows[0].get("rawSha256") != _sha(payloads[raw_path])
                or summary_rows[0].get("ownerPid") != owner.get("pid") or type(attr) is not dict or attr.get("attribute") != "AXEnabled"
                or attr.get("status") != "observed-bool" or type(attr.get("value")) is not bool):
            raise ObservationError(f"Mac AX run {index} has invalid exact bool observation")
        if attr["value"] is not True:
            raise ObservationError(f"Mac AX run {index} button was not enabled")
        if (raw.get("ownerPID") != owner.get("pid") or owner.get("caseId") != CASE_ID
                or owner.get("sourceSha256") != SOURCE_SHA256 or owner.get("unchangedPriorCaptureHost") is not True
                or result.get("ownerPid") != owner.get("pid") or result.get("rawSha256") != _sha(payloads[raw_path])):
            raise ObservationError(f"Mac AX run {index} owner/raw linkage mismatch")
        if owner.get("pid") in mac_ax_pids or raw.get("clientPID") in mac_ax_client_pids:
            raise ObservationError("Mac AX batch reused owner/client PID")
        mac_ax_pids.add(owner["pid"])
        mac_ax_client_pids.add(raw["clientPID"])
        mac_ax_runs.append({"run": index, "source": "macos-disabled-ax-batch-v1", "pid": owner["pid"],
                            "role": button["role"], "label": button["label"], "enabled": attr["value"],
                            "rawPath": raw_path, "rawSha256": refs[raw_path]["sha256"],
                            "resultPath": result_path, "ownerReceiptPath": owner_path})

    win_runs = []
    win_pids = set()
    win_print_hashes = set()
    for index in range(1, 21):
        run = f"disabled-repeatability-r1-{index:02d}"
        base = f"{WIN_ROOT}/{run}"
        native_path = f"{base}/native-observation.json"
        observation_path = f"{base}/observation.json"
        plan_path = f"{base}/plan.json"
        native = _data(payloads, native_path)
        obs = _data(payloads, observation_path)
        plan = _data(payloads, plan_path)
        if (native.get("index") != 1 or native.get("case", {}).get("id") != CASE_ID
                or native.get("case", {}).get("hash") != "sha256:" + CASE_SHA256
                or native.get("manifestHash") != "sha256:" + PROBE_SHA256
                or native.get("sourceHash") != "sha256:" + SOURCE_SHA256 or native.get("hostValid") is not True
                or native.get("occlusionQualified") is not False or native.get("nativeParity") != "hold"
                or native.get("frozenTupleBound") is not False or native.get("closureBinding") is not None
                or plan.get("case", {}).get("id") != CASE_ID or plan.get("sourceHash") != "sha256:" + SOURCE_SHA256
                or obs.get("planSha256") != _sha(payloads[plan_path])
                or obs.get("exitCode") != 0 or obs.get("timedOut") is not False or obs.get("nativeWindowOpened") is not False
                or obs.get("sourceHash") != "sha256:" + SOURCE_SHA256):
            raise ObservationError(f"Windows run {index} is not expected held native observation")
        owner_path = f"{base}/native-01/owned-process.json"
        owner = _data(payloads, owner_path)
        if owner.get("path") != obs.get("exePath") or native.get("exeSha256") != obs.get("exeSha256"):
            raise ObservationError(f"Windows run {index} executable/owner identity mismatch")
        uia_path = f"{base}/native-01/native.uia.json"
        uia = _data(payloads, uia_path)
        buttons = [n for n in _walk(uia) if n.get("controlType") == "ControlType.Button" and n.get("name") == "Continue"]
        if len(buttons) != 1:
            raise ObservationError(f"Windows UIA Continue button is not unique in run {index}")
        button = buttons[0]
        if type(button.get("enabled")) is not bool or button["enabled"] is not True:
            raise ObservationError(f"Windows run {index} enabled value is not exact true bool")
        pixels_path = f"{base}/native-01/native.pixels.json"
        pixels = _data(payloads, pixels_path)
        if (pixels.get("pid") != owner.get("pid") or pixels.get("width") != 800 or pixels.get("height") != 600
                or pixels.get("dpi") != 240):
            raise ObservationError(f"Windows run {index} process/viewport join mismatch")
        analysis_rows = [row for row in win_analysis.get("rows", []) if row.get("index") == index]
        if (len(analysis_rows) != 1 or analysis_rows[0].get("pid") != owner.get("pid")
                or analysis_rows[0].get("nativeObservationSha256") != refs[native_path]["sha256"]):
            raise ObservationError(f"Windows run {index} does not join exact analysis row")
        if owner.get("pid") in win_pids:
            raise ObservationError("Windows batch reused owner PID")
        win_pids.add(owner["pid"])
        files = native.get("files")
        if not isinstance(files, list):
            raise ObservationError(f"Windows run {index} missing native file receipts")
        filemap = {f.get("path"): f.get("sha256") for f in files if isinstance(f, dict)}
        for leaf in ("native.uia.json", "native.pixels.json", "owned-process.json", "native.printwindow.png", "native.printwindow.repeat.png"):
            if filemap.get(leaf) != refs[f"{base}/native-01/{leaf}"]["sha256"]:
                raise ObservationError(f"Windows run {index} sidecar hash link mismatch: {leaf}")
        print_hash = filemap["native.printwindow.png"]
        if filemap["native.printwindow.repeat.png"] != print_hash or analysis_rows[0].get("printWindowSha256") != print_hash:
            raise ObservationError(f"Windows run {index} PrintWindow repeated-capture linkage mismatch")
        win_print_hashes.add(print_hash)
        win_runs.append({"run": index, "source": "windows-disabled-repeatability-batch-v1-actual-r1",
                         "pid": owner["pid"], "role": button["controlType"], "label": button["name"],
                         "enabled": button["enabled"], "uiaPath": uia_path, "uiaSha256": refs[uia_path]["sha256"],
                         "nativeObservationPath": native_path, "printWindowSha256": next(
                             (f["sha256"] for f in files if f.get("path") == "native.printwindow.png"), None)})

    if (len(mac_ax_runs) != 20 or len(win_runs) != 20 or len(mac_ax_pids) != 20
            or len(mac_ax_client_pids) != 20 or len(win_pids) != 20 or len(win_print_hashes) != 1):
        raise ObservationError("run denominator, process uniqueness, or PrintWindow repeatability changed")
    mac_values = {(r["role"], r["label"], type(r["enabled"]).__name__, r["enabled"]) for r in mac_ax_runs}
    win_values = {(r["role"], r["label"], type(r["enabled"]).__name__, r["enabled"]) for r in win_runs}
    role_map = {"AXButton": "ControlType.Button"}
    if len(mac_values) != 1 or len(win_values) != 1:
        raise ObservationError("semantic values vary within an observational batch")
    mac_role, mac_label, mac_type, mac_enabled = next(iter(mac_values))
    win_role, win_label, win_type, win_enabled = next(iter(win_values))
    if (role_map.get(mac_role) != win_role or mac_label != win_label or mac_type != win_type
            or type(mac_enabled) is not bool or type(win_enabled) is not bool):
        raise ObservationError("explicit role/label/exact-type cross-batch mapping mismatch")

    return {
        "kind": "f9-paired-disabled-observational-report",
        "version": "2",
        "status": "observational-enabled-match-parity-held",
        "promotion": "none",
        "case": {"id": CASE_ID, "block": "swiftui.disabled", "caseSha256": CASE_SHA256,
                 "sourceSha256": SOURCE_SHA256, "probeManifestSha256": PROBE_SHA256},
        "batches": {
            "macOSAXEnabled": {"id": "macos-disabled-ax-batch-v1", "runs": 20, "uniqueOwnerPids": 20, "uniqueAXClientPids": 20,
                               "sourceReport": ax_report_path, "sourceReportSha256": refs[ax_report_path]["sha256"],
                               "rawRuns": mac_ax_runs, "rawEnabledTrueCount": 20, "permissionRequests": False,
                               "inputInvoked": False},
            "macOSPaint": {"id": "macos-disabled-paint-20-historical", "runs": 20,
                           "sourceSummary": old_summary_path, "sourceSummarySha256": refs[old_summary_path]["sha256"],
                           "status": paint.get("status"), "acceptance": paint.get("acceptance"),
                           "paintChannels": paint.get("channels"),
                           "runCaptureHashes": [run.get("captureHash") for run in paint["runs"]],
                           "enabledAttribute": "not captured in this historical paint batch"},
            "windowsUIA": {"id": "windows-disabled-repeatability-batch-v1-actual-r1", "runs": 20,
                           "uniqueOwnerPids": 20, "analysisPath": win_analysis_path,
                           "analysisSha256": refs[win_analysis_path]["sha256"], "rawRuns": win_runs,
                           "semanticRepeatabilityObserved": True, "distinctPrintWindowHashes": 1,
                           "printWindowHash": next(iter(win_print_hashes))},
        },
        "semanticComparison": {"roleMapping": role_map, "attributeMapping": {"macOS": "AXEnabled.value", "windows": "IsEnabled"},
                               "label": "Continue", "exactValueType": "bool", "macOSValueCounts": {"true": 20, "false": 0},
                               "windowsValueCounts": {"true": 20, "false": 0}, "batchValuesMatch": True,
                               "pairing": "independent batches; no run-to-run pairing asserted"},
        "independentReviews": {
            "macOSAX": {"path": mac_review_path, "sha256": refs[mac_review_path]["sha256"], "verdict": "bounded raw AX joins verified"},
            "windowsActualR1": {"path": win_review_path, "sha256": refs[win_review_path]["sha256"], "verdict": win_review["verdict"]},
        },
        "qualification": {"acceptedGoldenCount": 0, "nativeParity": "held", "qualifiedTiming": "held",
                          "hitTesting": "held-not-attempted", "controlledOcclusion": "held-unqualified",
                          "frozenTuple": "held-unbound", "reason": "AX/UIA enabled-state observations do not prove callback invocation, hit-testing, controlled occlusion, qualified timing, tuple binding, or cross-renderer parity."},
        "channels": {"macOSAX": "observed in separate new 20-run external AX batch",
                     "macOSPaint": "observed in original 20-run capture batch; no AX-enabled values joined into these records",
                     "windowsUIA": "observed in separate 20-run actual-r1 batch",
                     "timing": "raw timestamps remain in source files; no qualified timing metric emitted"},
        "rawInputManifest": {"path": "factory/pipeline/paired-disabled-observation-v2/evidence/input-manifest.json",
                             "sha256": _sha(manifest_bytes), "inputCount": len(manifest["inputs"]),
                             "inputs": manifest["inputs"]},
    }


def load_pinned_inputs() -> tuple[bytes, dict[str, bytes]]:
    root = Path(__file__).resolve().parents[3]
    manifest_path = Path(__file__).resolve().parent / "evidence/input-manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = _json(manifest_bytes, "input manifest")
    payloads = {row["path"]: (root / row["path"]).read_bytes() for row in manifest["inputs"]}
    return manifest_bytes, payloads
