#!/usr/bin/env python3
"""Offline independent review of paired stack/custom observational packet."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[4]
PACKET = ROOT / "factory/pipeline/paired-stack-custom-observation-v1"
STAGE_SHA = "47cc44505c72e5feaa96250c83cbb37bc60d42e0d2e7f79707741b308146fe62"
STACK_CASE = "sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0"
STACK_SOURCE = "sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee"
CUSTOM_CASE = "sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a"
CUSTOM_SOURCE = "sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b"


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def inventory_matches(root: Path, inv: dict[str, Any]) -> tuple[bool, list[str]]:
    failures: list[str] = []
    actual = []
    for p in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix()):
        b = p.read_bytes()
        actual.append({"path": p.relative_to(root).as_posix(), "bytes": len(b), "sha256": "sha256:" + hashlib.sha256(b).hexdigest()})
    if actual != inv.get("files", []):
        failures.append("file inventory or raw bytes")
    if len(actual) != inv.get("fileCount") or sum(x["bytes"] for x in actual) != inv.get("bytes"):
        failures.append("inventory count or byte total")
    digest = "sha256:" + hashlib.sha256(json.dumps(actual, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if digest != inv.get("inventorySha256"):
        failures.append("inventory hash")
    return not failures, failures


def summary_join(summary: dict[str, Any], case_hash: str, source_hash: str) -> bool:
    return (
        summary["case"]["hash"] == case_hash
        and summary["provenance"]["sourceHash"] == source_hash
        and summary["probeManifest"]["case"]["hash"] == case_hash
        and summary["probeManifest"]["sourceHash"] == source_hash
        and len(summary.get("runs", [])) == 20
    )


def validate(report: dict[str, Any], pins: dict[str, Any], *, check_raw: bool = True) -> dict[str, Any]:
    assert report["kind"] == "f9-paired-stack-custom-observation-v1"
    assert report["version"] == 1 and report["candidateOnly"] is True
    assert report["goldens"] == 0 and report["qualification"] == "held" and report["parity"] == "unavailable"
    assert report["controls"]["required"] == ["mismatched-source-rejected", "mismatched-case-rejected", "missing-raw-rejected", "forged-status-rejected"]
    assert len(report["observations"]) == 2 and len(report["inputs"]["windowsAttempts"]) == 2
    obs = {x["id"]: x for x in report["observations"]}
    assert set(obs) == {"windows-stack-overlay-r1", "windows-custom-layout-r1"}
    stack, custom = obs["windows-stack-overlay-r1"], obs["windows-custom-layout-r1"]

    assert stack["case"]["hash"] == STACK_CASE and stack["sourceHash"] == STACK_SOURCE
    assert stack["status"] == "probe-failure" and stack["failureClass"] == "unsupportedOverlay"
    assert stack["rawDispatchStatus"] == "hold-harness-error"
    assert all(stack["channels"][k] == "unavailable" for k in ("layout", "printWindow", "screen", "shape", "uia"))
    assert "no native DIFF" in stack["comparison"]
    assert custom["case"]["hash"] == CUSTOM_CASE and custom["sourceHash"] == CUSTOM_SOURCE
    assert custom["status"] == "observed-partial" and custom["rawDispatchStatus"] == "captured-single-observational-uia-printwindow"
    assert custom["channels"]["layout"] == "unavailable" and custom["channels"]["shape"] == "unavailable"
    assert custom["channels"]["role"] == "unavailable" and custom["channels"]["label"] == "unavailable"
    assert custom["channels"]["uia"] == "root-only-empty-children" and custom["uia"]["children"] == 0
    assert custom["channels"]["enabled"] == "raw-root-only-not-semantic"
    assert custom["capture"]["printWindowPngSha256"] == custom["capture"]["repeatPngSha256"]
    assert custom["capture"]["screenPngSha256"] == custom["capture"]["screenRepeatSha256"]
    assert custom["capture"]["printWindowRepeatStable"] is True and custom["capture"]["screenRepeatStable"] is True
    assert custom["capture"]["methodsEqual"] is False
    assert "no native DIFF" in custom["comparison"]

    if check_raw:
        for inv in pins["windows"] + pins["macArchives"]:
            ok, why = inventory_matches(ROOT / inv["root"], inv)
            assert ok, why
    for windows in report["inputs"]["windowsAttempts"]:
        pin = next(x for x in pins["windows"] if x["root"] == windows["root"])
        assert windows == pin
    for archive in report["inputs"]["macArchives"]:
        summary = ROOT / archive["summaryPath"]
        assert summary.is_file() and "sha256:" + sha(summary) == archive["summarySha256"] and archive["runs"] == 20
        sm = load(summary)
        expected = STACK_CASE if "stack-overlay" in archive["archiveInventoryRoot"] else CUSTOM_CASE
        source = STACK_SOURCE if expected == STACK_CASE else CUSTOM_SOURCE
        assert summary_join(sm, expected, source)
    return {"baseline": "accepted", "rawWindows": 2, "rawMacArchives": 2, "rawFileCount": sum(x["fileCount"] for x in pins["windows"] + pins["macArchives"])}


def fault_controls(report: dict[str, Any], pins: dict[str, Any]) -> dict[str, str]:
    outcomes = {}
    mutations = {
        "mismatched-source": lambda q: q["observations"][1].__setitem__("sourceHash", "sha256:" + "0" * 64),
        "mismatched-case": lambda q: q["observations"][1]["case"].__setitem__("hash", "sha256:" + "1" * 64),
        "missing-raw": lambda q: q["inputs"]["windowsAttempts"][1]["files"].pop(),
        "forged-status": lambda q: q["observations"][1].__setitem__("status", "native-diff"),
    }
    for name, mutate in mutations.items():
        q = copy.deepcopy(report)
        mutate(q)
        try:
            validate(q, pins, check_raw=False)
        except (AssertionError, KeyError, StopIteration):
            outcomes[name] = "rejected"
        else:
            outcomes[name] = "accepted-BUG"
    assert all(x == "rejected" for x in outcomes.values()), outcomes
    return outcomes


def review() -> dict[str, Any]:
    stage_path = PACKET / "stage-manifest.json"
    stage = load(stage_path)
    stage_rows = []
    failures = []
    for row in stage["trackedFiles"]:
        p = PACKET / row["path"]
        got = {"path": row["path"], "exists": p.is_file()}
        if p.is_file():
            got.update({"bytes": p.stat().st_size, "sha256": sha(p)})
            if got["bytes"] != row["bytes"] or got["sha256"] != row["sha256"].removeprefix("sha256:"):
                failures.append(row["path"])
        else:
            failures.append(row["path"])
        stage_rows.append(got)
    report = load(PACKET / "report.json")
    pins = load(PACKET / "raw-pins.json")
    baseline = validate(report, pins)
    faults = fault_controls(report, pins)
    return {
        "kind": "paired-stack-custom-observation-independent-review-v1",
        "status": "independently-verified-candidate-observation-held",
        "producerStage": {"sha256": sha(stage_path), "expectedSha256": STAGE_SHA, "fileCount": stage["fileCount"], "allRowsMatch": not failures, "rows": stage_rows},
        "rawJoins": baseline,
        "observations": {
            "stack": "probe-failure; renderer failed before UIA/PW capture; status is not DIFF",
            "custom": "observed-partial; one PrintWindow plus stable repeat, one screen plus stable repeat, root UIA children=0",
        },
        "holds": ["semantic layout unavailable", "shape unavailable", "provider unavailable", "timing unavailable", "zero goldens", "parity unavailable", "qualification held"],
        "faultControls": faults,
        "candidateOnly": True,
        "nativeDiff": False,
    }


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    args.output.write_text(json.dumps(review(), indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "ok", "output": str(args.output)}))
