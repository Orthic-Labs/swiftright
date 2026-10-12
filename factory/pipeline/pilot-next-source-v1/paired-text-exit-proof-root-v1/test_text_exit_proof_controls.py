#!/usr/bin/env python3
"""Controls invoke exit-proof production predicates with explicit raw inputs.

No raw evidence is rewritten.  Positive path checks run-001 receipt; seeded
faults must remain held: wrong source, missing exit, PNG mutation, ambiguous
Aa witness, & changed height.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("exit_proof_production", HERE / "compare_text_exit_proof.py")
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def expect_hold(name: str, fn) -> None:
    try:
        fn()
    except mod.Hold:
        return
    raise AssertionError(f"fault accepted: {name}")


def run(capture_root: Path, exit_root: Path) -> None:
    proof_path = exit_root / "run-001" / "exit-proof.json"
    b = mod.Bounded()
    proof = b.json(proof_path)
    mod.validate_exit_proof(exit_root, proof, b, 1)

    wrong_source = copy.deepcopy(proof)
    wrong_source["hostHash"] = mod.SHA + "0" * 64
    expect_hold("wrong-source-host", lambda: mod.validate_exit_proof(exit_root, wrong_source, mod.Bounded(), 1))

    missing_exit = copy.deepcopy(proof)
    missing_exit["host"].pop("exitCode", None)
    expect_hold("missing-exit-code", lambda: mod.validate_exit_proof(exit_root, missing_exit, mod.Bounded(), 1))

    mutated_pixel = copy.deepcopy(proof)
    mutated_pixel["plain"]["png"]["sha256"] = mod.SHA + "1" * 64
    expect_hold("mutated-pixel-hash", lambda: mod.validate_exit_proof(exit_root, mutated_pixel, mod.Bounded(), 1))

    plain = mod.Bounded().json(exit_root / "run-001" / "plain.raw.json")
    instrumented = mod.Bounded().json(exit_root / "run-001" / "instrumented.raw.json")
    ax = mod.Bounded().json(exit_root / "run-001" / "external-ax.raw.json")
    bad_old_new_pid = copy.deepcopy(plain); bad_old_new_pid["pid"] = int(proof["plain"]["pid"]) + 1
    expect_hold("old-new-pid-mismatch", lambda: mod.validate_fresh_pid_joins(1, proof, bad_old_new_pid, instrumented, ax))
    swapped_ax = copy.deepcopy(ax); swapped_ax["pid"], swapped_ax["clientPID"] = swapped_ax["clientPID"], swapped_ax["pid"]
    expect_hold("swapped-ax-owner-client", lambda: mod.validate_fresh_pid_joins(1, proof, plain, instrumented, swapped_ax))

    expect_hold("ambiguous-Aa-value", lambda: mod.select_ax_witness({"steps": [
        {"role": "AXStaticText", "value": "Aa", "bounds": {"x": 0, "y": 0, "w": 28, "h": 28}},
        {"role": "AXStaticText", "value": "Aa", "bounds": {"x": 1, "y": 1, "w": 28, "h": 28}},
    ]}))
    expect_hold("changed-height", lambda: mod.validate_mac_witness_geometry({
        "role": "AXStaticText", "value": "Aa", "frame": {"x": 166, "y": 922, "w": 28, "h": 29}
    }))

    # Production Mac source proof must reject source drift, rather than letting
    # a comparator fault control certify a separate mirror implementation.
    summary_path = capture_root / mod.CASE_ID / "summary.json"
    summary = mod.Bounded().json(summary_path)
    capture = mod.Bounded().json(capture_root / mod.CASE_ID / "run-001" / "capture.json")
    drifted = copy.deepcopy(summary)
    drifted["compilerReceipt"]["compiler"]["sourceAfter"]["Witness.swift"]["sha256"] = mod.SHA + "2" * 64
    expect_hold("wrong-source-witness", lambda: mod.validate_mac_provenance(drifted, capture))


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mac-capture-root", type=Path, required=True)
    p.add_argument("--mac-exit-root", type=Path, required=True)
    args = p.parse_args()
    run(args.mac_capture_root, args.mac_exit_root)
    print("text-exit-proof production controls: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
