#!/usr/bin/env python3
"""Independent offline review of frozen strict Mac join profile v2."""
from __future__ import annotations
import hashlib, importlib.util, json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
PACKET = ROOT / "factory/native/windows/round1-seeded-hosts-v1"
ACTUAL = PACKET / "actual-v2"
STRICT = PACKET / "strictmac-join-profile-v2"
MAC = ROOT / "factory/oracle/mac/seed-corrections-v1"
LINEAGE = ROOT / "factory/oracle/mac/seed-corrections-lineage-v2"
SEED = 14577611000270672472
BLOCKS = ("stack-overlay", "custom-layout", "padding-frame", "preference-key", "scroll-view")


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha(path: Path) -> str:
    return digest(path.read_bytes())


def load(path: Path):
    return json.loads(path.read_text())


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def load_strict():
    spec = importlib.util.spec_from_file_location("strict_mac_join_v2", STRICT / "verify.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stage_checks() -> dict:
    manifest = load(ACTUAL / "root-stage-manifest.json")
    files = manifest["files"]
    require(manifest["kind"] == "strict-mac-join-profile-v2-frozen-packet", "stage kind")
    require(len(files) == 384, "384-pin denominator")
    repo = ROOT.resolve()
    for entry in files:
        path = (ROOT / entry["path"]).resolve()
        require(path.is_file() and not path.is_symlink(), f"stage file {entry['path']}")
        require(repo == path or repo in path.parents, f"stage containment {entry['path']}")
        require(type(entry["bytes"]) is int and path.stat().st_size == entry["bytes"], f"stage size {entry['path']}")
        require(sha(path) == entry["sha256"], f"stage hash {entry['path']}")
    return {"pinCount": len(files), "manifestSha256": sha(ACTUAL / "root-stage-manifest.json"), "qualification": manifest["qualification"]}


def receipt_checks() -> dict:
    receipt = load(ACTUAL / "execution-receipt.json")
    require(receipt["compilerProcesses"] == 0 and receipt["nativeProcesses"] == 0 and receipt["dellActions"] == 0, "producer process boundary")
    require(len(receipt["processes"]) == 2, "proof process count")
    for process in receipt["processes"]:
        require(process["exitCode"] == 0 and type(process["pid"]) is int and process["pid"] > 0, "proof process result")
        require(process["tool"]["path"].endswith("python3.14"), "proof tool")
    source = receipt["source"]
    controls = receipt["controlsSource"]
    require(source["path"].endswith("strictmac-join-profile-v2/verify.py") and source["sha256"] == sha(STRICT / "verify.py"), "strict source receipt")
    require(controls["path"].endswith("strictmac-join-profile-v2/test_verify.py") and controls["sha256"] == sha(STRICT / "test_verify.py"), "controls source receipt")
    return {"processes": len(receipt["processes"]), "compilerProcesses": 0, "nativeProcesses": 0, "dellActions": 0, "strictVerifierSha256": source["sha256"], "controlsSha256": controls["sha256"]}


def join_checks(strict) -> dict:
    proof = strict.verify(MAC, LINEAGE, PACKET)
    require(proof["sourceReplayEligible"] is True, "source replay eligibility")
    require(proof["windowsCompileValidated"] is False and proof["nativeParity"] == "hold", "parity hold")
    require(proof["compilerProcessOrigin"].startswith("MISSING"), "compiler origin hold")
    require(proof["frozenPlansModified"] is False, "frozen plan mutation")
    source_join = load(ACTUAL / "source-join.json")
    require(sha(ACTUAL / "source-join.json") == "sha256:9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3", "proof hash")
    require(source_join["sourceReplayEligible"] is True, "stored eligibility")
    statuses = Counter()
    rows = []
    for case in proof["cases"]:
        require(case["block"] in BLOCKS and len(case["runs"]) == 20, f"case {case['block']}")
        for row in case["runs"]:
            statuses[row["rawStatus"]] += 1
            rows.append({"block": case["block"], "run": row["run"], "rawStatus": row["rawStatus"], "captureHash": row["captureHash"], "rawHash": row["rawHash"]})
    require(statuses == Counter({"OBSERVED": 80, "UNOBSERVED": 20}), "80/20 raw status closure")
    require(sum(row["rawStatus"] == "UNOBSERVED" for row in rows if row["block"] == "scroll-view") == 20, "scroll held status")
    return {"strictProofKind": proof["kind"], "sourceReplayEligible": True, "actualJoins": len(rows), "rawStatusCounts": dict(statuses), "scrollViewUnobserved": 20, "compilerOrigin": "MISSING_HELD", "nativeParity": "HOLD", "cases": rows}


def controls_summary() -> dict:
    tests = load(ACTUAL / "execution-receipt.json")["processes"][0]
    stderr = ROOT / "factory/native/windows/round1-seeded-hosts-v1/actual-v2/controls-r2.stderr.txt"
    require(sha(stderr) == tests["stderr"]["sha256"] and "Ran 10 tests" in stderr.read_text() and "OK" in stderr.read_text(), "10 control receipt")
    return {"count": 10, "status": "PASS", "receiptPath": "actual-v2/controls-r2.stderr.txt", "receiptSha256": sha(stderr)}


def main() -> None:
    strict = load_strict()
    review = {"kind": "strict-mac-join-profile-v2-independent-review", "version": 1, "scope": "Offline strict verifier/source/proof review; producer packets & frozen plans untouched.", "seed": SEED, "stage": stage_checks(), "receipt": receipt_checks(), "strictVerifier": {"sha256": sha(STRICT / "verify.py"), "bytes": (STRICT / "verify.py").stat().st_size}, "sourceJoin": join_checks(strict), "faultControls": controls_summary(), "sourceLevels": {"witness": "separate exact bytes", "instrumentedRaw": "separate exact bytes", "adaptedCaptureHost": "separate exact bytes", "compilerOrigin": "MISSING_HELD"}, "disposition": "observational source replay eligible; exact Witness/raw/adapter/binary joins verified; 80 OBSERVED & 20 UNOBSERVED preserved; qualified compiler origin, native parity, & production qualification remain held"}
    out = Path(__file__).resolve().parent / "review.json"
    out.write_text(json.dumps(review, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "pins": 384, "actualJoins": 100, "rawObserved": 80, "rawUnobserved": 20, "faultControls": 10, "compilerOrigin": "HELD"}, sort_keys=True))

if __name__ == "__main__":
    main()
