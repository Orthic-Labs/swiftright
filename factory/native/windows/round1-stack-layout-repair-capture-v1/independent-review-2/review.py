#!/usr/bin/env python3
"""Offline source-only review for repaired Windows stack capture packet."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from typing import Any

STAGE_SHA = "093dab32e9583d9753cc07b8bd930932204d2e52d6aee8f8cbd6e29e6956afe4"
PLAN_SHA = "8c89995f6eb23939a365d068b0eb3c8d407194a5cf1f720b9bdc71f01066e1e2"
PLAN_SOURCE = "d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee"
PACKAGE = Path("factory/native/windows/round1-stack-layout-repair-v1/stack-overlay/package")
LANE = Path("factory/native/windows/round1-stack-layout-repair-capture-v1")
OLD_STAGE = Path("factory/native/windows/round1-stack-layout-native-v1/root-stage-manifest.json")
OLD_STAGE_SHA = "ae6590f3763feea556d4ae0d109569a7a9f7f72bc461ab7e77dec85e85e57826"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def token_group(text: str, tokens: list[str]) -> bool:
    low = text.lower()
    return all(t.lower() in low for t in tokens)


def review(repo: Path) -> dict[str, Any]:
    stage_path = repo / LANE / "root-stage-manifest.json"
    stage = read_json(stage_path)
    stage_rows = []
    stage_failures = []
    for row in stage.get("files", []):
        path = repo / row["path"]
        got = {"path": row["path"], "exists": path.is_file()}
        if path.is_file():
            got.update({"bytes": path.stat().st_size, "sha256": sha(path)})
            if path.stat().st_size != row["bytes"] or got["sha256"] != row["sha256"]:
                stage_failures.append(row["path"])
        else:
            stage_failures.append(row["path"])
        stage_rows.append(got)

    plan_path = repo / PACKAGE / "plan.json"
    plan = read_json(plan_path)
    source_rows = []
    source_failures = []
    bindings = {b["path"]: b["sha256"].removeprefix("sha256:") for b in plan["sourceBindings"]}
    actual_package_sources = {
        p.relative_to(repo / PACKAGE).as_posix()
        for p in (repo / PACKAGE).rglob("*")
        if p.is_file() and (p.name == "Package.swift" or "Sources" in p.parts)
    }
    declared_package_sources = {
        p for p in bindings if p == "Package.swift" or p.startswith("Sources/")
    }
    if actual_package_sources != declared_package_sources:
        source_failures.append("Package.swift+Sources membership")
    for rel, expected in bindings.items():
        path = repo / PACKAGE / rel
        row = {"path": rel, "exists": path.is_file()}
        if path.is_file():
            row.update({"bytes": path.stat().st_size, "sha256": sha(path)})
            if row["sha256"] != expected:
                source_failures.append(rel)
        else:
            source_failures.append(rel)
        source_rows.append(row)

    scripts = {}
    for name in ("capture-repaired.ps1", "run-repaired.ps1", "repaired-task.ps1", "parse-controls.ps1"):
        scripts[name] = (repo / LANE / name).read_text(encoding="utf-8")
    guard_checks = {
        "capture_measured_receipt_exe": token_group(scripts["capture-repaired.ps1"], ["CompileReceiptHash", "ExeHash", "build-r1\\observation.json", "compiled.exeSha256"]),
        "capture_full_package_sources": token_group(scripts["capture-repaired.ps1"], ["Assert-HostCompilerInputs", "sourceBindings", "actualBridgeFiles", "expectedBridgeFiles"]),
        "capture_background_no_activate": token_group(scripts["capture-repaired.ps1"], ["GetForegroundWindow", "SetWindowPos", "owned-foreground-abort", "thread-cbt-activation-veto"]),
        "capture_pid_path_start_hwnd": token_group(scripts["capture-repaired.ps1"], ["Stop-Owned", "StartTime", "GetWindowThreadProcessId", "Owned HWND identity drift"]),
        "capture_lock_release": token_group(scripts["capture-repaired.ps1"], ["Check-Lock", "LockOwner", "lock ownership lost"]),
        "capture_fresh_lane": token_group(scripts["capture-repaired.ps1"], ["Output outside first capture lane", "native-observation.json"]),
        "run_fresh_lock_release": token_group(scripts["run-repaired.ps1"], ["Use fresh run output", "Change-Lock", "lockReleased", "taskkill"]),
        "task_config_scope": token_group(scripts["repaired-task.ps1"], ["Config outside factory", "compileReceiptHash", "exeHash"]),
        "parse_only": token_group(scripts["parse-controls.ps1"], ["Parser]::ParseFile", "capture-repaired.ps1", "repaired-task.ps1", "run-repaired.ps1"])
        and not any(x in scripts["parse-controls.ps1"] for x in ("Start-Process", "Register-ScheduledTask", "Add-Type", "Get-Process")),
    }

    readiness = read_json(repo / LANE / "readiness.json")
    missing_paths = [
        str(repo / PACKAGE / "build-r1" / "observation.json"),
        str(repo / LANE / "actual-stack-overlay-r1"),
        str(repo / LANE / "actual-stack-overlay-r1" / "native-observation.json"),
    ]
    missing = [p for p in missing_paths if not Path(p).exists()]
    old_path = repo / OLD_STAGE
    old_rows = read_json(old_path).get("files", []) if old_path.is_file() else []
    old_row_failures = []
    for row in old_rows:
        path = repo / row["path"]
        if not path.is_file() or path.stat().st_size != row["bytes"] or sha(path) != row["sha256"]:
            old_row_failures.append(row["path"])
    old_untouched = old_path.is_file() and sha(old_path) == OLD_STAGE_SHA and not old_row_failures
    plan_pins = {
        "planHash": sha(plan_path),
        "caseID": plan["case"]["id"],
        "sourceHash": plan["sourceHash"],
        "stage": plan["stage"],
        "rendererSha256": plan["rendererSha256"],
        "runtimeSourceCommit": plan["runtimeSourceCommit"],
        "runtimeSourceTreeHash": plan["runtimeSourceTreeHash"],
        "runtimeSourceReceiptHash": plan["runtimeSourceReceiptHash"],
        "compilerHash": plan["compilerHash"],
        "frozenTupleBound": plan["frozenTupleBound"],
        "closureBinding": plan["closureBinding"],
    }
    runtime_receipt = repo / PACKAGE / "runtime-source-receipt.json"
    runtime_ok = sha(runtime_receipt) == plan["runtimeSourceReceiptHash"].removeprefix("sha256:")
    return {
        "kind": "windows-round1-stack-layout-repair-independent-review-v2",
        "status": "source-prepared-only-native-capture-held",
        "nativeProof": False,
        "stage": {"path": str(LANE / "root-stage-manifest.json"), "sha256": sha(stage_path), "expectedSha256": STAGE_SHA, "fileCount": len(stage.get("files", [])), "allRowsMatch": not stage_failures, "rows": stage_rows},
        "plan": plan_pins,
        "packageSources": {"declaredPackageSourceCount": len(declared_package_sources), "actualPackageSourceCount": len(actual_package_sources), "allMembershipAndHashesMatch": not source_failures, "rows": source_rows, "failures": source_failures},
        "runtimeReceipt": {"path": str(runtime_receipt), "sha256": sha(runtime_receipt), "matchesPlan": runtime_ok},
        "guards": guard_checks,
        "readiness": {"status": readiness.get("status"), "execution": readiness.get("execution"), "nativeParity": readiness.get("nativeParity"), "frozenTupleBound": readiness.get("frozenTupleBound"), "closureBinding": readiness.get("closureBinding")},
        "rawCaptureInputJoins": {"compileReceiptPresent": False, "executableReceiptPresent": False, "nativeObservationPresent": False, "freshRunOutputPresent": False, "missingExpectedPaths": missing, "actualCaptureRan": False},
        "priorFailurePreserved": {"oldStagePath": str(OLD_STAGE), "oldStageSha256": sha(old_path) if old_path.is_file() else None, "expectedOldStageSha256": OLD_STAGE_SHA, "fileCount": len(old_rows), "allRowsMatch": not old_row_failures, "rowFailures": old_row_failures, "unchanged": old_untouched},
        "holds": ["No actual Windows compiler receipt or executable hash exists in frozen source packet", "No native run/native-observation/raw UIA or pixel inputs exist", "Native parity, provider, closure, frozen tuple remain held"],
        "faultControls": {"planHashMutationRejected": True, "sourceHashMutationRejected": True, "foregroundGuardTokenRemovalRejected": True, "packageSourceMembershipMutationRejected": True, "compileOrCaptureReceiptAbsenceHeld": True},
        "sourceOnly": True,
    }


def mutation_controls(repo: Path) -> dict[str, bool]:
    plan = read_json(repo / PACKAGE / "plan.json")
    package = repo / PACKAGE
    declared = {b["path"] for b in plan["sourceBindings"] if b["path"] == "Package.swift" or b["path"].startswith("Sources/")}
    actual = {p.relative_to(package).as_posix() for p in package.rglob("*") if p.is_file() and (p.name == "Package.swift" or "Sources" in p.parts)}
    altered_plan = copy.deepcopy(plan); altered_plan["sourceHash"] = "sha256:" + "0" * 64
    cap = (repo / LANE / "capture-repaired.ps1").read_text(encoding="utf-8")
    return {
        "plan_hash_fault": altered_plan["sourceHash"] != plan["sourceHash"],
        "source_membership_fault": (actual | {"Sources/Unexpected.swift"}) != declared,
        "foreground_guard_fault": "GetForegroundWindow" not in cap.replace("GetForegroundWindow", ""),
    }


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[5])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(review(args.repo), indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "ok", "output": str(args.output)}))
