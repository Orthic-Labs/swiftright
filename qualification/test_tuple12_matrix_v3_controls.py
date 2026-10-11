#!/usr/bin/env python3
"""Pure controls for matrix coordinator/runner-v3 source pins."""
from pathlib import Path


ROOT = Path(__file__).parents[1] / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-matrix-v1"


def main() -> int:
    coordinator = (ROOT / "coordinator-v3.ps1").read_text(encoding="utf-8")
    runner = (ROOT / "run-matrix-v3.ps1").read_text(encoding="utf-8")
    coordinator_positive = (
        "[Parameter(Mandatory)][string]$ExpectDriver",
        "[Parameter(Mandatory)][string]$ExpectWorker",
        "sourcePins.actualDriver",
        "sourcePins.actualWorker",
        "driver source hash mismatch",
        "worker source hash mismatch",
        "sr0-tuple12-startupguard-matrix-worker-v2",
        "sr0-tuple12-startupguard-matrix-worker-v3",
        "workerKind = ($allowedWorkerKinds -contains [string]$proof.kind)",
        "driverKernelTerminal",
        "childKernelTerminal",
        "driverSourceHashExact",
        "      childPathExact = $childPathExact",
        "terminalChecks",
    )
    runner_positive = (
        "[Parameter(Mandatory)][string]$ExpectWorker",
        "[Parameter(Mandatory)][string]$ExpectCoordinator",
        "candidate worker source hash mismatch",
        "candidate coordinator source hash mismatch",
        "-ExpectDriver",
        "-ExpectWorker",
        "coordinatorArguments",
        "kind='sr0-tuple12-matrix-run-v3'",
    )
    if not all(x in coordinator for x in coordinator_positive):
        print("V3_CONTROLS_FAIL coordinator-positive")
        return 1
    if not all(x in runner for x in runner_positive):
        print("V3_CONTROLS_FAIL runner-positive")
        return 1
    mutations = {
        "coordinator-driver-pin": ("driverSourceHashExact", "removedDriverSourceHashExact"),
        "coordinator-child-identity": ("      childPathExact = $childPathExact", "      removedChildPathExact = $childPathExact"),
        "coordinator-worker-kind": ("workerKind = ($allowedWorkerKinds -contains [string]$proof.kind)", "workerKind = $true"),
        "runner-worker-pin": ("candidate worker source hash mismatch", "removed worker source hash mismatch"),
        "runner-coordinator-pin": ("candidate coordinator source hash mismatch", "removed coordinator source hash mismatch"),
    }
    for name, (old, replacement) in mutations.items():
        source = coordinator if name.startswith("coordinator") else runner
        if old not in source:
            print(f"V3_CONTROLS_FAIL {name}-fixture")
            return 1
        mutated = source.replace(old, replacement, 1)
        needles = coordinator_positive if name.startswith("coordinator") else runner_positive
        if old in mutated or all(x in mutated for x in needles):
            print(f"V3_CONTROLS_FAIL {name}")
            return 1
        print(f"V3_CONTROLS_PASS {name}")
    print(f"V3_CONTROLS_PASS coordinator={len(coordinator_positive)} runner={len(runner_positive)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
