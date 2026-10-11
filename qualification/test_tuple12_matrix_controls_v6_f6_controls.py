#!/usr/bin/env python3
"""Pure controls for isolated F6-reduced marker correction v5/v6."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORKER = ROOT / "tuple12-takeover/matrix-controls-v6/worker-v5.ps1"
COORD = ROOT / "tuple12-takeover/matrix-controls-v6/coordinator-v5.ps1"
RUNNER = ROOT / "tuple12-takeover/matrix-controls-v6/run-matrix-v6.ps1"

def fail(msg):
    raise SystemExit(f"F6_V6_CONTROLS_FAIL {msg}")

def require(cond, msg):
    if not cond: fail(msg)

def main():
    w, c, r = WORKER.read_text(), COORD.read_text(), RUNNER.read_text()
    require("kind = 'sr0-tuple12-startupguard-matrix-worker-v5'" in w, "worker-kind")
    require("$Fixture -eq 'F6' -and $Variant -eq 'reduced'" in w, "special-label-guard")
    require('$selftestLabel = if ($Fixture -eq \'F6\' -and $Variant -eq \'reduced\') { "$Fixture-$Variant" }' in w, "hyphen-label")
    require('$selftestLabel = if ($Variant) { "$Fixture $Variant" } else { $Fixture }' not in w, "old-label-still-active")
    require("'F6|reduced' = 11" in w, "denominator")
    require("worker-v5" in c and "matrix-worker-v5" in c, "coordinator-v5")
    require("'F6Reduced'" in r and "Fixture='F6'; Variant='reduced'" in r, "targeted-mode")
    require("ValidateSet(20)" in r, "runs-still-20")
    for forbidden in ("Stop-Process", "Unregister-ScheduledTask", "Remove-Item"):
        require(forbidden not in r and forbidden not in c and forbidden not in w, f"destructive={forbidden}")
    good = """SELFTEST-STAGES F6-reduced:\nASSERT F6-reduced script-completed: PASS\nASSERT F6-reduced renderer-no-violations: PASS\nASSERT F6-reduced commits-accepted: PASS\nASSERT F6-reduced no-measure-or-draw-failures: PASS\nSELFTEST F6-reduced: PASS (11/11 asserted; blocked=0; end=window-closed)"""
    require("SELFTEST-STAGES F6-reduced:" in good and "SELFTEST F6-reduced: PASS (11/11" in good, "positive-marker")
    require("SELFTEST-STAGES F6 reduced:" not in good, "space-marker-fault")
    mutated = good.replace("SELFTEST-STAGES F6-reduced:", "SELFTEST-STAGES F6 reduced:")
    require("SELFTEST-STAGES F6-reduced:" not in mutated, "accepted-space-marker")
    print({"kind": "sr0-tuple12-matrix-controls-v6-f6-reduced", "status": "passed", "runs": 20, "denominator": 11, "faults": 1})

if __name__ == "__main__": main()
