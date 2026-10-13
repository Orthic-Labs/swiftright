#!/usr/bin/env python3
"""Source-only admission for reusing Windows host with fresh Mac r11 tuple."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def ref(path: Path) -> dict:
    return {"path": str(path.resolve()), "sha256": digest(path), "bytes": path.stat().st_size}


def load(path: Path):
    return json.loads(path.read_text())


def add_repo_import():
    candidates = []
    if os.environ.get("SWIFTRIGHT_REPO_ROOT"):
        candidates.append(Path(os.environ["SWIFTRIGHT_REPO_ROOT"]).expanduser().resolve())
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        if (candidate / "factory/core/artifacts.py").is_file():
            sys.path.insert(0, str(candidate))
            return
    raise RuntimeError("repository root marker not found")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--case", type=Path, required=True)
    ap.add_argument("--manifest", type=Path, required=True)
    ap.add_argument("--tuple", dest="tuple_packet", type=Path, required=True)
    ap.add_argument("--donor-tuple", type=Path, required=True)
    ap.add_argument("--windows-executable", type=Path, required=True)
    ap.add_argument("--witness-manifest", type=Path, required=True)
    ap.add_argument("--witness-source", type=Path, required=True)
    ap.add_argument("--compiler-receipt", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()

    reasons: list[str] = []
    case = load(args.case)
    manifest = load(args.manifest)
    packet = load(args.tuple_packet)
    donor = load(args.donor_tuple)

    case_id = case.get("id", "")
    tuple_obj = case.get("tuple", {})
    tuple_id = tuple_obj.get("id", "")
    if not re.fullmatch(r"swiftui\.padding-frame\.recipe\.gate-seeded\.[a-f0-9]{16}\.r11\.h[a-f0-9]{12}", case_id):
        reasons.append("fresh r11 case id required")
    if not re.fullmatch(r"sr1-source-bound-r11-mac20-host-[a-f0-9]{12}-20261011", tuple_id):
        reasons.append("fresh host-bound r11 tuple id required")
    try:
        add_repo_import()
        from factory.core.artifacts import canonical_hash, validate_artifact
        validate_artifact(case)
        case_ref = {"id": case_id, "hash": canonical_hash(case)}
    except Exception as exc:
        reasons.append("case schema/hash invalid: " + str(exc))
        case_ref = {"id": case_id, "hash": ""}

    if manifest.get("case") != case_ref:
        reasons.append("manifest does not bind fresh case")
    if packet.get("case") != case_ref:
        reasons.append("tuple packet does not bind fresh case")
    if packet.get("tuple") != tuple_obj:
        reasons.append("tuple packet fields differ from fresh case tuple")
    donor_case = donor.get("case", {})
    if donor_case == case_ref:
        reasons.append("donor tuple must remain separate from fresh case")

    if not args.windows_executable.is_file():
        reasons.append("Windows executable missing")
    else:
        actual_windows = digest(args.windows_executable)
        expected_windows = tuple_obj.get("hostHashes", {}).get("windows")
        if actual_windows != expected_windows:
            reasons.append("Windows executable hash differs from fresh tuple")

    if not args.witness_manifest.is_file():
        reasons.append("witness manifest missing")
        witness_manifest_ref = None
    else:
        witness_manifest_ref = ref(args.witness_manifest)
        witness_manifest = load(args.witness_manifest)
        if "case" in witness_manifest and witness_manifest["case"] != case_ref:
            reasons.append("witness manifest case differs from fresh case")
        source_name = witness_manifest.get("sourceFile")
        if source_name is not None and (Path(source_name).name != source_name or source_name != args.witness_source.name):
            reasons.append("witness source basename differs from witness manifest")
        declared = witness_manifest.get("sourceHash")
        if declared and args.witness_source.is_file() and digest(args.witness_source) != declared:
            reasons.append("witness source hash differs from witness manifest")

    if not args.witness_source.is_file():
        reasons.append("witness source missing")
        witness_source_ref = None
    else:
        witness_source_ref = ref(args.witness_source)

    if not args.compiler_receipt.is_file():
        reasons.append("compiler receipt missing")
        compiler_ref = None
    else:
        compiler_ref = ref(args.compiler_receipt)
        receipt = load(args.compiler_receipt)
        declared_output = receipt.get("outputBinaryHash") or receipt.get("binaryHash")
        if declared_output and args.windows_executable.is_file() and declared_output != digest(args.windows_executable):
            reasons.append("compiler receipt output hash differs from executable")

    if reasons:
        result = {
            "schema": "factory-windows-r11-replay-admission-v1",
            "status": "fresh-windows-compile-required",
            "candidateOnly": True,
            "case": case_ref,
            "tupleID": tuple_id,
            "donorTuple": donor.get("candidateID") or donor.get("tuple", {}).get("id"),
            "reasons": reasons,
            "effects": {"compilerActions": 0, "nativeWindowActions": 0, "remoteActions": 0, "lockActions": 0},
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
        print(json.dumps(result))
        return 2

    result = {
        "schema": "factory-windows-r11-replay-admission-v1",
        "status": "reuse-admitted-source-bound",
        "candidateOnly": True,
        "case": case_ref,
        "tuple": tuple_obj,
        "donorTuple": {"candidateID": donor.get("candidateID"), "case": donor_case},
        "windowsExecutable": ref(args.windows_executable),
        "witnessManifest": witness_manifest_ref,
        "witnessSource": witness_source_ref,
        "compilerReceipt": compiler_ref,
        "requirements": {"freshMetadata": True, "freshCaptureIDs": True, "historicalDonorRelabel": False},
        "effects": {"compilerActions": 0, "nativeWindowActions": 0, "remoteActions": 0, "lockActions": 0},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
