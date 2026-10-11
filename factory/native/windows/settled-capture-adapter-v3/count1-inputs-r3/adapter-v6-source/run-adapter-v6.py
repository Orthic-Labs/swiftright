#!/usr/bin/env python3
"""Runnable successor adapter: source admission, frozen normalization, proof derivation.

Proof-r2 is supplied by production proof builder after native/archive evidence;
this CLI never fabricates proof roles or changes raw observations.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
s = importlib.util.spec_from_file_location("adapter_v6", HERE / "adapter-v6.py")
adapter = importlib.util.module_from_spec(s); assert s.loader; s.loader.exec_module(adapter)
# Proof-r2 derivation remains byte-identical frozen v5 source; successor CLI
# imports it explicitly rather than relying on an absent copied file.
d = importlib.util.spec_from_file_location("derive_v5", HERE.parent / "adapter-v5-source" / "derive-v5.py")
derive_mod = importlib.util.module_from_spec(d); assert d.loader; d.loader.exec_module(derive_mod)


def read_json(path: Path): return json.loads(path.read_text(encoding="utf-8-sig"))

def safe_path(value: str) -> Path:
    p = PurePosixPath(value)
    if not isinstance(value, str) or not value or p.is_absolute() or str(p) != value or ".." in p.parts or "\\" in value or ":" in value:
        raise ValueError("unsafe archive ref")
    return Path(*p.parts)

def attach_raw_states(captures, inputs, root: Path):
    """Carry only producer-sealed rawHashStates into normalized conditions."""
    runs = inputs.get("runs")
    if not isinstance(runs, list) or len(runs) != len(captures):
        raise ValueError("run/capture count mismatch for raw state join")
    for capture, run in zip(captures, runs):
        outcome_ref = run.get("outcome") if isinstance(run, dict) else None
        if not isinstance(outcome_ref, dict):
            continue
        raw_path = safe_path(outcome_ref.get("path"))
        path = (root.resolve() / raw_path).resolve(); path.relative_to(root.resolve())
        raw = path.read_bytes()
        if "sha256:" + hashlib.sha256(raw).hexdigest() != outcome_ref.get("sha256") or len(raw) != outcome_ref.get("bytes"):
            raise ValueError("raw outcome byte/hash mismatch:" + outcome_ref.get("path", ""))
        outcome = json.loads(raw.decode("utf-8-sig"))
        states = outcome.get("rawHashStates")
        if states is None:
            continue
        if not isinstance(states, dict) or set(states) != {"stdout", "stderr"}:
            raise ValueError("rawHashStates must contain stdout/stderr")
        for name, state in states.items():
            if not isinstance(state, dict) or state.get("qualification") != "sealed-raw" or state.get("error") != "":
                raise ValueError("raw stream state not sealed:" + name)
            expected = outcome.get(name + "Sha256")
            if state.get("sha256") != expected:
                raise ValueError("raw stream state/output hash mismatch:" + name)
        conditions = capture.setdefault("meta", {}).setdefault("conditions", {})
        conditions["rawHashStates"] = states
        conditions["rawHashesQualification"] = outcome.get("rawHashesQualification")
    return captures

def normalize(input_path: Path, root: Path):
    inputs = read_json(input_path); root = root.resolve()
    def read_bytes(ref):
        if not isinstance(ref, dict) or not isinstance(ref.get("path"), str): raise ValueError("archive ref required")
        path = (root / safe_path(ref["path"])).resolve(); path.relative_to(root)
        raw = path.read_bytes()
        if "sha256:" + hashlib.sha256(raw).hexdigest() != ref.get("sha256") or (ref.get("bytes") not in (None, 0) and len(raw) != ref.get("bytes")):
            raise ValueError("archive byte/hash mismatch:" + ref["path"])
        return raw
    # adapter-v6._overlay_v4 performs exact successor/frozen overlay, issuer,
    # tuple sidecar, profile and source joins before frozen normalization.
    result = adapter.normalize(inputs, read_bytes)
    attach_raw_states(result.get("captures", []), inputs, root)
    return result

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--inputs", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--proof-bundle", type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists(): raise SystemExit("HOLD: refusing to overwrite output")
    try:
        normalized = normalize(args.inputs, args.archive_root)
        if normalized.get("typedStatus") not in ("normalized-observational", "normalized-observational-derived"):
            raise ValueError("normalized adapter held:" + ";".join(normalized.get("issues", [])))
        if args.proof_bundle:
            bundle = read_json(args.proof_bundle)
            derived = derive_mod.derive(normalized["captures"], bundle)
            out = {
                "kind": "settled-typed-capture-normalization-v6-composed",
                "version": 6,
                "typedStatus": "normalized-observational-derived",
                "qualified": False,
                "nativeParity": "hold",
                "normalizedStage": {
                    "kind": normalized.get("kind"),
                    "typedStatus": normalized.get("typedStatus"),
                    "captureCount": len(normalized.get("captures", [])),
                    "issues": normalized.get("issues", []),
                },
                "proofStage": {"schema": bundle.get("schema"), "status": bundle.get("status")},
                "captures": derived,
                "issues": list(normalized.get("issues", [])) + ["provider/native parity remains held"] + ([] if all("rawHashStates" in (c.get("meta", {}).get("conditions", {})) for c in derived) else ["rawHashStates await producer r7"]),
            }
        else:
            out = dict(normalized)
            out["kind"] = "settled-typed-capture-normalization-v6-composed"
            out["version"] = 6
            out["successorStage"] = {"status": "normalized-before-proof-r2", "nativeActions": 0}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as h: json.dump(out, h, indent=2, sort_keys=True); h.write("\n")
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    print(json.dumps({"status":out.get("typedStatus"),"count":len(out.get("captures",[])),"proofAttached":bool(args.proof_bundle),"nativeActions":0,"issues":out.get("issues",[])}, sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
