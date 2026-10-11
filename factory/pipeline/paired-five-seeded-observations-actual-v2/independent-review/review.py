#!/usr/bin/env python3
"""Independent offline review of paired-five-seeded-observations-actual-v1."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
STAGE = ROOT / "factory/pipeline/paired-five-seeded-observations-actual-v1"
MAC_ROOT = ROOT / "factory/native/macos/evidence/20261010-gate-seeded"
WIN_ROOT = ROOT / "factory/native/windows/round1-seeded-native-v2"
PROOF = WIN_ROOT / "root-mac-proof-actual-r1/proof-copy.json"
LINEAGE = ROOT / "factory/oracle/mac/seed-corrections-lineage-v2/lineage.json"
LINEAGE_REVIEW = ROOT / "factory/oracle/mac/seed-corrections-lineage-v2/independent-review/review.json"
ROLE_MAP = {"AXStaticText": "ControlType.Text"}
CASES = {
    "stack": {
        "mac": "swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258",
        "win": "single-stack-overlay-r1",
        "case": "sha256:88ee31aaaba4b6c1729c3530b1461b19167c9e55ee27c72a0124edaea0ec2380",
        "source": "sha256:fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35",
    },
    "custom": {
        "mac": "swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258",
        "win": "single-custom-layout-r1",
        "case": "sha256:0dba13824f3398666aba1b27b54c01ff02d3e282b2c429a66f3869a05ed0cb49",
        "source": "sha256:00989672411aae376c52781205b826c3e4ae5d6acc52e501a0032996dadcc98d",
    },
    "padding": {
        "mac": "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258",
        "win": "single-padding-frame-r1",
        "case": "sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d",
        "source": "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b",
    },
    "preference": {
        "mac": "swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258",
        "win": "single-preference-key-r1",
        "case": "sha256:d908821e18c8ad4e45eed24b446cf3d126fdbf18e17030be45bbbb7105b8459c",
        "source": "sha256:ec6837aefba5cd1b0d550675cb2577030ebc96b61ee5f5ee75a9bd852ca92463",
    },
    "scroll": {
        "mac": "swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258",
        "win": "single-scroll-view-r1",
        "case": "sha256:adeed134241b30dfeb873e27dd789b870977457c3b210268f10f3a1be8ffdd18",
        "source": "sha256:27ae712cafa50fd6fd14efe8594a170d26143587dfddc9bbda882dc00c7a4093",
    },
}


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for part in iter(lambda: f.read(1024 * 1024), b""):
            h.update(part)
    return h.hexdigest()


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def inventory(root: Path):
    files = []
    for p in sorted((x for x in root.rglob("*") if x.is_file()), key=lambda x: x.relative_to(root).as_posix()):
        files.append({"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size, "sha256": "sha256:" + digest(p)})
    canonical = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {
        "root": root.relative_to(ROOT).as_posix(),
        "exists": root.exists(),
        "fileCount": len(files),
        "bytes": sum(row["bytes"] for row in files),
        "inventorySha256": "sha256:" + hashlib.sha256(canonical).hexdigest(),
        "files": files,
    }


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def ax_labels(raw):
    steps = raw.get("steps")
    if not isinstance(steps, list) or not steps:
        return []
    tree = steps[0].get("tree", {})
    return [
        node["value"]
        for node in walk(tree)
        if node.get("role") == "AXStaticText"
        and isinstance(node.get("value"), str)
        and node.get("value") != raw.get("windowTitle")
    ]


def check_stage_files():
    manifest = read(STAGE / "stage-manifest.json")
    assert manifest["kind"] == "f9-paired-five-seeded-observations-actual-v1-stage"
    assert manifest["fileCount"] == 4
    for row in manifest["files"]:
        path = STAGE / row["path"]
        assert path.stat().st_size == row["bytes"], row["path"]
        assert "sha256:" + digest(path) == row["sha256"], row["path"]
    return "stage-files"


def review():
    report = read(STAGE / "report.json")
    pins = read(STAGE / "raw-pins.json")
    proof = read(PROOF)
    lineage = read(LINEAGE)
    lineage_review = read(LINEAGE_REVIEW)
    assert report["kind"] == "f9-paired-five-seeded-observations-actual-v1"
    assert report["seed"] == 14577611000270672472
    assert report["candidateOnly"] is True and report["macFreshRuns"] == 100 and report["windowsSeedSingles"] == 5
    assert proof["kind"] == "seed-mac100-two-source-level-join-v2"
    assert proof["sourceReplayEligible"] is True
    assert proof["nativeParity"] == "hold" and "MISSING" in proof["compilerProcessOrigin"]
    assert lineage["seed"] == report["seed"] and lineage_review["seed"] == report["seed"]
    assert lineage_review["disposition"] in ("lineage-complete; compiler-process-origin-held", "complete-lineage; qualification-held") or "held" in str(lineage_review["disposition"]).lower()
    assert report["provenance"]["macSourceProof"]["sha256"] == "sha256:" + digest(PROOF)
    assert report["provenance"]["macLineageV2"]["sha256"] == "sha256:" + digest(LINEAGE)
    assert report["provenance"]["macLineageIndependentReview"]["sha256"] == "sha256:" + digest(LINEAGE_REVIEW)

    proof_cases = {r["block"]: r for r in proof["cases"]}
    lineage_cases = {r["block"]: r for r in lineage["cases"]}
    assert len(proof_cases) == len(lineage_cases) == 5
    mac_run_total = 0
    win_total = 0
    per_case = {}
    for key, expected in CASES.items():
        case_report = report["cases"][key]
        mac_report = case_report["macFresh100"]
        win_report = case_report["windowsSeedSingle"]
        mac_root = MAC_ROOT / expected["mac"]
        win_root = WIN_ROOT / expected["win"]
        mac_inv = inventory(mac_root)
        win_inv = inventory(win_root)
        assert mac_inv == mac_report["rawInventory"] == pins["macRoots"][key]
        assert win_inv == win_report["rawInventory"] == pins["windowsRoots"][key]

        summary = read(mac_root / "summary.json")
        assert summary["case"] == {"id": expected["mac"], "hash": expected["case"]}
        assert summary["sourceHash"] == summary["provenance"]["sourceHash"] == summary["probeManifest"]["sourceHash"] == expected["source"]
        assert mac_report["caseId"] == expected["mac"] and mac_report["caseHash"] == expected["case"]
        assert mac_report["sourceHash"] == expected["source"] and len(mac_report["runs"]) == 20
        proof_case = proof_cases[key.replace("stack", "stack-overlay").replace("padding", "padding-frame").replace("preference", "preference-key").replace("custom", "custom-layout").replace("scroll", "scroll-view")]
        line_case = lineage_cases[proof_case["block"]]
        assert proof_case["case"]["id"] == expected["mac"] and proof_case["case"]["hash"] == expected["case"]
        assert proof_case["witnessHash"] == expected["source"] == line_case["sourceWitness"]["sha256"]
        witness_path = LINEAGE.parent / line_case["sourceWitness"]["ownedPath"]
        assert witness_path.stat().st_size == line_case["sourceWitness"]["bytes"]
        assert "sha256:" + digest(witness_path) == expected["source"]
        assert line_case["binary"]["sha256"] == proof_case["binaryHash"]

        mac_runs = {r["run"]: r for r in summary["runs"]}
        proof_runs = {r["run"]: r for r in proof_case["runs"]}
        report_runs = {r["run"]: r for r in mac_report["runs"]}
        assert set(mac_runs) == set(proof_runs) == set(report_runs) == set(range(1, 21))
        for run_id in range(1, 21):
            rd = mac_root / f"run-{run_id:03d}"
            instrumented_path = rd / "instrumented.raw.json"
            external_path = rd / "external-ax.raw.json"
            capture_path = rd / "capture.json"
            instrumented = read(instrumented_path)
            external = read(external_path)
            capture = read(capture_path)
            summary_run = mac_runs[run_id]
            proof_run = proof_runs[run_id]
            rrow = report_runs[run_id]
            inst_hash = "sha256:" + digest(instrumented_path)
            external_hash = "sha256:" + digest(external_path)
            capture_hash = "sha256:" + digest(capture_path)
            lineage_run = next(r for r in line_case["rawInstrumentedJoins"] if r["run"] == run_id)
            assert summary_run["instrumented"]["rawHash"] == proof_run["rawHash"] == lineage_run["rawSha256"] == inst_hash
            assert summary_run["externalAXRawHash"] == external_hash
            assert summary_run["captureHash"] == proof_run["captureHash"] == capture_hash
            assert proof_run["rawStatus"] == summary_run["instrumented"]["status"] == instrumented["status"]
            assert summary_run["externalAX"] == external["status"]
            assert capture["case"]["id"] == expected["mac"] and capture["case"]["hash"] == expected["case"]
            assert capture["sourceHash"] == expected["source"]
            assert rrow["rawAXSha256"] == external_hash and rrow["captureSha256"] == capture_hash
            assert rrow["rawStatus"] == instrumented["status"]
            assert rrow["externalAXStatus"] == external["status"]
            assert rrow["ownerPid"] == external["pid"] and rrow["clientPid"] == external["clientPID"]
        mac_runs_count = len(mac_report["runs"])
        mac_run_total += mac_runs_count

        batch_path = win_root / "batch.json"
        batch = read(batch_path)
        assert batch["requested"] == batch["attempted"] == 1 and batch["retry"] is False and len(batch["rows"]) == 1
        row = batch["rows"][0]
        run_root = win_root / "replays/run-001"
        plan, obs, native, dispatch = [read(run_root / fn) for fn in ("plan.json", "observation.json", "native-observation.json", "dispatch.json")]
        ui = read(run_root / "native-01/native.uia.json")
        capture = read(run_root / "native-01/capture-outcome.json")
        assert win_report["requested"] == win_report["attempted"] == 1 and win_report["successfulObservations"] == 1
        assert win_report["caseId"] == expected["mac"] and win_report["caseHash"] == expected["case"]
        assert win_report["sourceHash"] == expected["source"]
        assert plan["case"] == native["case"] == {"id": expected["mac"], "hash": expected["case"]}
        assert plan["sourceHash"] == obs["sourceHash"] == native["sourceHash"] == expected["source"]
        assert row["status"] == dispatch["status"] == "captured-single-observational-uia-printwindow"
        assert obs["exeSha256"] == native["exeSha256"] == batch["exeHash"] == win_report["exeHash"]
        assert capture["exeHash"] == batch["exeHash"] and capture["sourceHash"] == expected["source"]
        assert capture["macSourceProofHash"] == digest(PROOF)
        labels = [n["name"] for n in walk(ui) if n.get("controlType") == "ControlType.Text" and isinstance(n.get("name"), str)]
        assert labels == win_report["row"]["uiaLabels"]
        win_total += 1
        per_case[key] = {"macRuns": mac_runs_count, "windowsRuns": 1, "externalAXStatuses": sorted({r["externalAXStatus"] for r in report_runs.values()}), "instrumentedStatuses": sorted({r["rawStatus"] for r in report_runs.values()})}

    # Verify semantic adapter from the actual raw source channel, separately from instrumented status.
    comparisons = report["accessibility"]["comparisons"]
    assert report["accessibility"]["roleMap"] == ROLE_MAP
    assert report["accessibility"]["adapter"] == "protected exact AXStaticText to ControlType.Text mapping; no role/name heuristics"
    for key in ("stack", "padding", "preference"):
        mac_runs = report["cases"][key]["macFresh100"]["runs"]
        expected_labels = mac_runs[0]["labels"]
        assert all(r["labels"] == expected_labels for r in mac_runs)
        mapped = [{"role": "ControlType.Text", "value": v} for v in expected_labels]
        assert comparisons[key]["macValues"] == mapped
        assert comparisons[key]["windowsValues"] == mapped
        assert comparisons[key]["exactSequenceMatch"] is True and comparisons[key]["qualification"] == "held"
        assert comparisons[key]["macRawStatuses"] == ["OBSERVED"]

    custom = comparisons["custom"]
    assert custom["qualification"] == "held" and custom["exactSequenceMatch"] is False
    assert custom["windowsValues"] == [] and custom["macValues"] == []
    assert "held" in custom["macExternalAX"]

    scroll = comparisons["scroll"]
    scroll_runs = report["cases"]["scroll"]["macFresh100"]["runs"]
    win_labels = report["cases"]["scroll"]["windowsSeedSingle"]["row"]["uiaLabels"]
    mac_values = scroll_runs[0]["labels"]
    assert all(r["labels"] == mac_values for r in scroll_runs)
    assert scroll["macValues"] == [{"role": "ControlType.Text", "value": v} for v in mac_values]
    assert scroll["windowsValues"] == [{"role": "ControlType.Text", "value": v} for v in win_labels]
    assert mac_values == win_labels
    assert {r["externalAXStatus"] for r in scroll_runs} == {"OBSERVED"}
    assert {r["rawStatus"] for r in scroll_runs} == {"UNOBSERVED"}
    assert scroll["macRawStatuses"] == ["UNOBSERVED"] and scroll["exactSequenceMatch"] is False
    assert scroll["qualification"] == "held" and "instrumented raw status UNOBSERVED" in scroll["reason"]
    assert scroll["windowsValues"] == scroll["macValues"]  # raw equality is retained, never elevated to exactSequenceMatch

    # Guard claim boundary and raw timing separation.
    claims = report["claims"]
    assert claims["nativeParity"] == claims["qualifiedParity"] == claims["qualifiedPaint"] == "held"
    assert claims["compilerOSOrigin"] == "missing" and claims["goldens"] == 0 and claims["registryPromotion"] is False
    assert "UNOBSERVED" in claims["scrollRaw20"] and "no cross-host sequence claim" in claims["scrollRaw20"]
    assert report["rawTiming"]["scope"] == "raw timestamps & clock hashes retained; no timing claim"
    return {
        "decision": "clear-bounded-observation-with-distinct-scroll-channels",
        "stageManifestSha256": "sha256:" + digest(STAGE / "stage-manifest.json"),
        "macRuns": mac_run_total,
        "windowsSeedSingles": win_total,
        "caseCount": len(CASES),
        "scroll": {
            "labelsSource": "external-ax.raw.json AXStaticText",
            "externalAXStatusRuns": 20,
            "instrumentedStatusSource": "instrumented.raw.json status",
            "instrumentedStatusRuns": 20,
            "externalAXStatus": "OBSERVED",
            "instrumentedStatus": "UNOBSERVED",
            "valuesEqualRawly": True,
            "sequenceMatchClaim": False,
        },
        "claims": {"nativeParity": "held", "qualifiedParity": "held", "qualifiedPaint": "held", "compilerOSOrigin": "missing", "goldens": 0},
    }


if __name__ == "__main__":
    check_stage_files()
    print(json.dumps(review(), sort_keys=True, indent=2))
