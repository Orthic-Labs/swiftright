"""Independent offline integrity review for paired-disabled-observation-v1."""
from __future__ import annotations
from datetime import datetime
import hashlib, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = ROOT / "factory/pipeline/paired-disabled-observation-v1"
MANIFEST_PATH = PACKET / "evidence/input-manifest.json"
MANIFEST_SHA = "a2ad0ff7ad110b7fcea87842d4f3babaff733a5d720a447835f4aa03854b4ce7"
REPORT_SHA = "86a73d21083649c7b9b0efa1f27dbec57fc0ceab331f96d874f9668025ad9508"
CASE_ID = "swiftui.disabled.recipe/case/f113195a59446fc4"
SOURCE_SHA = "68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
WIN_PREFIX = "factory/native/windows/first-capture-corrections-v1/actual-corrected-r1/native-01/"
MAC_PREFIX = "factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4/"

class ReviewError(ValueError):
    pass

def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()

def load_json(raw: bytes, label: str):
    try:
        return json.loads(raw.decode("utf-8-sig"))
    except Exception as exc:
        raise ReviewError(f"{label}: invalid UTF-8 JSON") from exc

def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)

def load_payloads(root: Path = ROOT):
    manifest_raw = MANIFEST_PATH.read_bytes()
    manifest = load_json(manifest_raw, "input manifest")
    payloads = {row["path"]: (root / row["path"]).read_bytes() for row in manifest["inputs"]}
    return manifest_raw, manifest, payloads

def audit_payloads(manifest_raw: bytes, manifest: dict, payloads: dict[str, bytes], report_raw: bytes | None = None):
    if sha(manifest_raw) != MANIFEST_SHA:
        raise ReviewError("frozen input-manifest hash mismatch")
    if manifest.get("kind") != "paired-disabled-observation-input-manifest" or manifest.get("caseId") != CASE_ID:
        raise ReviewError("manifest identity mismatch")
    rows = manifest.get("inputs")
    if not isinstance(rows, list) or len(rows) != 78:
        raise ReviewError(f"expected 78 input rows, found {len(rows) if isinstance(rows,list) else 'non-list'}")
    by_role, paths = {}, set()
    for row in rows:
        if not all(isinstance(row.get(k), str) and row[k] for k in ("role", "path", "sha256")) or type(row.get("bytes")) is not int:
            raise ReviewError("malformed manifest row")
        if row["role"] in by_role or row["path"] in paths:
            raise ReviewError("duplicate manifest role/path")
        if row["path"].startswith("/") or ".." in Path(row["path"]).parts:
            raise ReviewError("unsafe manifest path")
        by_role[row["role"]] = row; paths.add(row["path"])
    if set(payloads) != paths:
        raise ReviewError("payload path set does not equal manifest path set")
    for row in rows:
        raw = payloads[row["path"]]
        if not isinstance(raw, bytes) or len(raw) != row["bytes"] or sha(raw) != row["sha256"]:
            raise ReviewError(f"payload mismatch: {row['role']}")
    def raw(role): return payloads[by_role[role]["path"]]
    def doc(role): return load_json(raw(role), role)
    case = doc("case"); f9 = doc("f9-manifest"); probe = doc("probe-manifest")
    source_hash = sha(raw("probe-source")); case_hash = sha(raw("case"))
    if source_hash != SOURCE_SHA or manifest.get("sourceSha256") != SOURCE_SHA:
        raise ReviewError("source hash is not frozen expected source")
    if case.get("id") != CASE_ID or case.get("block") != "swiftui.disabled":
        raise ReviewError("case identity mismatch")
    case_ref = {"id": CASE_ID, "hash": "sha256:" + case_hash}
    if [x for x in f9.get("cases", []) if x.get("id") == CASE_ID] != [case]:
        raise ReviewError("F9 case object is not exact source-bound object")
    if probe.get("kind") != "generated-probe" or probe.get("case") != case_ref or probe.get("sourceHash") != "sha256:" + source_hash:
        raise ReviewError("probe/case/source join mismatch")

    plan = doc("windows-plan"); compile = doc("windows-compile-observation"); native = doc("windows-native-observation")
    if plan.get("case") != case_ref or plan.get("sourceHash") != "sha256:" + SOURCE_SHA or plan.get("nativeParity") != "hold" or plan.get("frozenTupleBound") is not False:
        raise ReviewError("Windows plan/source/case hold join mismatch")
    started = datetime.fromisoformat(compile["startedAt"].replace("Z", "+00:00")); finished = datetime.fromisoformat(compile["finishedAt"].replace("Z", "+00:00"))
    if not (finished > started and compile.get("planSha256") == sha(raw("windows-plan")) and compile.get("sourceHash") == "sha256:" + SOURCE_SHA and compile.get("exitCode") == 0 and compile.get("timedOut") is False and compile.get("nativeWindowOpened") is False and compile.get("ownedExited") is True and compile.get("nativeParity") == "hold" and compile.get("frozenTupleBound") is False):
        raise ReviewError("compile receipt is not successful compile-only held observation")
    if native.get("case") != case_ref or native.get("sourceHash") != "sha256:" + SOURCE_SHA or native.get("manifestHash") != plan.get("manifestHash") or native.get("compileReceiptHash") != sha(raw("windows-compile-observation")) or native.get("exitCode") != 0 or native.get("hostValid") is not True or native.get("occlusionQualified") is not False or native.get("nativeParity") != "hold" or native.get("frozenTupleBound") is not False:
        raise ReviewError("native observation/source/compile/hold join mismatch")
    native_rows = native.get("files")
    if not isinstance(native_rows, list) or len(native_rows) != 10:
        raise ReviewError("native sidecar list is not exact 10-file set")
    native_paths = {WIN_PREFIX + x.get("path", "") for x in native_rows}
    expected_native_paths = {r["path"] for r in rows if r["path"].startswith(WIN_PREFIX)}
    if native_paths != expected_native_paths:
        raise ReviewError("native sidecar set does not cover manifest Windows native files")
    for x in native_rows:
        path = WIN_PREFIX + x["path"]
        if sha(payloads[path]) != x.get("sha256"):
            raise ReviewError("native sidecar hash join mismatch")

    uia = doc("windows-native.uia.json"); pixels = doc("windows-native.pixels.json")
    buttons = [x for x in walk(uia) if x.get("controlType") == "ControlType.Button" and x.get("name") == "Continue"]
    if len(buttons) != 1 or buttons[0].get("enabled") is not True or type(buttons[0].get("enabled")) is not bool or buttons[0].get("offscreen") is not False:
        raise ReviewError("Windows UIA Continue semantics mismatch")
    if pixels.get("width") != 800 or pixels.get("height") != 600 or pixels.get("dpi") != 240 or pixels.get("nativeParity") != "hold" or pixels.get("controlledOcclusionQualification") is not False or pixels.get("providerReadbackExport") is not False:
        raise ReviewError("Windows viewport/provider hold semantics mismatch")
    stdout = raw("windows-host.stdout.txt").decode("utf-8-sig")
    abi = re.search(r"FACTORY_ABI_INITIAL_METRICS width=(\d+) height=(\d+) scale=([0-9.]+)", stdout)
    measure = re.search(r"FACTORY_MEASURE text=Continue proposedDIP=([0-9.]+) widthPX=([0-9.]+) heightPX=([0-9.]+) lines=(\d+) scale=([0-9.]+)", stdout)
    retained = re.findall(r"FACTORY_RETAINED_RUN text=Continue widthPX=([0-9.]+) heightPX=([0-9.]+) snappedWidthPX=([0-9.]+) lines=(\d+) proposedDIP=([0-9.]+)", stdout)
    if not abi or not measure or len(retained) < 2 or len(set(retained)) != 1:
        raise ReviewError("Windows text/ABI raw stdout controls mismatch")

    mac_intervals = []; mac_paths = set()
    for i in range(1, 21):
        cr = doc(f"macos-run-{i:03d}-capture.json"); ax = doc(f"macos-run-{i:03d}-external-ax.raw.json"); plain = doc(f"macos-run-{i:03d}-plain.raw.json")
        if cr.get("id") != f"{CASE_ID}.macos.run-{i:03d}" or cr.get("platform") != "macos" or cr.get("case") != case_ref or cr.get("meta",{}).get("conditions",{}).get("caseInputs") != case.get("inputs"):
            raise ReviewError(f"Mac run {i} case/platform/input join mismatch")
        if ax.get("status") != "OBSERVED" or ax.get("permissionRequests") is not False:
            raise ReviewError(f"Mac run {i} raw AX status/permission mismatch")
        axb = [x for x in walk(ax) if x.get("role") == "AXButton" and x.get("label") == "Continue"]
        cab = [x for x in cr.get("ax",[]) if x.get("role") == "AXButton" and x.get("label") == "Continue"]
        if len(axb) != 1 or len(cab) != 1 or cab[0].get("actions") != axb[0].get("actions") or "enabled" in axb[0] or axb[0].get("frame",{}).get("w") != 79 or axb[0].get("frame",{}).get("h") != 24 or cab[0].get("bounds",{}) != {"x":axb[0]["frame"].get("x"),"y":axb[0]["frame"].get("y"),"width":79,"height":24}:
            raise ReviewError(f"Mac run {i} raw/normalized AX join mismatch")
        if cr.get("text") != [] or plain.get("text") not in ([], None):
            raise ReviewError(f"Mac run {i} text channel is unexpectedly populated")
        if len(cr.get("layout",[])) != 1 or cr["layout"][0].get("frame") != {"height":24,"width":79,"x":0,"y":0}:
            raise ReviewError(f"Mac run {i} layout frame mismatch")
        starts = [e for e in cr.get("events",[]) if e.get("id") == "offscreen.begin"]; ends = [e for e in cr.get("events",[]) if e.get("id") == "offscreen.end"]
        if len(starts) != 1 or len(ends) != 1 or type(starts[0].get("timeNs")) is not int or type(ends[0].get("timeNs")) is not int or starts[0].get("clockId") != ends[0].get("clockId") or ends[0]["timeNs"] < starts[0]["timeNs"]:
            raise ReviewError(f"Mac run {i} interval channel mismatch")
        mac_intervals.append(ends[0]["timeNs"] - starts[0]["timeNs"])
        mac_paths.update([by_role[f"macos-run-{i:03d}-capture.json"]["path"], by_role[f"macos-run-{i:03d}-external-ax.raw.json"]["path"], by_role[f"macos-run-{i:03d}-plain.raw.json"]["path"]])

    report = load_json(report_raw if report_raw is not None else (PACKET/"evidence/observational-report.json").read_bytes(), "producer report")
    report_bytes = report_raw if report_raw is not None else (PACKET/"evidence/observational-report.json").read_bytes()
    if sha(report_bytes) != REPORT_SHA:
        raise ReviewError("producer observational report hash mismatch")
    if report.get("status") != "observational-parity-held" or report.get("promotion") != "none" or report.get("counts") != {"macOSRuns":20,"windowsObservations":1,"qualifiedWindowsBatches":0,"parity":"held","registryOrBaselinePromotion":False}:
        raise ReviewError("producer report does not preserve held status")
    refs = report.get("evidence",{}).get("rawFiles")
    if refs != [{"role":r["role"],"path":r["path"],"bytes":r["bytes"],"sha256":r["sha256"]} for r in rows] or report.get("evidence",{}).get("manifestSha256") != MANIFEST_SHA:
        raise ReviewError("producer report evidence refs do not equal frozen manifest")
    if report.get("timing",{}).get("qualifiedTiming") != "unavailable" or report.get("buttonSemantics",{}).get("hitTesting",{}).get("status") != "untested" or report.get("buttonSemantics",{}).get("enabledComparison","").find("unavailable") < 0:
        raise ReviewError("unavailable channels are not preserved")
    if report.get("nativeObservation",{}).get("nativeParity") != "hold" or report.get("nativeObservation",{}).get("occlusionQualified") is not False or report.get("nativeObservation",{}).get("providerReadbackExport") is not False:
        raise ReviewError("native hold channels are not preserved")
    return {
        "kind":"paired-disabled-observation-independent-review",
        "version":1,
        "status":"independently-verified-observational-only",
        "producerPacket":{"manifestSha256":MANIFEST_SHA,"reportSha256":REPORT_SHA,"inputCount":len(rows),"macRuns":20,"windowsObservations":1},
        "checks":{
            "all78PayloadBytesAndHashes":True,"caseF9ProbeSourceJoin":True,"windowsPlanCompileNativeJoin":True,
            "windowsUIAAndViewportRawSemantics":True,"windowsNativeSidecarCoverage":True,
            "mac20CaseInputAXLayoutTextJoins":True,"macRenderIntervalsNonnegativeSameClock":True,
            "producerReportEvidenceRefsExact":True,
        },
        "channels":{"enabledBoolean":"unavailable-mac-field-absent","hitTesting":"untested","qualifiedTiming":"unavailable","nativeParity":"held","occlusionQualification":False,"providerReadbackExport":False,"promotion":"none"},
        "assertionHolds":[
            "Windows UIA Continue enabled=true is observed; Mac raw AX has no enabled field, so equality is unavailable.",
            "AXPress is availability only; no input/invoke or callback receipt exists, so hit-testing remains untested.",
            "One Windows observation is not qualified 20-run parity; native/provider/occlusion and frozen tuple bindings remain held.",
            "Mac intervals are same-process offscreen render begin/end durations, not input latency; Windows compile duration is separate.",
            "Mac text-renderer channel is empty and paint/geometry units are not cross-provider normalized.",
        ],
        "rawJoins":{"caseId":CASE_ID,"sourceSha256":SOURCE_SHA,"windowsManifestHash":plan["manifestHash"],"windowsCompilePlanSha256":compile["planSha256"],"windowsCompileReceiptSha256":sha(raw("windows-compile-observation")),"macRunIds":[f"{CASE_ID}.macos.run-{i:03d}" for i in range(1,21)],"macIntervalCount":len(mac_intervals)},
        "limits":["Review is offline and consumes frozen producer bytes only.","No qualified parity or promotion is implied."]
    }

def load_and_audit(root: Path = ROOT):
    manifest_raw, manifest, payloads = load_payloads(root)
    return audit_payloads(manifest_raw, manifest, payloads)
