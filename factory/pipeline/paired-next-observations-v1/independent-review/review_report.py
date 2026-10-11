#!/usr/bin/env python3
"""Independent raw-input and report consistency check; no producer imports."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = ROOT / "factory/pipeline/paired-next-observations-v1"
REPORT = PACKET / "evidence/report-v1.json"
INPUTS = PACKET / "source-inputs-v1.json"
EXPECTED = {
    "swiftui.padding-frame": {
        "caseId": "swiftui.padding-frame.recipe/case/8805e6d0729b052d",
        "caseSha256": "58a7c081166141df0b496c4b9ccd0043731d03048993f27842b171387d5c4d5b",
        "sourceSha256": "b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b",
        "macRoot": "factory/native/macos/evidence/20261010-primary-next-five/swiftui.padding-frame.recipe_case_8805e6d0729b052d",
        "windowsRoot": "factory/native/windows/round1-native-v3/single-padding-frame-r1",
        "labels": ["Box"],
    },
    "swiftui.preference-key": {
        "caseId": "swiftui.preference-key.recipe/case/66b6b44aaff817d6",
        "caseSha256": "b2292465cf5f9857b92345a973fc413611365606aec12c9dc435f14ed62bc96d",
        "sourceSha256": "e104e949a6e0f8c6e9e41a6d2d7815a112a40e19d5919b82d2074fd7f5bf9c1f",
        "macRoot": "factory/native/macos/evidence/20261010-corrected-primary/swiftui.preference-key.recipe_case_66b6b44aaff817d6",
        "windowsRoot": "factory/native/windows/round1-native-v3/single-preference-key-r1",
        "labels": ["0", "1", "2"],
    },
    "swiftui.scroll-view": {
        "caseId": "swiftui.scroll-view.recipe/case/6716afb4fb55269b",
        "caseSha256": "56c2625f63e7e633c18ea0cdfca37545748f1d098622391e3c270be07895dc98",
        "sourceSha256": "cd6615468e11e0137c6e1c9ada25c0cdf2f5a0f4c33668ec63161674b743a2c4",
        "macRoot": "factory/native/macos/evidence/20261010-primary-next-five/swiftui.scroll-view.recipe_case_6716afb4fb55269b",
        "windowsRoot": "factory/native/windows/round1-native-v4/single-scroll-r1",
        "labels": ["Row 0", "Row 1", "Row 2", "Row 3"],
    },
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)


def labels(tree, key, role):
    return [node[key] for node in walk(tree) if node.get("controlType" if role.startswith("ControlType") else "role") == role
            and isinstance(node.get(key), str)]


def run() -> dict:
    report_bytes, input_bytes = REPORT.read_bytes(), INPUTS.read_bytes()
    report, source_manifest = load(REPORT), load(INPUTS)
    assert report["schema"] == "paired-next-observational-report-v1"
    assert report["status"] == "source-bound-observation-only"
    assert report["inputManifestSha256"] == digest(input_bytes)
    assert digest(input_bytes) == "7ac004e1aa4e250e14b5b604eaffc450defa366addcc10608a828b61cb3d79d1"
    assert source_manifest["caseCount"] == 3 and len(source_manifest["inputs"]) == 409
    assert source_manifest["cases"] == {k: {n: v[n] for n in ("caseId", "caseSha256", "sourceSha256", "macRoot", "windowsRoot")}
                                         for k, v in EXPECTED.items()}

    payloads = {}
    input_refs = {}
    for row in source_manifest["inputs"]:
        assert row["path"] not in payloads
        raw = (ROOT / row["path"]).read_bytes()
        assert len(raw) == row["bytes"] and digest(raw) == row["sha256"], row["path"]
        payloads[row["path"]] = raw
        input_refs[row["path"]] = row

    stage = load(PACKET / "stage-manifest-v1.json")
    assert stage["sourceInputCount"] == len(input_refs)
    assert stage["sourceInputManifestSha256"] == digest(input_bytes)
    for row in stage["files"]:
        raw = (PACKET / row["path"]).read_bytes()
        assert len(raw) == row["bytes"] and digest(raw) == row["sha256"], row["path"]

    assert set(report["cases"]) == set(EXPECTED)
    checks = {}
    for block, expected in EXPECTED.items():
        actual = report["cases"][block]
        assert actual["identity"] == {k: expected[k] for k in ("caseId", "caseSha256", "sourceSha256")}
        assert actual["macOS"]["runs"] == 20 and actual["windows"]["runs"] == 1
        assert len(actual["macOS"]["runObservations"]) == 20
        assert len(actual["accessibilityComparisons"]) == 20
        summary_path = expected["macRoot"] + "/summary.json"
        summary = json.loads(payloads[summary_path].decode("utf-8-sig"))
        assert summary["case"]["id"] == expected["caseId"]
        assert summary["case"]["hash"] == "sha256:" + expected["caseSha256"]
        assert summary["provenance"]["sourceHash"] == "sha256:" + expected["sourceSha256"]
        assert summary["probeManifest"]["sourceHash"] == "sha256:" + expected["sourceSha256"]
        assert summary["candidateOnly"] is True and summary["independentProcessesPerRun"] is True
        assert len(summary["runs"]) == 20
        mac_values = []
        owners, clients = set(), set()
        for i, row in enumerate(actual["macOS"]["runObservations"], start=1):
            run = f"{expected['macRoot']}/run-{i:03d}"
            raw_ax = json.loads(payloads[run + "/external-ax.raw.json"].decode("utf-8-sig"))
            capture = json.loads(payloads[run + "/capture.json"].decode("utf-8-sig"))
            raw_ax_bytes, capture_bytes = payloads[run + "/external-ax.raw.json"], payloads[run + "/capture.json"]
            assert raw_ax["status"] == "OBSERVED" and raw_ax["permissionRequests"] is False
            assert raw_ax["mode"] == "fresh-external-ax"
            assert raw_ax["windowTitle"] == "SwiftRightFactory-" + expected["caseId"]
            assert capture["case"]["id"] == expected["caseId"]
            assert capture["case"]["hash"] == "sha256:" + expected["caseSha256"]
            row_summary = [s for s in summary["runs"] if s["run"] == i]
            assert len(row_summary) == 1
            assert row_summary[0]["externalAXRawHash"] == "sha256:" + digest(raw_ax_bytes)
            assert row_summary[0]["captureHash"] == "sha256:" + digest(capture_bytes)
            found = [node["value"] for node in walk(raw_ax["steps"][0]["tree"])
                     if node.get("role") == "AXStaticText" and isinstance(node.get("value"), str)
                     and node["value"] != raw_ax["windowTitle"]]
            assert found == expected["labels"]
            assert row["run"] == i and [x["value"] for x in row["labels"]] == found
            assert row["ownerPid"] == raw_ax["pid"] and row["clientPid"] == raw_ax["clientPID"]
            assert row["ownerPid"] not in owners and row["clientPid"] not in clients
            owners.add(row["ownerPid"]); clients.add(row["clientPid"])
            mac_values.append(found)
            compositor_raw = payloads[run + "/compositor.raw.json"]
            compositor_png = payloads[run + "/compositor.png"]
            paint_raw = json.loads(compositor_raw.decode("utf-8-sig"))
            capture_images = [img for img in capture["images"] if img.get("id") == "macos.compositor"]
            assert len(capture_images) == 1 and capture_images[0]["hash"] == "sha256:" + digest(compositor_png)
            assert paint_raw["status"] == "OBSERVED" and paint_raw["permissionRequests"] is False
            assert row["paint"]["compositorPngRawSha256"] == digest(compositor_png)
            assert row["paint"]["compositorRawInputSha256"] == digest(compositor_raw)
            expected_raw_paths = {
                "externalAX": run + "/external-ax.raw.json", "capture": run + "/capture.json",
                "clock": run + "/clock.json", "compositorRaw": run + "/compositor.raw.json",
                "compositorPng": run + "/compositor.png",
            }
            assert row["rawInputs"] == {name: input_refs[path]["sha256"] for name, path in expected_raw_paths.items()}

        winroot = expected["windowsRoot"] + "/replays/run-001"
        native_root = winroot + "/native-01"
        plan = json.loads(payloads[winroot + "/plan.json"].decode("utf-8-sig"))
        native = json.loads(payloads[winroot + "/native-observation.json"].decode("utf-8-sig"))
        obs = json.loads(payloads[winroot + "/observation.json"].decode("utf-8-sig"))
        uia = json.loads(payloads[native_root + "/native.uia.json"].decode("utf-8-sig"))
        pixels = json.loads(payloads[native_root + "/native.pixels.json"].decode("utf-8-sig"))
        assert plan["kind"] == "windows-observational-plan"
        assert native["nativeParity"] == "hold" and native["frozenTupleBound"] is False
        assert native["closureBinding"] is None and native["occlusionQualified"] is False
        assert obs["exitCode"] == 0 and obs["timedOut"] is False
        windows = [node["name"] for node in walk(uia) if node.get("controlType") == "ControlType.Text"]
        assert windows == expected["labels"]
        assert actual["windows"]["observation"]["uia"] == [{"role": "ControlType.Text", "value": x} for x in windows]
        assert len(actual["accessibilityComparisons"]) == 20
        for observed, comparison in zip(mac_values, actual["accessibilityComparisons"]):
            assert comparison["roleMap"] == {"AXStaticText": "ControlType.Text"}
            assert comparison["macMappedValues"] == [{"role": "ControlType.Text", "value": x} for x in observed]
            assert comparison["windowsValues"] == [{"role": "ControlType.Text", "value": x} for x in windows]
            assert comparison["exactSequenceMatch"] is True
            assert comparison["qualification"] == "not-claimed"
        assert pixels["screenRepeatStable"] is True and pixels["printWindowRepeatStable"] is True
        expected_packet_paths = sorted(p for p in input_refs if p.startswith(expected["macRoot"] + "/")
                                       or p.startswith(expected["windowsRoot"] + "/"))
        assert actual["inputPaths"] == expected_packet_paths
        assert actual["windows"]["observation"]["qualification"]["nativeParity"] == "held"
        assert actual["timingDisposition"] == "raw-clock-values-retained; no cross-platform timing comparison"
        checks[block] = {"macRuns": 20, "windowsRuns": 1, "labels": expected["labels"],
                         "semanticMatches": 20, "distinctMacOwnerPids": len(owners),
                         "distinctMacClientPids": len(clients), "windowsNativeParity": "held"}

    qual = report["qualification"]
    assert qual == {"acceptedGoldenCount": 0, "nativeParity": "held", "timingParity": "held",
                    "pixelParity": "held", "controlledOcclusion": "not-qualified",
                    "hitTesting": "not-attempted", "providerReadback": "unavailable",
                    "semanticPromotion": "not-requested"}
    test_log = (PACKET / "evidence-tests.stderr.txt").read_text()
    assert "Ran 10 tests" in test_log and "OK" in test_log
    return {
        "schema": "paired-next-observation-independent-review-v1",
        "decision": "clear-for-bounded-observational-report",
        "scope": "source/case/raw AX/UIA sequence joins only; 1 Windows capture vs 20 Mac runs per case",
        "producerFiles": {
            "adapterSha256": digest((PACKET / "adapter.py").read_bytes()),
            "testSha256": digest((PACKET / "test_adapter.py").read_bytes()),
            "generatorSha256": digest((PACKET / "generate_report.py").read_bytes()),
            "inputManifestSha256": digest(input_bytes),
            "reportSha256": digest(report_bytes),
        },
        "inputCount": len(payloads),
        "reportBytes": len(report_bytes),
        "cases": checks,
        "testReceipt": "10 tests; recorded producer run passed",
        "held": ["native parity", "pixel parity", "timing parity", "hit-testing",
                 "controlled occlusion", "accepted golden", "20-run Windows batch"],
    }


if __name__ == "__main__":
    output = run()
    target = Path(__file__).resolve().parent / "review-findings-v1.json"
    target.write_text(json.dumps(output, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"decision": output["decision"], "inputCount": output["inputCount"],
                      "reportSha256": output["producerFiles"]["reportSha256"],
                      "output": str(target)}, sort_keys=True))
