#!/usr/bin/env python3
"""Strict source-only Windows r11 replay admission against actual producer receipts."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path


def add_repo_import() -> None:
    candidates = []
    if os.environ.get("SWIFTRIGHT_REPO_ROOT"):
        candidates.append(Path(os.environ["SWIFTRIGHT_REPO_ROOT"]).expanduser().resolve())
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        if (candidate / "factory/core/artifacts.py").is_file():
            sys.path.insert(0, str(candidate))
            return
    raise RuntimeError("repository root marker not found")


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def raw_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ref(path: Path) -> dict:
    return {"path": str(path.resolve()), "sha256": digest(path), "bytes": path.stat().st_size}


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("case", "manifest", "tuple", "donor-tuple", "windows-executable", "witness-manifest", "witness-source", "actual-receipt", "actual-plan", "actual-binding", "actual-proof-bundle", "actual-reader", "actual-compiler", "actual-runtime-receipt", "actual-runtime-tree", "output"):
        ap.add_argument("--" + name, dest=name.replace("-", "_"), type=Path, required=True)
    args = ap.parse_args()

    add_repo_import()
    from factory.core.artifacts import canonical_hash, validate_artifact

    reasons: list[str] = []
    def need(label: str, path: Path):
        if not path.is_file():
            reasons.append(f"missing {label}: {path}")
            return None
        return load(path) if path.suffix.lower() == ".json" else None

    case = need("fresh case", args.case)
    manifest = need("fresh manifest", args.manifest)
    packet = need("fresh tuple packet", args.tuple)
    donor = need("donor tuple", args.donor_tuple)
    receipt = need("actual producer receipt", args.actual_receipt)
    plan = need("actual producer plan", args.actual_plan)
    binding = need("actual candidate binding", args.actual_binding)
    proof = need("actual proof bundle", args.actual_proof_bundle)
    reader = need("actual trusted reader", args.actual_reader)
    runtime_receipt = need("actual runtime receipt", args.actual_runtime_receipt)
    runtime_tree = need("actual runtime tree", args.actual_runtime_tree)

    case_ref = {"id": "", "hash": ""}
    tuple_obj = {}
    if case is not None:
        case_id = case.get("id", "")
        tuple_obj = case.get("tuple", {})
        if not re.fullmatch(r"swiftui\.padding-frame\.recipe\.gate-seeded\.[a-f0-9]{16}\.r11\.h[a-f0-9]{12}", case_id):
            reasons.append("fresh r11 case id required")
        if not re.fullmatch(r"sr1-source-bound-r11-mac20-host-[a-f0-9]{12}-20261011", tuple_obj.get("id", "")):
            reasons.append("fresh host-bound r11 tuple id required")
        try:
            validate_artifact(case)
            case_ref = {"id": case_id, "hash": canonical_hash(case)}
        except Exception as exc:
            reasons.append("fresh case schema/hash invalid: " + str(exc))
    if manifest is not None and manifest.get("case") != case_ref:
        reasons.append("fresh manifest case join mismatch")
    if packet is not None:
        if packet.get("case") != case_ref:
            reasons.append("fresh tuple packet case join mismatch")
        if packet.get("tuple") != tuple_obj:
            reasons.append("fresh tuple packet tuple join mismatch")
    if donor is not None and donor.get("case") == case_ref:
        reasons.append("donor tuple was relabeled to fresh case")

    windows_ref = None
    witness_ref = None
    source_ref = None
    if args.windows_executable.is_file():
        windows_ref = ref(args.windows_executable)
        if windows_ref["sha256"] != tuple_obj.get("hostHashes", {}).get("windows"):
            reasons.append("Windows executable hash differs from fresh tuple")
    else:
        reasons.append("Windows executable missing")
    if args.witness_manifest.is_file():
        witness_ref = ref(args.witness_manifest)
        witness = load(args.witness_manifest)
        if witness.get("case") != case_ref:
            reasons.append("witness manifest is not fresh-case bound")
        source_name = witness.get("sourceFile")
        if source_name and (Path(source_name).name != source_name or source_name != args.witness_source.name):
            reasons.append("witness source basename mismatch")
    else:
        reasons.append("witness manifest missing")
    if args.witness_source.is_file():
        source_ref = ref(args.witness_source)
        if manifest is not None and source_ref["sha256"] != manifest.get("sourceHash"):
            reasons.append("witness source differs from fresh Mac manifest")
        if witness_ref:
            witness = load(args.witness_manifest)
            if witness.get("sourceHash") and source_ref["sha256"] != witness["sourceHash"]:
                reasons.append("witness source differs from witness manifest")
    else:
        reasons.append("witness source missing")

    actual_receipt_ref = ref(args.actual_receipt) if args.actual_receipt.is_file() else None
    actual_plan_ref = ref(args.actual_plan) if args.actual_plan.is_file() else None
    actual_binding_ref = ref(args.actual_binding) if args.actual_binding.is_file() else None
    proof_ref = ref(args.actual_proof_bundle) if args.actual_proof_bundle.is_file() else None
    reader_ref = ref(args.actual_reader) if args.actual_reader.is_file() else None
    compiler_ref = ref(args.actual_compiler) if args.actual_compiler.is_file() else None
    runtime_receipt_ref = ref(args.actual_runtime_receipt) if args.actual_runtime_receipt.is_file() else None
    runtime_tree_ref = ref(args.actual_runtime_tree) if args.actual_runtime_tree.is_file() else None
    for label, value in (("actual compiler", compiler_ref), ("actual runtime receipt", runtime_receipt_ref), ("actual runtime tree", runtime_tree_ref)):
        if value is None:
            reasons.append(label + " missing")

    if receipt is not None:
        if receipt.get("exitCode") != 0 or receipt.get("timedOut") is True or receipt.get("error"):
            reasons.append("actual producer receipt is not successful")
        if receipt.get("sourceHash") != (source_ref or {}).get("sha256"):
            reasons.append("actual receipt source hash does not join witness source")
        if receipt.get("compilerHash") != (compiler_ref or {}).get("sha256", "").removeprefix("sha256:"):
            reasons.append("actual receipt compiler hash does not join compiler bytes")
        if receipt.get("runtimeSourceCommit") != tuple_obj.get("runtimeCommit"):
            reasons.append("actual receipt runtime commit differs from fresh tuple")
        runtime_tree_hash = (runtime_receipt or {}).get("sourceTreeHash")
        runtime_commit = (runtime_receipt or {}).get("sourceCommit")
        if not runtime_tree_hash or receipt.get("runtimeSourceTreeHash") != runtime_tree_hash:
            reasons.append("actual receipt runtime tree does not join actual runtime receipt")
        if runtime_commit and receipt.get("runtimeSourceCommit") != runtime_commit:
            reasons.append("actual receipt runtime commit does not join actual runtime receipt")
        if isinstance(runtime_tree, list):
            listed = runtime_tree
            receipt_entries = (runtime_receipt or {}).get("sourceBindings")
            if not isinstance(receipt_entries, list) or listed != receipt_entries:
                reasons.append("actual runtime tree bytes do not join actual runtime receipt")
        if receipt.get("rendererSha256") != tuple_obj.get("rendererHash", "").removeprefix("sha256:"):
            reasons.append("actual receipt renderer hash differs from fresh tuple")
    if plan is not None:
        source_bindings = plan.get("sourceBindings")
        if not isinstance(source_bindings, list) or len(source_bindings) < 5:
            reasons.append("actual plan lacks complete source bindings")
        else:
            by_path = {x.get("path"): x.get("sha256", "").removeprefix("sha256:") for x in source_bindings if isinstance(x, dict)}
            if by_path.get("Sources/FactoryProbe/Witness.swift") != (source_ref or {}).get("sha256", "").removeprefix("sha256:"):
                reasons.append("actual plan witness source binding does not join fresh source")
            if by_path.get("witness.manifest.json") != (witness_ref or {}).get("sha256", "").removeprefix("sha256:"):
                reasons.append("actual plan witness manifest binding does not join fresh manifest")
    if binding is not None:
        runtime = binding.get("runtime", {})
        renderer = binding.get("renderer", {}).get("sha256")
        if runtime.get("sourceCommit") != tuple_obj.get("runtimeCommit"):
            reasons.append("candidate binding runtime commit mismatch")
        if renderer != tuple_obj.get("rendererHash"):
            reasons.append("candidate binding renderer mismatch")

    required_roles = {"FactoryProbe.exe", "Witness.swift", "capture-outcome.json", "declared-worker-inventory.json", "final-exit-certificate.json", "host/witness.manifest.json", "observation.json", "plan.json", "host/runtime-source-receipt.json", "host/runtime-source-tree.json"}
    proof_entries = {}
    if proof is not None:
        for group in proof.get("archiveBindings", {}).values():
            if isinstance(group, dict): proof_entries.update(group)
        missing = sorted(required_roles - set(proof_entries))
        if missing:
            reasons.append("proof archive missing roles: " + ",".join(missing))
        def proof_hash(role: str): return proof_entries.get(role, {}).get("sha256")
        if proof_hash("FactoryProbe.exe") != (windows_ref or {}).get("sha256"):
            reasons.append("proof executable hash does not join executable")
        if proof_hash("Witness.swift") != (source_ref or {}).get("sha256"):
            reasons.append("proof witness source hash does not join source")
        if proof_hash("host/witness.manifest.json") != (witness_ref or {}).get("sha256"):
            reasons.append("proof witness manifest hash does not join fresh manifest")
        if proof_hash("observation.json") != (actual_receipt_ref or {}).get("sha256"):
            reasons.append("proof compile receipt hash does not join actual receipt")
        if proof_hash("host/runtime-source-receipt.json") != (runtime_receipt_ref or {}).get("sha256"):
            reasons.append("proof runtime receipt hash does not join runtime receipt")
        if proof_hash("host/runtime-source-tree.json") != (runtime_tree_ref or {}).get("sha256"):
            reasons.append("proof runtime tree hash does not join runtime tree")
        if proof_hash("tool/compiler.bin") != (compiler_ref or {}).get("sha256"):
            reasons.append("proof compiler hash does not join compiler bytes")
    if reader is not None:
        if reader.get("count") != 20 or len(reader.get("rows", [])) != 20:
            reasons.append("trusted reader lacks 20 actual rows")
        if reader.get("nativeActions") != 0 or reader.get("lockActions") != 0:
            reasons.append("trusted reader reports unexpected effects")
        for row in reader.get("rows", []):
            compile_hash = row.get("evidence", {}).get("rawInputs", {}).get("compile", {}).get("hash")
            if compile_hash != (actual_receipt_ref or {}).get("sha256"):
                reasons.append("trusted reader compile receipt join mismatch")
                break

    if reasons:
        result = {"schema": "factory-windows-r11-replay-admission-v2", "status": "fresh-windows-compile-required", "candidateOnly": True, "case": case_ref, "tupleID": tuple_obj.get("id", ""), "actualReceipt": actual_receipt_ref, "proofBundle": proof_ref, "reasons": sorted(set(reasons)), "effects": {"compilerActions": 0, "nativeWindowActions": 0, "remoteActions": 0, "lockActions": 0}}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
        print(json.dumps(result))
        return 2
    result = {"schema": "factory-windows-r11-replay-admission-v2", "status": "reuse-admitted-source-bound-v2", "candidateOnly": True, "case": case_ref, "tuple": tuple_obj, "actualReceipt": actual_receipt_ref, "proofBundle": proof_ref, "requirements": {"freshMetadata": True, "freshCaptureIDs": True, "historicalDonorRelabel": False}, "effects": {"compilerActions": 0, "nativeWindowActions": 0, "remoteActions": 0, "lockActions": 0}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
