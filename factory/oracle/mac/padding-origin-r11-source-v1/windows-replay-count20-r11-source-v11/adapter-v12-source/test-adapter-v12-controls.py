#!/usr/bin/env python3
"""Real r17 v12 emitted-map controls; faults mutate in memory only."""
from __future__ import annotations
import argparse, copy, importlib.util, json
from pathlib import Path
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("producer_v12_controls", HERE / "produce-input-map-v12.py")
if spec is None or spec.loader is None: raise SystemExit("HOLD: v12 producer source unavailable")
producer = importlib.util.module_from_spec(spec); spec.loader.exec_module(producer)

def reject(label, value):
    try: producer.validate_emitted_map(value)
    except (producer.Hold, ValueError) as exc: return {"name": label, "status": "rejected", "reason": str(exc)}
    raise SystemExit("control unexpectedly accepted: " + label)

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--inputs", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink(): raise SystemExit("HOLD: output must be fresh")
    try: baseline = json.loads(args.inputs.read_text(encoding="utf-8-sig"))
    except Exception as exc: raise SystemExit("HOLD: input map unreadable") from exc
    producer.validate_emitted_map(baseline)
    faults=[]
    swapped = copy.deepcopy(baseline); swapped["lineage"]["issuedPairs"][0], swapped["lineage"]["issuedPairs"][1] = swapped["lineage"]["issuedPairs"][1], swapped["lineage"]["issuedPairs"][0]; faults.append(reject("issued-pair-order", swapped))
    bad_compiler = copy.deepcopy(baseline); bad_compiler["compilerAdmission"]["sha256"] = "sha256:" + "0" * 64; faults.append(reject("compiler-byte-hash", bad_compiler))
    missing_stream = copy.deepcopy(baseline); missing_stream["runs"][0]["rawClosure"] = []; faults.append(reject("full-raw-closure", missing_stream))
    bad_status = copy.deepcopy(baseline); bad_status["status"] = "ready"; faults.append(reject("held-status", bad_status))
    wrong_active = copy.deepcopy(baseline); wrong_active["cleanupAdmission"]["activeProcessCount"] = 0; faults.append(reject("self-only-active-count", wrong_active))
    missing_self_only = copy.deepcopy(baseline); missing_self_only["cleanupAdmission"]["selfOnlyAccepted"] = False; faults.append(reject("self-only-control", missing_self_only))
    missing_quiescence = copy.deepcopy(baseline); missing_quiescence["cleanupAdmission"]["externalTaskTerminal"] = False; faults.append(reject("external-task-terminal", missing_quiescence))
    output={"schema":"factory-native-count20-r17-adapter-controls-v12","status":"baseline-admitted-faults-rejected","baseline":{"schema":baseline.get("schema"),"count":len(baseline.get("runs",[])),"orderedPairs":len(baseline.get("lineage",{}).get("issuedPairs",[]))},"faultControls":faults,"nativeActions":0,"lockActions":0,"qualification":"source-control-only"}
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(output, indent=2, sort_keys=True)+"\n", encoding="utf-8"); print(json.dumps({"status":output["status"],"faults":len(faults),"nativeActions":0,"lockActions":0},sort_keys=True)); return 0
if __name__ == "__main__": raise SystemExit(main())
