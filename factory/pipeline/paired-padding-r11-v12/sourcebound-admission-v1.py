#!/usr/bin/env python3
"""Append-only source-bound Count20 report; protected Windows gate stays untouched."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path, PurePosixPath

SHA = re.compile(r"^sha256:[0-9a-f]{64}$")
MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
ROLES = {"outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr"}


class Hold(ValueError):
    pass


def safe(value: object) -> Path:
    if not isinstance(value, str) or not value or value.startswith("/") or "\\" in value or ":" in value:
        raise Hold("unsafe source-bound path")
    p = PurePosixPath(value)
    if str(p) != value or p.is_absolute() or ".." in p.parts:
        raise Hold("source-bound path escapes repository")
    return Path(*p.parts)


def raw(repo: Path, ref: dict, label: str, *, limit: int = MAX_FILE) -> bytes:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str) or not SHA.fullmatch(str(ref.get("sha256"))):
        raise Hold(f"{label} ref malformed")
    expected = ref.get("bytes")
    if not isinstance(expected, int) or expected < 0 or expected > limit:
        raise Hold(f"{label} byte bound invalid")
    candidate = repo / safe(ref["path"])
    if candidate.is_symlink() or not candidate.is_file():
        raise Hold(f"{label} file missing or symlink")
    path = candidate.resolve()
    try: path.relative_to(repo.resolve())
    except ValueError as exc: raise Hold(f"{label} escapes repository") from exc
    if path.stat().st_size != expected or expected > limit:
        raise Hold(f"{label} file exceeds bound or byte count differs")
    data = path.read_bytes()
    if len(data) != expected or "sha256:" + hashlib.sha256(data).hexdigest() != ref["sha256"]:
        raise Hold(f"{label} byte/hash mismatch")
    return data


def obj(repo: Path, ref: dict, label: str) -> dict:
    value = json_value(repo, ref, label)
    if not isinstance(value, dict): raise Hold(f"{label} JSON object required")
    return value


def json_value(repo: Path, ref: dict, label: str) -> object:
    data = raw(repo, ref, label, limit=MAX_JSON)
    try: return json.loads(data.decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc: raise Hold(f"{label} JSON invalid") from exc


def path_obj(repo: Path, path: str, label: str) -> dict:
    candidate = repo / safe(path)
    if candidate.is_symlink() or not candidate.is_file() or candidate.stat().st_size > MAX_JSON:
        raise Hold(f"{label} unavailable or exceeds bound")
    try: value = json.loads(candidate.read_text(encoding="utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc: raise Hold(f"{label} JSON invalid") from exc
    if not isinstance(value, dict): raise Hold(f"{label} JSON object required")
    return value


def canonical(value: object, label: str) -> str:
    if not isinstance(value, str): raise Hold(f"{label} hash missing")
    result = value if value.startswith("sha256:") else "sha256:" + value
    if not SHA.fullmatch(result): raise Hold(f"{label} hash malformed")
    return result


def validate_sourcebound(inputs: dict, normalized: dict, proof: dict, adapter_plan: dict, repo: Path) -> dict:
    if inputs.get("schema") != "factory-native-count20-r17-input-map-v12" or inputs.get("version") != 12:
        raise Hold("v12 input map required")
    if normalized.get("kind") != "factory-native-count20-r17-normalized-inputs-v12" or normalized.get("typedStatus") != "normalized-observational" or normalized.get("qualified") is not False:
        raise Hold("v12 normalized observational output required")
    if proof.get("status") != "proofs-attached" or not isinstance(proof.get("captures"), list) or len(proof["captures"]) != 20:
        raise Hold("proof bundle must contain 20 attached captures")
    if adapter_plan.get("kind") != "factory-fresh-r11-count20-adapter-plan-r17" or adapter_plan.get("count") != 20:
        raise Hold("fresh r17 adapter plan required")
    tuple_doc = adapter_plan.get("tuple") or {}
    expected_case = {"id": tuple_doc.get("caseID"), "hash": tuple_doc.get("caseHash")}
    expected_source = canonical(tuple_doc.get("sourceHash"), "fresh source")
    expected_exe = canonical(tuple_doc.get("windowsHostHash"), "fresh executable")
    if not isinstance(expected_case["id"], str) or not SHA.fullmatch(str(expected_case["hash"])):
        raise Hold("fresh adapter case missing")
    profile = inputs.get("freshSourceProfile") or {}
    if profile.get("caseID") != expected_case["id"] or profile.get("caseHash") != expected_case["hash"] or profile.get("sourceHash") != expected_source or (profile.get("hostHashes") or {}).get("windows") != expected_exe:
        raise Hold("fresh adapter/input profile join missing")
    pairs = (inputs.get("lineage") or {}).get("issuedPairs")
    runs = inputs.get("runs")
    captures = normalized.get("captures")
    if not isinstance(pairs, list) or len(pairs) != 20 or not isinstance(runs, list) or len(runs) != 20 or not isinstance(captures, list) or len(captures) != 20:
        raise Hold("ordered Count20 source-bound rows missing")
    compile_doc = obj(repo, inputs["roles"]["compile"], "compile observation")
    renderer = canonical(profile.get("rendererHash"), "fresh renderer")
    source_plan = obj(repo, inputs["roles"]["plan"], "source plan")
    source_plan_case = source_plan.get("case")
    comparator_ref = ((adapter_plan.get("mac") or {}).get("comparator") or {}).get("path")
    comparator = path_obj(repo, comparator_ref, "Mac20 comparator") if isinstance(comparator_ref, str) else None
    rows = []
    for index, (pair, run, capture, attached) in enumerate(zip(pairs, runs, captures, proof["captures"]), 1):
        if capture.get("id") != pair.get("captureID") or (capture.get("images") or [{}])[0].get("id") != pair.get("imageID"):
            raise Hold(f"run {index} issued pair mismatch")
        if capture.get("case") != expected_case or capture.get("provenance", {}).get("sourceHash") != expected_source:
            raise Hold(f"run {index} fresh case/source mismatch")
        tuple_value = capture.get("tuple") or {}
        if tuple_value.get("id") != tuple_doc.get("id") or tuple_value.get("hostHashes", {}).get("windows") != expected_exe or tuple_value.get("rendererHash") != renderer:
            raise Hold(f"run {index} candidate tuple/executable/renderer mismatch")
        measurement = obj(repo, run["measurement"], f"run {index} measurement")
        if measurement.get("run") != index or measurement.get("captureID") != pair.get("captureID") or measurement.get("imageID") != pair.get("imageID"):
            raise Hold(f"run {index} measured pair mismatch")
        if canonical(measurement.get("issuedMetadataHash"), f"run {index} issued metadata") != canonical((inputs.get("lineage") or {}).get("issuedMetadataSha256"), "issued metadata"):
            raise Hold(f"run {index} issued metadata mismatch")
        observation = json_value(repo, run["observation"], f"run {index} observation")
        observed_rows = observation if isinstance(observation, list) else [observation]
        matches = [row for row in observed_rows if isinstance(row, dict) and row.get("index") == index]
        if len(matches) != 1 or matches[0].get("case") != expected_case or matches[0].get("sourceHash") != expected_source or matches[0].get("hostValid") is not True:
            raise Hold(f"run {index} measured observation join missing")
        if canonical(compile_doc.get("exeSha256"), "compile executable") != expected_exe:
            raise Hold("compile/fresh executable mismatch")
        proof_meta = (attached.get("meta") or {}).get("conditions") or {}
        windows = proof_meta.get("windowsExitProof") or {}
        if attached.get("id") != pair.get("captureID") or not isinstance(windows.get("files"), dict) or set(windows["files"]) != ROLES:
            raise Hold(f"run {index} proof role closure missing")
        if proof_meta.get("actualSourceHash") not in (None, expected_source) or proof_meta.get("actualHostExecutableHash") not in (None, expected_exe) or proof_meta.get("actualRendererHash") not in (None, renderer):
            raise Hold(f"run {index} proof source/executable/renderer join mismatch")
        rows.append({"run": index, "captureID": pair["captureID"], "imageID": pair["imageID"], "sourceHash": expected_source, "case": expected_case, "measuredObservation": True, "proofRoles": len(windows["files"])})
    protected_issues = []
    if source_plan_case != expected_case:
        protected_issues.append("protected windows_exit_admission requires capture.case==plan.case; source plan retains legacy case while issued/native capture uses fresh adapter case")
    raw_windows = {"timing": 0, "lifecycle": 0, "stdout": 0, "stderr": 0, "uia": 0, "pixels": 0, "printWindow": 0}
    for run in runs:
        for entry in run.get("rawClosure", []):
            name = Path(str(entry.get("path", ""))).name
            if name in ("capture-ordering.json", "lifecycle-timing.json"): raw_windows["timing"] += 1
            if name == "lifecycle-timing.json": raw_windows["lifecycle"] += 1
            if name == "host.stdout.txt": raw_windows["stdout"] += 1
            if name == "host.stderr.txt": raw_windows["stderr"] += 1
            if name == "native.uia.json": raw_windows["uia"] += 1
            if name == "native.pixels.json": raw_windows["pixels"] += 1
            if name == "native.printwindow.png": raw_windows["printWindow"] += 1
    mac_case = comparator.get("case") if isinstance(comparator, dict) else None
    mac_captures = comparator.get("macCaptures") if isinstance(comparator, dict) else []
    paired = {
        "caseMatch": mac_case == expected_case,
        "mac": {"count": len(mac_captures) if isinstance(mac_captures, list) else 0, "status": comparator.get("status") if isinstance(comparator, dict) else "missing", "case": mac_case, "semantic": comparator.get("semantic") if isinstance(comparator, dict) else None, "timingRaw": comparator.get("timing", {}).get("rawEvidence", []) if isinstance(comparator, dict) else []},
        "windows": {"count": 20, "sourceBoundRows": len(rows), "channels": {"uia": raw_windows["uia"], "pixels": raw_windows["pixels"], "printWindow": raw_windows["printWindow"], "stdout": raw_windows["stdout"], "stderr": raw_windows["stderr"]}, "timingRaw": raw_windows, "readerRoute": "production ArchiveByteReader unchanged; protected exit gate not bypassed"},
        "passed": {"issuedPairs": 20, "measuredObservations": 20, "proofRoleRows": 20},
        "mismatched": list(protected_issues) + ([] if mac_case == expected_case else ["Mac comparator case differs from fresh Windows adapter case"]),
        "missing": [key for key, count in raw_windows.items() if count < 20],
        "parityClaim": False,
    }
    return {"rows": rows, "sourcePlanCase": source_plan_case, "freshAdapterCase": expected_case, "protectedIssues": protected_issues, "sourceBoundEvidence": "admitted", "count": 20, "pairedComparison": paired}


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--repo", required=True, type=Path); ap.add_argument("--input-map", required=True, type=Path); ap.add_argument("--normalized", required=True, type=Path); ap.add_argument("--proof-bundle", required=True, type=Path); ap.add_argument("--adapter-plan", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink(): raise SystemExit("HOLD: output must be fresh")
    try:
        repo = args.repo.resolve()
        inputs = path_obj(repo, args.input_map.resolve().relative_to(repo).as_posix(), "input map")
        normalized = path_obj(repo, args.normalized.resolve().relative_to(repo).as_posix(), "normalized")
        proof = path_obj(repo, args.proof_bundle.resolve().relative_to(repo).as_posix(), "proof bundle")
        adapter_plan = path_obj(repo, args.adapter_plan.resolve().relative_to(repo).as_posix(), "adapter plan")
        evidence = validate_sourcebound(inputs, normalized, proof, adapter_plan, repo)
        protected_issues = list(evidence["protectedIssues"]) + ([] if evidence["pairedComparison"]["caseMatch"] else ["paired comparator case mismatch"])
        output = {"schema": "factory-native-count20-sourcebound-admission-v1", "version": 1, "status": "blocked-by-protected-production-gate" if protected_issues else "source-bound-admitted-protected-gate-ready", "count": 20, "sourceBoundEvidence": evidence["sourceBoundEvidence"], "protectedGate": {"status": "blocked" if protected_issues else "not-run", "issues": protected_issues}, "freshAdapterPlan": adapter_plan.get("kind"), "sourcePlanCase": evidence["sourcePlanCase"], "freshAdapterCase": evidence["freshAdapterCase"], "rows": evidence["rows"], "pairedComparison": evidence["pairedComparison"], "comparisonEligible": False, "nativeActions": 0, "lockActions": 0, "qualification": "truthful-source-bound-comparison-hold"}
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8"); print(json.dumps({"status": output["status"], "count": output["count"], "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0


if __name__ == "__main__": raise SystemExit(main())
