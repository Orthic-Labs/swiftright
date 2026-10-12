#!/usr/bin/env python3
"""Prepare bounded fresh Mac20/Windows20 comparison inputs; never runs reader/native work."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from factory.core.artifacts import canonical_hash

MAX_JSON = 8 * 1024 * 1024
MAX_SUPPORT = 256 * 1024 * 1024


class Hold(ValueError):
    pass


def read_json(path: Path, label: str) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON:
        raise Hold(f"{label} unavailable, symlinked, or exceeds bound")
    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} object required")
    return value


def digest(path: Path, label: str, limit: int = MAX_SUPPORT) -> tuple[str, int]:
    if path.is_symlink() or not path.is_file():
        raise Hold(f"{label} must be regular")
    size = path.stat().st_size
    if size > limit:
        raise Hold(f"{label} exceeds bound")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest(), size


def bare(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise Hold(f"{label} hash missing")
    result = value.removeprefix("sha256:").lower()
    if len(result) != 64 or any(c not in "0123456789abcdef" for c in result):
        raise Hold(f"{label} hash malformed")
    return result


def ref(value: Any, label: str) -> dict[str, str]:
    if not isinstance(value, dict) or not isinstance(value.get("id"), str) or not isinstance(value.get("hash"), str):
        raise Hold(f"{label} reference missing")
    return {"id": value["id"], "hash": value["hash"]}


def case_ref(value: dict[str, Any], label: str) -> dict[str, str]:
    if value.get("kind") != "case" or value.get("version") != "0.1":
        raise Hold(f"{label} must be case v0.1")
    body = dict(value)
    supplied = body.pop("hash", None)
    result = {"id": str(value.get("id", "")), "hash": canonical_hash(body)}
    if not result["id"] or (supplied is not None and supplied not in {result["hash"], result["hash"].removeprefix("sha256:")}):
        raise Hold(f"{label} canonical identity invalid")
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    for name in ("repo", "case", "fresh-package-plan", "capture-plan", "compile-receipt", "executable", "candidate-tuple", "issued-metadata", "normalized", "adapter-proof", "reader-report", "mac-report", "mac-root", "mac-manifest", "reader-archive", "output"):
        ap.add_argument("--" + name, required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        case_value = read_json(args.case, "fresh case")
        fresh = case_ref(case_value, "fresh case")
        plan = read_json(args.fresh_package_plan, "fresh package plan")
        capture = read_json(args.capture_plan, "fresh capture plan")
        compile_receipt = read_json(args.compile_receipt, "fresh compile receipt")
        candidate = read_json(args.candidate_tuple, "fresh candidate tuple")
        issued = read_json(args.issued_metadata, "fresh issued metadata")
        normalized = read_json(args.normalized, "fresh normalized inputs")
        proof = read_json(args.adapter_proof, "fresh adapter proof")
        reader = read_json(args.reader_report, "trusted reader report")
        mac = read_json(args.mac_report, "Mac comparator report")
        mac_manifest = read_json(args.mac_manifest, "Mac raw manifest")

        if ref(plan.get("case"), "package plan case") != fresh or ref(capture.get("case"), "capture plan case") != fresh:
            raise Hold("fresh package/capture case mismatch")
        if plan.get("executionEligible") is not False or capture.get("executionEligible") is not False:
            raise Hold("fresh plan/capture must remain execution-ineligible")
        if not isinstance(plan.get("candidateTuple"), dict) or plan["candidateTuple"].get("id") != candidate.get("candidateID"):
            raise Hold("package plan candidate identity mismatch")
        if ref(candidate.get("case"), "candidate case") != fresh or ref(issued.get("case"), "issued case") != fresh:
            raise Hold("candidate/issued case mismatch")
        if issued.get("expectedCount") != 20:
            raise Hold("issued Count20 required")
        if candidate.get("candidateID") != plan["candidateTuple"].get("id"):
            raise Hold("candidate tuple ID mismatch")

        package_hash, package_bytes = digest(args.fresh_package_plan, "fresh package plan", MAX_JSON)
        compile_hash, compile_bytes = digest(args.compile_receipt, "fresh compile receipt", MAX_JSON)
        exe_hash, exe_bytes = digest(args.executable, "fresh executable")
        if bare(compile_receipt.get("planSha256"), "compile receipt plan") != package_hash:
            raise Hold("compile receipt plan hash differs from package plan")
        if capture.get("sourcePlanSha256") and bare(capture["sourcePlanSha256"], "capture source plan") != package_hash:
            raise Hold("capture plan source hash differs from package plan")
        actual_build = capture.get("actualBuild")
        if not isinstance(actual_build, dict) or bare(actual_build.get("compileReceiptSha256"), "capture compile receipt") != compile_hash or bare(actual_build.get("exeSha256"), "capture executable") != exe_hash:
            raise Hold("capture actual build refs differ from current compile outputs")
        if compile_receipt.get("exitCode") != 0 or compile_receipt.get("kernelWait") != 0 or compile_receipt.get("ownedExited") is not True or compile_receipt.get("streamDrainComplete") is not True or compile_receipt.get("error") or compile_receipt.get("cleanupError"):
            raise Hold("compile terminal proof incomplete")
        if bare(issued.get("exe", {}).get("sha256"), "issued executable") != exe_hash:
            raise Hold("issued executable differs from fresh executable")
        if bare(issued.get("sourceHash"), "issued source") != bare(plan.get("sourceHash"), "plan source"):
            raise Hold("issued source differs from package plan")

        mac_case = ref(mac.get("case"), "Mac report case")
        if mac.get("kind") != "verdict" or mac.get("version") != "0.1" or mac_case != fresh or len(mac.get("macCaptures", [])) != 20 or mac.get("status") in {"pass", "qualified", "parity-passed", "golden-frozen"}:
            raise Hold("Mac report must be fresh observational Mac20")
        if mac.get("tuple") != case_value.get("tuple"):
            raise Hold("Mac tuple differs from fresh case tuple")
        if normalized.get("kind") != "factory-native-count20-r17-normalized-inputs-v12" or len(normalized.get("captures", [])) != 20:
            raise Hold("normalized fresh Windows20 required")
        if proof.get("status") != "proofs-attached" or proof.get("count") != 20 or len(proof.get("captures", [])) != 20:
            raise Hold("adapter proof Windows20 required")
        for index, (nrow, prow) in enumerate(zip(normalized["captures"], proof["captures"]), 1):
            if nrow.get("platform") != "windows" or prow.get("platform") != "windows" or nrow.get("case") != fresh or prow.get("case") != fresh or nrow.get("id") != prow.get("id"):
                raise Hold(f"Windows capture/proof join missing at run {index}")
        if reader.get("count") != 20 or len(reader.get("rows", [])) != 20 or reader.get("status") not in {"reader-verified", "reader-observed-rejections"}:
            raise Hold("trusted reader Count20 report required")
        if reader.get("status") == "reader-verified" and any(row.get("status") != "pass" for row in reader["rows"]):
            raise Hold("reader-verified report contains non-pass row")
        if reader.get("status") == "reader-observed-rejections" and not any(row.get("status") == "blocked" for row in reader["rows"]):
            raise Hold("reader-observed-rejections report lacks blocked row")
        if mac_manifest.get("kind") != "root-macos-factory-whole-archive-v1" or not isinstance(mac_manifest.get("entries"), list):
            raise Hold("Mac raw archive manifest required")
        if not args.mac_root.is_dir() or not args.reader_archive.is_dir():
            raise Hold("Mac root & reader archive directories required")
        missing_archives = []
        for prow in proof["captures"]:
            key = str(prow["id"]).split("/")[-1]
            if not (args.reader_archive / ("capture-" + key)).is_dir():
                missing_archives.append(key)
        if missing_archives:
            raise Hold("trusted reader archive missing: " + ",".join(missing_archives[:4]))
        output = {
            "kind": "factory-padding-fresh-paired-analysis-plan-v1",
            "status": "ready-for-trusted-reader-pair-run",
            "comparisonEligible": False,
            "case": fresh,
            "candidateID": candidate.get("candidateID"),
            "macCount": 20,
            "windowsCount": 20,
            "readerStatus": reader.get("status"),
            "inputs": {
                "case": str(args.case),
                "freshPackagePlan": str(args.fresh_package_plan),
                "capturePlan": str(args.capture_plan),
                "compileReceipt": {"path": str(args.compile_receipt), "sha256": compile_hash, "bytes": compile_bytes},
                "executable": {"path": str(args.executable), "sha256": exe_hash, "bytes": exe_bytes},
                "candidateTuple": str(args.candidate_tuple),
                "issuedMetadata": str(args.issued_metadata),
                "normalized": str(args.normalized),
                "adapterProof": str(args.adapter_proof),
                "readerReport": str(args.reader_report),
                "macReport": str(args.mac_report),
                "macRoot": str(args.mac_root),
                "macManifest": str(args.mac_manifest),
                "readerArchive": str(args.reader_archive),
            },
            "trustedRunner": "factory/pipeline/paired-padding-r11-v12/run-paired-comparison-v1.py",
            "trustedControls": "factory/pipeline/paired-padding-r11-v12/test-paired-comparison-controls-v1.py",
            "requiredResult": "comparison count=20, Mac20 + Windows20 reader joins, protected parity/golden qualification held",
            "packagePlanSha256": package_hash,
            "compileReceiptSha256": compile_hash,
            "executableSha256": exe_hash,
            "nativeActions": 0,
            "compilerActions": 0,
            "lockActions": 0,
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"status": output["status"], "case": fresh, "macCount": 20, "windowsCount": 20, "comparisonEligible": False}, sort_keys=True))
        return 0
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc


if __name__ == "__main__":
    raise SystemExit(main())
