#!/usr/bin/env python3
"""Pure source controls for strict tuple12 matrix worker/coordinator/runner v4."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/matrix-controls-v4"
WORKER = SRC / "worker-v4.ps1"
COORD = SRC / "coordinator-v4.ps1"
RUNNER = SRC / "run-matrix-v4.ps1"

DENOMS = {
    "'F1|' = 17", "'F2|' = 13", "'F3|list-0s' = 15", "'F3|list-1s' = 15",
    "'F3|list-3s' = 15", "'F3|vstack-1s' = 15", "'F3|vstack-3s' = 15",
    "'F3|lazy-1s' = 15", "'F3|lazy-3s' = 15", "'F4|' = 12", "'F5|' = 13",
    "'F6|' = 16", "'F6|reduced' = 11", "'F7|' = 20", "'F8|' = 15", "'F9|' = 11",
}


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(worker, coord, runner):
    for n in (
        "kind = 'sr0-tuple12-startupguard-matrix-worker-v4'",
        "$selftestLabel = if ($Variant)",
        "$denominatorKey = \"$Fixture|$Variant\"",
        "SELFTEST-STAGES {0}:",
        "ASSERT {0} script-completed: PASS",
        "ASSERT {0} renderer-no-violations: PASS",
        "ASSERT {0} commits-accepted: PASS",
        "ASSERT {0} no-measure-or-draw-failures: PASS",
        "SELFTEST {0}: PASS ({1}/{1} asserted",
        "unsupported fixture/variant denominator",
        "worker-v4",
        "semantic proof failed",
    ):
        if n not in worker + coord:
            fail("positive", n)
    for n in DENOMS:
        if n not in worker:
            fail("denominator", n)
    for n in (
        "kind='sr0-tuple12-matrix-run-v4'",
        "sr0-tuple12-startupguard-matrix-worker-v4",
        "if ($cfg.Variant) { $coordinatorArguments += @('-Variant',$cfg.Variant) }",
        "MATRIX_PASS mode=",
        "targetedDelivery=$true",
        "noActivate=$true",
    ):
        if n not in runner:
            fail("runner", n)
    if "'SR0-T12-F1-'" in coord:
        fail("coordinator", "fixture hardcoded in task name")
    for text in (worker, coord, runner):
        if "Remove-Item" in text or ".Kill()" in text:
            fail("destructive", "destructive process/output action")


def main():
    worker = WORKER.read_text(encoding="utf-8")
    coord = COORD.read_text(encoding="utf-8")
    runner = RUNNER.read_text(encoding="utf-8")
    positive(worker, coord, runner)
    mutations = (
        ("unqualified-selftest", lambda w, c, r: (w.replace("$selftestLabel = if ($Variant)", "$selftestLabel = $Fixture #", 1), c, r)),
        ("wrong-f3-denominator", lambda w, c, r: (w.replace("'F3|list-0s' = 15", "'F3|list-0s' = 14", 1), c, r)),
        ("missing-stage-assertion", lambda w, c, r: (w.replace("ASSERT {0} renderer-no-violations: PASS", "ASSERT {0} renderer-no-violations: OMIT", 1), c, r)),
        ("worker-kind-v3", lambda w, c, r: (w.replace("worker-v4", "worker-v3"), c.replace("worker-v4", "worker-v3"), r.replace("worker-v4", "worker-v3"))),
        ("missing-matrix-pass", lambda w, c, r: (w, c, r.replace("MATRIX_PASS mode=", "MATRIX_DONE mode=", 1))),
        ("activation-admission", lambda w, c, r: (w, c, r.replace("noActivate=$true", "noActivate=$false", 1))),
    )
    caught=[]
    for label, mutate in mutations:
        try: positive(*mutate(worker, coord, runner))
        except AssertionError: caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 matrix v4 controls: PASS positive + 6 mutation faults")
    for path in (WORKER, COORD, RUNNER):
        print(path.name + "_sha256=" + hashlib.sha256(path.read_bytes()).hexdigest())

if __name__ == "__main__":
    raise SystemExit(main())
