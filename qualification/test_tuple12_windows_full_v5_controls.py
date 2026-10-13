#!/usr/bin/env python3
"""Pure source controls for strict matrix-v8 assembler v5; root runs it."""
from pathlib import Path
import importlib.util
from copy import deepcopy

ROOT = Path(__file__).resolve().parent
ASSEMBLER = ROOT / "assemble-tuple12-windows-full-v5.py"
spec = importlib.util.spec_from_file_location("full_v5", ASSEMBLER)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)
fixture_spec = importlib.util.spec_from_file_location("no_native_fixture", ROOT / "tuple12-takeover/matrix-assembler-v5/no-native-fixture.py")
assert fixture_spec is not None and fixture_spec.loader is not None
fixture_mod = importlib.util.module_from_spec(fixture_spec)
fixture_spec.loader.exec_module(fixture_mod)


def main() -> int:
    assert len(mod.CONFIGS) == 16
    assert len(mod.EXPECTED_DENOMINATORS) == 16
    assert len(fixture_mod.positive_fixture()) == 320
    assert len(fixture_mod.fault_fixture()) == 320
    assert fixture_mod.fault_fixture()[0]["status"] == "failed"
    expected = fixture_mod.PINS
    positive = fixture_mod.positive_fixture()
    ok, failures = mod.validate_batch(positive, expected)
    assert ok, failures
    assert len(failures) == 0
    fault = fixture_mod.fault_fixture()
    assert not mod.validate_batch(fault, expected)[0], "fault-fixture"
    for field, value in (("originalHandleRetained", False), ("jobHandleRetained", False), ("streamsDrained", False), ("activeReadable", False), ("cleanupZero", False)):
        fault = deepcopy(positive); fault[0]["coordinatorKernel"][field] = value
        assert not mod.validate_batch(fault, expected)[0], field
    fault = deepcopy(positive); fault[0]["coordinatorKernel"]["activeProcesses"] = 1
    assert not mod.validate_batch(fault, expected)[0], "activeProcesses"
    assert not mod.validate_batch(positive[:-1], expected)[0], "count320"
    assert not mod.validate_batch(positive[1:] + [deepcopy(positive[1])], expected)[0], "duplicate-coordinate"
    assert mod.RUNNER_HASH == "PENDING_ROOT_HASH" or mod.SHA256.fullmatch(mod.RUNNER_HASH)
    source = ASSEMBLER.read_text(encoding="utf-8")
    for needle in (
        "sr0-tuple12-matrix-run-v8", "coordinator_ok", "cleanupZero",
        "activeProcesses", "streamsDrained", "originalHandleRetained", "jobHandleRetained", "peakRssBytes", "rssSamples",
        "def validate(", "def validate_batch(", "count320", "duplicate-config-run",
        "CreateProcess(CREATE_SUSPENDED)", "AssignProcessToJobObject", "ResumeThread",
        "10800", "8388608", "2147483648", "sr0-tuple12-windows-full-report-v5",
        '"requiredRuns": 320',
    ):
        assert needle in source, needle
    good = {"coordinatorKernel": {"terminal": True, "streamsDrained": True, "assigned": True, "activeReadable": True, "cleanupZero": True, "originalHandleRetained": True, "jobHandleRetained": True, "activeProcesses": 0, "timedOut": False, "outputExceeded": False, "rssExceeded": False, "processId": 1, "peakRssBytes": 1, "rssSamples": 1, "deadlineSeconds": 1200, "streamCapBytes": 8388608, "rssCapBytes": 2147483648}}
    assert mod.coordinator_ok(good)[0]
    for field in ("cleanupZero", "activeReadable", "streamsDrained"):
        bad = {"coordinatorKernel": dict(good["coordinatorKernel"], **{field: False})}
        assert not mod.coordinator_ok(bad)[0], field
    bad = {"coordinatorKernel": dict(good["coordinatorKernel"], activeProcesses=1)}
    assert not mod.coordinator_ok(bad)[0]
    print("tuple12 Full16x20 assembler v5 source controls: PASS strict v8 supervisor gates")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
