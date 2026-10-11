#!/usr/bin/env python3
"""Read-only audit of failed actual-single-r1 capture receipts."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
STAGE = ROOT / "factory/native/windows/padding-window-diagnosis-capture-v2"
RUN = STAGE / "actual-single-r1"
NATIVE = RUN / "native-01"
COORD = STAGE / "coordinator-single-r1"
REVIEW = STAGE / "actual-failure-review-v1"


def read(p: Path):
    return json.loads(p.read_text(encoding="utf-8-sig"))


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    outcome = read(NATIVE / "capture-outcome.json")
    cert = read(NATIVE / "final-exit-certificate.json")
    start = read(NATIVE / "final-start.json")
    terminal = read(NATIVE / "terminal-worker.json")
    timing = read(NATIVE / "lifecycle-timing.json")
    worker = read(NATIVE / "uia-worker/worker-exit.json")
    worker_failure = read(NATIVE / "uia-worker/worker-exit-failure.json")
    coordinator = read(COORD / "coordinator.json")
    checks: list[dict[str, object]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})

    # Receipt bytes are immutable evidence; all hashes are retained in report.
    receipt_paths = [
        NATIVE / "capture-outcome.json", NATIVE / "final-exit-certificate.json",
        NATIVE / "final-start.json", NATIVE / "lifecycle-timing.json",
        NATIVE / "terminal-worker.json", NATIVE / "uia-worker/worker-exit.json",
        NATIVE / "uia-worker/worker-exit-failure.json", COORD / "coordinator.json",
        COORD / "task-result.json", NATIVE / "host.stdout.txt", NATIVE / "host.stderr.txt",
    ]
    receipt_hashes = {str(p.relative_to(STAGE)): {"sha256": sha(p), "bytes": p.stat().st_size}
                      for p in receipt_paths}
    check("renderer-failure", outcome["primaryError"] == "Owned renderer identity drift" and
          coordinator["error"] == "Interactive capture failed: Owned renderer identity drift",
          "capture & coordinator preserve exact failure")
    check("worker-failure", worker["status"] == "failed" and
          worker["primaryError"] == "Owned renderer identity drift", str(worker["primaryError"]))
    check("worker-cleanup-unconfirmed", worker["cleanup"]["confirmedOwnedExit"] is False and
          worker["cleanup"]["kernelWaitResult"] == 258 and
          worker["cleanup"]["killAttempted"] is True and
          worker["cleanup"]["status"] == "hold-cleanup", str(worker["cleanup"]))
    check("failure-receipt-before-drain", worker_failure["cleanup"]["confirmedOwnedExit"] is False and
          worker_failure["preCleanupKernelWaitResult"] is None and
          worker_failure["rawStreams"] == [], "durable failure receipt lacks natural worker exit/raw proof")
    check("renderer-final-cert-only", cert["sample"]["kernelBefore"] == 0 and
          cert["sample"]["kernelAfter"] == 0 and cert["sample"]["exitCode"] == 0 and
          cert["sample"]["retainedHandle"] == start["retainedHandle"] and
          cert["sample"]["handlePid"] == start["pid"] and
          all(s["hashQualification"] == "sealed-raw" and s["sealed"] and
              s["destinationClosed"] for s in cert["rawStreams"]),
          "final certificate proves renderer handle/raw closure only")
    check("final-certificate-byte-joins", sha(NATIVE / "final-exit-certificate.json") == terminal["finalCertificateHash"] and
          sha(NATIVE / "capture-outcome.json") == terminal["originalOutcomeHash"] and
          cert["start"] == start and terminal["start"] == start,
          "renderer final cert & original outcome exact hashes/lineage")
    check("host-window-close-observed", any("phase\":\"window-closed\"" in line
          for line in (NATIVE / "host.stdout.txt").read_text(errors="replace").splitlines()),
          "stdout includes renderer Bridge.onWindowClosed record")
    check("coordinator-hold-status", coordinator["status"] == "hold-harness-error" and
          coordinator["qualification"] == "hold" and coordinator["nativeParity"] == "hold",
          "failure remains unqualified")
    check("release-overclaim", coordinator["wholeBatchExitConfirmed"] is True and
          coordinator["lockReleased"] is True and coordinator["terminalResultConfirmed"] is True,
          "coordinator claims whole-batch exit/release despite worker failure")
    source = (STAGE / "coordinator.ps1").read_text()
    check("source-release-path", "$releaseAllowed=$true" in source and
          "if(-not(Test-FactoryFinalReleaseProof $certificate $expected $reader))" in source and
          "uia-worker" not in source,
          "fallback releases from renderer-only final cert; no UIA-worker proof gate")

    report = {
        "kind": "padding-window-diagnosis-capture-v2-actual-failure-review-v1",
        "verdict": "HOLD_WORKER_EXIT_AND_RELEASE",
        "scope": "read-only actual receipt audit; no native/remote/compiler/Git/lock actions",
        "failure": {
            "rendererPid": start["pid"], "workerPid": worker["ownedIdentity"]["pid"],
            "rendererPrimaryError": outcome["primaryError"],
            "workerPrimaryError": worker["primaryError"],
            "workerCleanup": worker["cleanup"],
            "coordinatorStatus": coordinator["status"],
            "coordinatorWholeBatchExitConfirmed": coordinator["wholeBatchExitConfirmed"],
            "coordinatorLockReleased": coordinator["lockReleased"],
        },
        "evidence": {
            "rendererInitial": {
                "utc": timing["observations"][0]["utc"],
                "kernelBefore": timing["observations"][0]["kernelBefore"],
                "exitCode": timing["observations"][0]["exitCode"],
            },
            "rendererFinal": cert["sample"],
            "workerFailureReceipt": worker_failure["cleanup"],
            "receiptHashes": receipt_hashes,
        },
        "findings": [
            {
                "severity": "release-blocker",
                "id": "auxiliary-worker-natural-exit-unconfirmed",
                "detail": "UIA worker receipt records status failed, renderer identity drift, kernel wait 258, killAttempted true, confirmedOwnedExit false. Final raw streams are sealed, but no natural worker exit proof exists; helper then disposes process object.",
                "required": "Require worker terminal receipt with kernel0/no-kill/sealed raw closure before any whole-batch release claim."
            },
            {
                "severity": "release-blocker",
                "id": "coordinator-renderer-only-release",
                "detail": "Coordinator records hold-harness-error yet sets wholeBatchExitConfirmed=true & lockReleased=true. Final fallback validates renderer final cert only; coordinator has no UIA-worker receipt gate.",
                "required": "Keep lock held unless task result is successful & every auxiliary owned worker has natural exit proof, or bind auxiliary proof into final release reader."
            },
        ],
        "checks": checks,
    }
    (REVIEW / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if all(x["ok"] for x in checks if x["name"] not in ("release-overclaim",)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
