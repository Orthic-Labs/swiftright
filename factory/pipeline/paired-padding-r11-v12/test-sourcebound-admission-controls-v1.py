#!/usr/bin/env python3
"""Fault controls for source-bound admission; no protected reader/gate mutation."""
from __future__ import annotations
import argparse, copy, importlib.util, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("sourcebound_admission_v1", HERE / "sourcebound-admission-v1.py")
if _spec is None or _spec.loader is None: raise SystemExit("HOLD: source-bound admission unavailable")
admission = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(admission)
MAX_JSON = 8 * 1024 * 1024


def bounded(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON: raise ValueError("control input exceeds bounded JSON read")
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict): raise ValueError("control input object required")
    return value


def reject(label: str, inputs: dict, normalized: dict, proof: dict, plan: dict, repo: Path) -> dict:
    try:
        admission.validate_sourcebound(inputs, normalized, proof, plan, repo)
    except admission.Hold as exc:
        return {"name": label, "status": "rejected", "reason": str(exc)}
    raise SystemExit("control unexpectedly accepted: " + label)


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--repo", required=True, type=Path); ap.add_argument("--input-map", required=True, type=Path); ap.add_argument("--normalized", required=True, type=Path); ap.add_argument("--proof-bundle", required=True, type=Path); ap.add_argument("--adapter-plan", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink(): raise SystemExit("HOLD: output must be fresh")
    try:
        inputs = bounded(args.input_map); normalized = bounded(args.normalized); proof = bounded(args.proof_bundle); plan = bounded(args.adapter_plan); repo = args.repo.resolve()
        admission.validate_sourcebound(inputs, normalized, proof, plan, repo)
        faults = []
        pair_swap = copy.deepcopy(normalized); pair_swap["captures"][0]["id"], pair_swap["captures"][1]["id"] = pair_swap["captures"][1]["id"], pair_swap["captures"][0]["id"]; faults.append(reject("issued-pair-order", inputs, pair_swap, proof, plan, repo))
        case_drift = copy.deepcopy(normalized); case_drift["captures"][0]["case"]["id"] = "legacy-plan-case"; faults.append(reject("fresh-case-identity", inputs, case_drift, proof, plan, repo))
        source_drift = copy.deepcopy(normalized); source_drift["captures"][0]["provenance"]["sourceHash"] = "sha256:" + "0" * 64; faults.append(reject("source-hash-identity", inputs, source_drift, proof, plan, repo))
        proof_drift = copy.deepcopy(proof); del proof_drift["captures"][0]["meta"]["conditions"]["windowsExitProof"]["files"]["witness"]; faults.append(reject("proof-role-closure", inputs, normalized, proof_drift, plan, repo))
        renderer_drift = copy.deepcopy(normalized); renderer_drift["captures"][0]["tuple"]["rendererHash"] = "sha256:" + "0" * 64; faults.append(reject("renderer-byte-identity", inputs, renderer_drift, proof, plan, repo))
        output = {"schema": "factory-native-count20-sourcebound-admission-controls-v1", "status": "baseline-admitted-faults-rejected", "count": 20, "faultControls": faults, "nativeActions": 0, "lockActions": 0, "qualification": "source-control-only"}
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8"); print(json.dumps({"status": output["status"], "faults": len(output["faultControls"]), "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0


if __name__ == "__main__": raise SystemExit(main())
