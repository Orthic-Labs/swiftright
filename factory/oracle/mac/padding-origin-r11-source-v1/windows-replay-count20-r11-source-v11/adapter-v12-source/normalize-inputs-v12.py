#!/usr/bin/env python3
"""Normalize strict r17 inputs through frozen v6 schema logic.

This stage performs no native action, archive copy, proof minting, or readiness
claim.  New r17 admission owns joins; frozen v6 owns canonical capture schema.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, re
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
REPO = next((parent for parent in HERE.parents if (parent / "factory").is_dir()), None)
if REPO is None:
    raise SystemExit("HOLD: repository root unavailable")
V6 = REPO / "factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/adapter-v6.py"
if not V6.is_file():
    raise SystemExit("HOLD: frozen adapter-v6 source unavailable")
_spec = importlib.util.spec_from_file_location("frozen_adapter_v6_for_r17", V6)
_frozen = importlib.util.module_from_spec(_spec); assert _spec.loader; _spec.loader.exec_module(_frozen)

SHA = re.compile(r"^sha256:[0-9a-f]{64}$")
MAX_FILE = 64 * 1024 * 1024
MAX_JSON = 2 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024

class Hold(ValueError): pass

def safe_path(value: object) -> Path:
    if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value or ":" in value:
        raise Hold("unsafe archive reference")
    parsed = PurePosixPath(value)
    if str(parsed) != value or parsed.is_absolute() or ".." in parsed.parts:
        raise Hold("archive reference escapes root")
    return Path(*parsed.parts)

def ref_bytes(root: Path, ref: object, label: str, *, limit: int = MAX_FILE) -> bytes:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str) or not SHA.fullmatch(str(ref.get("sha256"))):
        raise Hold(f"{label} reference malformed")
    candidate = root / safe_path(ref["path"])
    if candidate.is_symlink(): raise Hold(f"{label} file missing or symlink")
    path = candidate.resolve()
    try: path.relative_to(root.resolve())
    except ValueError as exc: raise Hold(f"{label} reference escapes root") from exc
    if not path.is_file(): raise Hold(f"{label} file missing or symlink")
    expected = ref.get("bytes")
    if not isinstance(expected, int) or expected < 0 or expected > limit: raise Hold(f"{label} bytes outside bound")
    try:
        actual_size = path.stat().st_size
    except OSError as exc:
        raise Hold(f"{label} stat failed") from exc
    if actual_size != expected or actual_size > limit:
        raise Hold(f"{label} bytes outside bound")
    raw = path.read_bytes()
    if len(raw) != expected or "sha256:" + hashlib.sha256(raw).hexdigest() != ref["sha256"]:
        raise Hold(f"{label} byte/hash join mismatch")
    return raw

def doc(root: Path, ref: object, label: str) -> dict:
    raw = ref_bytes(root, ref, label, limit=MAX_JSON)
    try: value = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc: raise Hold(f"{label} JSON invalid") from exc
    if not isinstance(value, dict): raise Hold(f"{label} must be object")
    return value

def digest(raw: bytes) -> str: return "sha256:" + hashlib.sha256(raw).hexdigest()


def validate_normalized(value: object, inputs: dict, root: Path) -> None:
    """Re-admit normalized reader evidence against bounded producer refs."""
    if not isinstance(value, dict) or value.get("kind") != "factory-native-count20-r17-normalized-inputs-v12" or value.get("version") != 12:
        raise Hold("normalized v12 schema mismatch")
    captures = value.get("captures")
    runs = inputs.get("runs") if isinstance(inputs, dict) else None
    pairs = (inputs.get("lineage") or {}).get("issuedPairs") if isinstance(inputs, dict) else None
    archive_root_value = (inputs.get("inputRoot") or {}).get("archiveRoot") if isinstance(inputs, dict) else None
    if value.get("typedStatus") != "normalized-observational" or value.get("qualified") is not False or not isinstance(captures, list) or len(captures) != 20 or not isinstance(runs, list) or len(runs) != 20 or not isinstance(pairs, list) or len(pairs) != 20:
        raise Hold("normalized admission status/count mismatch")
    archive_root = safe_path(archive_root_value).as_posix()
    expected = value.get("freshSourceProfile") or {}
    case = {"id": expected.get("caseID"), "hash": expected.get("caseHash")}
    host_hash = (expected.get("hostHashes") or {}).get("windows")
    if not isinstance(case["id"], str) or not SHA.fullmatch(str(case["hash"])) or not SHA.fullmatch(str(host_hash)):
        raise Hold("normalized fresh profile missing")
    total = 0
    for index, (capture, run, pair) in enumerate(zip(captures, runs, pairs), 1):
        if not isinstance(capture, dict) or capture.get("id") != pair.get("captureID") or (capture.get("images") or [{}])[0].get("id") != pair.get("imageID") or capture.get("case") != case:
            raise Hold(f"run {index} normalized identity join missing")
        if capture.get("meta", {}).get("host", {}).get("hash") != host_hash:
            raise Hold(f"run {index} normalized host join missing")
        evidence = capture.get("meta", {}).get("conditions", {}).get("readerEvidence")
        if not isinstance(evidence, dict) or evidence.get("kind") != "measured-uia-paint-proof-v1":
            raise Hold(f"run {index} normalized reader evidence missing")
        closure = {entry.get("path"): entry for entry in run.get("rawClosure", []) if isinstance(entry, dict)}
        prefix = archive_root.rstrip("/") + f"/replays/r1/native-{index:02d}/"
        required = {
            "uiaSha256": "native.uia.json",
            "pixelsReceiptSha256": "native.pixels.json",
            "printWindowSha256": "native.printwindow.png",
            "printWindowRepeatSha256": "native.printwindow.repeat.png",
            "stdoutSha256": "host.stdout.txt",
        }
        for evidence_key, filename in required.items():
            source_ref = closure.get(prefix + filename)
            if not isinstance(source_ref, dict) or evidence.get(evidence_key) != source_ref.get("sha256"):
                raise Hold(f"run {index} normalized raw reader join missing: {filename}")
            raw = ref_bytes(root, source_ref, f"run {index} {filename}")
            if digest(raw) != evidence[evidence_key]:
                raise Hold(f"run {index} normalized raw reader hash mismatch: {filename}")
            total += len(raw)
            if total > MAX_TOTAL:
                raise Hold("normalized reader input bound exceeded")
        dims = evidence.get("printWindow") or {}
        image = (capture.get("images") or [{}])[0]
        if image.get("hash") != evidence.get("printWindowSha256") or image.get("widthPx") != dims.get("widthPx") or image.get("heightPx") != dims.get("heightPx"):
            raise Hold(f"run {index} normalized paint image join missing")
        if evidence.get("uiaParsed") is not True or evidence.get("pixelsReceiptParsed") is not True or not isinstance(evidence.get("uiaNodeCount"), int) or evidence["uiaNodeCount"] <= 0:
            raise Hold(f"run {index} normalized UIA/pixels proof missing")

def normalize(inputs: dict, root: Path) -> dict:
    if inputs.get("schema") != "factory-native-count20-r17-input-map-v12" or inputs.get("version") != 12:
        raise Hold("v12 input map required")
    roles = inputs.get("roles")
    if not isinstance(roles, dict): raise Hold("input roles missing")
    issued = doc(root, roles.get("issuedMetadata"), "issued metadata")
    plan = doc(root, roles.get("plan"), "r17 plan")
    compile_doc = doc(root, roles.get("compile"), "r17 compile observation")
    tuple_doc = doc(root, roles.get("tuple"), "candidate tuple")
    candidate = tuple_doc.get("tuple")
    if not isinstance(candidate, dict): raise Hold("candidate tuple value missing")
    lineage = inputs.get("lineage") or {}; pairs = lineage.get("issuedPairs")
    if not isinstance(pairs, list) or len(pairs) != 20: raise Hold("issued ordered pairs missing")
    runs = inputs.get("runs")
    if not isinstance(runs, list) or len(runs) != 20: raise Hold("normalized run count mismatch")
    expected = inputs.get("freshSourceProfile") or {}
    case = {"id": expected.get("caseID"), "hash": expected.get("caseHash")}
    if issued.get("case") != case or not isinstance(case["id"], str) or not SHA.fullmatch(str(case["hash"])):
        raise Hold("fresh issued/candidate case admission missing")
    compile_exe = compile_doc.get("exeSha256")
    if not isinstance(compile_exe, str) or not re.fullmatch(r"[0-9a-f]{64}", compile_exe.removeprefix("sha256:")):
        raise Hold("fresh compile executable hash missing")
    compile_exe_hash = "sha256:" + compile_exe.removeprefix("sha256:")
    if expected.get("hostHashes", {}).get("windows") != compile_exe_hash:
        raise Hold("fresh candidate/compile executable join missing")
    archive_root_value = (inputs.get("inputRoot") or {}).get("archiveRoot")
    archive_root = safe_path(archive_root_value).as_posix()
    captures = []
    total = 0
    for index, run in enumerate(runs, 1):
        if not isinstance(run, dict) or run.get("run") != index or run.get("captureID") != pairs[index-1].get("captureID") or run.get("imageID") != pairs[index-1].get("imageID"):
            raise Hold(f"run {index} issued pair join missing")
        outcome = doc(root, run.get("outcome"), f"run {index} outcome")
        measurement = doc(root, run.get("measurement"), f"run {index} measurement")
        if measurement.get("captureID") != run["captureID"] or measurement.get("imageID") != run["imageID"]:
            raise Hold(f"run {index} measurement pair mismatch")
        prefix = f"replays/r1/native-{index:02d}/"
        archive_prefix = archive_root.rstrip("/") + "/" + prefix
        # Explicit top-level roles are selected from full closure; no discovery.
        closure = {entry.get("path"): entry for entry in run.get("rawClosure", []) if isinstance(entry, dict)}
        required = ("native.uia.json", "native.pixels.json", "native.printwindow.png", "native.printwindow.repeat.png", "host.stdout.txt")
        required_refs = {name: closure.get(archive_prefix + name) for name in required}
        if any(not isinstance(value, dict) for value in required_refs.values()): raise Hold(f"run {index} reader channels missing")
        uia_raw = ref_bytes(root, required_refs["native.uia.json"], f"run {index} UIA", limit=MAX_JSON)
        pixels_raw = ref_bytes(root, required_refs["native.pixels.json"], f"run {index} pixels", limit=MAX_JSON)
        png_raw = ref_bytes(root, required_refs["native.printwindow.png"], f"run {index} PrintWindow")
        repeat_png_raw = ref_bytes(root, required_refs["native.printwindow.repeat.png"], f"run {index} repeated PrintWindow")
        stdout_raw = ref_bytes(root, required_refs["host.stdout.txt"], f"run {index} stdout")
        total += len(uia_raw) + len(pixels_raw) + len(png_raw) + len(repeat_png_raw) + len(stdout_raw)
        if total > MAX_TOTAL: raise Hold("normalized reader input bound exceeded")
        try:
            ui = _frozen.frozen.r.parse(uia_raw)
            pixels_receipt = _frozen.frozen.r.parse(pixels_raw)
            if not isinstance(pixels_receipt, dict):
                raise ValueError("pixels receipt must be object")
            projection = _frozen.frozen.r.channels(ui, png_raw, stdout_raw)
        except Exception as exc: raise Hold(f"run {index} frozen channel normalization failed") from exc
        host = measurement.get("measuredHostIdentity") or {}
        if host.get("hash") != compile_exe_hash:
            raise Hold(f"run {index} measured host/compiler executable join missing")
        provenance = {"sourceHash": expected.get("sourceHash"), "createdAt": (issued.get("captures") or [])[index-1].get("provenance", {}).get("createdAt"), "producer": "r17-measured-export"}
        reader_evidence = {
            "kind": "measured-uia-paint-proof-v1",
            "uiaSha256": digest(uia_raw),
            "pixelsReceiptSha256": digest(pixels_raw),
            "printWindowSha256": digest(png_raw),
            "printWindowRepeatSha256": digest(repeat_png_raw),
            "stdoutSha256": digest(stdout_raw),
            "uiaParsed": True,
            "pixelsReceiptParsed": True,
            "uiaNodeCount": len(projection["ax"]),
            "printWindow": projection["printWindow"],
        }
        capture = {
            "kind": "capture", "version": "0.1", "id": run["captureID"], "provenance": provenance,
            "case": case, "platform": "windows", "tuple": candidate,
            "meta": {"run": index, "host": {"id": host.get("id"), "hash": host.get("hash")}, "clock": {"clockId": (measurement.get("measuredClockIdentity") or {}).get("clockId"), "correlationHash": run["measurement"]["sha256"]}, "conditions": {"evidenceClass": "observational-native", "frozenTupleBound": False, "nativeParity": "hold", "providerPaintAvailable": False, "layoutAvailable": False, "animationClockCorrelated": False, "nativeProviderClockQualified": False, "clockKind": "process-local-stopwatch", "issuedMetadataHash": lineage.get("issuedMetadataSha256"), "originalOutcomeHash": run["outcome"]["sha256"], "sourceBoundCandidateTupleHash": roles["candidateBinding"]["sha256"], "rawHashesQualification": outcome.get("rawHashesQualification"), "rawHashStates": outcome.get("rawHashStates"), "readerEvidence": reader_evidence}},
            "layout": [], "ax": projection["ax"], "events": [], "anim": [], "images": [dict(id=run["imageID"], **projection["printWindow"])], "text": [],
        }
        try: _frozen.validate_capture(capture)
        except Exception as exc: raise Hold(f"run {index} frozen canonical capture admission failed") from exc
        captures.append(capture)
    result = {"kind": "factory-native-count20-r17-normalized-inputs-v12", "version": 12, "typedStatus": "normalized-observational", "qualified": False, "nativeParity": "hold", "nativeActions": 0, "lockActions": 0, "captures": captures, "issues": ["provider/layout/text/event/animation/native-provider-clock unavailable", "proof and trusted reader admission remain held"], "lineage": {"runID": lineage.get("runID"), "issuedMetadataSha256": lineage.get("issuedMetadataSha256"), "issuedPairs": pairs}, "freshSourceProfile": expected, "sourceInputMapSchema": inputs.get("schema"), "normalizer": {"kind": "frozen-v6-canonical-schema-composed", "source": str(V6.relative_to(root)) if V6.is_relative_to(root) else str(V6)}}
    validate_normalized(result, inputs, root)
    return result

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--inputs", required=True, type=Path); ap.add_argument("--repo", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink(): raise SystemExit("HOLD: output must be fresh")
    try:
        if args.inputs.is_symlink() or not args.inputs.is_file() or args.inputs.stat().st_size > MAX_JSON:
            raise Hold("input map exceeds bounded JSON read")
        raw = args.inputs.read_bytes()
        if len(raw) > MAX_JSON: raise Hold("input map exceeds bounded JSON read")
        inputs = json.loads(raw.decode("utf-8-sig")); root = args.repo.resolve()
        out = normalize(inputs, root)
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": out["typedStatus"], "count": len(out["captures"]), "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0
if __name__ == "__main__": raise SystemExit(main())
