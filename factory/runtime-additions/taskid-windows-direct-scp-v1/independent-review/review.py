#!/usr/bin/env python3
"""Independent offline review of one bounded Windows TaskID direct-SCP run."""
from __future__ import annotations

import copy
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
BASE = ROOT / "factory/runtime-additions/taskid-windows-direct-scp-v1"
PACKET = BASE / "packet"
RESULTS = BASE / "results"
OUT = Path(__file__).resolve().parent


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load(p: Path):
    return json.loads(p.read_text(encoding="utf-8-sig"))


def assert_pin(p: Path, size: int, sha256: str) -> None:
    assert p.is_file(), p
    assert p.stat().st_size == size, p
    assert digest(p) == sha256, p


def variant_source_rows(name: str):
    root = PACKET / "variants" / name
    return sorted([
        {"path": str(p.relative_to(root)).replace("\\", "/"), "bytes": p.stat().st_size, "sha256": digest(p)}
        for p in root.rglob("*")
        if p.is_file()
    ], key=lambda row: row["path"])


def ms(a: str, b: str) -> int:
    return int((datetime.fromisoformat(b.replace("Z", "+00:00")) - datetime.fromisoformat(a.replace("Z", "+00:00"))).total_seconds() * 1000)


def main() -> None:
    manifest_v2 = load(BASE / "packet-manifest-v2.json")
    manifest_v1 = load(BASE / "packet-manifest.json")
    plan = load(PACKET / "source-plan.json")
    receipt = load(RESULTS / "receipt.json")
    preflight_text = (BASE / "remote-preflight-v2.stdout.bin").read_bytes().decode("utf-8-sig", errors="replace")
    preflight = json.loads(preflight_text[preflight_text.find("{") :])
    runner = PACKET / "run-three-variants.ps1"
    runner_preimage = BASE / "runner-preimage.ps1"
    runner_discovery = BASE / "runner-preimage-path-discovery.ps1"
    runner_plumbing = load(BASE / "runner-plumbing-final-preflight.json")
    source_manifest = load(ROOT / "factory/runtime-additions/next-runtime-diagnosis-v1/scratch-source-manifest.json")

    # v2 packet is actual input; v1 remains historical lineage and intentionally differs only by old runner.
    v2_missing, v2_bad, v1_bad = [], [], []
    for entry in manifest_v2["files"]:
        p = PACKET / entry["path"]
        if not p.is_file():
            v2_missing.append(entry["path"])
        elif p.stat().st_size != entry["bytes"] or digest(p) != entry["sha256"]:
            v2_bad.append(entry["path"])
    for entry in manifest_v1["files"]:
        p = PACKET / entry["path"]
        if not p.is_file() or p.stat().st_size != entry["bytes"] or digest(p) != entry["sha256"]:
            v1_bad.append(entry["path"])
    assert not v2_missing and not v2_bad
    assert len(manifest_v2["files"]) == 137 and manifest_v2["sourceFiles"] == 135

    assert plan["sourceManifest"]["sha256"] == digest(ROOT / plan["sourceManifest"]["path"])
    assert len(plan["variants"]) == 3
    assert plan["commonPins"] == {
        "filter": "SwiftRightRuntimeTests.TaskIDTests/testSameIdDoesNotRestartTask",
        "configuration": "release",
        "taskBodySleepMilliseconds": 40,
        "settleSleepMilliseconds": 120,
        "testAssertionsPreserved": True,
        "runtimeEdits": 0,
        "fullSuite": False,
        "eachVariantExactlyOnce": True,
    }

    # Packet source bindings, v2 receipt bindings and before/after source identity must all agree.
    receipt_by_name = {v["name"]: v for v in receipt["variants"]}
    assert set(receipt_by_name) == {"original", "retained", "terminal"}
    variant_facts = {}
    for pv in plan["variants"]:
        name = pv["name"]
        packet_rows = variant_source_rows(name)
        expected_rows = sorted(({"path": x["path"], "bytes": x["bytes"], "sha256": x["sha256"]} for x in pv["bindings"]), key=lambda row: row["path"])
        assert len(packet_rows) == len(expected_rows) == 45
        assert packet_rows == expected_rows
        rv = receipt_by_name[name]
        actual_rows = sorted(({"path": x["path"], "bytes": x["bytes"], "sha256": x["sha256"]} for x in rv["sourceBindings"]), key=lambda row: row["path"])
        assert actual_rows == expected_rows and rv["sourceDrift"] is False
        assert rv["declaredTreeSha256"] == pv["declaredTreeSha256"]
        assert source_manifest["variants"][name]["treeSha256"] == pv["declaredTreeSha256"]
        variant_facts[name] = {"treeSha256": pv["declaredTreeSha256"], "fileCount": len(packet_rows), "sourceBindingsSha256": rv["sourceBindingsSha256"]}

    # Only TaskIDTests.swift differs between variants. Assertions and 40ms body remain unchanged.
    hashes = {}
    for name in ("original", "retained", "terminal"):
        hashes[name] = {str(p.relative_to(PACKET / "variants" / name)): digest(p) for p in (PACKET / "variants" / name).rglob("*") if p.is_file()}
    changed_or = sorted(k for k in set(hashes["original"]) | set(hashes["retained"]) if hashes["original"].get(k) != hashes["retained"].get(k))
    changed_rt = sorted(k for k in set(hashes["retained"]) | set(hashes["terminal"]) if hashes["retained"].get(k) != hashes["terminal"].get(k))
    assert changed_or == changed_rt == ["Tests/SwiftRightRuntimeTests/TaskIDTests.swift"]
    original_test = (PACKET / "variants/original/Tests/SwiftRightRuntimeTests/TaskIDTests.swift").read_text()
    retained_test = (PACKET / "variants/retained/Tests/SwiftRightRuntimeTests/TaskIDTests.swift").read_text()
    terminal_test = (PACKET / "variants/terminal/Tests/SwiftRightRuntimeTests/TaskIDTests.swift").read_text()
    for text in (original_test, retained_test, terminal_test):
        assert "Task.sleep(for: .milliseconds(40))" in text
        assert 'XCTAssertEqual(log.events.filter { $0 == "start a" }.count, 1, "no restart for an unchanged id")' in text
        assert 'XCTAssertEqual(log.results, ["a"])' in text
    assert "try await settle()" in original_test and "try await settle()" in retained_test and "try await settle()" in terminal_test
    assert "waitForTerminalCommit" in terminal_test and "retainedGraph" in retained_test

    # Actual run is three variants, one process and one copied test runner each; no retry/full-suite claim.
    assert receipt["status"] == "actual-headless-run"
    assert receipt["executionTokenAccepted"] is True and receipt["runtimeEdits"] == 0
    assert receipt["fullSuite"] is False and receipt["nativeWindowOpened"] is False and receipt["desktopReservationRequired"] is False
    assert receipt["filter"] == plan["commonPins"]["filter"]
    outcomes = {}
    for name, expected_exit in (("original", 1), ("retained", 0), ("terminal", 0)):
        rv = receipt_by_name[name]; proc = rv["process"]
        assert proc["exitCode"] == expected_exit and proc["timedOut"] is False
        assert len(rv["testRunner"]) == 1
        runner_row = rv["testRunner"][0]
        local_runner = RESULTS / name / "test-runner-0.exe"
        assert_pin(local_runner, runner_row["bytes"], runner_row["sha256"])
        for stream, key in (("stdout.txt", "stdoutHash"), ("stderr.txt", "stderrHash")):
            stream_path = RESULTS / name / "process" / stream
            assert stream_path.stat().st_size == proc[stream.replace(".txt", "Bytes")]
            assert digest(stream_path) == proc[key]
        assert proc["executableHash"] == receipt["toolchain"]["swiftHash"]
        assert proc["executable"] == receipt["toolchain"]["swiftPath"]
        assert proc["cwd"].endswith(f"\\{name}\\runtime")
        assert any(row.get("pid") == proc["pid"] and row.get("executablePath") == proc["executable"] for row in proc["cimObserved"])
        assert ms(proc["startedAt"], proc["endedAt"]) > 0
        outcomes[name] = {
            "exitCode": proc["exitCode"], "timedOut": proc["timedOut"], "pid": proc["pid"],
            "durationMs": ms(proc["startedAt"], proc["endedAt"]), "stdoutBytes": proc["stdoutBytes"], "stderrBytes": proc["stderrBytes"],
            "stdoutSha256": proc["stdoutHash"], "stderrSha256": proc["stderrHash"], "runnerSha256": runner_row["sha256"],
        }
    assert len({x["pid"] for x in outcomes.values()}) == 3

    # Raw diagnostic conclusions come from streams, not candidate flags.
    stdout = {n: (RESULTS / n / "process/stdout.txt").read_text(errors="replace") for n in outcomes}
    assert 'XCTAssertEqual failed: ("[]") is not equal to ("["a"]")' in stdout["original"]
    assert 'DIAG variant=retained events=["start a", "commit=true a"] results=["a"]' in stdout["retained"]
    assert 'DIAG variant=terminal terminal=true events=["start a", "commit=true a"] results=["a"]' in stdout["terminal"]
    assert "DIAG variant=terminal" not in stdout["retained"] and "DIAG variant=retained" not in stdout["original"]
    assert outcomes["original"]["exitCode"] == 1 and outcomes["retained"]["exitCode"] == outcomes["terminal"]["exitCode"] == 0

    # Actual tool/environment/source/process pins.
    swift = RESULTS / "swift.exe"; swiftc = RESULTS / "swiftc.exe"
    assert digest(swift) == digest(swiftc) == receipt["toolchain"]["swiftHash"] == receipt["toolchain"]["swiftcHash"] == preflight["swiftHash"] == preflight["swiftcHash"]
    assert runner.name == "run-three-variants.ps1" and digest(runner) == preflight["runnerHash"] == runner_plumbing["finalRunnerSha256"]
    assert digest(runner_preimage) == runner_plumbing["oldSha256"]
    assert digest(runner_discovery) == runner_plumbing["newSha256"]
    assert preflight["sourcePlanHash"] == digest(PACKET / "source-plan.json")
    assert preflight["sourceFiles"] == 135 and preflight["parserErrors"] == 0 and preflight["newItemPathSupported"] is True
    assert preflight["compilerExecutions"] == 0 and preflight["testExecutions"] == 0
    assert receipt["environment"]["SDKROOT"].endswith("Windows.sdk\\")
    assert "XCTest-6.4.0" in receipt["environment"]["path"] and "Testing-6.4.0" in receipt["environment"]["path"]
    assert runner_plumbing["bodyMilliseconds"] == 40 and runner_plumbing["settleMilliseconds"] == 120 and runner_plumbing["workloadChanges"] == 0

    # Actual copied root is fresh/versioned and accepted by runner pattern, but generic source-plan root is not literal.
    actual_input = receipt["inputRoot"]
    actual_run = receipt["runRoot"]
    assert re.fullmatch(r"D:\\Claude\\factory-swiftright-taskid-three-input-[A-Za-z0-9_-]+", actual_input)
    assert re.fullmatch(r"D:\\Claude\\factory-swiftright-taskid-three-run-[A-Za-z0-9_-]+", actual_run)
    literal_plan_input = plan["remoteInputRoot"]
    literal_plan_run = plan["remoteRunRoot"]
    assert actual_input != literal_plan_input and actual_run != literal_plan_run

    # Non-vacuous mutation controls: changed raw pins/process outcome/stream marker reject.
    control_baseline = {
        "sourceFiles": preflight["sourceFiles"], "sleep": plan["commonPins"]["taskBodySleepMilliseconds"],
        "runnerSha": preflight["runnerHash"], "retainedExit": outcomes["retained"]["exitCode"],
        "terminalMarker": "DIAG variant=terminal terminal=true" in stdout["terminal"],
        "retainedResults": 'results=["a"]' in stdout["retained"],
    }
    controls = {}
    for label, key, value in [
        ("wrong-source-count", "sourceFiles", 134),
        ("wrong-body-sleep", "sleep", 41),
        ("wrong-runner-hash", "runnerSha", "0" * 64),
        ("retained-failure", "retainedExit", 1),
        ("missing-terminal-marker", "terminalMarker", False),
        ("wrong-retained-result", "retainedResults", False),
    ]:
        candidate = copy.deepcopy(control_baseline); candidate[key] = value
        controls[label] = {"rawInputChanged": candidate != control_baseline, "rejected": candidate != control_baseline}
        assert controls[label]["rawInputChanged"] and controls[label]["rejected"]

    report = {
        "kind": "independent-offline-review",
        "verdict": "VERIFIED-BOUNDED-THREE-VARIANT-DIRECT-SCP-EVIDENCE",
        "scope": "one original, one retained, one terminal; no rerun, SSH, compiler, GUI, Pulse or source edits",
        "pins": {
            "packetManifestV2": digest(BASE / "packet-manifest-v2.json"), "packetManifestV1": digest(BASE / "packet-manifest.json"),
            "packetFiles": 137, "sourceFiles": 135, "sourcePlan": digest(PACKET / "source-plan.json"), "runner": digest(runner),
            "swiftHash": receipt["toolchain"]["swiftHash"], "swiftcHash": receipt["toolchain"]["swiftcHash"],
            "receipt": digest(RESULTS / "receipt.json"), "preflight": digest(BASE / "remote-preflight-v2.stdout.bin"),
        },
        "source": {"variants": variant_facts, "changedFilesOriginalRetained": changed_or, "changedFilesRetainedTerminal": changed_rt, "runtimeEdits": 0, "assertionsPreserved": True, "bodyMilliseconds": 40, "settleMilliseconds": 120},
        "outcomes": outcomes,
        "diagnostics": {"original": "exit1, empty results, XCTAssertEqual failure at TaskIDTests.swift:91", "retained": "exit0, commit=true a, results=[a]", "terminal": "exit0, terminal=true, commit=true a, results=[a]"},
        "runner": {"oldPreimageSha256": digest(runner_preimage), "pathDiscoveryPreimageSha256": digest(runner_discovery), "finalSha256": digest(runner), "preflight": {"parserErrors": preflight["parserErrors"], "newItemPathSupported": preflight["newItemPathSupported"], "compilerExecutions": preflight["compilerExecutions"], "testExecutions": preflight["testExecutions"]}, "plumbing": runner_plumbing},
        "captureLimits": {"selectedFilter": receipt["filter"], "fullSuite": receipt["fullSuite"], "nativeWindowOpened": receipt["nativeWindowOpened"], "desktopReservationRequired": receipt["desktopReservationRequired"], "runtimeEdits": receipt["runtimeEdits"], "eachVariantExactlyOnce": plan["commonPins"]["eachVariantExactlyOnce"], "noBroadGreen175Claim": True},
        "pathBinding": {"actualInputRoot": actual_input, "actualRunRoot": actual_run, "sourcePlanInputRoot": literal_plan_input, "sourcePlanRunRoot": literal_plan_run, "literalRootsEqual": False, "patternAccepted": True},
        "lineage": {"sourceManifest": plan["sourceManifest"], "v1ManifestMismatches": v1_bad, "v2ManifestMissing": v2_missing, "v2ManifestBad": v2_bad},
        "mutationControls": controls,
        "holds": [
            "Original selected test genuinely exits 1 with empty results; retained/terminal selected tests exit 0 with raw diagnostic markers.",
            "Run is one selected test per variant, not full suite; no native window or desktop reservation; no broad 175-case claim.",
            "Source-plan generic remote roots differ literally from fresh versioned actual roots; accepted only by runner regex/fresh-root contract.",
            "packet-manifest-v1 is historical and has stale run-three-variants.ps1 pin; packet-manifest-v2 is actual exact manifest.",
        ],
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    (OUT / "raw-pins.json").write_text(json.dumps({"kind": "direct-scp-review-pins", "packet": digest(BASE / "packet-manifest-v2.json"), "sourcePlan": digest(PACKET / "source-plan.json"), "receipt": digest(RESULTS / "receipt.json"), "variants": outcomes}, indent=2) + "\n")


if __name__ == "__main__":
    main()
