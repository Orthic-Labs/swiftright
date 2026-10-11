#!/usr/bin/env python3
"""Offline independent review for corrected Windows first-capture packet."""
from __future__ import annotations

import copy
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
CORRECTED = ROOT / "factory/native/windows/first-capture-corrections-v1/actual-corrected-r1"
BUILD = ROOT / "factory/native/windows/first-capture-corrections-v1/build-actual-r1"
ORIGINAL = ROOT / "factory/native/windows/first-capture-readiness-v1/actual-first-r1"
MAC_SUMMARY = ROOT / "factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4/swiftui.disabled.recipe_case_f113195a59446fc4/summary.json"
# Correct path is retained separately below because fixture has one case directory.
MAC_SUMMARY = ROOT / "factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4/summary.json"
STAGE = ROOT / "factory/native/windows/first-capture-corrections-v1/root-stage-manifest.json"
OUT = Path(__file__).resolve().parent


def raw(path: Path) -> bytes:
    return path.read_bytes()


def sha(path: Path) -> str:
    return hashlib.sha256(raw(path)).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def png_size(path: Path) -> tuple[int, int]:
    b = raw(path)
    if b[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"not PNG: {path}")
    return struct.unpack(">II", b[16:24])


def pin_list(root: Path) -> list[dict]:
    return [
        {
            "path": str(p.relative_to(ROOT)),
            "bytes": p.stat().st_size,
            "sha256": sha(p),
        }
        for p in sorted(root.rglob("*"))
        if p.is_file()
    ]


def assert_file_pin(path: Path, expected: str) -> None:
    if not path.is_file() or sha(path) != expected:
        raise AssertionError(f"file pin mismatch: {path}")


def main() -> None:
    obs = load(CORRECTED / "native-observation.json")
    compile_obs = load(CORRECTED / "observation.json")
    plan = load(CORRECTED / "plan.json")
    pixels_path = CORRECTED / "native-01/native.pixels.json"
    pixels = load(pixels_path)
    uia = load(CORRECTED / "native-01/native.uia.json")
    process = load(CORRECTED / "native-01/owned-process.json")
    launch = load(CORRECTED / "native-01/launch-observation.json")
    config = load(CORRECTED / "config.json")
    build_obs = load(BUILD / "observation.json")
    original_obs = load(ORIGINAL / "native-observation.json")
    original_pixels = load(ORIGINAL / "native-01/native.pixels.json")
    mac_summary = load(MAC_SUMMARY)
    stage = load(STAGE)

    expected_source = "sha256:68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
    expected_renderer = "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
    expected_tree = "sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e"
    expected_exe = "62379065c9576702cca26a09f021b2d66ecabf607b3ed93fdd6bfaf5d8cc23f7"
    expected_compile = "203a64759059f526f549767e753e54670aa63e116a2977928790d9ea44d09def"
    expected_plan = "fcee0329217171a63fd39206708be1721dad141dfd31a7b093d5e48f5e870fcb"
    expected_hwnd, expected_pid = 17829170, 57068

    # Every corrected fetched file is hashed independently; receipt pins are checked too.
    corrected_files = pin_list(CORRECTED)
    if len(corrected_files) != 26:
        raise AssertionError(f"expected 26 corrected files, got {len(corrected_files)}")
    for entry in obs["files"]:
        assert_file_pin(CORRECTED / "native-01" / entry["path"], entry["sha256"])
    for entry in compile_obs["files"]:
        # Compile receipt paths are relative to its build-actual-r1 sibling.
        assert_file_pin(BUILD / entry["path"], entry["sha256"])
    assert_file_pin(BUILD / "FactoryProbe.exe", expected_exe)

    # Stage manifest remains independently complete; actual capture/build trees are supplemental.
    stage_checked = []
    stage_missing, stage_bad = [], []
    for entry in stage["files"] + stage["dependencies"]:
        p = ROOT / entry["path"]
        if not p.is_file():
            stage_missing.append(entry["path"])
        elif p.stat().st_size != entry["bytes"] or sha(p) != entry["sha256"]:
            stage_bad.append(entry["path"])
        else:
            stage_checked.append(entry["path"])
    if stage_missing or stage_bad:
        raise AssertionError({"stageMissing": stage_missing, "stageBad": stage_bad})

    # Source/compiler/runtime lineage and actual executable join.
    for x in (obs, compile_obs, plan):
        assert x["sourceHash"] == expected_source
        assert x["rendererSha256"] == expected_renderer
        assert x["runtimeSourceTreeHash"] == expected_tree
    assert compile_obs["planSha256"] == expected_plan
    assert sha(CORRECTED / "plan.json") == expected_plan
    assert obs["compileReceiptHash"] == expected_compile
    assert sha(CORRECTED / "observation.json") == expected_compile
    for x in (obs, compile_obs, config, build_obs):
        if "exeSha256" in x:
            assert x["exeSha256"] == expected_exe
    assert compile_obs["exitCode"] == 0 and compile_obs["timedOut"] is False
    assert build_obs["exitCode"] == 0 and build_obs["timedOut"] is False
    assert compile_obs["nativeWindowOpened"] is False and compile_obs["ownedExited"] is True
    assert compile_obs["compilerHash"] == "1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"

    # Native identity join is exact across process, launch, pixel record, host log and observation.
    assert process["pid"] == expected_pid and pixels["pid"] == expected_pid
    assert pixels["hwnd"] == launch["ownedWindow"] == expected_hwnd
    host_out = (CORRECTED / "native-01/host.stdout.txt").read_text(errors="replace")
    host_err = (CORRECTED / "native-01/host.stderr.txt").read_text(errors="replace")
    ready = re.search(
        r"FACTORY_RENDERER_READY scale=([0-9.]+) width=(\d+) height=(\d+) hwnd=(\d+) pid=(\d+).* dpi=(\d+)",
        host_out,
    )
    assert ready and (ready.group(1), int(ready.group(2)), int(ready.group(3)), int(ready.group(4)), int(ready.group(5)), int(ready.group(6))) == ("2.5", 800, 600, expected_hwnd, expected_pid, 240)
    assert f"hwnd=0x{expected_hwnd:x}" in host_err and "scale=2.5" in host_err

    # Viewport, DPI, UIA and geometry are joined without normalizing disagreement.
    assert (pixels["width"], pixels["height"], pixels["dpi"]) == (800, 600, 240)
    assert png_size(CORRECTED / "native-01/native.printwindow.png") == (800, 600)
    assert png_size(CORRECTED / "native-01/native.screen.png") == (800, 600)
    assert uia["children"][0]["name"] == "Continue"
    assert uia["children"][0]["bounds"][2:] == [160, 60]
    measure = re.search(r"FACTORY_MEASURE text=Continue proposedDIP=([0-9.]+) widthPX=([0-9.]+) heightPX=([0-9.]+) lines=(\d+) scale=([0-9.]+)", host_out)
    assert measure and measure.groups() == ("320.0", "160.27344", "60.0", "1", "2.5")
    retained = re.findall(r"FACTORY_RETAINED_RUN text=Continue widthPX=([0-9.]+) heightPX=([0-9.]+) snappedWidthPX=([0-9.]+) lines=(\d+) proposedDIP=([0-9.]+)", host_out)
    commits = re.findall(r"FACTORY_COMMIT version=(\d+) nodes=(\d+)", host_out)
    assert len(retained) == len(commits) == 606 and retained and all(r == ("160.27344", "60.0", "160.0", "1", "320.0") for r in retained)
    # Host's old initial 2560x1396 diagnostic is retained as distinct from owned 800x600 client.
    assert "client=2560x1396px" in host_err
    assert obs["foregroundBeforeLaunch"] == 395622 and obs["foregroundAfterWindow"] == 0 and obs["probeForegroundAtCapture"] is False

    # Visual evidence proves repeatability only: methods differ and no controlled clean sample exists.
    samples = {s["path"]: s["sha256"] for s in pixels["samples"] if "path" in s}
    assert samples["native.printwindow.png"] == sha(CORRECTED / "native-01/native.printwindow.png")
    assert samples["native.screen.png"] == sha(CORRECTED / "native-01/native.screen.png")
    assert sha(CORRECTED / "native-01/native.printwindow.png") == sha(CORRECTED / "native-01/native.printwindow.repeat.png")
    assert sha(CORRECTED / "native-01/native.screen.png") == sha(CORRECTED / "native-01/native.screen.repeat.png")
    assert pixels["methodsEqual"] is False and pixels["controlledOcclusionQualification"] is False and pixels["providerReadbackExport"] is False
    assert obs["occlusionQualified"] is False and obs["nativeParity"] == "hold"
    assert obs["frozenTupleBound"] is False and obs["closureBinding"] is None

    # Baseline lineage: same source/case/UIA geometry, changed executable/process/pixel identities.
    assert original_obs["sourceHash"] == expected_source
    assert original_obs["case"]["hash"] == obs["case"]["hash"]
    assert original_pixels["width"] == pixels["width"] and original_pixels["height"] == pixels["height"]
    assert original_obs["nativeParity"] == "hold"
    assert original_obs["exeSha256"] != obs["exeSha256"]
    assert load(ORIGINAL / "native-01/native.uia.json")["children"][0]["bounds"] == uia["children"][0]["bounds"]
    assert mac_summary["sourceHash"] == expected_source and mac_summary["status"] == "CANDIDATE_CAPTURED"
    assert len(mac_summary["runs"]) == 20

    # Non-vacuous raw-input mutation controls. Each mutation changes a real joined field & rejects.
    baseline = {
        "sourceHash": obs["sourceHash"],
        "width": pixels["width"],
        "pid": pixels["pid"],
        "printHash": samples["native.printwindow.png"],
        "buttonName": uia["children"][0]["name"],
        "measure": measure.groups(),
        "retainedCount": len(retained),
    }

    def accepts(candidate: dict) -> bool:
        return (
            candidate["sourceHash"] == baseline["sourceHash"]
            and candidate["width"] == baseline["width"]
            and candidate["pid"] == baseline["pid"]
            and candidate["printHash"] == baseline["printHash"]
            and candidate["buttonName"] == baseline["buttonName"]
            and candidate["measure"] == baseline["measure"]
            and candidate["retainedCount"] == baseline["retainedCount"]
        )

    mutations = {}
    for name, key, value in [
        ("wrong-source-hash", "sourceHash", "sha256:" + "0" * 64),
        ("wrong-viewport-width", "width", 801),
        ("wrong-owned-pid", "pid", expected_pid + 1),
        ("wrong-printwindow-hash", "printHash", "0" * 64),
        ("wrong-uia-button-name", "buttonName", "Continue-mutated"),
        ("wrong-measure-log", "measure", ("320.0", "161.27344", "60.0", "1", "2.5")),
        ("missing-retained-log", "retainedCount", baseline["retainedCount"] - 1),
    ]:
        candidate = copy.deepcopy(baseline)
        before = json.dumps(candidate, sort_keys=True)
        candidate[key] = value
        after = json.dumps(candidate, sort_keys=True)
        mutations[name] = {"rawInputChanged": before != after, "rejected": not accepts(candidate)}
        assert mutations[name]["rawInputChanged"] and mutations[name]["rejected"]

    report = {
        "kind": "independent-offline-review",
        "verdict": "VERIFIED-CORRECTED-SOURCE-BOUND-OBSERVATION-PARITY-HELD",
        "scope": "actual-corrected-r1 only; no rerun, GUI, SSH, compiler, Pulse or source edits",
        "correctedPacket": {
            "path": str(CORRECTED.relative_to(ROOT)),
            "fileCount": len(corrected_files),
            "bytes": sum(x["bytes"] for x in corrected_files),
            "files": corrected_files,
        },
        "rawPins": {
            "sourceHash": expected_source,
            "rendererSha256": expected_renderer,
            "runtimeCommit": compile_obs["runtimeSourceCommit"],
            "runtimeTreeHash": expected_tree,
            "compilerHash": compile_obs["compilerHash"],
            "planSha256": expected_plan,
            "compileReceiptSha256": expected_compile,
            "exeSha256": expected_exe,
            "nativeObservationSha256": sha(CORRECTED / "native-observation.json"),
            "pixelsSha256": sha(pixels_path),
            "uiaSha256": sha(CORRECTED / "native-01/native.uia.json"),
            "hostStdoutSha256": sha(CORRECTED / "native-01/host.stdout.txt"),
            "hostStderrSha256": sha(CORRECTED / "native-01/host.stderr.txt"),
            "rootStageManifestSha256": sha(STAGE),
        },
        "joins": {
            "compile": {"exitCode": compile_obs["exitCode"], "timedOut": compile_obs["timedOut"], "exe": expected_exe},
            "native": {"pid": expected_pid, "hwnd": expected_hwnd, "dpi": 240, "client": [800, 600], "foregroundBefore": 395622, "foregroundAfter": 0},
            "geometry": {"measure": list(measure.groups()), "retainedRuns": len(retained), "commits": len(commits), "uiaContinueBounds": uia["children"][0]["bounds"]},
            "visual": {"printWindowRepeatStable": True, "screenRepeatStable": True, "methodsEqual": False, "controlledOcclusion": False, "providerReadbackExport": False},
            "distinctInitialDiagnostic": {"hostStderrClient": [2560, 1396], "ownedClient": [800, 600], "normalizationApplied": False},
        },
        "lineage": {
            "originalActualFirstR1": {"observationSha256": sha(ORIGINAL / "native-observation.json"), "pixelsSha256": sha(ORIGINAL / "native-01/native.pixels.json"), "nativeParity": original_obs["nativeParity"]},
            "matchedMacSummary20": {"path": str(MAC_SUMMARY.relative_to(ROOT)), "sha256": sha(MAC_SUMMARY), "runs": len(mac_summary["runs"]), "status": mac_summary["status"]},
        },
        "mutationControls": mutations,
        "holds": [
            "foregroundBefore 395622 becomes 0 after launch; probeForegroundAtCapture=false",
            "print/screen repeats are stable but differ; natural occlusion grid has no controlled clean sample",
            "corrected packet still reports nativeParity=hold, frozenTupleBound=false, closureBinding=null",
            "Windows run count remains 1 vs matched Mac summary 20",
            "diagnosis.json status PREPARED-UNBUILT is stale beside later successful compile/capture receipts; observation receipts are authoritative for those completed processes",
        ],
        "stageManifest": {"checked": len(stage_checked), "missing": stage_missing, "bad": stage_bad, "actualRunAndBuildSupplemental": True},
    }
    (OUT / "raw-pins.json").write_text(json.dumps({"kind": "corrected-packet-file-pins", "files": corrected_files}, indent=2) + "\n")
    report["reviewScriptSha256"] = sha(Path(__file__))
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
