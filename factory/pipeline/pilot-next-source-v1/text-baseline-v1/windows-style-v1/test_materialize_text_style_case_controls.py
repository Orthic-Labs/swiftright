#!/usr/bin/env python3
"""Pure admission controls for fresh Text tuple/case materialization.

Controls mutate measured documents in memory; they never launch compilers/native hosts.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("text_style_materializer", HERE / "materialize-text-style-case-v1.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("materializer import unavailable")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def rejected(label, plan, receipt, capture, *, tuple_id, acceptance, plan_hash, witness_hash, recipe_hash):
    try:
        MOD.validate_inputs(plan, receipt, capture, tuple_id=tuple_id, acceptance_hash=acceptance, plan_hash=plan_hash, witness_hash=witness_hash, recipe_hash=recipe_hash)
    except ValueError:
        return
    raise AssertionError(f"fault accepted: {label}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows-plan", type=Path, required=True)
    ap.add_argument("--windows-receipt", type=Path, required=True)
    ap.add_argument("--mac-capture", type=Path, required=True)
    ap.add_argument("--tuple-id", required=True)
    ap.add_argument("--acceptance-config-hash", required=True)
    args = ap.parse_args()
    plan = MOD.bounded_json(args.windows_plan)
    receipt = MOD.bounded_json(args.windows_receipt)
    capture = MOD.bounded_json(args.mac_capture)
    plan_hash = MOD.file_hash(args.windows_plan)
    witness_hash = MOD.file_hash(MOD.PACKET / "witness.swift")
    recipe_hash = MOD.canonical_hash(MOD.bounded_json(MOD.PACKET / "recipe.json"))
    MOD.validate_inputs(plan, receipt, capture, tuple_id=args.tuple_id, acceptance_hash=args.acceptance_config_hash, plan_hash=plan_hash, witness_hash=witness_hash, recipe_hash=recipe_hash)
    old_id = capture["tuple"]["id"]
    cases = []
    def mutate(label, fn):
        p, r, c = copy.deepcopy(plan), copy.deepcopy(receipt), copy.deepcopy(capture)
        fn(p, r, c)
        rejected(label, p, r, c, tuple_id=args.tuple_id, acceptance=args.acceptance_config_hash, plan_hash=plan_hash, witness_hash=witness_hash, recipe_hash=recipe_hash)
        cases.append(label)
    mutate("windows-exe-reuse", lambda p, r, c: r.__setitem__("exeSha256", c["tuple"]["hostHashes"]["windows"].split(":", 1)[1]))
    mutate("windows-source-drift", lambda p, r, c: r.__setitem__("sourceHash", "sha256:" + "0" * 64))
    mutate("plan-runtime-drift", lambda p, r, c: p.__setitem__("runtimeSourceCommit", "0" * 40))
    mutate("plan-renderer-drift", lambda p, r, c: p.__setitem__("rendererSha256", "0" * 64))
    mutate("receipt-exit", lambda p, r, c: r.__setitem__("exitCode", 1))
    mutate("receipt-streams", lambda p, r, c: r.__setitem__("streamsSealed", False))
    mutate("receipt-active", lambda p, r, c: r.__setitem__("jobActiveCount", 1))
    mutate("mac-runtime-drift", lambda p, r, c: c["tuple"].__setitem__("runtimeCommit", "0" * 40))
    mutate("mac-host-drift", lambda p, r, c: c["tuple"]["hostHashes"].__setitem__("macos", "sha256:" + "0" * 64))
    rejected("old-tuple-id", plan, receipt, capture, tuple_id=old_id, acceptance=args.acceptance_config_hash, plan_hash=plan_hash, witness_hash=witness_hash, recipe_hash=recipe_hash)
    rejected("bad-acceptance", plan, receipt, capture, tuple_id=args.tuple_id, acceptance="sha256:" + "0" * 63, plan_hash=plan_hash, witness_hash=witness_hash, recipe_hash=recipe_hash)
    cases.append("old-tuple-id")
    cases.append("bad-acceptance")
    print(f"SOURCE_CONTROLS_PASS baseline+{len(cases)}_faults")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
