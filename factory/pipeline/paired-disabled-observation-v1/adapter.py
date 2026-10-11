"""Read-only F9-format observation adapter for one corrected Windows capture."""
from __future__ import annotations

from datetime import datetime
import hashlib
import json
import re
from statistics import median
from typing import Any

INPUT_MANIFEST_SHA256 = "a2ad0ff7ad110b7fcea87842d4f3babaff733a5d720a447835f4aa03854b4ce7"
EXPECTED_CASE_ID = "swiftui.disabled.recipe/case/f113195a59446fc4"
EXPECTED_SOURCE_SHA256 = "68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
WINDOWS_PREFIX = "factory/native/windows/first-capture-corrections-v1/actual-corrected-r1/native-01/"
MAC_PREFIX = "factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4/"


class ObservationError(ValueError):
    pass


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ObservationError(f"{label} is not valid UTF-8 JSON") from exc


def _walk(node: Any):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


def _role_map(manifest: dict) -> dict[str, dict]:
    rows = manifest.get("inputs")
    if not isinstance(rows, list) or not rows:
        raise ObservationError("input manifest has no rows")
    result = {}
    paths = set()
    for row in rows:
        role, path, digest, size = row.get("role"), row.get("path"), row.get("sha256"), row.get("bytes")
        if not all(isinstance(value, str) and value for value in (role, path, digest)) or type(size) is not int:
            raise ObservationError("malformed input manifest row")
        if role in result or path in paths:
            raise ObservationError("duplicate role or path in input manifest")
        result[role] = row
        paths.add(path)
    return result


def build_report(manifest_bytes: bytes, payloads: dict[str, bytes]) -> dict:
    if not isinstance(manifest_bytes, bytes) or _sha(manifest_bytes) != INPUT_MANIFEST_SHA256:
        raise ObservationError("frozen input manifest pin mismatch")
    manifest = _load(manifest_bytes, "input manifest")
    if manifest.get("kind") != "paired-disabled-observation-input-manifest" or manifest.get("caseId") != EXPECTED_CASE_ID or manifest.get("sourceSha256") != EXPECTED_SOURCE_SHA256:
        raise ObservationError("input manifest identity mismatch")
    roles = _role_map(manifest)
    if set(payloads) != {row["path"] for row in roles.values()}:
        raise ObservationError("payload set differs from frozen input manifest")
    for row in roles.values():
        raw = payloads[row["path"]]
        if not isinstance(raw, bytes) or len(raw) != row["bytes"] or _sha(raw) != row["sha256"]:
            raise ObservationError(f"raw input mismatch: {row['role']}")

    def data(role: str):
        try:
            return _load(payloads[roles[role]["path"]], role)
        except KeyError as exc:
            raise ObservationError(f"required role missing: {role}") from exc

    case_raw = payloads[roles["case"]["path"]]
    case = data("case")
    f9_manifest = data("f9-manifest")
    probe = data("probe-manifest")
    source_raw = payloads[roles["probe-source"]["path"]]
    source_hash = _sha(source_raw)
    case_hash = _sha(case_raw)
    if case.get("id") != EXPECTED_CASE_ID or case.get("block") != "swiftui.disabled":
        raise ObservationError("F9 case identity changed")
    case_ref = {"id": EXPECTED_CASE_ID, "hash": "sha256:" + case_hash}
    case_candidates = [row for row in f9_manifest.get("cases", []) if row.get("id") == EXPECTED_CASE_ID]
    if len(case_candidates) != 1 or case_candidates[0] != case:
        raise ObservationError("F9 manifest does not bind exact case object")
    if (probe.get("kind") != "generated-probe" or probe.get("case") != case_ref
            or probe.get("sourceHash") != "sha256:" + source_hash
            or source_hash != EXPECTED_SOURCE_SHA256):
        raise ObservationError("F9 probe source/case linkage mismatch")

    plan = data("windows-plan")
    compile_observation = data("windows-compile-observation")
    native = data("windows-native-observation")
    if (plan.get("case") != case_ref or plan.get("sourceHash") != "sha256:" + EXPECTED_SOURCE_SHA256
            or plan.get("nativeParity") != "hold" or plan.get("frozenTupleBound") is not False):
        raise ObservationError("corrected Windows plan does not bind held source/case observation")
    if (compile_observation.get("planSha256") != _sha(payloads[roles["windows-plan"]["path"]])
            or compile_observation.get("sourceHash") != "sha256:" + EXPECTED_SOURCE_SHA256
            or compile_observation.get("exitCode") != 0 or compile_observation.get("nativeWindowOpened") is not False):
        raise ObservationError("Windows compile observation does not bind plan/source or is not compile-only")
    if (native.get("case") != case_ref or native.get("sourceHash") != "sha256:" + EXPECTED_SOURCE_SHA256
            or native.get("hostValid") is not True or native.get("nativeParity") != "hold"
            or native.get("frozenTupleBound") is not False or native.get("occlusionQualified") is not False):
        raise ObservationError("Windows native observation is not the expected held single observation")
    for file_ref in native.get("files", []):
        path = WINDOWS_PREFIX + file_ref.get("path", "")
        if path not in payloads or _sha(payloads[path]) != file_ref.get("sha256"):
            raise ObservationError("Windows native observation sidecar linkage mismatch")

    uia = data("windows-native.uia.json")
    pixels = data("windows-native.pixels.json")
    buttons = [row for row in _walk(uia) if row.get("controlType") == "ControlType.Button" and row.get("name") == "Continue"]
    if len(buttons) != 1:
        raise ObservationError("Windows UIA Continue button is not unique")
    win_button = buttons[0]
    if type(win_button.get("enabled")) is not bool or win_button.get("enabled") is not True:
        raise ObservationError("Windows UIA Continue button is not observed enabled")
    if (pixels.get("width") != 800 or pixels.get("height") != 600 or pixels.get("dpi") != 240
            or pixels.get("nativeParity") != "hold" or pixels.get("controlledOcclusionQualification") is not False
            or pixels.get("providerReadbackExport") is not False):
        raise ObservationError("Windows corrected viewport/pixel observation changed")

    stdout = payloads[roles["windows-host.stdout.txt"]["path"]].decode("utf-8-sig")
    abi = re.search(r"FACTORY_ABI_INITIAL_METRICS width=(\d+) height=(\d+) scale=([0-9.]+)", stdout)
    measured = re.search(r"FACTORY_MEASURE text=Continue proposedDIP=([0-9.]+) widthPX=([0-9.]+) heightPX=([0-9.]+) lines=(\d+) scale=([0-9.]+)", stdout)
    retained = re.findall(r"FACTORY_RETAINED_RUN text=Continue widthPX=([0-9.]+) heightPX=([0-9.]+) snappedWidthPX=([0-9.]+) lines=(\d+) proposedDIP=([0-9.]+)", stdout)
    if not abi or not measured or not retained:
        raise ObservationError("corrected Windows viewport/text metric records missing")
    abi_metrics = {"width": int(abi[1]), "height": int(abi[2]), "scale": float(abi[3])}
    text_metrics = {"proposedDIP": float(measured[1]), "measuredWidthPX": float(measured[2]),
                    "heightPX": float(measured[3]), "lines": int(measured[4]), "scale": float(measured[5]),
                    "retainedLayoutEventCount": len(retained), "retainedWidthsAndLineCountsUnique": len(set(retained)) == 1,
                    "retainedWidthPX": float(retained[0][0]), "snappedWidthPX": float(retained[0][2])}

    mac_rows = []
    mac_runs = []
    for index in range(1, 21):
        capture_role = f"macos-run-{index:03d}-capture.json"
        ax_role = f"macos-run-{index:03d}-external-ax.raw.json"
        plain_role = f"macos-run-{index:03d}-plain.raw.json"
        if not all(role in roles for role in (capture_role, ax_role, plain_role)):
            raise ObservationError("Mac run manifest incomplete")
        capture = data(capture_role)
        raw_ax = data(ax_role)
        plain = data(plain_role)
        expected_id = f"{EXPECTED_CASE_ID}.macos.run-{index:03d}"
        if (capture.get("id") != expected_id or capture.get("platform") != "macos" or capture.get("case") != case_ref
                or capture.get("meta", {}).get("conditions", {}).get("caseInputs") != case.get("inputs")):
            raise ObservationError(f"Mac run {index} has wrong case/platform/inputs")
        if raw_ax.get("status") != "OBSERVED" or raw_ax.get("permissionRequests") is not False:
            raise ObservationError(f"Mac raw AX run {index} is missing or permission-gated")
        ax_buttons = [node for node in _walk(raw_ax) if node.get("role") == "AXButton" and node.get("label") == "Continue"]
        if len(ax_buttons) != 1:
            raise ObservationError(f"Mac raw AX Continue button is not unique in run {index}")
        ax_button = ax_buttons[0]
        frame = ax_button.get("frame", {})
        if (frame.get("w") != 79 or frame.get("h") != 24 or "enabled" in ax_button):
            raise ObservationError(f"Mac raw AX button fields/extent changed in run {index}")
        cap_ax = [row for row in capture.get("ax", []) if row.get("role") == "AXButton" and row.get("label") == "Continue"]
        if len(cap_ax) != 1 or cap_ax[0].get("actions") != ax_button.get("actions"):
            raise ObservationError(f"Mac normalized AX row differs from raw external AX in run {index}")
        if capture.get("text") != [] or plain.get("text") not in ([], None):
            raise ObservationError("Mac text renderer channel is not empty as captured")
        layout = capture.get("layout", [])
        frame_layout = layout[0].get("frame", {}) if len(layout) == 1 else {}
        if frame_layout != {"height": 24, "width": 79, "x": 0, "y": 0}:
            raise ObservationError(f"Mac layout frame differs in run {index}")
        events = capture.get("events", [])
        starts = [e for e in events if e.get("id") == "offscreen.begin"]
        ends = [e for e in events if e.get("id") == "offscreen.end"]
        if len(starts) != 1 or len(ends) != 1 or type(starts[0].get("timeNs")) is not int or type(ends[0].get("timeNs")) is not int:
            raise ObservationError(f"Mac raw render interval missing in run {index}")
        duration = ends[0]["timeNs"] - starts[0]["timeNs"]
        if duration < 0 or starts[0].get("clockId") != ends[0].get("clockId"):
            raise ObservationError(f"Mac raw render interval invalid in run {index}")
        mac_runs.append({"run": index, "capturePath": roles[capture_role]["path"],
                         "captureSha256": roles[capture_role]["sha256"], "externalAXPath": roles[ax_role]["path"],
                         "externalAXSha256": roles[ax_role]["sha256"], "plainRawPath": roles[plain_role]["path"],
                         "plainRawSha256": roles[plain_role]["sha256"], "rawRenderIntervalNs": duration,
                         "buttonLabel": ax_button["label"], "buttonActions": ax_button.get("actions", []),
                         "buttonEnabledField": "absent", "buttonFrame": frame_layout})
        mac_rows.append({"role": ax_button["role"], "label": ax_button["label"], "enabledField": "absent",
                         "actions": ax_button.get("actions", []), "frame": frame})
    durations = [row["rawRenderIntervalNs"] for row in mac_runs]
    win_started = datetime.fromisoformat(compile_observation["startedAt"].replace("Z", "+00:00"))
    win_finished = datetime.fromisoformat(compile_observation["finishedAt"].replace("Z", "+00:00"))

    evidence_refs = [{"role": row["role"], "path": row["path"], "bytes": row["bytes"], "sha256": row["sha256"]} for row in manifest["inputs"]]
    return {
        "kind": "f9-paired-disabled-observational-report",
        "version": "1",
        "status": "observational-parity-held",
        "promotion": "none",
        "qualification": {"qualifiedWindowsBatchCount": 0, "nativeParity": "held",
                          "reason": "One Windows observation is not a 20-run qualified Windows batch; occlusion/provider/callback and frozen tuple bindings remain held."},
        "case": {"id": EXPECTED_CASE_ID, "block": "swiftui.disabled", "hash": "sha256:" + case_hash,
                 "inputs": case.get("inputs"), "sourceSha256": source_hash,
                 "probeManifestPath": roles["probe-manifest"]["path"], "probeManifestSha256": roles["probe-manifest"]["sha256"]},
        "counts": {"macOSRuns": len(mac_runs), "windowsObservations": 1, "qualifiedWindowsBatches": 0,
                   "parity": "held", "registryOrBaselinePromotion": False},
        "buttonSemantics": {
            "windowsUIA": {"role": win_button.get("controlType"), "label": win_button.get("name"),
                           "enabled": win_button.get("enabled"), "offscreen": win_button.get("offscreen"),
                           "boundsRaw": win_button.get("bounds"), "evidencePath": roles["windows-native.uia.json"]["path"],
                           "evidenceSha256": roles["windows-native.uia.json"]["sha256"]},
            "macOSRawAX": {"role": "AXButton", "label": "Continue", "enabled": "not exposed in raw AX records",
                           "actions": sorted(set(action for row in mac_runs for action in row["buttonActions"])),
                           "runCount": len(mac_runs), "evidencePaths": [row["externalAXPath"] for row in mac_runs],
                           "evidenceSha256": [row["externalAXSha256"] for row in mac_runs]},
            "labelMatch": True,
            "enabledComparison": "Windows reports enabled=true; Mac raw AX has no enabled field, so boolean equality is unavailable.",
            "hitTesting": {"requiredByF9AssertionChannel": "hit-testing", "status": "untested",
                           "reason": "No input/invoke event or callback receipt is present; AXPress availability alone is not an invocation."},
        },
        "correctionMetrics": {
            "windowsViewport": {"initialAbiMetrics": abi_metrics, "actualOwnedClientPixels": {"width": pixels["width"], "height": pixels["height"]},
                                "dpi": pixels["dpi"], "actualViewportSource": "owned-client-rect", "evidencePath": roles["windows-native.pixels.json"]["path"],
                                "evidenceSha256": roles["windows-native.pixels.json"]["sha256"]},
            "windowsText": {**text_metrics, "evidencePath": roles["windows-host.stdout.txt"]["path"],
                            "evidenceSha256": roles["windows-host.stdout.txt"]["sha256"]},
            "macOSContent": {"rootLayoutPointFrame": {"width": 79, "height": 24}, "capturePixelFrame": {"width": 79, "height": 24},
                             "textRendererRecordCount": 0, "resolvedFont": "held by Mac capture", "runCount": len(mac_runs),
                             "crossProviderPaintComparison": "not semantically normalized"},
            "units": "Windows measurements are raw physical pixels/DIP as reported; Mac frame is points/pixels from capture records. No cross-host geometry equality is asserted.",
        },
        "timing": {
            "rawMacRenderIntervals": {"clock": "macos.dispatch.uptime", "runs": mac_runs,
                                       "minimumNs": min(durations), "medianNs": median(durations), "maximumNs": max(durations),
                                       "meaning": "same-process offscreen render begin/end only; not input latency"},
            "windowsCompileElapsedMs": (win_finished - win_started).total_seconds() * 1000,
            "windowsCompileMeaning": "compile process duration; not native interaction timing",
            "qualifiedTiming": "unavailable",
            "qualifiedTimingReason": "No qualified Windows timing batch or paired repeat timing protocol is present.",
        },
        "nativeObservation": {"count": 1, "hostValid": native["hostValid"], "occlusionQualified": native["occlusionQualified"],
                              "providerReadbackExport": pixels["providerReadbackExport"], "nativeParity": native["nativeParity"],
                              "frozenTupleBound": native["frozenTupleBound"], "reason": native.get("reason"),
                              "evidencePath": roles["windows-native-observation"]["path"],
                              "evidenceSha256": roles["windows-native-observation"]["sha256"]},
        "macOSRuns": mac_runs,
        "evidence": {"manifestPath": "factory/pipeline/paired-disabled-observation-v1/evidence/input-manifest.json",
                     "manifestSha256": _sha(manifest_bytes), "rawFiles": evidence_refs},
    }


def load_pinned_inputs():
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    manifest_path = Path(__file__).resolve().parent / "evidence/input-manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = _load(manifest_bytes, "input manifest")
    payloads = {row["path"]: (root / row["path"]).read_bytes() for row in manifest["inputs"]}
    return manifest_bytes, payloads
