#!/usr/bin/env python3
"""Independent byte, source, case, executable and raw-channel review for F9 v4."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = ROOT / "factory/pipeline/paired-stack-custom-actual-v4"
EXPECTED_STAGE = "519df923250e311c7c455f2c6232f5790fab2bcc46297e67ff2c636774621634"
CASES = {
    "stack": {
        "block": "swiftui.stack-overlay",
        "label": "native-v5-stack-overlay",
        "windows": "factory/native/windows/round1-native-v5/repeat-stack-overlay-r1",
        "mac": "factory/native/macos/evidence/20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515",
        "caseId": "swiftui.stack-overlay.recipe/case/aac89c30fbc61515",
        "caseHash": "sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0",
        "sourceHash": "sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee",
        "uiaChildren": 1,
    },
    "custom": {
        "block": "swiftui.custom-layout",
        "label": "native-v5-custom-layout",
        "windows": "factory/native/windows/round1-native-v5/repeat-custom-layout-r1",
        "mac": "factory/native/macos/evidence/20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29",
        "caseId": "swiftui.custom-layout.recipe/case/b30ed0b185e8cb29",
        "caseHash": "sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a",
        "sourceHash": "sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b",
        "uiaChildren": 0,
    },
}


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def inventory(root: Path) -> dict:
    files = []
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix()):
        raw = path.read_bytes()
        files.append({"path": path.relative_to(root).as_posix(), "bytes": len(raw), "sha256": "sha256:" + sha(raw)})
    blob = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"root": root.relative_to(ROOT).as_posix(), "exists": root.exists(), "fileCount": len(files),
            "bytes": sum(x["bytes"] for x in files), "inventorySha256": "sha256:" + sha(blob), "files": files}


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def verify_stage() -> tuple[dict, dict]:
    stage_bytes = (PACKET / "stage-manifest.json").read_bytes()
    assert sha(stage_bytes) == EXPECTED_STAGE
    stage = json.loads(stage_bytes)
    assert stage["kind"] == "f9-paired-stack-custom-actual-v4-stage"
    assert stage["fileCount"] == 4 and stage["totalBytes"] == 920455 and stage["maxBytes"] == 489835
    assert {x["path"] for x in stage["files"]} == {"README.md", "build_report.py", "raw-pins.json", "report.json"}
    for row in stage["files"]:
        raw = (PACKET / row["path"]).read_bytes()
        assert len(raw) == row["bytes"]
        assert "sha256:" + sha(raw) == row["sha256"], row["path"]
    return stage, load(PACKET / "report.json")


def review() -> dict:
    stage, report = verify_stage()
    pins = load(PACKET / "raw-pins.json")
    assert pins["kind"] == "f9-v4-raw-input-pins" and pins["sourceCaseExeBound"] is True
    assert report["kind"] == "f9-paired-stack-custom-actual-v4" and report["version"] == 4
    assert report["candidateOnly"] is True
    assert report["actualCapture"]["sourceBound"] is True
    assert report["actualCapture"]["windows20vs20Available"] is True
    assert report["claims"]["windowsActual20vs20Available"] is True
    assert report["claims"]["qualification"] == report["claims"]["parity"] == "held"
    assert report["claims"]["goldens"] == 0
    assert report["claims"]["timing"] == "unavailable"
    assert report["claims"]["pixelGeometry"] == report["claims"]["color"] == "raw-only"
    assert report["claims"]["occlusion"] == report["claims"]["focus"] == "unavailable"
    assert report["claims"]["nativeDiff"] == "unavailable"

    pin_roots = {row["root"]: row for row in pins["roots"]}
    assert set(pin_roots) == {c["windows"] for c in CASES.values()} | {c["mac"] for c in CASES.values()}
    case_results = {}
    for name, expected in CASES.items():
        winroot = ROOT / expected["windows"]
        macroot = ROOT / expected["mac"]
        # Rebuild full raw inventory from disk, including all files, rather than
        # trusting report's summary counters or the producer's helper.
        for root in (winroot, macroot):
            actual_inventory = inventory(root)
            assert actual_inventory == pin_roots[root.relative_to(ROOT).as_posix()]
        actual = report["actualCapture"]["windowsStack" if name == "stack" else "windowsCustom"]
        assert actual["label"] == expected["label"]
        assert actual["path"] == expected["windows"]
        assert actual["caseHash"] == expected["caseHash"] and actual["sourceHash"] == expected["sourceHash"]
        assert actual["requested"] == 20 and actual["attempted"] == 20 and actual["rowCount"] == 20
        assert actual["successfulRows"] == 20 and actual["integrityPassed"] is True
        assert actual["nativeParity"] == "hold" and actual["retry"] is False
        assert actual["errors"] == []
        batch = load(winroot / "batch.json")
        assert batch["status"] == "completed-20-observational" and batch["requested"] == batch["attempted"] == 20
        assert batch["retry"] is False and len(batch["rows"]) == 20
        assert len({row["index"] for row in batch["rows"]}) == 20
        expected_case_name = "stack-overlay" if name == "stack" else "custom-layout"
        assert batch["case"] == expected_case_name
        assert actual["rawInventory"] == pin_roots[winroot.relative_to(ROOT).as_posix()]
        assert "sha256:" + sha((winroot / "batch.json").read_bytes()) == actual["batchSha256"]
        assert batch["exeHash"] == actual["exeHash"]
        assert batch["compileReceiptHash"] == actual["compileReceiptHash"]

        uia_counts = []
        uia_labels = []
        exe_linked_rows = 0
        for idx, batch_row in enumerate(sorted(batch["rows"], key=lambda x: x["index"]), start=1):
            assert type(batch_row["index"]) is int and batch_row["index"] == idx
            assert batch_row["run"] == f"run-{idx:03d}"
            assert batch_row["status"] == "captured-single-observational-uia-printwindow"
            run = winroot / "replays" / batch_row["run"]
            assert "sha256:" + sha((run / "dispatch.json").read_bytes()) == "sha256:" + batch_row["dispatchHash"]
            dispatch = load(run / "dispatch.json")
            task = load(run / "task-result.json")
            plan = load(run / "plan.json")
            obs = load(run / "observation.json")
            native = load(run / "native-observation.json")
            config = load(run / "config.json")
            capture = load(run / "native-01/capture-outcome.json")
            process = load(run / "native-01/owned-process.json")
            close = load(run / "native-01/owned-close.json")
            launch = load(run / "native-01/launch-observation.json")
            pixels = load(run / "native-01/native.pixels.json")
            uia = load(run / "native-01/native.uia.json")
            assert dispatch["status"] == task["status"] == "captured-single-observational-uia-printwindow"
            assert plan["case"]["id"] == expected["caseId"]
            assert plan["case"]["hash"] == expected["caseHash"] and plan["sourceHash"] == expected["sourceHash"]
            assert obs["sourceHash"] == expected["sourceHash"] and obs["exitCode"] == 0
            assert obs["exeSha256"] == batch["exeHash"]
            assert obs["ownedExited"] is True
            assert native["case"]["hash"] == expected["caseHash"] and native["case"]["id"] == expected["caseId"]
            assert native["sourceHash"] == expected["sourceHash"] and native["exeSha256"] == batch["exeHash"]
            assert native["compileReceiptHash"] == batch["compileReceiptHash"]
            assert native["hostValid"] is True and native["exitCode"] == 0
            assert config["exeHash"] == capture["exeHash"] == batch["exeHash"]
            assert config["compileReceiptHash"] == capture["compileReceiptHash"] == batch["compileReceiptHash"]
            assert capture["sourceHash"] == expected["sourceHash"] and capture["primaryError"] == ""
            assert process["pid"] == capture["ownedIdentity"]["pid"] == close["pid"]
            assert process["path"] == capture["ownedIdentity"]["path"]
            assert process["startedAt"] == capture["ownedIdentity"]["startedAt"]
            assert close["hwnd"] == launch["ownedWindow"] and close["posted"] is True
            assert capture["cleanup"]["confirmedOwnedExit"] is True
            assert capture["stdoutSha256"] == sha((run / "native-01/host.stdout.txt").read_bytes())
            assert capture["stderrSha256"] == sha((run / "native-01/host.stderr.txt").read_bytes())
            assert pixels["width"] == 800 and pixels["height"] == 600 and pixels["dpi"] == 240
            assert pixels["printWindowRepeatStable"] is True
            assert pixels["methodsEqual"] is False and pixels["controlledOcclusionQualification"] is False
            # The native per-run inventory closes on exact bytes, including UIA,
            # PrintWindow and process/capture receipts.
            refs = native["files"]
            assert len({r["path"] for r in refs}) == len(refs)
            for ref in refs:
                raw = (run / "native-01" / ref["path"]).read_bytes()
                assert "sha256:" + sha(raw) == "sha256:" + ref["sha256"].removeprefix("sha256:")
            assert uia["controlType"] == "ControlType.Window"
            assert type(uia["enabled"]) is bool
            children = uia["children"]
            assert type(children) is list and len(children) == expected["uiaChildren"]
            if name == "stack":
                assert len(children) == 1
                assert children[0]["controlType"] == "ControlType.Text"
                assert children[0]["name"] == "+" and type(children[0]["enabled"]) is bool
                uia_labels.append(children[0]["name"])
            else:
                assert children == []
            uia_counts.append(len(children))
            exe_linked_rows += 1
            reported = actual["rows"][idx - 1]
            assert reported["valid"] is True and reported["index"] == idx
            assert reported["uiaChildren"] == len(children)
            assert reported["uiaRootControlType"] == "ControlType.Window"
            assert reported["nativeObservationSha256"] == "sha256:" + sha((run / "native-observation.json").read_bytes())
            assert reported["uiaSha256"] == "sha256:" + sha((run / "native-01/native.uia.json").read_bytes())
            printwindow_hash = "sha256:" + sha((run / "native-01/native.printwindow.png").read_bytes())
            screen_hash = "sha256:" + sha((run / "native-01/native.screen.png").read_bytes())
            assert reported["printWindowSha256"] == printwindow_hash
            assert reported["screenSha256"] == screen_hash
        assert actual["semantic"]["uiaChildrenCounts"] == uia_counts
        assert actual["semantic"]["uiaRootControlType"] == ["ControlType.Window"]
        assert actual["semantic"]["roleLabelEnabled"] == "unavailable"
        if name == "custom":
            assert uia_counts == [0] * 20
            assert report["claims"]["customWindowsUIAChildren"] == "0 in every captured run"
        else:
            assert uia_counts == [1] * 20 and set(uia_labels) == {"+"}

        mac_summary = load(macroot / "summary.json")
        assert report["mac20"][name]["rawInventory"] == pin_roots[macroot.relative_to(ROOT).as_posix()]
        assert report["mac20"][name]["summarySha256"] == "sha256:" + sha((macroot / "summary.json").read_bytes())
        assert mac_summary["block"] == expected["block"]
        assert mac_summary["case"]["id"] == expected["caseId"]
        assert mac_summary["case"]["hash"] == expected["caseHash"]
        assert mac_summary["sourceHash"] == mac_summary["provenance"]["sourceHash"] == mac_summary["probeManifest"]["sourceHash"] == expected["sourceHash"]
        assert len(mac_summary["runs"]) == 20 and mac_summary["candidateOnly"] is True
        assert mac_summary["acceptance"] == "not-promoted"
        if name == "custom":
            assert mac_summary["channels"]["externalAX"] == "HELD"
            assert report["claims"]["macCustomExternalAX"] == "held in exact Mac20 archive"
        else:
            assert mac_summary["channels"]["externalAX"] == "OBSERVED"

        mac_text_labels = []
        for idx in range(1, 21):
            run = macroot / f"run-{idx:03d}"
            ax = load(run / "external-ax.raw.json")
            assert ax["permissionRequests"] is False
            assert ax["windowTitle"] == "SwiftRightFactory-" + expected["caseId"]
            texts = [node["value"] for node in walk(ax["steps"][0]["tree"])
                     if node.get("role") == "AXStaticText" and isinstance(node.get("value"), str)]
            if name == "stack":
                assert texts == ["+"]
                mac_text_labels += texts
            else:
                # Raw snapshots expose host chrome only; no target text is
                # promoted to a meaningful external AX observation.
                assert texts == []
            run_summary = [r for r in mac_summary["runs"] if r.get("run") == idx]
            assert len(run_summary) == 1
            assert run_summary[0].get("status") in (None, "OBSERVED", "candidate")
        case_report = report["mac20"][name]
        assert case_report["runs"] == 20 and case_report["caseHash"] == expected["caseHash"]
        assert case_report["sourceHash"] == expected["sourceHash"]
        case_results[name] = {"windowsRows": 20, "macRuns": 20, "windowsUIAChildren": sorted(set(uia_counts)),
                              "windowsExecutableSourceRowsBound": exe_linked_rows,
                              "macExternalAX": mac_summary["channels"]["externalAX"],
                              "macStackAXTextLabels": sorted(set(mac_text_labels)) if name == "stack" else [],
                              "windowsStackUIATextLabels": sorted(set(uia_labels)) if name == "stack" else [],
                              "crossProviderRoleLabelMatchClaimed": False}

    # No report field maps role/label/enabled state across providers. Stack has
    # raw +/+ text observations on both sides, while custom's Mac AX is held and
    # Windows UIA exposes zero children. Preserve that boundary explicitly.
    for case in report["actualCapture"]["windowsStack"], report["actualCapture"]["windowsCustom"]:
        assert case["semantic"]["shapeLayout"] == "unavailable"
        assert case["semantic"]["roleLabelEnabled"] == "unavailable"
        assert case["semantic"]["screenRepeatStableRaw"] == "raw per-run field retained; not used as qualification"
    assert report["claims"]["semanticChannels"] == "raw UIA child counts plus raw PrintWindow/screen presence only"
    assert report["claims"]["parity"] == "held" and report["claims"]["qualification"] == "held"
    assert report["claims"]["timing"] == "unavailable" and report["claims"]["goldens"] == 0
    assert report["claims"]["pixelGeometry"] == "raw-only" and report["claims"]["color"] == "raw-only"
    assert report["claims"]["occlusion"] == "unavailable" and report["claims"]["focus"] == "unavailable"
    fault_path = Path(__file__).resolve().parent / "fault-controls-replay.stdout.json"
    fault_run = json.loads(fault_path.read_text())
    expected_faults = {"source-hash-mismatch", "case-hash-mismatch", "batch-count-mismatch",
                       "raw-inventory-mismatch", "semantic-mutation", "forged-qualification"}
    assert fault_run["baseline"] == "accepted"
    assert set(fault_run["controls"]) == expected_faults
    assert set(fault_run["controls"].values()) == {"rejected"}
    for receipt in report["reviewReceipts"].values():
        path = ROOT / receipt["path"]
        assert path.is_file() and "sha256:" + sha(path.read_bytes()) == receipt["sha256"]
        assert load(path)["status"] == receipt["status"]
    v3_manifest = ROOT / "factory/pipeline/paired-stack-custom-observation-v3/stage-manifest.json"
    assert "sha256:" + sha(v3_manifest.read_bytes()) == report["priorReports"]["v3StageManifest"]
    return {"schema": "f9-paired-stack-custom-independent-review-v1", "decision": "clear-for-bounded-observational-report",
            "stageManifestSha256": EXPECTED_STAGE, "caseCount": 2, "windowsRunsPerCase": 20,
            "macRunsPerCase": 20, "rawRootCount": len(pins["roots"]), "cases": case_results,
            "semanticBoundary": "raw UIA counts only; stack AX/UIA both show + but no cross-provider role/label/enabled mapping is claimed",
            "faultControls": fault_run["controls"],
            "held": ["custom Mac external AX", "timing", "pixel geometry parity", "color", "occlusion",
                     "focus", "native diff", "parity", "goldens", "qualification"]}


if __name__ == "__main__":
    result = review()
    out = Path(__file__).resolve().parent / "findings-v1.json"
    out.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"decision": result["decision"], "report": "factory/pipeline/paired-stack-custom-actual-v4/report.json",
                      "stageManifestSha256": result["stageManifestSha256"], "cases": result["caseCount"]}, sort_keys=True))
