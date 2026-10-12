"""Bounded source controls for Count1/Count20 lifecycle overlay.

This control inspects only own four PS1 sources; it launches nothing & is not native evidence.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = {
    "coordinator": ROOT / "coordinator-count20-lifecycle-v1.ps1",
    "interactive": ROOT / "interactive-task-rectangle-count20-v1.ps1",
    "dispatch": ROOT / "dispatch-rectangle-count20-v1.ps1",
    "capture": ROOT / "capture-rectangle-count20-v1.ps1",
}

def read(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or st.st_size > 512 * 1024:
        raise AssertionError(f"bounded source required: {path}")
    return path.read_text(encoding="utf-8")

def main() -> int:
    text = {key: read(path) for key, path in FILES.items()}
    assert "@(1,20)" in text["coordinator"]
    assert "@(1,20)" in text["interactive"]
    assert "ValidateSet(1,20)" in text["dispatch"]
    assert "ValidateSet(1,20)" in text["capture"]
    assert "$c.count" in text["coordinator"] and "Assert-LeaseIssuedMetadata" in text["coordinator"]
    assert "-Count ([int]$c.count)" in text["coordinator"]
    assert "$sourceDocument.count -ne $Count" in text["dispatch"]
    assert "$sourceDocument.count -ne $Count" in text["capture"]
    assert "dispatch.repeat" in text["dispatch"]
    assert "native-{0:00}" in text["capture"]
    assert "@($issuedMetadata.captures).Count -ne $Count" in text["capture"]
    assert "Sort-Object -Unique).Count -ne $Count" in text["capture"]
    assert "CreateCurrentProcess(1073741824)" in text["interactive"]
    assert "WaitForOnlyCurrent" in text["interactive"]
    assert "Assert-RootRectangleAllOwnedRelease" in text["coordinator"]
    assert "wholeBatchExitConfirmed=$release" in text["coordinator"]
    assert "$captureBudgetSeconds=if($c.count -eq 20){600}else{60}" in text["coordinator"]
    assert "$outerBudgetSeconds=$setupBudgetSeconds+$captureBudgetSeconds+$cleanupBudgetSeconds" in text["coordinator"]
    assert "$schedulerMinutes=if($c.count -eq 20){15}else{5}" in text["coordinator"]
    assert "AddSeconds($captureBudgetSeconds)" in text["coordinator"]
    print("SOURCE_CONTROLS_PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
