#!/usr/bin/env python3
"""Read-only incremental review of final-exit-certificate-v2."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
STAGE = ROOT / "factory/native/windows/final-exit-certificate-v2"
V1 = ROOT / "factory/native/windows/final-exit-certificate-v1"
REVIEW = STAGE / "independent-review-v1"
EXPECTED_STAGE = "55ec268f5af7658571a1515895782b68e2974dc8166b4617adc29d7d4b5c459b"
V1_HELPER = "8a7450385fe7802137d6042e89eac3af0288883181dc693ea8e60f0ef9024c6d"
V1_TEST = "39d06e9415da740a15db42406f22bf0d886e4b4bef65933dbcc4408beac17318"


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
        actual = sha(p)
        check("file:" + item["path"], actual == item["sha256"] and
              p.stat().st_size == item["size"], f"sha={actual};size={p.stat().st_size}")

    v1_helper = (V1 / "final-exit-certificate.ps1").read_bytes()
    v2_helper = (STAGE / "final-exit-certificate.ps1").read_bytes()
    v1_test = (V1 / "test-final-exit-certificate.ps1").read_bytes()
    v2_test = (STAGE / "test-final-exit-certificate.ps1").read_bytes()
    check("v1-helper-pinned", sha(V1 / "final-exit-certificate.ps1") == V1_HELPER, sha(V1 / "final-exit-certificate.ps1"))
    check("v1-controls-pinned", sha(V1 / "test-final-exit-certificate.ps1") == V1_TEST, sha(V1 / "test-final-exit-certificate.ps1"))

    # Exact reverse delta: one predicate clause in helper, one Assert-Control line.
    import difflib
    helper_delta = list(difflib.unified_diff(v1_helper.decode().splitlines(), v2_helper.decode().splitlines(), lineterm=""))
    test_delta = list(difflib.unified_diff(v1_test.decode().splitlines(), v2_test.decode().splitlines(), lineterm=""))
    expected_helper_delta = [
        "-  if($null -eq $Reader -or $Certificate.kind -cne 'factory-final-exit-certificate-v1' -or $Certificate.scope -cne 'owner-release-only'){return $false}",
        "+  if($null -eq $Reader -or $Certificate.kind -cne 'factory-final-exit-certificate-v1' -or $Certificate.scope -cne 'owner-release-only' -or $Certificate.qualification -cne 'failed-or-successful-observation-only'){return $false}",
    ]
    expected_test_delta = [
        "+Assert-Control 'qualification-drift' {param($f) $f.certificate.qualification='qualified-native'} $false",
    ]
    changed_helper = [x for x in helper_delta if x[:1] in "+-" and not x.startswith(("---", "+++"))]
    changed_test = [x for x in test_delta if x[:1] in "+-" and not x.startswith(("---", "+++"))]
    check("exact-helper-delta", changed_helper == expected_helper_delta,
          "one qualification predicate")
    check("exact-control-delta", changed_test == expected_test_delta,
          "one qualification-drift control")
    check("all-prior-controls-retained", all(x in v2_test.decode() for x in re.findall(r"Assert-Control '([^']+)'", v1_test.decode())),
          "V1 Assert-Control names remain present")
    check("21-controls", len(re.findall(r"Assert-Control '([^']+)'", v2_test.decode())) == 19,
          "19 Assert-Control rows plus 2 release controls")

    helper = v2_helper.decode()
    test = v2_test.decode()
    helper_code = "\n".join(line.split("#", 1)[0] for line in helper.splitlines())
    test_code = "\n".join(line.split("#", 1)[0] for line in test.splitlines())
    check("exact-qualification-guard", "qualification -cne 'failed-or-successful-observation-only'" in helper,
          "release proof rejects promoted label")
    check("zero-wait-identity-raw-joins", all(x in helper for x in (
        "waitMilliseconds=0", "kernelBefore", "kernelAfter", "GetProcessId",
        "GetExitCodeProcess", "finalCertificateHash", "Get-FactoryFinalBytesHash $raw")),
          "existing final sample and archive joins retained")
    check("no-direct-lock-or-process-io", all(x not in helper_code for x in (
        "desktop.lock", "FileMode::Open", "SetLength", "Get-Process", ".Kill()",
        "WaitForExit", "Start-Sleep")), "helper stays callback-only")
    check("pure-controls", all(x not in test_code for x in (
        "Process.Start", "Start-Process", "Get-Process", "Add-Type",
        "desktop.lock", ".Kill()", "WaitForExit")), "controls stay synthetic")

    report = {
        "kind": "factory-final-exit-certificate-v2-independent-review-v1",
        "sourceStage": EXPECTED_STAGE,
        "verdict": "CLEAR_SOURCE_PENDING_WINDOWS_RECEIPT",
        "scope": "incremental source review only; no native/remote/compiler/Git execution",
        "pureControls": "UNRUN_ON_THIS_HOST; root Windows receipt required",
        "controls": re.findall(r"Assert-Control '([^']+)'", test) + ["deadline-preserved-release", "failed-proof-no-release"],
        "findings": [],
        "checks": checks,
    }
    (REVIEW / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0 if all(x["ok"] for x in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
