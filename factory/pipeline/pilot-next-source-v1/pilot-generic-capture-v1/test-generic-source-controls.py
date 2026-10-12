#!/usr/bin/env python3
"""Bounded static controls for generic Text/Circle adapter packet; no execution."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
MAX = 512 * 1024

def read(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX:
        raise AssertionError(f"bounded source required: {path}")
    return path.read_text(encoding="utf-8")

def main() -> int:
    contracts = json.loads(read(ROOT / "profile-contracts.json"))
    assert contracts["nativeActions"] == 0
    assert contracts["budgets"] == {"windowSeconds": 30, "exitSeconds": 15, "count1OuterSeconds": 300, "count20OuterSeconds": 840}
    supplemental = read(ROOT / "support" / "supplemental-no-start-release-v1.ps1")
    for marker in (
        "Assert-FactorySupplementalNoStartRelease", "worker-contract.json",
        "Process.Start", "Original coordinator parent exit-1 proof absent",
        "Self-only 1GiB memory proof absent", "Existing production renderer release proof failed",
        "contractFailureBeforeWorkerStart",
    ):
        assert marker in supplemental
    supplemental_controls = read(ROOT / "support" / "test-supplemental-no-start-release-controls.ps1")
    assert "Invoke-Supplemental" in supplemental_controls
    assert "wrong-owner" in supplemental_controls and "wrong-parent-exit" in supplemental_controls
    assert "extra-memory-child" in supplemental_controls and "worker-start-artifact" in supplemental_controls
    assert "lock-owner-drift" in supplemental_controls and "lockReleased=$false" in supplemental
    assert "lockFlushReadback=$true" in supplemental
    definite = read(ROOT / "support" / "definite-no-worker-start-v1.ps1")
    definite_controls = read(ROOT / "support" / "test-definite-no-worker-start-controls.ps1")
    for marker in ("Assert-FactoryDefiniteNoWorkerStart", "processStartReached", "contractFailureBeforeWorkerStart", "Pinned worker contract read-before-start proof absent"):
        assert marker in definite
    for marker in ("Invoke-Case", "started", "attempt-lineage", "worker-artifact", "wrong-error", "source-drift", "SOURCE_CONTROLS_PASS"):
        assert marker in definite_controls
    for name, profile in contracts["profiles"].items():
        assert profile["runtimeCommit"] == "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
        assert profile["rendererSha256"].startswith("sha256:") and len(profile["rendererSha256"]) == 71
        assert profile["recipeHash"].startswith("sha256:") and len(profile["recipeHash"]) == 71
        assert Path(ROOT / profile["sourceManifest"]).is_file()
        integration = read(ROOT / name / "integration.ps1")
        issuer = read(ROOT / name / "issue-metadata.ps1")
        single = read(ROOT / name / "capture-single.ps1")
        repeat = read(ROOT / name / "count20" / "capture-repeat.ps1")
        # Controls assert each source's production role; avoid artificial marker
        # requirements that cannot prove runtime behavior.
        assert "Assert-FactoryIntegrationSources" in integration
        assert "sourceHash" in integration and "tuple" in integration and "context" in integration
        assert "Assert-" in integration and "Get-FileHash" in integration
        assert "New-ID" in issuer and "captureID" in issuer and "imageID" in issuer
        assert "uiaWorkerPath" in issuer and "uiaWorkerHash" in issuer
        assert "Ref(" in issuer and "Json(" in issuer
        assert "Get-FileHash" in issuer and "CreateNew" in issuer
        assert "PreflightOnly" in single and "Assert-FactoryIntegrationSources" in single
        assert "uiaWorkerPath" in single and "uiaWorkerHash" in single
        assert "-Phase Launch" in single and "-CompileReceiptSha256" in single
        for capture_source in (single, repeat):
            assert "$workerSourceRoot=Join-Path $captureRoot 'dependencies\\uia-worker'" in capture_source
            assert "Invoke-FactoryUiaSnapshotWorker $target $workerRoot $workerGuard (Join-Path $captureRoot 'dependencies\\uia-worker')" in capture_source
            assert "uia-worker-prelaunch.json" in capture_source
            assert "contractFailureBeforeWorkerStart" in capture_source
            assert "processStartReached" in capture_source
            assert "noInvocationConfirmed" in capture_source
            assert "worker-launch-attempt.json" in capture_source
            assert "config.json" in capture_source and "final-start.json" in capture_source
            assert "owned-worker.json" in capture_source
        if name != "circle":
            assert "$plan.executionEligible -ne $true" in single
        assert "PreflightOnly" in repeat and "Assert-FactoryIntegrationSources" in repeat
        assert "uiaWorkerPath" in repeat and "uiaWorkerHash" in repeat
        assert "-Phase Launch" in repeat and "-CompileReceiptSha256" in repeat
        if name != "circle":
            assert "$plan.executionEligible -ne $true" in repeat
        if name == "circle":
            assert "system.blue" in integration and "frameDip" in integration
            assert "factory-circle-compiler-plan-v1" in issuer
            assert "Assert-CircleFinalPlanAdmission" in single and "Assert-CircleFinalPlanAdmission" in repeat
            eligibility = read(ROOT / name / "final-plan-eligibility.ps1")
            assert "function Assert-CircleFinalPlanAdmission" in eligibility
            assert "executionEligible -ne $true" in eligibility
            assert "phase -cne 'final'" in eligibility
            assert (ROOT / name / "test-final-plan-eligibility-controls.ps1").is_file()
        else:
            assert "font.family" in integration and "viewport" in integration
            assert "factory-text-compiler-plan-v1" in issuer
        assert "factory-" + profile["compileReceiptKind"][8:] in issuer
        # Local overlay names must resolve inside fresh profile root; source-manifest
        # provenance may retain historical donor names, but dispatch cannot.
        for rel in (
            "integration.ps1", "issue-metadata.ps1", "build-preflight.ps1",
            "capture-single.ps1", "dispatch-single.ps1", "interactive-single.ps1",
            "count20/capture-repeat.ps1", "count20/dispatch-repeat.ps1",
            "count20/interactive-repeat.ps1", "count20/controller.ps1",
        ):
            assert (ROOT / name / rel).is_file(), f"missing local overlay: {name}/{rel}"
        single_dispatch = read(ROOT / name / "dispatch-single.ps1")
        repeat_dispatch = read(ROOT / name / "count20" / "dispatch-repeat.ps1")
        single_interactive = read(ROOT / name / "interactive-single.ps1")
        repeat_interactive = read(ROOT / name / "count20" / "interactive-repeat.ps1")
        assert "capture-single.ps1" in single_dispatch
        assert "capture-repeat.ps1" in repeat_dispatch
        assert "dispatch-single.ps1" in single_interactive
        assert "dispatch-repeat.ps1" in repeat_interactive
    assert "sourceHash" in read(ROOT / "text" / "integration.ps1")
    assert "semanticColor" in read(ROOT / "circle" / "integration.ps1")
    print("SOURCE_CONTROLS_PASS generic-text-circle-count1-count20")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
