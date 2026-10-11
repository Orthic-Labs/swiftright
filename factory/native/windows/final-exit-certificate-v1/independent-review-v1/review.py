#!/usr/bin/env python3
"""Read-only source admission checks for final-exit-certificate-v1."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[5]
STAGE = ROOT / "factory/native/windows/final-exit-certificate-v1"
REVIEW = STAGE / "independent-review-v1"
EXPECTED_STAGE = "e2672aef4a123e808a0b7b34629f61ff4a39ac5763481a8a9234119e8adfe308"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    manifest_path = STAGE / "root-stage-manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    checks: list[dict[str, object]] = []
    def check(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})

    check("stage-manifest-sha", sha(manifest_path) == EXPECTED_STAGE,
          sha(manifest_path))
    listed = []
    for item in manifest["files"]:
        p = ROOT / item["path"]
        listed.append(item["path"])
        actual = sha(p)
        check("file:" + item["path"], actual == item["sha256"] and
              p.stat().st_size == item["size"],
              f"sha={actual};size={p.stat().st_size}")
    check("manifest-file-count", listed == [x["path"] for x in manifest["files"]],
          f"count={len(listed)}")

    helper_path = STAGE / "final-exit-certificate.ps1"
    test_path = STAGE / "test-final-exit-certificate.ps1"
    helper = helper_path.read_text(encoding="utf-8")
    test = test_path.read_text(encoding="utf-8")
    # Ignore PowerShell comments when checking executable API use. Here-string
    # C# declarations remain visible because they contain no PowerShell '#'.
    helper_code = "\n".join(line.split("#", 1)[0] for line in helper.splitlines())
    test_code = "\n".join(line.split("#", 1)[0] for line in test.splitlines())
    required = {
        "strict-start-identity": all(x in helper for x in (
            "retainedHandle", "pid", "lockOwner", "workerId",
            "compileReceiptHash", "exeHash")),
        "zero-wait-double-kernel": all(x in helper for x in (
            "waitMilliseconds=0", "WaitForSingleObject($OriginalRetainedHandle,0)",
            "$sample.kernelBefore", "$sample.kernelAfter")),
        "same-handle-pid-exit": all(x in helper for x in (
            "$Sample.retainedHandle -ne $Start.retainedHandle",
            "$Sample.handlePid -ne $Start.pid", "GetProcessId", "GetExitCodeProcess")),
        "sealed-raw-join": all(x in helper for x in (
            "taskStatus", "closureTaskStatus", "hashQualification", "destinationClosed",
            "Get-FactoryFinalBytesHash $raw")),
        "lineage-byte-joins": all(x in helper for x in (
            "workerReceiptHash", "finalCertificateHash", "compileReceiptRef",
            "exeRef", "ConvertFrom-Json")),
        "release-after-proof": all(x in helper for x in (
            "if(-not(Test-FactoryFinalReleaseProof", "& $Release $Expected.lockOwner")),
        "no-direct-lock-io": all(x not in helper_code for x in (
            "desktop.lock", "FileMode::Open", "SetLength", "Get-Process", ".Kill()",
            "WaitForExit", "Start-Sleep")),
        "controls-pure": all(x not in test_code for x in (
            "Process.Start", "Start-Process", "Get-Process", "Add-Type",
            "desktop.lock", ".Kill()", "WaitForExit")),
    }
    for name, ok in required.items():
        check(name, ok, "required source tokens present" if ok else "missing or forbidden token")

    control_names = re.findall(r"Assert-Control '([^']+)'", test)
    check("twenty-controls", len(control_names) == 18,
          f"assert-controls={len(control_names)} plus 2 release controls")
    check("failed-outcome-preserved", all(x in test for x in (
        "primaryError='Owned renderer child deadline'", "qualification='hold'",
        "nativeParity='hold'", "Failure outcome changed", "CALLBACK_REACHED")),
          "deadline failure and callback refusal controls present")

    # Constructor emits this immutable semantic value, but proof currently only
    # checks kind/scope. This allows a hash-bound archived certificate carrying
    # an altered qualification label to reach owner release.
    qualification_guard = "qualification -cne 'failed-or-successful-observation-only'" in helper
    check("qualification-immutable-in-proof", qualification_guard,
          "proof must reject certificate qualification drift")

    report = {
        "kind": "factory-final-exit-certificate-independent-review-v1",
        "sourceStage": EXPECTED_STAGE,
        "verdict": "HOLD_QUALIFICATION_BINDING",
        "scope": "read-only source review; no native/remote/compiler/Git execution",
        "pureControls": "UNRUN_ON_THIS_HOST; root Windows receipt required",
        "controls": control_names + ["deadline-preserved-release", "failed-proof-no-release"],
        "findings": [{
            "severity": "admission-blocker",
            "id": "certificate-qualification-not-bound",
            "file": "factory/native/windows/final-exit-certificate-v1/final-exit-certificate.ps1",
            "function": "Test-FactoryFinalReleaseProof",
            "detail": "Proof enforces kind/scope, start lineage, worker/cert/raw/compile/exe hashes, but does not enforce qualification == failed-or-successful-observation-only. Constructor emits label, yet an archived cert with altered qualification can pass owner-release proof.",
            "fix": "Require exact qualification label in proof & add one negative control mutating it; preserve qualification as diagnostic-only."
        }],
        "checks": checks,
    }
    (REVIEW / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if all(x["ok"] for x in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
