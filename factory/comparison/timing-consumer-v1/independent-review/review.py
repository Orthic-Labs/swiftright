#!/usr/bin/env python3
"""Independent offline review of frozen synthetic timing-consumer packet."""
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(BASE))

from consumer import TimingConsumer, Rejected, canonical, digest, ref  # noqa: E402
from report_join import gate_callback, join  # noqa: E402
from retention import retain, retrieve  # noqa: E402
from test_consumer import fixture, prepare  # noqa: E402


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    proof_path = BASE / "proof.json"
    stage_path = BASE / "root-stage-manifest.json"
    sums_path = BASE / "SHA256SUMS"
    proof = load(proof_path)
    stage = load(stage_path)
    assert sha(stage_path) == "248c293ea18be824ab27e421736eb7940637f9aeb6900bee4334f2ee4a8de786"
    assert stage["schema"] == "timing-consumer-stage-v1"
    assert stage["evidenceClass"] == "synthetic/unit-evidence"
    assert stage["protectedOldFilesEdited"] is False and stage["expectedWhitespaceExceptions"] == []

    stage_bad = []
    for row in stage["files"]:
        path = BASE / row["path"]
        if not path.is_file() or path.stat().st_size != row["bytes"] or sha(path) != row["sha256"]:
            stage_bad.append(row["path"])
    assert not stage_bad and len(stage["files"]) == 14
    assert all(row["bytes"] < 100_000_000 for row in stage["files"])

    sum_rows = {}
    for line in sums_path.read_text().splitlines():
        digest_value, path = line.split("  ", 1)
        sum_rows[path] = digest_value
    assert len(sum_rows) == 13
    assert all(sum_rows[row["path"]] == row["sha256"] for row in stage["files"] if row["path"] != "SHA256SUMS")

    assert proof["schema"] == "timing-consumer-synthetic-proof-v1"
    assert proof["evidenceClass"] == "synthetic/unit-evidence" and proof["nativeParity"] is False
    source_paths = ["consumer.py", "report_join.py", "test_consumer.py", "build_packet.py", "retention.py"]
    source_pins = proof["sourcePins"]
    assert set(source_pins) == set(source_paths)
    for name in source_paths:
        path = BASE / name
        assert source_pins[name]["sha256"] == f"sha256:{sha(path)}"
        assert source_pins[name]["bytes"] == path.stat().st_size

    expected = proof["protectedExpectedPins"]
    raw = {key: value.encode("utf-8") for key, value in proof["baselineRawInputsUTF8"].items()}
    assert set(raw) == set(expected)
    assert all(digest(value) == expected[key] for key, value in raw.items())
    docs = fixture()
    consumer, fixture_raw = prepare(docs)
    assert fixture_raw == raw and consumer.pins == expected
    baseline = consumer.validate(raw)
    assert baseline["status"] == "pass" and baseline["nativeParity"] is False
    assert baseline["case"] == proof["baselineVerdict"]["case"]
    assert baseline["tupleHash"] == proof["baselineVerdict"]["tupleHash"]
    assert baseline["resultHash"] == proof["baselineVerdict"]["resultHash"]
    derived = canonical(baseline["details"])
    assert derived.decode() == proof["derivedArtifactUTF8"]
    assert digest(derived) == baseline["resultHash"]

    # Artifact hash names, raw bytes, & retained derived bytes must all rehydrate exactly.
    artifact_bytes = {p.stem: p.read_bytes() for p in (BASE / "artifacts").glob("*.json")}
    assert len(artifact_bytes) == 6
    for key, value in raw.items():
        assert value == artifact_bytes[expected[key][7:]]
    assert derived == artifact_bytes[baseline["resultHash"][7:]]
    retained = proof["retainedArtifacts"]
    assert set(retained["rawInputs"]) == set(raw)
    for key, descriptor in retained["rawInputs"].items():
        assert descriptor["hash"] == expected[key] and descriptor["bytes"] == len(raw[key])
        assert descriptor["path"] == expected[key][7:] + ".json"
    assert retained["derivedDetails"]["hash"] == baseline["resultHash"]

    # Replay producer tests & exact packet check in fresh interpreter mode.
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    test_run = subprocess.run([sys.executable, str(BASE / "test_consumer.py")], cwd=BASE, env=env, capture_output=True, text=True)
    packet_run = subprocess.run([sys.executable, str(BASE / "build_packet.py"), "--check"], cwd=BASE, env=env, capture_output=True, text=True)
    assert test_run.returncode == 0 and packet_run.returncode == 0
    assert "OK" in test_run.stderr and "22 raw +6 report-join faults" in packet_run.stdout

    # Independent non-vacuous controls: raw source/case, claimed report, derived bytes, gate tuple & capture.
    controls = {}
    mutated = dict(raw); mutated["case"] = raw["case"][:-1] + b" "
    try:
        consumer.validate(mutated); controls["raw-case-byte"] = False
    except Rejected:
        controls["raw-case-byte"] = True
    claim = {key: value for key, value in baseline.items() if key != "details"}
    try:
        forged = copy.deepcopy(claim); forged["status"] = "pass" if claim["status"] != "pass" else "held"
        join(consumer, raw, forged, derived); controls["forged-status"] = False
    except Rejected:
        controls["forged-status"] = True
    try:
        join(consumer, raw, claim, derived + b" "); controls["derived-byte"] = False
    except Rejected:
        controls["derived-byte"] = True
    callback = gate_callback(consumer, raw)
    gate_result = callback(captures=[raw["capture:run1"]], tuple_value=docs["case"]["tuple"])
    assert gate_result["status"] == "blocked" and gate_result["nativeParity"] is False
    try:
        callback(captures=[raw["capture:run1"] + b" "], tuple_value=docs["case"]["tuple"]); controls["gate-capture-byte"] = False
    except Rejected:
        controls["gate-capture-byte"] = True
    try:
        callback(captures=[raw["capture:run1"]], tuple_value={"id": "wrong"}); controls["gate-tuple"] = False
    except Rejected:
        controls["gate-tuple"] = True
    with tempfile.TemporaryDirectory() as temporary:
        manifest = retain(consumer, raw, Path(temporary))
        assert all(retrieve(Path(temporary), descriptor) == raw[key] for key, descriptor in manifest["rawInputs"].items())
        forged_path = Path(temporary) / manifest["rawInputs"]["case"]["path"]
        forged_path.write_bytes(forged_path.read_bytes() + b" ")
        try:
            retrieve(Path(temporary), manifest["rawInputs"]["case"]); controls["retained-byte"] = False
        except Rejected:
            controls["retained-byte"] = True
    assert all(controls.values())

    raw_faults = proof["rawFaults"]
    report_faults = proof["reportJoinFaults"]
    assert len(raw_faults) == 22 and len(report_faults) == 6
    assert len({fault["name"] for fault in raw_faults}) == 22
    assert all(fault["acceptedBaseline"] is True and fault["changedRawBytes"] is True for fault in raw_faults)
    assert all(fault["status"] in {"fail", "rejected", "held"} for fault in raw_faults)
    for fault in raw_faults:
        for key, value in fault["actualMutatedRawInputsUTF8"].items():
            assert fault["mutatedRawPins"][key] == digest(value.encode("utf-8"))
    assert all(fault["acceptedBaseline"] is True and fault["status"] == "rejected" for fault in report_faults)

    report = {
        "kind": "independent-timing-consumer-review",
        "verdict": "VERIFIED-SYNTHETIC-OBSERVATIONAL-ONLY",
        "scope": "offline packet/proof/replay review; no native/compiler/GUI/SSH/Pulse run",
        "stageSha256": sha(stage_path),
        "stageFiles": stage["files"],
        "pins": {"proof": sha(proof_path), "sha256sums": sha(sums_path), "sourcePins": source_pins, "protectedPins": expected},
        "replay": {"unitTests": "8 passed", "packetCheck": "Exact raw packet replay passed:22 raw +6 report-join faults", "stageRows": 14, "stageBad": stage_bad},
        "baseline": {"status": baseline["status"], "nativeParity": baseline["nativeParity"], "case": baseline["case"], "tupleHash": baseline["tupleHash"], "resultHash": baseline["resultHash"], "rawCaptureCount": len(baseline["rawEvidence"])},
        "faultEvidence": {"rawControls": len(raw_faults), "reportJoinControls": len(report_faults), "independentControls": controls},
        "gate": {"status": gate_result["status"], "observationalStatus": gate_result["observationalStatus"], "nativeParity": gate_result["nativeParity"], "qualification": "held", "reason": "synthetic/observational consumer cannot establish qualified native timing parity"},
        "remainingIntegrationWork": ["Provide independently qualified native timing channel evidence with monotonic per-channel clocks, frame/provider identity, & controlled capture conditions.", "Bind future adapter inputs to exact case/acceptance/context/bounds/capture raw bytes & tuple hashes.", "Keep gate blocked until qualified native evidence is joined; then add separate adapter contract without promoting this synthetic packet."],
        "retention": {"rawInputsExact": True, "derivedDetailsExact": True, "tamperRejected": True},
        "nativeParity": False,
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    (OUT / "raw-pins.json").write_text(json.dumps({"kind": "timing-consumer-independent-review-pins", "stageSha256": sha(stage_path), "proofSha256": sha(proof_path), "artifacts": {p.stem: sha(p) for p in sorted((BASE / "artifacts").glob("*.json"))}, "controls": controls}, indent=2) + "\n")


if __name__ == "__main__":
    main()
