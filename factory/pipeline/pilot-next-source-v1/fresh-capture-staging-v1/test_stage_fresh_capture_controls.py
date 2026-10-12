#!/usr/bin/env python3
"""Pure fresh-capture admission controls; no compiler/native/lock action."""
from __future__ import annotations

import argparse
import copy
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("fresh_capture_stage", HERE / "stage_fresh_capture_v1.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("stage helper unavailable")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", choices=("text-style", "circle"), required=True)
    for name in ("final-plan", "manifest", "case", "tuple", "recipe", "compile-receipt", "executable", "witness", "uia-overlay", "serializer-control"):
        ap.add_argument("--" + name, dest=name.replace("-", "_"), type=Path, required=True)
    args = ap.parse_args()
    plan = MOD.json_file(args.final_plan); manifest = MOD.json_file(args.manifest); case = MOD.json_file(args.case); tuple_value = MOD.json_file(args.tuple); recipe = MOD.json_file(args.recipe); receipt = MOD.json_file(args.compile_receipt)
    plan_hash = MOD.file_hash(args.final_plan, MOD.MAX_JSON); manifest_hash = MOD.file_hash(args.manifest, MOD.MAX_JSON); case_hash = MOD.canonical_hash(case); tuple_hash = MOD.canonical_hash(tuple_value); recipe_hash = MOD.canonical_hash(recipe); receipt_hash = MOD.file_hash(args.compile_receipt, MOD.MAX_JSON); exe_hash = MOD.file_hash(args.executable, MOD.MAX_COMPILER); witness_hash = MOD.file_hash(args.witness, MOD.MAX_SOURCE)
    MOD.validate_inputs(args)
    faults = []
    def reject(label, mutate):
        p, m, c, t, r, q = copy.deepcopy(plan), copy.deepcopy(manifest), copy.deepcopy(case), copy.deepcopy(tuple_value), copy.deepcopy(recipe), copy.deepcopy(receipt)
        mutate(p, m, c, t, r, q)
        try:
            MOD.validate_candidate(args.profile, p, m, c, t, r, q, plan_hash=plan_hash, case_hash=case_hash, tuple_hash=tuple_hash, recipe_hash=recipe_hash, receipt_hash=receipt_hash, exe_hash=exe_hash, witness_hash=witness_hash)
        except ValueError:
            faults.append(label)
            return
        raise AssertionError(f"fault accepted: {label}")
    reject("plan-host-hash", lambda p, m, c, t, r, q: p.__setitem__("expectedHostHash", "sha256:" + "0" * 64))
    reject("plan-source-hash", lambda p, m, c, t, r, q: p.__setitem__("sourceHash", "sha256:" + "0" * 64))
    reject("manifest-case-hash", lambda p, m, c, t, r, q: m["case"].__setitem__("hash", "sha256:" + "0" * 64))
    reject("manifest-tuple-id", lambda p, m, c, t, r, q: m["tuple"].__setitem__("id", "stale-tuple"))
    reject("tuple-host-hash", lambda p, m, c, t, r, q: t["hostHashes"].__setitem__("windows", "sha256:" + "0" * 64))
    reject("recipe-bytes", lambda p, m, c, t, r, q: r["inputs"].__setitem__("text", "Ab"))
    reject("receipt-exit", lambda p, m, c, t, r, q: q.__setitem__("exitCode", 1))
    reject("receipt-native-action", lambda p, m, c, t, r, q: q.__setitem__("nativeActions", 1))
    reject("receipt-plan-hash", lambda p, m, c, t, r, q: q.__setitem__("planSha256", "sha256:" + "0" * 64))
    reject("source-bindings-missing", lambda p, m, c, t, r, q: p.__setitem__("sourceBindings", []))
    reject("wrong-candidate", lambda p, m, c, t, r, q: p.__setitem__("candidate", "stale.candidate"))
    if len(faults) != 11:
        raise AssertionError(f"fault coverage incomplete: {faults}")
    print("SOURCE_CONTROLS_PASS baseline+11_faults nativeActions=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
