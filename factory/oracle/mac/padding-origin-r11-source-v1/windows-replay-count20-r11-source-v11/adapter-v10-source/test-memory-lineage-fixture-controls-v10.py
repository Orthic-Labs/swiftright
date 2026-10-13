#!/usr/bin/env python3
"""Source-only memory/nonce lineage controls; fixtures never qualify native evidence."""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "adapter-v9-source"))
from bounded_io_v9 import bounded_json, stream_hash, verify_ref
from lineage_v10 import EXPECTED_ISSUED_SHA256, EXPECTED_RUN_ID, validate_memory_receipt


def write_case(root: Path, name: str, task: dict) -> dict:
    path = root / (name + ".json")
    with path.open("x", encoding="utf-8") as handle:
        json.dump(task, handle, indent=2, sort_keys=True)
        handle.write("\n")
    actual, size = stream_hash(path, max_bytes=2 * 1024 * 1024)
    ref = {"path": path.name, "sha256": actual, "bytes": size}
    verify_ref(path, ref, max_bytes=2 * 1024 * 1024)
    return ref


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--control-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    args.control_root.mkdir(parents=True, exist_ok=True)
    plan = {"issuedLineage": {"runID": EXPECTED_RUN_ID, "issuedMetadataSha256": EXPECTED_ISSUED_SHA256}}
    receipt = {"kind": "factory-interactive-job-memory-receipt-v1", "status": "passed", "runID": EXPECTED_RUN_ID, "issuedMetadataHash": EXPECTED_ISSUED_SHA256, "jobMemoryLimitBytes": 1073741824, "limitFlags": 0x200, "activeProcessCount": 1, "killOnJobClose": False, "peakJobMemoryUsedBytes": 65536, "parentPid": 4242}
    baseline = {"status": "completed-source-bound-observation", "issuedMetadataHash": EXPECTED_ISSUED_SHA256, "memoryReceipt": receipt}
    cases = [("baseline", baseline, True), ("wrong-nonce", {**baseline, "memoryReceipt": {**receipt, "runID": "0" * 32}}, False), ("wrong-task-hash", {**baseline, "issuedMetadataHash": "sha256:" + "0" * 64}, False), ("wrong-memory-cap", {**baseline, "memoryReceipt": {**receipt, "jobMemoryLimitBytes": 1073741823}}, False), ("wrong-active-count", {**baseline, "memoryReceipt": {**receipt, "activeProcessCount": 2}}, False), ("wrong-limit-flags", {**baseline, "memoryReceipt": {**receipt, "limitFlags": 0}}, False), ("wrong-kill-policy", {**baseline, "memoryReceipt": {**receipt, "killOnJobClose": True}}, False), ("wrong-peak", {**baseline, "memoryReceipt": {**receipt, "peakJobMemoryUsedBytes": 1073741825}}, False)]
    controls = []
    for name, task, accepted in cases:
        ref = write_case(args.control_root, name, task)
        observed = "accepted"
        error = ""
        try:
            validate_memory_receipt(task, plan)
        except Exception as exc:
            observed = "rejected"
            error = str(exc)
        if (observed == "accepted") != accepted:
            raise SystemExit("HOLD: fixture control expectation mismatch:" + name)
        controls.append({"name": name, "accepted": observed == "accepted", "rejected": observed == "rejected", "expectedAccepted": accepted, "error": error, "resealedRef": ref, "nativeWindowActions": 0, "lockActions": 0})
    result = {"kind": "factory-adapter-v10-memory-lineage-fixture-controls", "status": "passed-source-only", "controls": controls, "nativeEvidence": False, "qualification": "fixture-only-no-fresh-qualification", "nativeWindowActions": 0, "lockActions": 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": result["status"], "controls": len(controls), "nativeEvidence": False, "nativeWindowActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
