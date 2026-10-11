#!/usr/bin/env python3
"""Create fresh producer capture-plan metadata after an admitted Windows build.

This copies the v3 producer plan, binds it to fresh package/case/receipt bytes,
& leaves producer PowerShell sources unchanged.  It performs metadata joins only;
it does not compile, launch, acquire desktop lock, or create capture output.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

MAX_JSON = 8 * 1024 * 1024
MAX_SUPPORT = 32 * 1024 * 1024


class Hold(ValueError):
    pass


def _safe_file(path: Path, label: str, limit: int = MAX_SUPPORT) -> Path:
    if path.is_symlink() or not path.is_file():
        raise Hold(f"{label} missing or symlink")
    size = path.stat().st_size
    if size > limit:
        raise Hold(f"{label} exceeds bounded read")
    return path


def file_sha256(path: Path, label: str, limit: int = MAX_SUPPORT) -> tuple[str, int]:
    path = _safe_file(path, label, limit)
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            total += len(chunk)
    return digest.hexdigest(), total


def bounded_json(path: Path, label: str) -> dict:
    _safe_file(path, label, MAX_JSON)

    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise Hold(f"{label} duplicate JSON key")
            value[key] = item
        return value

    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"), object_pairs_hook=pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} object required")
    return value


def sha256_ref(value: str, label: str) -> str:
    if not isinstance(value, str):
        raise Hold(f"{label} hash missing")
    bare = value.removeprefix("sha256:")
    if len(bare) != 64 or any(char not in "0123456789abcdef" for char in bare.lower()):
        raise Hold(f"{label} hash malformed")
    return "sha256:" + bare.lower()


def fresh_case(source_plan: dict) -> dict:
    case = source_plan.get("case")
    if not isinstance(case, dict) or not isinstance(case.get("id"), str) or not isinstance(case.get("hash"), str):
        raise Hold("fresh source-plan case reference missing")
    return {"id": case["id"], "hash": sha256_ref(case["hash"], "fresh case")}


def require_path(value: str | None, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise Hold(f"{label} required")
    return value


def materialize(base: dict, source_plan: dict, package: Path, receipt: Path, executable: Path,
                preflight: Path, renderer: Path, serializer: Path, producer_root: str,
                first_root: str, repeat_root: str, output_root: str,
                issued: Path, candidate: Path | None) -> dict:
    if base.get("kind") != "padding-capture-lease-capture-source-plan-v1":
        raise Hold("v3 capture-plan kind required")
    if source_plan.get("executionEligible") is not False:
        raise Hold("fresh source plan must remain execution-ineligible before native replay")
    case = fresh_case(source_plan)
    source_hash = sha256_ref(source_plan.get("sourceHash"), "source witness")
    receipt_value = bounded_json(receipt, "compile receipt")
    package_plan = _safe_file(package / "plan.json", "compiled package plan", MAX_JSON)
    package_plan_hash, package_plan_bytes = file_sha256(package_plan, "compiled package plan", MAX_JSON)
    receipt_hash, receipt_bytes = file_sha256(receipt, "compile receipt", MAX_JSON)
    exe_hash, exe_bytes = file_sha256(executable, "compiled executable", MAX_SUPPORT)
    preflight_hash, preflight_bytes = file_sha256(preflight, "launch preflight", MAX_JSON)
    renderer_hash, renderer_bytes = file_sha256(renderer, "renderer", 64 * 1024 * 1024)
    serializer_hash, serializer_bytes = file_sha256(serializer, "serializer control", MAX_JSON)
    if receipt_value.get("exitCode") != 0 or receipt_value.get("timedOut") is True or receipt_value.get("ownedExited") is False:
        raise Hold("compile receipt is not successful")
    receipt_plan = receipt_value.get("planSha256")
    if receipt_plan != package_plan_hash.removeprefix("sha256:"):
        raise Hold("compile receipt plan hash differs from package plan")
    receipt_source = receipt_value.get("sourceHash")
    if receipt_source != source_hash:
        raise Hold("compile receipt source hash differs from fresh source plan")
    receipt_exe = receipt_value.get("exeSha256")
    if receipt_exe is not None and receipt_exe != exe_hash.removeprefix("sha256:"):
        raise Hold("compile receipt executable hash differs from executable")
    expected_renderer = source_plan.get("rendererSha256")
    if isinstance(expected_renderer, str) and expected_renderer.removeprefix("sha256:") != renderer_hash.removeprefix("sha256:"):
        raise Hold("renderer differs from source-plan pin")
    if receipt_value.get("rendererSha256") and receipt_value["rendererSha256"] != renderer_hash.removeprefix("sha256:"):
        raise Hold("compile receipt renderer differs from renderer")
    issued_value = bounded_json(issued, "issued metadata")
    if issued_value.get("case") != case or issued_value.get("expectedCount") != 20:
        raise Hold("issued metadata case/count differs from fresh source plan")
    if issued_value.get("sourceHash") != source_hash:
        raise Hold("issued metadata source hash differs from fresh source plan")
    if issued_value.get("exe", {}).get("sha256") != exe_hash:
        raise Hold("issued metadata executable differs from compiled executable")
    if issued_value.get("renderer", {}).get("sha256") != renderer_hash:
        raise Hold("issued metadata renderer differs from renderer")
    issued_hash, issued_bytes = file_sha256(issued, "issued metadata", MAX_JSON)
    candidate_ref = None
    if candidate is not None:
        candidate_value = bounded_json(candidate, "candidate tuple")
        if candidate_value.get("case") != case:
            raise Hold("candidate tuple case differs from fresh source plan")
        candidate_hash, candidate_bytes = file_sha256(candidate, "candidate tuple", MAX_JSON)
        candidate_ref = {"path": str(candidate), "sha256": candidate_hash, "bytes": candidate_bytes}
    result = copy.deepcopy(base)
    result.update({
        "case": case,
        "sourceHash": source_hash,
        "runtimeSourceCommit": source_plan.get("runtimeSourceCommit"),
        "runtimeSourceTreeHash": source_plan.get("runtimeSourceTreeHash"),
        "sourcePackagePath": str(package),
        "sourcePlanSha256": package_plan_hash,
        "compiledPlanSha256": package_plan_hash,
        "compiledHostPackagePath": str(package),
        "launchPreflightPath": str(preflight),
        "launchPreflightSha256": preflight_hash,
        "captureRoot": producer_root,
        "renderer": {"rollingInputPath": str(renderer), "sha256": renderer_hash},
        "dispatch": {
            "first": {"count": 1, "runRoot": first_root},
            "retries": False,
            "repeat": {"count": 20, "runRoot": repeat_root, "firstProofRequired": True},
        },
        "freshOutputRoot": output_root,
        "actualBuild": {
            "compileReceiptSha256": receipt_hash.removeprefix("sha256:"),
            "compileReceiptBytes": receipt_bytes,
            "exeSha256": exe_hash.removeprefix("sha256:"),
            "exeBytes": exe_bytes,
            "receiptRef": str(receipt),
            "exeRef": str(executable),
        },
        "serializerControlSha256": serializer_hash,
        "serializerControlBytes": serializer_bytes,
        "metadataIssuerSha256": base.get("metadataIssuerSha256"),
        "hostArguments": source_plan.get("hostArguments", base.get("hostArguments", [])),
        "freshBindings": {
            "sourcePlanCase": case,
            "sourcePlanPath": str(package / "plan.json"),
            "sourcePlanSha256": package_plan_hash,
            "issuedMetadata": {"path": str(issued), "sha256": issued_hash, "bytes": issued_bytes},
            "candidateTuple": candidate_ref,
            "renderer": {"path": str(renderer), "sha256": renderer_hash, "bytes": renderer_bytes},
            "compileReceipt": {"path": str(receipt), "sha256": receipt_hash, "bytes": receipt_bytes},
            "executable": {"path": str(executable), "sha256": exe_hash, "bytes": exe_bytes},
            "launchPreflight": {"path": str(preflight), "sha256": preflight_hash, "bytes": preflight_bytes},
            "serializerControl": {"path": str(serializer), "sha256": serializer_hash, "bytes": serializer_bytes},
        },
        "lineage": {
            "baseCapturePlanKind": base.get("kind"),
            "baseCapturePlanCase": base.get("case"),
            "baseCapturePlanUntouched": True,
            "freshSourcePlanKind": source_plan.get("kind"),
            "freshSourcePlanCase": case,
            "nativeActions": 0,
            "compilerActions": 0,
            "guiActions": 0,
            "remoteActions": 0,
            "lockActions": 0,
        },
    })
    result["qualification"] = "sourceBoundCandidate-observation-only; fresh compile/replay pending"
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-capture-plan", required=True, type=Path)
    parser.add_argument("--source-plan", required=True, type=Path)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--compile-receipt", required=True, type=Path)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--launch-preflight", required=True, type=Path)
    parser.add_argument("--renderer", required=True, type=Path)
    parser.add_argument("--serializer-control", required=True, type=Path)
    parser.add_argument("--producer-root", required=True)
    parser.add_argument("--first-run-root", required=True)
    parser.add_argument("--repeat-run-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--issued-metadata", required=True, type=Path)
    parser.add_argument("--candidate-tuple", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: fresh capture plan output must be new")
    try:
        result = materialize(
            bounded_json(args.base_capture_plan, "base capture plan"),
            bounded_json(args.source_plan, "fresh source plan"),
            args.package, args.compile_receipt, args.executable, args.launch_preflight,
            args.renderer, args.serializer_control, args.producer_root,
            args.first_run_root, args.repeat_run_root, args.output_root,
            args.issued_metadata, args.candidate_tuple,
        )
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": "source-only-ready", "case": result["case"], "count": 20,
                      "sourcePlanSha256": result["sourcePlanSha256"], "nativeActions": 0,
                      "compilerActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
