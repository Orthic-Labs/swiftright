#!/usr/bin/env python3
"""Source controls for paired production comparison admission; no native actions."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("paired_comparison_v1", HERE / "run-paired-comparison-v1.py")
if SPEC is None or SPEC.loader is None:
    raise SystemExit("HOLD: paired comparison source unavailable")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


def reject(label: str, case: dict, normalized: dict, proof: dict, reader: dict, mac: dict, plan: dict) -> dict:
    try:
        runner.validate_pair_inputs(case, normalized, proof, reader, mac, plan)
    except runner.Hold as exc:
        return {"name": label, "status": "rejected", "reason": str(exc)}
    raise SystemExit("control unexpectedly accepted: " + label)


def main() -> int:
    ap = argparse.ArgumentParser()
    for name in ("case", "normalized", "adapter-proof", "reader-report", "mac-report", "source-plan", "output"):
        ap.add_argument("--" + name, required=True, type=Path)
    ap.add_argument("--mac-root", required=True, type=Path)
    ap.add_argument("--mac-manifest", type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        case = runner.bounded_json(args.case, "case")
        normalized = runner.bounded_json(args.normalized, "normalized")
        proof = runner.bounded_json(args.adapter_proof, "adapter proof")
        reader = runner.bounded_json(args.reader_report, "reader report")
        mac = runner.bounded_json(args.mac_report, "Mac comparator")
        plan = runner.bounded_json(args.source_plan, "source plan")
        mac_root = args.mac_root.resolve()
        manifest_path = args.mac_manifest or (args.mac_root / "raw-archive-manifest.json")
        raw_manifest = runner.bounded_json(manifest_path, "Mac raw archive manifest")
        baseline = runner.validate_pair_inputs(case, normalized, proof, reader, mac, plan)
        faults = []
        bad_capture = copy.deepcopy(normalized); bad_capture["captures"][0]["id"] = "capture/fault"; faults.append(reject("capture-identity", case, bad_capture, proof, reader, mac, plan))
        bad_proof = copy.deepcopy(proof); bad_proof["captures"][0]["id"] = "capture/fault"; faults.append(reject("adapter-proof-identity", case, normalized, bad_proof, reader, mac, plan))
        bad_reader = copy.deepcopy(reader); bad_reader["count"] = 19; faults.append(reject("reader-count", case, normalized, proof, bad_reader, mac, plan))
        bad_mac = copy.deepcopy(mac); bad_mac["macCaptures"] = bad_mac["macCaptures"][:-1]; faults.append(reject("mac-count", case, normalized, proof, reader, bad_mac, plan))
        bad_mac_case = copy.deepcopy(mac); bad_mac_case["case"] = copy.deepcopy(mac["case"]); bad_mac_case["case"]["id"] = bad_mac_case["case"]["id"] + "/fault"; faults.append(reject("mac-case-identity", case, normalized, proof, reader, bad_mac_case, plan))
        bad_mac_tuple = copy.deepcopy(mac); bad_mac_tuple["tuple"] = copy.deepcopy(case["tuple"]); bad_mac_tuple["tuple"]["rendererHash"] = "sha256:" + "0" * 64; faults.append(reject("mac-tuple-identity", case, normalized, proof, reader, bad_mac_tuple, plan))
        bad_mac_status = copy.deepcopy(mac); bad_mac_status["status"] = "pass"; faults.append(reject("mac-fabricated-qualification", case, normalized, proof, reader, bad_mac_status, plan))
        fake_pass = copy.deepcopy(reader); fake_pass["status"] = "reader-verified"; fake_pass["rows"] = [{**row, "status": "pass"} for row in fake_pass["rows"]]; faults.append(reject("fabricated-reader-pass", case, normalized, proof, fake_pass, mac, plan))
        missing_proof = copy.deepcopy(proof); del missing_proof["captures"][0]["meta"]["conditions"]["windowsExitProof"]["files"]["witness"]; faults.append(reject("missing-proof-role", case, normalized, missing_proof, reader, mac, plan))
        for field, label in (("actualSourceHash", "source-identity"), ("actualHostExecutableHash", "executable-identity"), ("actualRendererHash", "renderer-identity"), ("rawReceiptHash", "raw-receipt-identity")):
            bad_identity = copy.deepcopy(proof); bad_identity["captures"][0]["meta"]["conditions"][field] = "sha256:" + "0" * 64; faults.append(reject(label, case, normalized, bad_identity, reader, mac, plan))
        from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError
        mac_reader = ArchiveByteReader(mac_roots=[mac_root], max_bytes=runner.MAX_ARCHIVE_BYTES)
        runner.load_mac_captures(mac_root, mac, case, mac_reader, raw_manifest)
        bad_manifest = copy.deepcopy(raw_manifest)
        target = next(item for item in bad_manifest["files"] if item.get("path", "").endswith("/run-001/capture.json"))
        target["bytes"] += 1
        try:
            runner.load_mac_captures(mac_root, mac, case, mac_reader, bad_manifest)
        except (runner.Hold, ArchiveReadError) as exc:
            faults.append({"name": "mac-raw-byte-binding", "status": "rejected", "reason": str(exc)})
        else:
            raise SystemExit("control unexpectedly accepted: mac-raw-byte-binding")
        output = {"schema": "factory-native-count20-paired-comparison-controls-v1", "status": "baseline-admitted-faults-rejected", "count": 20, "baselineReaderStatus": baseline["readerStatus"], "baselineProtectedIssues": baseline["protectedIssues"], "faultControls": faults, "nativeActions": 0, "lockActions": 0, "qualification": "source-control-only"}
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": output["status"], "faults": len(output["faultControls"]), "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
