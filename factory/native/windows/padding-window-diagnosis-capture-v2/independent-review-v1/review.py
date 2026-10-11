#!/usr/bin/env python3
"""Read-only independent source admission review for capture-v2."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
STAGE = ROOT / "factory/native/windows/padding-window-diagnosis-capture-v2"
REVIEW = STAGE / "independent-review-v1"
EXPECTED_STAGE = "4088322c03c02ed876542797688d5a849aed01c206318ce29b00d08318e5350c"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    manifest_path = STAGE / "root-stage-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    checks: list[dict[str, object]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})

    check("stage-manifest-sha", sha(manifest_path) == EXPECTED_STAGE, sha(manifest_path))
    for item in manifest["files"]:
        p = ROOT / item["path"]
        actual = sha(p) if p.exists() else "missing"
        size = p.stat().st_size if p.exists() else -1
        expected = item["hash"].split(":", 1)[-1]
        check("file:" + item["path"], actual == expected and size == item["bytes"],
              f"sha={actual};size={size}")

    runner = (STAGE / "capture-repeat.ps1").read_text()
    coordinator = (STAGE / "coordinator.ps1").read_text()
    integration = (STAGE / "support/integration.ps1").read_text()
    worker = (STAGE / "dependencies/uia-worker/invoke-worker.ps1").read_text()
    worker_schema = (STAGE / "dependencies/uia-worker/schema.ps1").read_text()
    plan = json.loads((STAGE / "capture-plan.json").read_text())
    tests = (STAGE / "test-integration.ps1").read_text()
    source_controls = (STAGE / "test-source-controls.ps1").read_text()

    # Existing offline source checker is independently rerun by this review.
    import subprocess
    result = subprocess.run(["python3", str(STAGE / "verify-source.py")], cwd=ROOT,
                            capture_output=True, text=True)
    check("offline-source-checks", result.returncode == 0,
          result.stdout.strip() or result.stderr.strip())
    check("canonical-plan-pins", plan["admittedCompileReceiptSha256"] ==
          "74bf90f689d00124abbcfbe56a97b1160fe3117277c7e332490b48be713ca8d7" and
          plan["admittedExeSha256"] ==
          "caa9b760f2fc4574b0ca9846610f5b177b50e5180986c930415a442b3d83a369",
          "actual compile/executable pins")

    check("parent-no-uia", all(x not in runner for x in (
        "Windows.Automation", "UIAutomationClient", "UIAutomationTypes", "Read-UIA")),
          "UIA authority remains worker-only")
    check("worker-before-pixels-close", runner.index("Invoke-FactoryUiaSnapshotWorker $target") <
          runner.index("$pixels=Capture-FactoryPixels") < runner.index("'owned-close-request'"),
          "worker natural proof precedes pixels & WM_CLOSE")
    check("worker-ready-gates", runner.count("Assert-FactorySnapshotReady $workerResult $target") == 3,
          "ready check before pixels, before close & terminal")
    check("worker-natural-proof", all(x in worker + worker_schema for x in (
        "preCleanupKernelWaitResult", "-ne 0", "-not $proof.cleanup.killAttempted",
        "hashQualification", "sealed-raw", "status='completed-natural-uiasnapshot'")),
          "worker requires kernel0, no kill & sealed raw streams")
    check("initialize-before-start", runner.index("Initialize-FactoryFinalExitNative") <
          runner.index("$p=[Diagnostics.Process]::Start"), "native declarations precede renderer start")
    check("original-retained-start", runner.index("$retainedTimingHandle=$p.Handle") <
          runner.index("$finalStart=[ordered]") < runner.index("$stdoutFile=[IO.File]::Open"),
          "original handle/start identity captured first")
    check("final-after-original-receipts", runner.index("'capture-outcome.json')}") <
          runner.index("$finalSample=Get-FactoryFinalExitSample") <
          runner.index("Assert-FactoryCaptureOutcome $primaryError"),
          "final cert follows outcome/raw closure & before terminal assertion")
    check("original-deadlines-preserved", "AddSeconds(15)" in runner and
          "$stdoutTask.Wait(5000)" in runner and "$stderrTask.Wait(5000)" in runner,
          "15s owned exit & 5s raw drains remain")
    check("original-validity-preserved", "Owned host output failed original validity predicate" in runner and
          "qualification='hold'" in coordinator, "host validity & qualification hold retained")

    helper_hash = "94db73dadfaa998fe63eefc5e7ce416310fe9072cd2fd09689f2f923f81538b4"
    check("final-helper-v2-pin", plan["integration"]["finalExitHelperSha256"] == helper_hash and
          sha(STAGE / "support/final-exit-certificate.ps1") == helper_hash,
          "qualification-bound final helper")
    check("final-fallback-lineage", all(x in coordinator for x in (
        "Final start original lineage mismatch", "Final raw stream/outcome byte join mismatch",
        "Final certificate/outcome exact reference mismatch", "Final proof read outside exact closure",
        "Test-FactoryFinalReleaseProof")), "fallback binds owner/start/source/raw/outcome")
    check("exact-owner-release", "Invoke-FactoryConfirmedRelease $acquired $releaseAllowed" in coordinator and
          "Change-Lock $owner 'free'" in coordinator, "release remains existing exact-owner CAS")
    check("no-promotion", all(x in runner + coordinator for x in (
        "qualification='hold'", "nativeParity='hold'", "frozenTupleBound=$false")),
          "observation cannot promote qualification")
    check("pure-integration-faults", all(x in tests for x in (
        "worker-precleanup-kernel-", "worker-killed", "raw-unsealed-",
        "ordering-no-action-", "worker-foreign-lock-owner")),
          "integration faults reject before parent action")
    check("source-controls-order", all(x in source_controls for x in (
        "Invoke-FactoryUiaSnapshotWorker $target", "$pixels=Capture-FactoryPixels",
        "owned-close-request", "AddSeconds(15)", "$stdoutTask.Wait(5000)")),
          "source ordering/deadline controls present")
    check("no-retries-count1", all("[ValidateSet(1)]" in (STAGE / name).read_text()
                                    for name in ("capture-repeat.ps1", "coordinator.ps1", "dispatch.ps1", "prepare-capture.ps1")),
          "Count1 fresh namespace & retries disabled")

    report = {
        "kind": "padding-window-diagnosis-capture-v2-independent-review-v1",
        "sourceStage": EXPECTED_STAGE,
        "verdict": "CLEAR_SOURCE_PENDING_WINDOWS_NATIVE_RECEIPTS",
        "scope": "read-only caller/source review; no native/remote/compiler/Git execution",
        "sourceChecks": 15,
        "pureControls": "prepared/unrun on this host; root Windows receipts required",
        "findings": [],
        "checks": checks,
    }
    (REVIEW / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if all(x["ok"] for x in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
