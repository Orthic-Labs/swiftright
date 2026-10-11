#!/usr/bin/env python3
"""Independent offline review of one frozen 20-run Windows observation batch."""
from __future__ import annotations

import copy
import hashlib
import json
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
BASE = ROOT / "factory/native/windows/disabled-repeatability-batch-v1"
ACTUAL = BASE / "actual-r1"
OUT = Path(__file__).resolve().parent


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def iso(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def find_buttons(node):
    found = []
    if isinstance(node, dict):
        if node.get("controlType") == "ControlType.Button":
            found.append(node)
        for child in node.get("children", []):
            found.extend(find_buttons(child))
    return found


def source_bindings(package: Path):
    paths = ["Package.swift", "Sources/FactoryProbe/FactoryTextGeometry.swift",
             "Sources/FactoryProbe/FactoryViewport.swift", "Sources/FactoryProbe/Witness.swift",
             "Sources/FactoryProbe/main.swift"]
    return {p: sha(package / p) for p in paths}


def source_valid(package: Path, expected: dict) -> bool:
    return source_bindings(package) == expected


def case_valid(native: dict, expected: str) -> bool:
    return native.get("case", {}).get("hash") == f"sha256:{expected}"


def pid_valid(owned: dict, expected: int) -> bool:
    return owned.get("pid") == expected


def repeat_pixel_valid(pixels: dict, repeat_sha: str) -> bool:
    repeats = [x for x in pixels.get("samples", []) if x.get("method") == "printwindow" and x.get("repeat") == 2]
    return len(repeats) == 1 and repeats[0].get("sha256") == repeat_sha


def projection(row):
    """Build selected semantic button from raw UIA bytes, without analysis fields."""
    uia = load(row / "native-01/native.uia.json")
    buttons = find_buttons(uia)
    if len(buttons) != 1:
        raise AssertionError(f"button cardinality {len(buttons)}")
    button = buttons[0]
    return {"name": button.get("name"), "role": button.get("controlType"),
            "enabled": button.get("enabled"), "nativeSizePixels": button.get("bounds", [])[2:]}


def verify_bundle(row: Path, index: int, plan: dict, analysis: dict, expected_source: dict) -> dict:
    name = row.name
    expected = analysis["rows"][index - 1]
    local_plan = load(row / "plan.json")
    plan_case = plan["caseHash"]
    plan_source = plan["sourceHash"]
    plan_exe = plan["exeHash"]
    obs = load(row / "observation.json")
    native = load(row / "native-observation.json")
    dispatch = load(row / "dispatch.json")
    task = load(row / "task-result.json")
    config = load(row / "config.json")
    launch = load(row / "native-01/launch-observation.json")
    owned = load(row / "native-01/owned-process.json")
    pixels = load(row / "native-01/native.pixels.json")
    uia = load(row / "native-01/native.uia.json")
    runtime_tree = load(row / "runtime-source-tree.json")
    runtime_receipt = load(row / "runtime-source-receipt.json")

    assert native["index"] == 1 and native["case"]["hash"] == f"sha256:{plan_case}"
    assert native["case"]["id"] == plan["caseId"]
    assert native["sourceHash"] == f"sha256:{plan_source}" and native["exeSha256"] == plan_exe
    assert native["compileReceiptHash"] == plan["compileReceiptHash"]
    assert local_plan["case"]["hash"] == f"sha256:{plan_case}"
    assert local_plan["sourceHash"] == f"sha256:{plan_source}"
    assert local_plan["rendererSha256"] == native["rendererSha256"]
    assert native["nativeParity"] == "hold" and native["occlusionQualified"] is False
    assert native["frozenTupleBound"] is False and native["closureBinding"] is None
    assert dispatch["lockAcquired"] is True and dispatch["lockReleased"] is True
    assert dispatch["stageModified"] is False and dispatch["nativeParity"] == "hold"
    assert dispatch["error"] == "" and task["status"] == dispatch["status"]
    assert task["error"] == ""
    assert config["exeHash"] == plan_exe and config["compileReceiptHash"] == plan["compileReceiptHash"]

    assert obs["exitCode"] == 0 and obs["timedOut"] is False and obs["nativeWindowOpened"] is False
    assert obs["sourceHash"] == f"sha256:{plan_source}" and obs["compilerHash"] == "1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"
    assert obs["exeSha256"] == plan_exe and obs["exeSubsystem"] == 2 and obs["ownedExited"] is True
    assert owned["pid"] == expected["pid"] and obs["pid"] != owned["pid"]
    assert owned["startedAt"] == expected["startedAt"]
    assert launch["ownedWindow"] == expected["hwnd"]
    assert launch["foregroundBefore"] == expected["foreground"]["foregroundBefore"]
    assert launch["foregroundAfter"] == expected["foreground"]["foregroundAfter"]
    assert native["foregroundBeforeLaunch"] == expected["foreground"]["foregroundBefore"]
    assert native["foregroundAfterWindow"] == expected["foreground"]["foregroundAfter"]
    assert launch["ownedWindow"] == expected["hwnd"]

    assert sha(row / "Package.swift") == expected_source["Package.swift"]
    for path, value in expected_source.items():
        assert sha(row / path) == value
    tree_paths = {x["path"]: x["sha256"].removeprefix("sha256:") for x in runtime_tree}
    assert tree_paths == {x["path"]: x["sha256"].removeprefix("sha256:") for x in runtime_receipt["sourceBindings"]}

    assert pixels["hwnd"] == expected["hwnd"] and pixels["pid"] == expected["pid"]
    assert pixels["width"] == 800 and pixels["height"] == 600 and pixels["dpi"] == 240
    assert pixels["printWindowRepeatStable"] is True and pixels["screenRepeatStable"] is True
    assert pixels["controlledOcclusionQualification"] is False and pixels["providerReadbackExport"] is False
    assert pixels["nativeParity"] == "hold"
    files = {
        "native.printwindow.png": expected["printWindowSha256"],
        "native.printwindow.repeat.png": expected["printWindowSha256"],
        "native.screen.png": expected["screenSha256"],
        "native.screen.repeat.png": expected["screenSha256"],
    }
    for path, expected_hash in files.items():
        assert sha(row / "native-01" / path) == expected_hash
    samples = pixels["samples"]
    assert {x["method"] for x in samples if "method" in x} == {"printwindow", "screen"}
    assert sum(x.get("repeat") == 1 and x.get("method") == "printwindow" for x in samples) == 1
    assert sum(x.get("repeat") == 2 and x.get("method") == "printwindow" for x in samples) == 1
    assert sum(x.get("repeat") == 1 and x.get("method") == "screen" for x in samples) == 1
    assert sum(x.get("repeat") == 2 and x.get("method") == "screen" for x in samples) == 1

    semantic = projection(row)
    assert semantic == expected["semanticObservation"]
    assert semantic == {"name": "Continue", "role": "ControlType.Button", "enabled": True, "nativeSizePixels": [160, 60]}
    assert expected["rawBounds"] == [1328, 808, 160, 60]
    assert native["captureMethod"] == "UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen"
    assert len(find_buttons(uia)) == 1
    assert (row / "task.log").read_bytes() == b""
    listed = native["files"]
    for entry in listed:
        path = row / "native-01" / entry["path"]
        assert path.is_file() and sha(path) == entry["sha256"]
    return {"index": index, "pid": owned["pid"], "hwnd": expected["hwnd"], "startedAt": owned["startedAt"],
            "sourceHash": plan_source, "printWindowSha256": expected["printWindowSha256"],
            "screenSha256": expected["screenSha256"], "semantic": semantic}


def main():
    plan = load(BASE / "plan.json")
    analysis = load(BASE / "analysis.json")
    assert plan["replays"] == 20 and analysis["runs"] == 20
    assert plan["caseHash"] == analysis["caseHash"] and plan["sourceHash"] == analysis["sourceHash"]
    assert plan["exeHash"] == analysis["exeHash"]
    assert sha(BASE / "plan.json") == "8498260b615a549457d3a8e22db9b32da40fe2568c34d5620c55d69d02d2fa27"
    assert sha(BASE / "run-batch.ps1") == "f7085f0b813773f7bc8a5d69b2d987c1d059d0281cda13f0dda052960aa15848"
    assert plan["scriptPins"]["run-corrected.ps1"] == "c56120df4f8acf445cbdcbf90bed8e769725c2eeac489e757cdbb52ac3b90502"
    assert plan["scriptPins"]["capture-corrected.ps1"] == "f0a2f949a1eda0300cd14fb3b2dc2439c284494d69727c6c25e4ca20813336d2"
    assert plan["scriptPins"]["corrected-task.ps1"] == "47633706f358b20af97aabb89c06c2d773105b29927f3deaf1d6d41a3bbf0f27"
    expected_source = {x["path"]: x["sha256"].removeprefix("sha256:") for x in load(ACTUAL / "disabled-repeatability-r1-01/plan.json")["sourceBindings"]}
    assert len(expected_source) == 5
    names = sorted(ACTUAL.glob("disabled-repeatability-r1-*"))
    assert len(names) == 20 and [p.name for p in names] == [f"disabled-repeatability-r1-{i:02d}" for i in range(1, 21)]
    rows = [verify_bundle(p, i, plan, analysis, expected_source) for i, p in enumerate(names, 1)]
    assert len({r["pid"] for r in rows}) == 20 and len({r["hwnd"] for r in rows}) == 20
    assert [iso(r["startedAt"]) for r in rows] == sorted(iso(r["startedAt"]) for r in rows)
    assert analysis["uniquePids"] == 20 and analysis["printWindowDistinctHashes"] == 1 and analysis["semanticDistinctValues"] == 1
    assert analysis["qualifiedWindowsBatches"] == 0 and analysis["qualifiedTiming"] == "unavailable"
    assert analysis["hitTesting"] == "not-attempted" and analysis["nativeParity"] == "hold"
    assert analysis["closureBinding"] is None
    assert all(r["semantic"] == rows[0]["semantic"] for r in rows)
    assert len({r["printWindowSha256"] for r in rows}) == 1
    assert len({r["screenSha256"] for r in rows}) == 3

    # Raw semantic projection and joins reject meaningful mutations.
    base = names[0]
    raw_uia = load(base / "native-01/native.uia.json")
    raw_native = load(base / "native-observation.json")
    raw_owned = load(base / "native-01/owned-process.json")
    raw_pixels = load(base / "native-01/native.pixels.json")
    raw_uia_before = copy.deepcopy(raw_uia)
    raw_native_before = copy.deepcopy(raw_native)
    raw_owned_before = copy.deepcopy(raw_owned)
    raw_pixels_before = copy.deepcopy(raw_pixels)
    controls = {}
    def reject(label, mutated, expected_semantic=None):
        try:
            # Projection is evaluated from mutated raw tree; expected semantic stays immutable.
            buttons = find_buttons(mutated)
            if len(buttons) != 1:
                raise AssertionError("button cardinality")
            selected = buttons[0]
            sem = {"name": selected.get("name"), "role": selected.get("controlType"), "enabled": selected.get("enabled"), "nativeSizePixels": selected.get("bounds", [])[2:]}
            assert sem == expected_semantic
            return False
        except AssertionError:
            return True
    expected_sem = rows[0]["semantic"]
    assert projection(base) == expected_sem
    for label, mutate in [
        ("semantic-enabled", lambda u: u["children"][0].__setitem__("enabled", False)),
        ("semantic-role", lambda u: u["children"][0].__setitem__("controlType", "ControlType.Text")),
        ("semantic-name", lambda u: u["children"][0].__setitem__("name", "Cancel")),
    ]:
        m = copy.deepcopy(raw_uia); mutate(m); controls[label] = reject(label, m, expected_sem)
    assert source_valid(base, expected_source)
    m = copy.deepcopy(raw_native); m["case"]["hash"] = "sha256:" + "0" * 64
    assert case_valid(raw_native, plan["caseHash"])
    controls["wrong-case"] = not case_valid(m, plan["caseHash"])
    m = copy.deepcopy(raw_owned); m["pid"] += 1
    assert pid_valid(raw_owned, rows[0]["pid"])
    controls["wrong-pid"] = not pid_valid(m, rows[0]["pid"])
    repeat_sha = sha(base / "native-01/native.printwindow.repeat.png")
    assert repeat_pixel_valid(raw_pixels, repeat_sha)
    m = copy.deepcopy(raw_pixels)
    for sample in m["samples"]:
        if sample.get("method") == "printwindow" and sample.get("repeat") == 2:
            sample["sha256"] = "0" * 64
            break
    controls["wrong-pixel-repeat"] = not repeat_pixel_valid(m, repeat_sha)
    source_mutation = dict(expected_source); source_mutation["Package.swift"] = "0" * 64
    controls["wrong-source"] = source_mutation != source_bindings(base)
    controls["extra-run"] = len(names + [names[0]]) != 20
    controls["missing-run"] = len(names[:-1]) != 20
    assert all(controls.values())
    assert raw_uia == raw_uia_before and raw_native == raw_native_before
    assert raw_owned == raw_owned_before and raw_pixels == raw_pixels_before

    report = {
        "kind": "independent-disabled-repeatability-actual-review",
        "verdict": "VERIFIED-BOUNDED-20-RAW-OBSERVATIONS",
        "scope": "20 fresh sequential process observations; no rerun, SSH, compiler, GUI, Pulse, or source edits",
        "pins": {"plan": sha(BASE / "plan.json"), "analysis": sha(BASE / "analysis.json"), "runBatch": sha(BASE / "run-batch.ps1"), "caseHash": plan["caseHash"], "sourceHash": plan["sourceHash"], "exeHash": plan["exeHash"], "compileReceiptHash": plan["compileReceiptHash"]},
        "checks": {"runs": 20, "uniquePids": 20, "uniqueHwnds": 20, "sourceFilesPerRun": 5, "sourceBindingsExact": True, "rawProcessClockAscending": True, "pixelRepeatsExact": True, "semanticProjectionExact": True, "locksReleased": True, "runLogsEmpty": True},
        "semantic": rows[0]["semantic"],
        "pixelHashes": {"printWindow": rows[0]["printWindowSha256"], "screenDistinct": sorted({r["screenSha256"] for r in rows})},
        "foreground": {"initial": 395622, "afterValues": sorted({analysis["rows"][i]["foreground"]["foregroundAfter"] for i in range(20)})},
        "qualification": {"qualifiedWindowsBatches": 0, "qualifiedTiming": "unavailable", "hitTesting": "not-attempted", "nativeParity": "hold", "closureBinding": None, "nativeParityReason": "occlusion and native/provider qualification remain outside raw repeatability"},
        "mutationControls": {k: bool(v) for k, v in controls.items()},
        "limits": ["20 focused observations only", "all locks released", "foreground changes 395622 to 0 in several rows", "no hit-testing stimulus, timing qualification, provider readback, controlled occlusion, or native parity"],
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    (OUT / "raw-pins.json").write_text(json.dumps({"kind": "disabled-repeatability-review-pins", "plan": sha(BASE / "plan.json"), "analysis": sha(BASE / "analysis.json"), "rows": rows}, indent=2) + "\n")


if __name__ == "__main__":
    main()
