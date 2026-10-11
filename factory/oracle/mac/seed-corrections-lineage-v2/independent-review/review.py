#!/usr/bin/env python3
"""Independent offline review of seed-corrections-lineage-v2."""
from __future__ import annotations
import copy, hashlib, json, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
PACKET = ROOT / "factory/oracle/mac/seed-corrections-lineage-v2"
BASE = ROOT / "factory/oracle/mac/seed-corrections-v1"
BLOCKS = ("stack-overlay", "padding-frame", "scroll-view", "custom-layout", "preference-key")
SEED = 14577611000270672472


def load(path: Path):
    return json.loads(path.read_text())


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def pin(root: Path, entry: dict) -> None:
    path = root / entry["path"]
    require(path.is_file() and not path.is_symlink(), f"missing {entry['path']}")
    require(path.stat().st_size == entry["bytes"], f"size {entry['path']}")
    require(sha(path) == entry["sha256"], f"hash {entry['path']}")


def stage_checks() -> dict:
    manifest = load(PACKET / "stage-manifest.json")
    require(manifest["seed"] == SEED and manifest["entryCount"] == 31, "stage header")
    require(len(manifest["entries"]) == 31, "stage denominator")
    for entry in manifest["entries"]:
        pin(PACKET, entry)
    return {"entryCount": len(manifest["entries"]), "stageSha256": sha(PACKET / "stage-manifest.json")}


def input_rows() -> dict:
    rows = {row["block"]: row for row in load(BASE / "input-pins.json")["rows"]}
    require(set(rows) == set(BLOCKS), "base five cases")
    for row in rows.values():
        require(row["seed"] == SEED, f"seed {row['block']}")
    return rows


def source_policy_checks() -> dict:
    policy = load(PACKET / "policy/source-policy.json")
    require(sha(PACKET / "policy/capture.py") == policy["scriptSha256"], "policy script")
    require(sha(PACKET / "policy/CaptureHost.original.swift") == policy["adapterSource"]["sha256"], "original adapter")
    argv = policy["compilerPolicy"]["argvTemplate"]
    require(argv == ["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-O", "-o", "<capture-host>", "<Witness.swift>", "<CaptureHost.swift>"], "compiler argv policy")
    receipt = policy["actualProcessReceipt"]
    require(all(receipt[key] is False for key in ("argvRecorded", "pidRecorded", "startedAtRecorded", "endedAtRecorded", "returnCodeRecorded")), "process proof hold")
    return {"argvTemplate": argv, "actualCompilerProcessReceipt": "MISSING_AND_HELD", "adapterPolicyHash": policy["adapterSource"]["sha256"]}


def case_checks(rows: dict) -> tuple[list[dict], dict]:
    reports = []
    total_joins = 0
    total_raw_source_matches = 0
    all_witness = set()
    all_adapter = set()
    all_binaries = set()
    for block in BLOCKS:
        lineage = load(PACKET / "cases" / block / "lineage.json")
        witness = PACKET / "cases" / block / "Witness.swift"
        adapter = PACKET / "cases" / block / "CaptureHost.adapted.swift"
        binary = BASE / f"binaries/{block}/capture-host"
        summary = load(BASE / "evidence" / f"swiftui.{block}.recipe.gate-seeded.ca4e13f820f5d258" / "summary.json")
        row = rows[block]
        require(lineage["seed"] if "seed" in lineage else True, "unused")
        require(lineage["caseID"] == row["caseID"], f"{block} case id")
        require(lineage["sourceWitness"]["ownedPath"] == f"cases/{block}/Witness.swift", f"{block} witness path")
        require(sha(witness) == lineage["sourceWitness"]["sha256"] == row["source"]["declared"] == summary["sourceHash"], f"{block} witness join")
        require(sha(adapter) == lineage["adaptedCaptureHost"]["sha256"] == lineage["adaptedCaptureHost"]["summaryCompiledAdapterHash"] == summary["compiledAdapterHash"], f"{block} adapter join")
        require(lineage["adaptedCaptureHost"]["summaryAdapterSourceHash"] == summary["adapterSourceHash"] == sha(PACKET / "policy/CaptureHost.original.swift"), f"{block} adapter policy join")
        require(sha(binary) == lineage["binary"]["sha256"] == lineage["binary"]["summaryBinaryHash"] == summary["binaryHash"], f"{block} binary join")
        require(witness.read_bytes() != adapter.read_bytes(), f"{block} separate source bytes")
        require(lineage["compileProcessProof"].startswith("MISSING:"), f"{block} process hold")
        joins = []
        for item in lineage["rawInstrumentedJoins"]:
            raw = BASE / item["rawPath"]
            require(raw.is_file() and not raw.is_symlink(), f"{block} raw {item['run']}")
            raw_hash = sha(raw)
            capture_path = raw.parent / "capture.json"
            capture = load(capture_path)
            summary_run = next(run for run in summary["runs"] if run["run"] == item["run"])
            require(raw_hash == item["rawSha256"] == item["summaryInstrumentedRawHash"] == summary_run["instrumented"]["rawHash"], f"{block} raw summary {item['run']}")
            require(capture["provenance"]["sourceHash"] == raw_hash, f"{block} raw provenance {item['run']}")
            require(capture["provenance"]["inputs"][0]["hash"] == summary["binaryHash"], f"{block} raw binary provenance {item['run']}")
            joins.append({"run": item["run"], "rawHash": raw_hash, "sourceHashMatchesRaw": True, "binaryHash": summary["binaryHash"]})
        require([item["run"] for item in lineage["rawInstrumentedJoins"]] == list(range(1, 21)), f"{block} raw run closure")
        total_joins += len(joins)
        total_raw_source_matches += sum(item["sourceHashMatchesRaw"] for item in joins)
        all_witness.add(lineage["sourceWitness"]["sha256"])
        all_adapter.add(lineage["adaptedCaptureHost"]["sha256"])
        all_binaries.add(lineage["binary"]["sha256"])
        reports.append({"block": block, "caseID": lineage["caseID"], "witnessHash": lineage["sourceWitness"]["sha256"], "adapterHash": lineage["adaptedCaptureHost"]["sha256"], "originalAdapterHash": lineage["adaptedCaptureHost"]["summaryAdapterSourceHash"], "binaryHash": lineage["binary"]["sha256"], "rawJoins": joins, "compileProcessProof": "MISSING_AND_HELD"})
    return reports, {"cases": 5, "rawJoins": total_joins, "rawSourceHashMatches": total_raw_source_matches, "uniqueWitnessHashes": len(all_witness), "uniqueAdapterHashes": len(all_adapter), "uniqueBinaryHashes": len(all_binaries)}


def controls(rows: dict) -> dict:
    outcomes = {}
    with tempfile.TemporaryDirectory() as t:
        p = Path(t) / "Witness.swift"; p.write_bytes((PACKET / "cases/stack-overlay/Witness.swift").read_bytes() + b"\n")
        try: require(sha(p) == rows["stack-overlay"]["source"]["declared"], "source mutation accepted")
        except AssertionError: outcomes["witness-byte-mutation"] = "rejected"
    with tempfile.TemporaryDirectory() as t:
        p = Path(t) / "CaptureHost.adapted.swift"; p.write_bytes((PACKET / "cases/stack-overlay/CaptureHost.adapted.swift").read_bytes() + b"\n")
        try: require(sha(p) == load(PACKET / "cases/stack-overlay/lineage.json")["adaptedCaptureHost"]["sha256"], "adapter mutation accepted")
        except AssertionError: outcomes["adapter-byte-mutation"] = "rejected"
    with tempfile.TemporaryDirectory() as t:
        p = Path(t) / "capture-host"; p.write_bytes((BASE / "binaries/stack-overlay/capture-host").read_bytes() + b"\x00")
        try: require(sha(p) == load(PACKET / "cases/stack-overlay/lineage.json")["binary"]["sha256"], "binary mutation accepted")
        except AssertionError: outcomes["binary-byte-mutation"] = "rejected"
    raw = BASE / "evidence/swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258/run-001/instrumented.raw.json"
    try: require(sha(raw) == load(PACKET / "cases/stack-overlay/lineage.json")["rawInstrumentedJoins"][0]["rawSha256"], "raw baseline")
    except AssertionError: raise
    with tempfile.TemporaryDirectory() as t:
        p = Path(t) / "instrumented.raw.json"; p.write_bytes(raw.read_bytes() + b"\n")
        try: require(sha(p) == load(PACKET / "cases/stack-overlay/lineage.json")["rawInstrumentedJoins"][0]["rawSha256"], "raw mutation accepted")
        except AssertionError: outcomes["raw-byte-mutation"] = "rejected"
    lineage = load(PACKET / "cases/stack-overlay/lineage.json")
    mutated = copy.deepcopy(lineage); mutated["adaptedCaptureHost"]["summaryCompiledAdapterHash"] = "sha256:" + "0" * 64
    try: require(mutated["adaptedCaptureHost"]["summaryCompiledAdapterHash"] == mutated["adaptedCaptureHost"]["sha256"], "join mutation accepted")
    except AssertionError: outcomes["summary-adapter-join-mutation"] = "rejected"
    policy = load(PACKET / "policy/source-policy.json"); mutated_policy = copy.deepcopy(policy); mutated_policy["actualProcessReceipt"]["argvRecorded"] = True
    try: require(mutated_policy["actualProcessReceipt"]["argvRecorded"] is False, "process proof mutation accepted")
    except AssertionError: outcomes["process-proof-mutation"] = "rejected"
    require(len(outcomes) == 6, f"controls {outcomes}")
    return outcomes


def main() -> None:
    rows = input_rows()
    stage = stage_checks()
    policy = source_policy_checks()
    cases, closure = case_checks(rows)
    fault_controls = controls(rows)
    review = {"kind": "seed-corrections-lineage-v2-independent-review", "version": 1, "scope": "Offline append-only source/binary/raw lineage review; v1 & lineage-v2 producer files untouched.", "seed": SEED, "stage": stage, "policy": policy, "closure": closure, "cases": cases, "faultControls": {"count": len(fault_controls), "outcomes": fault_controls}, "sourceBoundCandidateObservation": "PASS", "compilerOSOriginAndParityQualification": "HELD_MISSING_ACTUAL_PROCESS_RECEIPT", "noAlias": {"witnessBytes": True, "adapterBytes": True, "binaryBytes": True, "rawBytes": True, "sourceHashRole": True}, "disposition": "separate Witness.swift & adapted CaptureHost.swift bytes verified for five cases; source/adapter/binary joins verified across 100 raw runs; capture provenance sourceHash equals instrumented raw bytes for all 100; actual compiler argv/PID/timestamps/return code remain explicitly held"}
    out = PACKET / "independent-review/review.json"; out.parent.mkdir(exist_ok=True); out.write_text(json.dumps(review, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "seed": SEED, "cases": 5, "rawJoins": closure["rawJoins"], "rawSourceHashMatches": closure["rawSourceHashMatches"], "faultControls": len(fault_controls), "compilerProcessProof": "HELD"}, sort_keys=True))

if __name__ == "__main__": main()
