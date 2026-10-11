#!/usr/bin/env python3
"""Derive typed r7 metadata from exact proof-role byte bindings.

Frozen adapter-v4 output and native raw receipts remain untouched. This
successor only adds fields whose values are hashes already sealed by proof r2.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path

PROFILE_SHA256 = "sha256:72016fe5689e9cb74ef851ab6be2665f74b1b5a73ec0711e406046748b287967"
CAPTURE_PLAN_SHA256 = "sha256:db405b87fd926bbe45744f19b0c23990ea8dcf9c1d92d553781c9cef9920362a"
COMPILER_SHA256 = "sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"
ROLES = ("outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr")


def read(path):
    return json.loads(Path(path).read_bytes().decode("utf-8-sig"))


def derive(captures, bundle):
    if bundle.get("schema") != "windows-exit-proof-bundle-v2" or bundle.get("status") != "proofs-attached":
        raise ValueError("proof r2 source bundle not admitted")
    if len(bundle.get("captures", [])) != len(captures):
        raise ValueError("proof/capture count mismatch")
    bindings = bundle.get("archiveBindings", {})
    result = []
    for i, capture in enumerate(captures, 1):
        proof = bundle["captures"][i - 1].get("meta", {}).get("conditions", {}).get("windowsExitProof")
        if not isinstance(proof, dict) or set(proof.get("files", {})) != set(ROLES):
            raise ValueError("exact proof roles required")
        archive = bindings.get(str(i), {})
        def role_hash(role):
            ref = proof["files"][role]
            if ref["path"] not in archive or archive[ref["path"]]["sha256"] != ref["hash"]:
                raise ValueError("proof archive role byte join:" + role)
            return ref["hash"]
        source_hash = role_hash("witness")
        observation_hash = role_hash("observation")
        exe_hash = role_hash("exe")
        renderer_hash = role_hash("renderer")
        derived = copy.deepcopy(capture)
        meta = derived.setdefault("meta", {})
        conditions = meta.setdefault("conditions", {})
        conditions["windowsExitProof"] = copy.deepcopy(proof)
        conditions["actualSourceHash"] = source_hash
        conditions["actualHostExecutableHash"] = exe_hash
        conditions["actualRendererHash"] = renderer_hash
        conditions["rawReceiptHash"] = observation_hash
        # Existing r7 clock correlation points at measured identity. Derived
        # v5 receipt binds correlation to native observation bytes consumed by
        # reader gate; old capture/output bytes stay immutable.
        meta.setdefault("clock", {})["correlationHash"] = observation_hash
        conditions["typedMetadataDerivation"] = {
            "kind": "exact-proof-role-byte-hashes-v1",
            "proofBundleSchema": bundle["schema"],
            "proofIndex": i,
            "sourceHash": source_hash,
            "observationHash": observation_hash,
            "hostExecutableHash": exe_hash,
            "rendererHash": renderer_hash,
        }
        result.append(derived)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--captures", type=Path, required=True)
    ap.add_argument("--proof-bundle", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    payload = read(args.captures)
    captures = payload.get("captures")
    bundle = read(args.proof_bundle)
    derived = derive(captures, bundle)
    out = {
        "kind": "settled-typed-capture-normalization-v5-derived",
        "typedStatus": "normalized-observational-derived",
        "qualified": False,
        "nativeParity": "hold",
        "profileSha256": PROFILE_SHA256,
        "capturePlanSha256": CAPTURE_PLAN_SHA256,
        "compilerSha256": COMPILER_SHA256,
        "sourceProofBundle": str(args.proof_bundle),
        "captures": derived,
        "issues": ["provider/native parity remains held", "rawHashStates await producer r8/repeat5"],
    }
    if args.output.exists():
        raise ValueError("output must be fresh")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": out["typedStatus"], "count": len(derived), "issues": out["issues"]}, sort_keys=True))


if __name__ == "__main__":
    main()
