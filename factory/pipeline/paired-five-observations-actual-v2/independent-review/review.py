#!/usr/bin/env python3
"""Independent raw evidence and report consistency review for F9 actual v1."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = ROOT / "factory/pipeline/paired-five-observations-actual-v1"
EXPECTED_STAGE = "06dbd5dbd2646a53495fca2b1c930a75a8c7b743c18e9a9d7bc735c96ba84eb0"
WINDOWS = ROOT / "factory/native/windows"
MAC = ROOT / "factory/native/macos/evidence"
V5 = WINDOWS / "round1-native-v5"
PREF_V3 = WINDOWS / "round1-native-v3/single-preference-key-r1/replays/run-001"
CASES = {
    "stack": {"id": "swiftui.stack-overlay.recipe/case/aac89c30fbc61515",
              "case": "sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0",
              "source": "sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee",
              "win": V5 / "repeat-stack-overlay-r1",
              "mac": MAC / "20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515",
              "expected": ["+"]},
    "custom": {"id": "swiftui.custom-layout.recipe/case/b30ed0b185e8cb29",
               "case": "sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a",
               "source": "sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b",
               "win": V5 / "repeat-custom-layout-r1",
               "mac": MAC / "20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29",
               "expected": []},
    "padding": {"id": "swiftui.padding-frame.recipe/case/8805e6d0729b052d",
                "case": "sha256:58a7c081166141df0b496c4b9ccd0043731d03048993f27842b171387d5c4d5b",
                "source": "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b",
                "win": V5 / "repeat-padding-frame-r1",
                "mac": MAC / "20261010-primary-next-five/swiftui.padding-frame.recipe_case_8805e6d0729b052d",
                "expected": ["Box"]},
    "scroll": {"id": "swiftui.scroll-view.recipe/case/6716afb4fb55269b",
               "case": "sha256:56c2625f63e7e633c18ea0cdfca37545748f1d098622391e3c270be07895dc98",
               "source": "sha256:cd6615468e11e0137c6e1c9ada25c0cdf2f5a0f4c33668ec63161674b743a2c4",
               "win": V5 / "repeat-scroll-view-r1",
               "mac": MAC / "20261010-primary-next-five/swiftui.scroll-view.recipe_case_6716afb4fb55269b",
               "expected": ["Row 0", "Row 1", "Row 2", "Row 3"]},
    "preference": {"id": "swiftui.preference-key.recipe/case/66b6b44aaff817d6",
                   "case": "sha256:b2292465cf5f9857b92345a973fc413611365606aec12c9dc435f14ed62bc96d",
                   "source": "sha256:e104e949a6e0f8c6e9e41a6d2d7815a112a40e19d5919b82d2074fd7f5bf9c1f",
                   "win": PREF_V3,
                   "mac": MAC / "20261010-corrected-primary/swiftui.preference-key.recipe_case_66b6b44aaff817d6",
                   "expected": ["0", "1", "2"]},
}
ROLE_MAP = {"AXStaticText": "ControlType.Text"}
SUCCESS = "captured-single-observational-uia-printwindow"


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def inventory(root: Path) -> dict:
    files = []
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix()):
        raw = path.read_bytes()
        files.append({"path": path.relative_to(root).as_posix(), "bytes": len(raw), "sha256": "sha256:" + sha(raw)})
    blob = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"root": root.relative_to(ROOT).as_posix(), "exists": root.exists(), "fileCount": len(files),
            "bytes": sum(row["bytes"] for row in files), "inventorySha256": "sha256:" + sha(blob), "files": files}


def verify_stage() -> tuple[dict, dict, dict]:
    stage_bytes = (PACKET / "stage-manifest.json").read_bytes()
    assert sha(stage_bytes) == EXPECTED_STAGE
    stage, report, pins = load(PACKET / "stage-manifest.json"), load(PACKET / "report.json"), load(PACKET / "raw-pins.json")
    assert stage["kind"] == "f9-paired-five-observations-actual-v1-stage"
    assert stage["fileCount"] == 4 and stage["totalBytes"] == 3163326
    assert {row["path"] for row in stage["files"]} == {"README.md", "build_report.py", "raw-pins.json", "report.json"}
    for row in stage["files"]:
        raw = (PACKET / row["path"]).read_bytes()
        assert len(raw) == row["bytes"] and "sha256:" + sha(raw) == row["sha256"]
    return stage, report, pins


def extract_mac_labels(ax: dict, window_title: str) -> list[str]:
    return [node["value"] for node in walk(ax.get("steps", [{}])[0].get("tree", {}))
            if node.get("role") == "AXStaticText" and isinstance(node.get("value"), str)
            and node["value"] != window_title]


def review() -> dict:
    stage, report, pins = verify_stage()
    assert report["kind"] == "f9-paired-five-observations-actual-v1" and report["version"] == 1
    assert report["caseCount"] == 5 and report["candidateOnly"] is True
    assert report["claims"]["windows20Cases"] == ["stack", "custom", "padding", "scroll"]
    assert report["claims"]["preferenceWindowsUsableRuns"] == 1
    assert report["claims"]["preferenceV5FailureRetained"] is True
    assert report["claims"]["nativeParity"] == "held" and report["claims"]["qualification"] == "held"
    assert report["claims"]["qualifiedPaint"] == "held" and report["claims"]["focus"] == "held"
    assert report["claims"]["occlusion"] == "held" and report["claims"]["goldens"] == 0
    assert report["claims"]["timing"] == "raw-only"
    assert report["rawTiming"]["scope"] == "retained per-run timestamps & Mac clock JSON hashes; no timing claim"
    assert report["accessibility"]["roleMap"] == ROLE_MAP
    assert report["accessibility"]["adapter"] == "independently reviewed exact AXStaticText to ControlType.Text role mapping"
    assert set(pins) == {"roots"}

    expected_roots = {str(c["win"].relative_to(ROOT)) for c in CASES.values()}
    expected_roots.remove(str(PREF_V3.relative_to(ROOT)))
    expected_roots.add("factory/native/windows/round1-native-v3/single-preference-key-r1/replays/run-001")
    expected_roots.update(str(c["mac"].relative_to(ROOT)) for c in CASES.values())
    expected_roots.add("factory/native/windows/round1-native-v5/repeat-preference-key-r1")
    pin_rows = {row["root"]: row for row in pins["roots"]}
    assert len(pin_rows) == 11 and set(pin_rows) == expected_roots
    actual_pins = {row["root"]: row for row in report["rawPins"]["roots"]}
    assert actual_pins == pin_rows
    for root_label, expected_pin in pin_rows.items():
        actual = inventory(ROOT / root_label)
        assert actual == expected_pin, root_label

    # Each exact 20-run Windows case is independently joined from source files.
    case_results = {}
    for key in ("stack", "custom", "padding", "scroll"):
        c = CASES[key]
        winroot = c["win"]
        batch = load(winroot / "batch.json")
        w_report = report["cases"][key]["windows"]
        assert w_report["mode"] == "windows-native-v5-20"
        assert w_report["path"] == str(winroot.relative_to(ROOT))
        assert w_report["caseId"] == c["id"] and w_report["caseHash"] == c["case"]
        assert w_report["sourceHash"] == c["source"]
        assert w_report["requested"] == w_report["attempted"] == w_report["successfulObservations"] == 20
        assert w_report["nativeParity"] == "held"
        assert batch["requested"] == batch["attempted"] == 20 and batch["retry"] is False
        assert batch["status"] == "completed-20-observational"
        expected_batch_case = {"stack": "stack-overlay", "custom": "custom-layout",
                               "padding": "padding-frame", "scroll": "scroll-view"}[key]
        assert batch["case"] == expected_batch_case
        assert batch["exeHash"] == w_report["exeHash"]
        assert batch["compileReceiptHash"] == w_report["compileReceiptHash"]
        assert "sha256:" + sha((winroot / "batch.json").read_bytes()) == w_report["batchSha256"]
        assert w_report["rawInventory"] == pin_rows[winroot.relative_to(ROOT).as_posix()]
        assert len(batch["rows"]) == 20 and len(w_report["rows"]) == 20
        assert {row["index"] for row in batch["rows"]} == set(range(1, 21))
        assert len({row["index"] for row in batch["rows"]}) == 20

        win_sequences = []
        for idx, (batch_row, report_row) in enumerate(zip(sorted(batch["rows"], key=lambda r: r["index"]), w_report["rows"]), start=1):
            assert type(batch_row["index"]) is int and batch_row["index"] == idx
            assert batch_row["run"] == report_row["run"] == f"run-{idx:03d}"
            assert batch_row["status"] == SUCCESS and report_row["valid"] is True
            run = winroot / "replays" / batch_row["run"]
            assert batch_row["dispatchHash"] == sha((run / "dispatch.json").read_bytes())
            plan, obs = load(run / "plan.json"), load(run / "observation.json")
            native, dispatch = load(run / "native-observation.json"), load(run / "dispatch.json")
            task = load(run / "task-result.json")
            config, capture = load(run / "config.json"), load(run / "native-01/capture-outcome.json")
            pixels, uia = load(run / "native-01/native.pixels.json"), load(run / "native-01/native.uia.json")
            assert plan["case"]["id"] == c["id"] and plan["case"]["hash"] == c["case"]
            assert plan["sourceHash"] == obs["sourceHash"] == native["sourceHash"] == c["source"]
            assert native["case"]["id"] == c["id"] and native["case"]["hash"] == c["case"]
            assert batch["exeHash"] == obs["exeSha256"] == native["exeSha256"] == config["exeHash"] == capture["exeHash"]
            assert batch["compileReceiptHash"] == native["compileReceiptHash"] == config["compileReceiptHash"] == capture["compileReceiptHash"]
            assert obs["exitCode"] == 0 and obs["ownedExited"] is True
            assert native["hostValid"] is True and native["exitCode"] == 0
            assert dispatch["status"] == task["status"] == SUCCESS
            assert capture["sourceHash"] == c["source"] and capture["primaryError"] == ""
            assert pixels["width"] == 800 and pixels["height"] == 600 and pixels["dpi"] == 240
            assert pixels["printWindowRepeatStable"] is True
            assert pixels["methodsEqual"] is False and pixels["controlledOcclusionQualification"] is False
            assert uia["controlType"] == "ControlType.Window" and type(uia["children"]) is list
            values = [node["name"] for node in walk(uia) if node.get("controlType") == "ControlType.Text"
                      and isinstance(node.get("name"), str)]
            assert values == c["expected"]
            win_sequences.append(values)
            assert report_row["caseHash"] == c["case"] and report_row["sourceHash"] == c["source"]
            assert report_row["exeHash"] == batch["exeHash"]
            assert report_row["compileReceiptHash"] == batch["compileReceiptHash"]
            assert report_row["uiaLabels"] == values and report_row["uiaChildren"] == len(uia["children"])
            assert report_row["uiaSha256"] == "sha256:" + sha((run / "native-01/native.uia.json").read_bytes())
            assert report_row["nativeObservationSha256"] == "sha256:" + sha((run / "native-observation.json").read_bytes())
            assert report_row["pixelsSha256"] == "sha256:" + sha((run / "native-01/native.pixels.json").read_bytes())
            assert report_row["printWindowSha256"] == "sha256:" + sha((run / "native-01/native.printwindow.png").read_bytes())
            assert report_row["screenSha256"] == "sha256:" + sha((run / "native-01/native.screen.png").read_bytes())
            expected_timing = {"startedAt": obs.get("startedAt"), "processStartedAt": obs.get("processStartedAt"),
                               "finishedAt": obs.get("finishedAt"), "timedOut": obs.get("timedOut")}
            assert report_row["timingRaw"] == expected_timing
            for ref in native["files"]:
                raw = (run / "native-01" / ref["path"]).read_bytes()
                assert sha(raw) == ref["sha256"].removeprefix("sha256:")

        assert all(seq == win_sequences[0] for seq in win_sequences)
        macroot = c["mac"]
        summary = load(macroot / "summary.json")
        mac_report = report["cases"][key]["mac20"]
        assert mac_report["caseId"] == c["id"] and mac_report["caseHash"] == c["case"]
        assert mac_report["sourceHash"] == c["source"] and mac_report["runs"]
        assert len(mac_report["runs"]) == 20
        assert mac_report["summarySha256"] == "sha256:" + sha((macroot / "summary.json").read_bytes())
        assert mac_report["rawInventory"] == pin_rows[macroot.relative_to(ROOT).as_posix()]
        assert summary["case"]["id"] == c["id"] and summary["case"]["hash"] == c["case"]
        assert summary["sourceHash"] == summary["provenance"]["sourceHash"] == summary["probeManifest"]["sourceHash"] == c["source"]
        assert summary["acceptance"] == "not-promoted" and summary["candidateOnly"] is True
        assert len(summary["runs"]) == 20
        mac_sequences = []
        owner_pids, client_pids = set(), set()
        for idx, (summary_row, report_row) in enumerate(zip(summary["runs"], mac_report["runs"]), start=1):
            assert summary_row["run"] == idx and report_row["run"] == idx
            run = macroot / f"run-{idx:03d}"
            ax_bytes, capture_bytes, clock_bytes = [(run / filename).read_bytes()
                                                     for filename in ("external-ax.raw.json", "capture.json", "clock.json")]
            ax, capture, clock = load(run / "external-ax.raw.json"), load(run / "capture.json"), load(run / "clock.json")
            assert summary_row["externalAXRawHash"] == "sha256:" + sha(ax_bytes)
            assert summary_row["captureHash"] == "sha256:" + sha(capture_bytes)
            assert capture["case"]["id"] == c["id"] and capture["case"]["hash"] == c["case"]
            assert ax["permissionRequests"] is False
            assert ax["windowTitle"] == "SwiftRightFactory-" + c["id"]
            values = extract_mac_labels(ax, ax["windowTitle"])
            assert values == c["expected"]
            mac_sequences.append(values)
            assert report_row["labels"] == values
            assert report_row["rawAXSha256"] == "sha256:" + sha(ax_bytes)
            assert report_row["captureSha256"] == "sha256:" + sha(capture_bytes)
            assert report_row["clockSha256"] == "sha256:" + sha(clock_bytes)
            assert report_row["timingRaw"] == clock
            assert report_row["ownerPid"] == ax["pid"] and report_row["clientPid"] == ax["clientPID"]
            assert ax["pid"] not in owner_pids and ax["clientPID"] not in client_pids
            owner_pids.add(ax["pid"]); client_pids.add(ax["clientPID"])
        assert all(seq == mac_sequences[0] for seq in mac_sequences)
        comparison = report["accessibility"]["comparisons"][key]
        assert comparison["roleMap"] == ROLE_MAP
        if key == "custom":
            assert comparison["macExternalAX"] == "held"
            assert comparison["windowsValues"] == []
            assert comparison["exactSequenceMatch"] is False
            assert comparison["qualification"] == "not-claimed"
            case_results[key] = {"windowsRuns": 20, "macRuns": 20, "windowsUIAChildrenPerRun": 0,
                                 "macExternalAX": "held", "semanticMatchClaimed": False}
            continue
        expected_win_mapped = [{"role": "ControlType.Text", "value": value} for value in win_sequences[0]]
        expected_mac_mapped = [{"role": "ControlType.Text", "value": value} for value in mac_sequences[0]]
        assert comparison["windowsValues"] == expected_win_mapped
        assert comparison["macMappedValues"] == expected_mac_mapped
        assert comparison["exactSequenceMatch"] is True and comparison["qualification"] == "not-claimed"
        case_results[key] = {"windowsRuns": 20, "macRuns": 20, "labelSequence": c["expected"],
                             "windowsExecutableCompileSourceRowsJoined": len(win_sequences),
                             "distinctMacOwnerPids": len(owner_pids), "distinctMacClientPids": len(client_pids),
                             "exactRawRoleLabelMatches": 20}

    # Custom Mac AX is not treated as empty content; summary holds that channel.
    custom_summary = load(CASES["custom"]["mac"] / "summary.json")
    assert custom_summary["channels"]["externalAX"] == "HELD"
    custom_cmp = report["accessibility"]["comparisons"]["custom"]
    assert custom_cmp["macExternalAX"] == "held" and custom_cmp["exactSequenceMatch"] is False
    assert custom_cmp["qualification"] == "not-claimed" and custom_cmp["windowsValues"] == []
    assert all(report["cases"]["custom"]["windows"]["rows"][i]["uiaChildren"] == 0 for i in range(20))

    # Preference combines a source-bound v3 usable singleton with retained v5
    # first-run failure; those distinct Windows batches must remain distinct.
    pref = CASES["preference"]
    single = report["cases"]["preference"]["windows"]
    assert single["mode"] == "windows-native-v3-single" and single["successfulObservations"] == 1
    assert single["caseId"] == pref["id"] and single["caseHash"] == pref["case"] and single["sourceHash"] == pref["source"]
    single_root = PREF_V3
    single_run = single_root
    single_plan, single_obs = load(single_run / "plan.json"), load(single_run / "observation.json")
    single_native, single_cfg = load(single_run / "native-observation.json"), load(single_run / "config.json")
    assert single_plan["case"]["id"] == pref["id"] and single_plan["case"]["hash"] == pref["case"]
    assert single_plan["sourceHash"] == single_obs["sourceHash"] == pref["source"]
    assert single_native["case"]["id"] == pref["id"] and single_native["case"]["hash"] == pref["case"]
    assert single_native["sourceHash"] == pref["source"] and single_native["hostValid"] is True
    assert single_cfg["exeHash"] == single_obs["exeSha256"] == single["exeHash"]
    assert single_native["compileReceiptHash"] == single["compileReceiptHash"]
    assert single["rawInventory"] == pin_rows[single_root.relative_to(ROOT).as_posix()]
    pref_single_labels = [node["name"] for node in walk(load(single_run / "native-01/native.uia.json"))
                          if node.get("controlType") == "ControlType.Text" and isinstance(node.get("name"), str)]
    assert pref_single_labels == pref["expected"]
    assert single["rows"][0]["uiaLabels"] == pref_single_labels
    assert single["rows"][0]["timingRaw"] == {"startedAt": single_obs.get("startedAt"),
                                               "processStartedAt": single_obs.get("processStartedAt"),
                                               "finishedAt": single_obs.get("finishedAt"),
                                               "timedOut": single_obs.get("timedOut")}

    failed_root = V5 / "repeat-preference-key-r1"
    failed_batch = load(failed_root / "batch.json")
    failed = report["cases"]["preference"]["v5Failure"]
    assert failed_batch["case"] == "preference-key"
    assert failed_batch["status"] == "hold-batch-error" and failed_batch["requested"] == 20
    assert failed_batch["attempted"] == 1 and failed_batch["retry"] is False
    assert failed_batch["error"] == "First failed dispatch/lock abort; no retries"
    assert failed["requested"] == 20 and failed["attempted"] == 1 and failed["successfulObservations"] == 0
    assert failed["status"] == failed_batch["status"] and failed["retry"] is False
    assert failed["rawInventory"] == pin_rows[failed_root.relative_to(ROOT).as_posix()]
    assert failed["rawInventory"]["fileCount"] == 25
    failed_row = failed_batch["rows"][0]
    failed_run = failed_root / "replays/run-001"
    assert failed_row["index"] == 1 and failed_row["run"] == "run-001" and failed_row["status"] == "hold-harness-error"
    assert failed_row["dispatchHash"] == sha((failed_run / "dispatch.json").read_bytes())
    failed_plan, failed_obs = load(failed_run / "plan.json"), load(failed_run / "observation.json")
    failed_capture, failed_config = load(failed_run / "native-01/capture-outcome.json"), load(failed_run / "config.json")
    assert failed_plan["case"]["id"] == pref["id"] and failed_plan["case"]["hash"] == pref["case"]
    assert failed_plan["sourceHash"] == failed_obs["sourceHash"] == failed_capture["sourceHash"] == pref["source"]
    assert failed_obs["exeSha256"] == failed_batch["exeHash"] == failed_config["exeHash"] == failed_capture["exeHash"]
    assert failed_config["compileReceiptHash"] == failed_batch["compileReceiptHash"] == failed_capture["compileReceiptHash"]
    assert failed_capture["primaryError"] == "Renderer window deadline"
    assert failed_obs["nativeWindowOpened"] is False
    case_results["preference"] = {"macRuns": 20, "usableWindowsObservations": 1,
                                  "v5FirstAttemptStatus": failed["status"], "v5RawFiles": 25,
                                  "labelSequence": pref["expected"], "exactRawRoleLabelMatches": 20}

    for key in CASES:
        expected_win_timing = [row["timingRaw"] for row in report["cases"][key]["windows"]["rows"]]
        expected_mac_timing = [row["timingRaw"] for row in report["cases"][key]["mac20"]["runs"]]
        assert report["rawTiming"]["windows"][key] == expected_win_timing
        assert report["rawTiming"]["mac"][key] == expected_mac_timing

    for name, receipt in report["reviewReceipts"].items():
        path = ROOT / receipt["path"]
        assert path.is_file() and "sha256:" + sha(path.read_bytes()) == receipt["sha256"], name
        referenced = load(path)
        assert referenced.get("status", referenced.get("decision")) == receipt["status"], name

    # Freshly rerun documented fault packet; each mutation tests different
    # source/case/executable/raw/semantic/qualification invariants.
    fault_path = Path(__file__).resolve().parent / "fault-controls.stdout.json"
    controls = json.loads(fault_path.read_text())
    assert controls["baseline"] == "accepted"
    assert set(controls["controls"]) == {"source", "case", "exe", "semantic", "raw", "pref-count", "qualification"}
    assert set(controls["controls"].values()) == {"rejected"}

    return {"schema": "f9-paired-five-independent-review-v1", "decision": "clear-for-bounded-observational-report",
            "stageManifestSha256": EXPECTED_STAGE, "rawRootCount": len(pin_rows), "sourceTreesRehashed": len(pin_rows),
            "cases": case_results, "roleMapping": ROLE_MAP, "faultControls": controls["controls"],
            "custom": {"macExternalAX": "held", "windowsUIAChildrenPerRun": 0, "semanticMatchClaimed": False},
            "held": ["timing qualification", "paint qualification", "focus", "occlusion", "parity", "goldens", "qualification"]}


if __name__ == "__main__":
    result = review()
    target = Path(__file__).resolve().parent / "findings-v1.json"
    target.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"decision": result["decision"], "stageManifestSha256": result["stageManifestSha256"],
                      "rawRoots": result["sourceTreesRehashed"], "cases": len(result["cases"])}, sort_keys=True))
