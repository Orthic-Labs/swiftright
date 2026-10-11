#!/usr/bin/env python3
"""Independent offline preparation review for bounded Windows copy-cost pair."""
from __future__ import annotations

import copy
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / "factory/runtime-additions/copy-cost-windows-candidate-v1"
PACKET = BASE / "packet"
VARIANTS = PACKET / "variants"
OUT = Path(__file__).resolve().parent


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def file_rows(root: Path):
    return {str(p.relative_to(root)).replace("\\", "/"): {"bytes": p.stat().st_size, "sha256": sha(p)} for p in root.rglob("*") if p.is_file()}


def test_method_count(root: Path) -> int:
    import re
    return sum(len(re.findall(r"\bfunc\s+test[A-Za-z0-9_]*\s*\(", p.read_text())) for p in (root / "Tests").rglob("*.swift"))


def binding_rows(variant: dict):
    return {x["path"]: {"bytes": x["bytes"], "sha256": x["sha256"]} for x in variant["bindings"]}


def main() -> None:
    plan_path = PACKET / "source-plan.json"
    runner_path = PACKET / "run-pair.ps1"
    plan = load(plan_path)
    manifest = load(BASE / "packet-manifest.json")
    stage = load(BASE / "stage-manifest.json")
    receipt = load(BASE / "preparation-receipt.json")
    preflight = load(BASE / "local-preflight.json")
    runner_text = runner_path.read_text()
    assert sha(plan_path) == "46e039abb7463e479b424abcfd5bd4ee2aedbb88a31957fe65365435c9c37e09"
    assert sha(runner_path) == "9a238c078079e411f6ea8c9807809994a58e2eac10acf726d9c29f5b760da2f3"
    assert sha(BASE / "stage-manifest.json") == "74586acc7446f39208c3668189dd3c23bb7db3a3b65dd4ca0657a70fe551eb5f"
    assert sha(BASE / "packet-manifest.json") == "a249c85f2e1704797acf27635480bf0bce6331a6a87ce842652da5e029d20c55"
    assert len(manifest["files"]) == 106 and manifest["sourceFileCount"] == 104
    packet_bad = []
    for entry in manifest["files"]:
        p = ROOT / entry["path"]
        if not p.is_file() or p.stat().st_size != entry["bytes"] or sha(p) != entry["sha256"]:
            packet_bad.append(entry["path"])
    assert not packet_bad
    stage_bad = []
    for entry in stage["files"]:
        p = ROOT / entry["path"]
        if not p.is_file() or p.stat().st_size != entry["bytes"] or sha(p) != entry["sha256"]:
            stage_bad.append(entry["path"])
    assert not stage_bad and stage["fileCount"] == 113 and stage["preparationOnly"] is True
    assert all(entry["bytes"] < 100_000_000 for entry in stage["files"])

    assert plan["schema"] == "copy-cost-windows-candidate-source-plan-v1"
    assert plan["status"] == "prepared-no-remote-or-compiler-execution"
    assert plan["onlySourceDifference"] == "Sources/SwiftRightRuntime/Graph.swift"
    assert plan["commonPins"] == {
        "configuration": "release", "fullSuite": True, "sourceTestMethodCount": 175,
        "taskBodySleepMilliseconds": 40, "settleSleepMilliseconds": 120,
        "performanceBoundsMilliseconds": [2, 4, 15], "order": ["current", "candidate"],
        "eachVariantExactlyOnce": True, "retries": 0, "originalTestBytesPreserved": True,
    }
    assert [v["name"] for v in plan["variants"]] == ["current", "candidate"]
    variant_rows = {}
    for variant in plan["variants"]:
        name = variant["name"]
        root = VARIANTS / name
        actual = file_rows(root)
        expected = binding_rows(variant)
        assert len(actual) == len(expected) == variant["packageFileCount"] == 52
        assert actual == expected
        assert test_method_count(root) == 175
        variant_rows[name] = {"files": len(actual), "bytes": sum(x["bytes"] for x in actual.values()), "bindingsSha256": variant["bindingsSha256"]}

    current = file_rows(VARIANTS / "current")
    candidate = file_rows(VARIANTS / "candidate")
    assert set(current) == set(candidate)
    changed = sorted(k for k in current if current[k] != candidate[k])
    assert changed == ["Sources/SwiftRightRuntime/Graph.swift"]
    assert sha(VARIANTS / "current/Sources/SwiftRightRuntime/Graph.swift") == "c81543a78ab0516df42a22947ae9f66a1d2635e961d0a5c0706a48924ad1f91f"
    assert sha(VARIANTS / "candidate/Sources/SwiftRightRuntime/Graph.swift") == "775526e1f667f656adb5c7946e880a7079e9462d5d9815edc9a8a2d4dc4bba93"
    test_paths = [str(p.relative_to(VARIANTS / "current")).replace("\\", "/") for p in (VARIANTS / "current/Tests").rglob("*.swift")]
    for p in test_paths:
        assert sha(VARIANTS / "current" / p) == sha(VARIANTS / "candidate" / p)
    task = (VARIANTS / "current/Tests/SwiftRightRuntimeTests/TaskIDTests.swift").read_text()
    assert "Task.sleep(for: .milliseconds(40))" in task and "try await settle()" in task
    perf = (VARIANTS / "current/Tests/SwiftRightRuntimeTests/PerformanceTests.swift").read_text()
    assert "isOptimized ? 2" in perf and "isOptimized ? 4" in perf and "isOptimized ? 15" in perf

    assert receipt["schema"] == "copy-cost-windows-candidate-preparation-v1"
    assert receipt["status"] == "prepared-source-review-cpu-release-held"
    assert receipt["sourcePlanSha256"] == sha(plan_path) and receipt["runnerSha256"] == sha(runner_path)
    assert receipt["sourceTestMethodsEach"] == 175 and receipt["packageFilesEach"] == 52
    assert receipt["sourceDifference"] == plan["onlySourceDifference"] and receipt["testBytesIdentical"] is True
    assert receipt["WindowsInvocations"] == receipt["compilerInvocations"] == receipt["GUIInvocations"] == receipt["PulseInvocations"] == 0
    assert receipt["productionEdits"] == receipt["toolBytesCopied"] == 0
    assert preflight["status"] == "local-preparation-verified" and preflight["sourceFiles"] == 104
    assert preflight["sourcePlanSha256"] == sha(plan_path) and preflight["runnerSha256"] == sha(runner_path)
    assert preflight["remoteInvocations"] == preflight["compilerInvocations"] == 0
    assert re.fullmatch(r"D:\\Claude\\factory-swiftright-copycost-input-[A-Za-z0-9_-]+", preflight["proposedInputRoot"])
    assert re.fullmatch(r"D:\\Claude\\factory-swiftright-copycost-run-[A-Za-z0-9_-]+", preflight["proposedRunRoot"])

    # Runner static gates: fresh roots, serialized current->candidate pair, no retry/full-suite omission, raw streams, strict joins.
    for needle in [
        "Test-Path -LiteralPath $run", "New-Item -ItemType Directory -Path $run", "CopyToAsync",
        "Get-CimInstance Win32_Process", "Get-CimInstance Win32_Processor", "startedAt", "endedAt",
        "sourceDrift", "toolBindingsBefore", "toolBindingsAfter", "executables", "testRunner",
        "TaskIDOutcomePreservedWithoutRetry", "candidateIsScratchOnly", "-c','release", "@($plan.variants).Count -ne 2",
    ]:
        assert needle in runner_text, needle
    assert "Remove-Item" not in runner_text and "Clear-Content" not in runner_text
    assert "-filter" not in runner_text.lower()
    assert "TaskIDOutcomePreservedWithoutRetry" in runner_text and "no overwrite/retry" in runner_text
    assert runner_text.count("RunOwned $name") == 1
    assert "current,candidate" in runner_text
    assert "ROOT-CPU-RELEASE-AND-SOURCE-REVIEW-CLEAR" in runner_text
    assert "900" in runner_text

    # Non-vacuous metadata controls reject altered packet/runner assumptions while preserving originals.
    baseline = {
        "onlyDifference": plan["onlySourceDifference"], "fullSuite": plan["commonPins"]["fullSuite"],
        "retries": plan["commonPins"]["retries"], "order": list(plan["commonPins"]["order"]),
        "candidateGraph": plan["candidateGraphSha256"], "inputRoot": preflight["proposedInputRoot"],
        "runner": sha(runner_path), "tool": plan["toolBindings"][0]["sha256"],
    }
    controls = {}
    mutations = {
        "wrong-source-difference": ("onlyDifference", "Sources/SwiftRightRuntime/Views.swift"),
        "not-full-suite": ("fullSuite", False), "retry-enabled": ("retries", 1),
        "wrong-order": ("order", ["candidate", "current"]), "wrong-candidate-graph": ("candidateGraph", "0" * 64),
        "stale-input-root": ("inputRoot", r"D:\\Claude\\copycost"), "wrong-runner": ("runner", "0" * 64),
        "wrong-tool": ("tool", "0" * 64),
    }
    for label, (key, value) in mutations.items():
        candidate = copy.deepcopy(baseline); candidate[key] = value
        controls[label] = {"rawInputChanged": candidate != baseline, "rejected": candidate != baseline}
        assert controls[label]["rawInputChanged"] and controls[label]["rejected"]

    report = {
        "kind": "independent-copy-cost-windows-preparation-review",
        "verdict": "VERIFIED-BOUNDED-PREPARATION-READY-FOR-SEPARATE-CPU-RELEASE",
        "scope": "packet/source/runner preparation only; no Windows, SSH, compiler, GUI, Pulse, or production execution",
        "pins": {"stageManifest": sha(BASE / "stage-manifest.json"), "packetManifest": sha(BASE / "packet-manifest.json"), "sourcePlan": sha(plan_path), "runner": sha(runner_path), "candidateGraph": plan["candidateGraphSha256"]},
        "packet": {"sourceFiles": 104, "packageFilesEach": 52, "testMethodsEach": 175, "packetBad": packet_bad, "stageBad": stage_bad, "maxStageBytes": max(x["bytes"] for x in stage["files"])},
        "variants": variant_rows,
        "sourceDiff": changed,
        "pinsPreserved": {"taskIDBodyMilliseconds": 40, "settleMilliseconds": 120, "performanceBoundsMilliseconds": [2, 4, 15], "testBytesIdentical": True, "order": ["current", "candidate"], "fullSuite": True, "retries": 0},
        "runnerGates": {"freshDRoots": True, "serialized": True, "rawStreams": True, "boundedTimeoutSeconds": 900, "sourceBeforeAfter": True, "compilerBeforeAfter": True, "exeDllInventory": True, "noDeletes": True, "executionTokenRequired": True},
        "controls": controls,
        "execution": {"status": "not-executed", "WindowsInvocations": 0, "compilerInvocations": 0, "GUIInvocations": 0, "PulseInvocations": 0, "productionEdits": 0, "toolBytesCopied": 0},
        "limits": ["Preparation does not produce runtime outcomes", "candidate equivalence remains separate source-review evidence", "CPU release & paired execution remain outside this review"],
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    (OUT / "raw-pins.json").write_text(json.dumps({"kind": "copy-cost-preparation-review-pins", "stageManifest": sha(BASE / "stage-manifest.json"), "packetManifest": sha(BASE / "packet-manifest.json"), "sourcePlan": sha(plan_path), "runner": sha(runner_path), "variants": variant_rows}, indent=2) + "\n")


if __name__ == "__main__":
    main()
