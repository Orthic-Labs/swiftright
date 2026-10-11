#!/usr/bin/env python3
from __future__ import annotations
import copy
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
COMPARATOR = HERE / "compare_final_candidate.py"
BASELINE = ROOT / "factory/registry/public-source-binding-v1/archive/inputs/catalogue.json"
PENDING = ROOT / "factory/registry/public-source-binding-v1/final-candidate-resolution.json"

def sha_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()

def run_case(name: str, candidate: Path, output: Path, expected_fragment: str, preserve_output: bool = False) -> dict:
    argv = [sys.executable, str(COMPARATOR), str(candidate), "--output", str(output)]
    result = subprocess.run(argv, cwd=ROOT, capture_output=True)
    text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    passed = result.returncode != 0 and expected_fragment in text and output.exists() == preserve_output
    return {"name": name, "argv": argv, "returncode": result.returncode,
            "stdoutSha256": sha_bytes(result.stdout), "stderrSha256": sha_bytes(result.stderr),
            "expectedFailure": expected_fragment, "outputExists": output.exists(), "passed": passed}

def main() -> int:
    baseline = json.loads(BASELINE.read_text())
    controls = []
    with tempfile.TemporaryDirectory(prefix="f2-comparator-controls-") as temp:
        work = Path(temp)
        x = copy.deepcopy(baseline); x["kind"] = "wrong"
        p = work / "wrong-kind.json"; p.write_text(json.dumps(x))
        controls.append(run_case("wrong-catalogue-kind", p, work / "wrong-kind.out.json", "candidate must be a v0.1 catalogue"))
        x = copy.deepcopy(baseline); x["symbols"][0]["status"] = "bogus"
        p = work / "invalid-status.json"; p.write_text(json.dumps(x))
        controls.append(run_case("invalid-selected-status", p, work / "invalid-status.out.json", "candidate catalogue schema errors"))
        x = copy.deepcopy(baseline)
        target_usr = "s:7SwiftUI9RectangleV"
        target = next(symbol for symbol in x["symbols"] if symbol["usr"] == target_usr)
        target["usr"] = "s:missing"
        p = work / "wrong-usr.json"; p.write_text(json.dumps(x))
        controls.append(run_case("wrong-selected-usr", p, work / "wrong-usr.out.json", "has no exact match"))
        x = copy.deepcopy(baseline); x["symbols"].append(copy.deepcopy(x["symbols"][0]))
        p = work / "duplicate-usr.json"; p.write_text(json.dumps(x))
        controls.append(run_case("duplicate-catalogue-usr", p, work / "duplicate-usr.out.json", "repeats USR"))
        output = work / "existing.out.json"; output.write_text("reserved")
        controls.append(run_case("existing-output", BASELINE, output, "output must not already exist", True))
        controls.append(run_case("reserved-pending-output", BASELINE, PENDING, "output must not already exist", True))
    pending_hash = sha_bytes(PENDING.read_bytes())
    receipt = {"kind": "f2-public-source-binding-comparator-fault-controls", "version": 1,
               "status": "controls-pass" if all(x["passed"] for x in controls) else "controls-failed",
               "comparatorPath": str(COMPARATOR.relative_to(ROOT)),
               "comparatorSha256": sha_bytes(COMPARATOR.read_bytes()),
               "candidatePath": str(BASELINE.relative_to(ROOT)),
               "candidateSha256": sha_bytes(BASELINE.read_bytes()),
               "pendingReceiptPath": str(PENDING.relative_to(ROOT)),
               "pendingReceiptSha256": pending_hash,
               "controls": controls}
    out = HERE / "fault-controls.json"
    out.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    return 0 if receipt["status"] == "controls-pass" and pending_hash == sha_bytes(PENDING.read_bytes()) else 1

if __name__ == "__main__":
    raise SystemExit(main())
