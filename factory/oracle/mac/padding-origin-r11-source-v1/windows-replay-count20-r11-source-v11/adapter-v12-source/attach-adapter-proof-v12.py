#!/usr/bin/env python3
"""Attach only producer-backed Windows proof roles to v12 normalized captures."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path, PurePosixPath

SHA = re.compile(r"^sha256:[0-9a-f]{64}$")
MAX_JSON = 2 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
ROLE_NAMES = ("outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr")
class Hold(ValueError): pass

def safe(value: object) -> Path:
    if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value or ":" in value: raise Hold("unsafe proof ref")
    p = PurePosixPath(value)
    if str(p) != value or p.is_absolute() or ".." in p.parts: raise Hold("proof ref escapes repo")
    return Path(*p.parts)

def raw(root: Path, ref: object, label: str) -> bytes:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str): raise Hold(f"{label} ref malformed")
    expected_hash = ref.get("sha256", ref.get("hash"))
    if not SHA.fullmatch(str(expected_hash)): raise Hold(f"{label} ref hash malformed")
    if ref.get("bytes") is not None and (not isinstance(ref.get("bytes"), int) or ref["bytes"] < 0 or ref["bytes"] > MAX_FILE): raise Hold(f"{label} bound invalid")
    path = (root / safe(ref["path"])).resolve()
    try: path.relative_to(root.resolve())
    except ValueError as exc: raise Hold(f"{label} escapes root") from exc
    if path.is_symlink() or not path.is_file(): raise Hold(f"{label} missing or symlink")
    data = path.read_bytes()
    if ref.get("bytes") is not None and len(data) != ref["bytes"]: raise Hold(f"{label} byte count mismatch")
    if "sha256:" + hashlib.sha256(data).hexdigest() != expected_hash: raise Hold(f"{label} byte/hash mismatch")
    return data

def obj(root: Path, ref: object, label: str) -> dict:
    data = raw(root, ref, label)
    if len(data) > MAX_JSON: raise Hold(f"{label} exceeds JSON bound")
    try: value = json.loads(data.decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc: raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict): raise Hold(f"{label} must be object")
    return value

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--normalized", required=True, type=Path); ap.add_argument("--inputs", required=True, type=Path); ap.add_argument("--proof-bundle", required=True, type=Path); ap.add_argument("--repo", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink(): raise SystemExit("HOLD: output must be fresh")
    try:
        root = args.repo.resolve(); normalized = obj(root, {"path": args.normalized.resolve().relative_to(root).as_posix(), "sha256": "sha256:" + hashlib.sha256(args.normalized.read_bytes()).hexdigest(), "bytes": args.normalized.stat().st_size}, "normalized")
        inputs = obj(root, {"path": args.inputs.resolve().relative_to(root).as_posix(), "sha256": "sha256:" + hashlib.sha256(args.inputs.read_bytes()).hexdigest(), "bytes": args.inputs.stat().st_size}, "inputs")
        bundle = obj(root, {"path": args.proof_bundle.resolve().relative_to(root).as_posix(), "sha256": "sha256:" + hashlib.sha256(args.proof_bundle.read_bytes()).hexdigest(), "bytes": args.proof_bundle.stat().st_size}, "proof bundle")
        if normalized.get("typedStatus") != "normalized-observational" or normalized.get("qualified") is not False: raise Hold("normalized stage must remain observational")
        if bundle.get("status") != "proofs-attached" or not isinstance(bundle.get("captures"), list) or len(bundle["captures"]) != 20: raise Hold("proof bundle status/count mismatch")
        admission = inputs.get("cleanupAdmission") or {}
        if (admission.get("activeProcessCount") != 1 or admission.get("selfOnlyAccepted") is not True or admission.get("liveChildRejected") is not True
                or admission.get("externalTaskTerminal") is not True or admission.get("wholeBatchExitConfirmed") is not True
                or admission.get("lockReleased") is not True or admission.get("cleanupErrors") != []):
            raise Hold("self-only active-process cleanup admission missing")
        if not isinstance((inputs.get("roles") or {}).get("memoryControls"), dict):
            raise Hold("memory controls role missing")
        captures = normalized.get("captures"); pairs = (inputs.get("lineage") or {}).get("issuedPairs")
        if not isinstance(captures, list) or len(captures) != 20 or not isinstance(pairs, list) or len(pairs) != 20: raise Hold("normalized pairs missing")
        rows = []
        for index, (capture, proof) in enumerate(zip(captures, bundle["captures"]), 1):
            expected_capture = pairs[index-1].get("captureID"); expected_image = pairs[index-1].get("imageID")
            if capture.get("id") != expected_capture or (capture.get("images") or [{}])[0].get("id") != expected_image or proof.get("id") != expected_capture: raise Hold(f"run {index} issued pair mismatch")
            conditions = proof.setdefault("meta", {}).setdefault("conditions", {})
            files = conditions.get("windowsExitProof", {}).get("files")
            if not isinstance(files, dict) or set(files) != set(ROLE_NAMES): raise Hold(f"run {index} requires exact 13 proof roles")
            archive_row = (bundle.get("archiveBindings") or {}).get(str(index))
            if not isinstance(archive_row, dict): raise Hold(f"run {index} archive binding missing")
            for role in ROLE_NAMES:
                descriptor = files[role]; entry = archive_row.get(descriptor.get("path")) if isinstance(descriptor, dict) else None
                if not isinstance(entry, dict) or entry.get("sha256") != descriptor.get("hash") or not isinstance(entry.get("sourcePath"), str): raise Hold(f"run {index} proof/source join missing: {role}")
                source_path = Path(entry["sourcePath"]).resolve()
                try: source_path.relative_to(root)
                except ValueError as exc: raise Hold(f"run {index} proof source outside repo: {role}") from exc
                source_ref = {"path": source_path.relative_to(root).as_posix(), "sha256": entry["sha256"], "bytes": entry.get("bytes")}
                raw(root, source_ref, f"run {index} proof {role}")
            run = inputs["runs"][index-1]; outcome = obj(root, run["outcome"], f"run {index} outcome"); cert = obj(root, run["finalExit"], f"run {index} final exit"); terminal = obj(root, run["terminal"], f"run {index} terminal")
            cleanup = outcome.get("cleanup") or {}; sample = cert.get("sample") or {}
            if outcome.get("primaryError") != "" or outcome.get("streamErrors") != [] or cleanup.get("confirmedOwnedExit") is not True or cleanup.get("kernelExitSignaled") is not True or cleanup.get("kernelWaitResult") != 0: raise Hold(f"run {index} cleanup not proven")
            if sample.get("waitMilliseconds") != 0 or sample.get("kernelBefore") != 0 or sample.get("kernelAfter") != 0 or sample.get("getExitCodeSucceeded") is not True or sample.get("exitCode") != 0 or sample.get("errors") != []: raise Hold(f"run {index} retained original-handle exit not proven")
            if terminal.get("terminalResultConfirmed") is not True: raise Hold(f"run {index} terminal worker not proven")
            states = outcome.get("rawStreams")
            if not isinstance(states, list) or len(states) != 2 or {state.get("name") for state in states} != {"stdout", "stderr"} or any(state.get("sealed") is not True or state.get("hashQualification") != "sealed-raw" for state in states): raise Hold(f"run {index} stream drain not proven")
            conditions["windowsExitProof"] = {"version": 1, "status": "producer-attached", "files": files, "run": index, "captureID": expected_capture, "imageID": expected_image, "originalHandleTerminal": True, "streamsDrained": True, "activeProcessCount": 1, "activeCountQualification": "self-only-after-child-terminal", "liveChildCount": 0, "externalTaskTerminal": True, "wholeBatchExitConfirmed": True, "lockReleased": True}
            rows.append({"run": index, "captureID": expected_capture, "imageID": expected_image, "proofRoles": len(files), "originalHandleTerminal": True, "streamsDrained": True, "activeProcessCount": 1, "activeCountQualification": "self-only-after-child-terminal", "liveChildCount": 0, "externalTaskTerminal": True, "wholeBatchExitConfirmed": True, "lockReleased": True})
        out = {"schema": "factory-native-count20-r17-adapter-proof-v12", "status": "proofs-attached", "count": 20, "qualified": False, "nativeActions": 0, "lockActions": 0, "captures": bundle["captures"], "archiveBindings": bundle.get("archiveBindings", {}), "rows": rows, "lineage": normalized.get("lineage"), "sourceInputMap": inputs.get("schema"), "cleanupAdmission": admission, "readyForTrustedReader": True, "hold": "qualification remains held for parity/golden/freeze; trusted reader may verify producer-backed exit proof"}
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8"); print(json.dumps({"status": out["status"], "count": 20, "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0
if __name__ == "__main__": raise SystemExit(main())
