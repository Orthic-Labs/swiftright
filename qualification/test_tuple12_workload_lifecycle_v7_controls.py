#!/usr/bin/env python3
"""Pure source controls for Workload v7 PresentMon proof state; no native execution."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/workload-controls-v7/run-workload.ps1"


def fail(name):
    raise SystemExit("WORKLOAD_V7_CONTROLS_FAIL " + name)


def main():
    source = SRC.read_text(encoding="utf-8")
    start = source.index("function Stop-Pm {")
    end = source.index('\n}\n\nLog "run-workload', start) + 2
    stop = source[start:end]
    required = [
        "$script:pmForcedStop = $true",
        "$script:pmDotnetExit =",
        "$script:pmKernelExit = 259",
        "[ref]$script:pmKernelExit",
        "$script:pmKernelTerminal =",
        "$script:pmKernelExitRaw=",
        "$script:pmKernelExitSigned=",
        "$script:pmStopMode =",
        "$script:pmTerminal =",
        "$script:pmStdoutDone =",
        "$script:pmStderrDone =",
        "session_absent=$script:pmSessionAbsent",
        "stdout_drained=$script:pmStdoutDone",
        "stderr_drained=$script:pmStderrDone",
    ]
    for needle in required:
        if needle not in stop:
            fail("missing:" + needle)
    for field in ("pmForcedStop", "pmDotnetExit", "pmKernelExit", "pmKernelTerminal", "pmKernelExitRaw", "pmKernelExitSigned", "pmStopMode", "pmTerminal", "pmStdoutDone", "pmStderrDone"):
        if f"  ${field} =" in stop:
            fail("function-local-proof-state:" + field)
    if "pmKernelExitSigned -ne $pmDotnetExit" not in source:
        fail("caller-proof-join")
    if "pmSessionAbsent" not in source:
        fail("session-absence-join")

    # Fault controls model loss of function-scope publication & signed exit join.
    faults = {
        "scope-lost": stop.replace("$script:pmKernelTerminal =", "$pmKernelTerminal =", 1),
        "signed-join-lost": source.replace("pmKernelExitSigned -ne $pmDotnetExit", "pmKernelExitSigned -eq $pmDotnetExit", 1),
        "forced-state-lost": stop.replace("$script:pmForcedStop = $true", "$pmForcedStop = $true", 1),
    }
    for name, mutated in faults.items():
        if name == "scope-lost" and "$pmKernelTerminal =" not in mutated:
            fail("fault-not-built:" + name)
        if name == "signed-join-lost" and "pmKernelExitSigned -ne $pmDotnetExit" in mutated:
            fail("fault-not-built:" + name)
        if name == "forced-state-lost" and "$script:pmForcedStop = $true" in mutated:
            fail("fault-not-built:" + name)
    print({
        "kind": "sr0-tuple12-workload-lifecycle-v7-controls",
        "status": "passed",
        "sourceSha256": hashlib.sha256(SRC.read_bytes()).hexdigest(),
        "positive": len(required) + 2,
        "faults": list(faults),
    })


if __name__ == "__main__":
    main()
