#!/usr/bin/env python3
"""Read-only supplemental release gate for archived SR0 native-r10c.

It never opens, mutates, unlocks, terminates, or reopens any process.  It
separates terminal-child evidence from desktop-lock release eligibility.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

MAX_JSON = 2 * 1024 * 1024
MAX_TEXT = 4 * 1024 * 1024
EXPECTED_MEMORY = 1073741824
EXPECTED_FLAGS = 512


class Hold(Exception):
    pass


def read_json(path: Path) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON:
        raise Hold(f"unsafe or oversized JSON: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_TEXT:
        raise Hold(f"unsafe or oversized evidence: {path}")
    h = hashlib.sha256()
    with path.open("rb") as f:
        while block := f.read(1024 * 1024):
            h.update(block)
    return h.hexdigest()


def gate(root: Path) -> dict[str, Any]:
    run = root / "run"
    launcher = read_json(run / "launcher-receipt.json")
    collector = read_json(run / "collector-receipt.json")
    coordinator = read_json(run / "coordinator-verdict.json")
    start = read_json(run / "start-receipt.json")
    holds: list[str] = []

    if launcher.get("status") != "completed":
        holds.append("launcher status is held, not completed")
    if launcher.get("coordinatorTerminal") is not True or launcher.get("coordinatorExitIdentity") is not True:
        holds.append("coordinator retained-handle terminal/exit identity incomplete")
    if launcher.get("collectorTerminal") is not True or launcher.get("collectorExitIdentity") is not True:
        holds.append("collector retained-handle terminal/exit identity incomplete")
    if launcher.get("aggregateDescendantsQuiesced") is not True or launcher.get("aggregateSelfOnly") is not True:
        holds.append("aggregate descendant quiescence/self-only proof incomplete")
    if launcher.get("aggregateActiveAfter") != 1:
        holds.append("aggregate active count is not retained self-only count 1")
    if launcher.get("aggregateJobMemoryLimitBytes") != EXPECTED_MEMORY or launcher.get("aggregateLimitFlags") != EXPECTED_FLAGS:
        holds.append("aggregate memory admission differs from 1GiB flags 512")
    if launcher.get("aggregateMemoryCapExceeded") is not False:
        holds.append("aggregate memory cap proof missing")

    for key in ("parentOriginalHandleRetained", "parentOriginalHandleAcquired", "presentMonHandleAcquired", "presentMonTerminal", "presentMonExitIdentity", "workloadHandleAcquired", "workloadTerminal", "workloadExitIdentity"):
        if collector.get(key) is not True:
            holds.append(f"collector field {key} is not proven true")
    if collector.get("workloadExit") != 0:
        holds.append("workload exit is not zero")
    if collector.get("presentMonExitSigned") != -1 or collector.get("presentMonStopExit") != 0:
        holds.append("forced-owned PresentMon stop identity is incomplete")
    if collector.get("presentMonStreamsSealed") is not True:
        holds.append("PresentMon stream seal proof is absent")
    if collector.get("presentMonCsvEvidence") is None:
        holds.append("PresentMon CSV evidence is absent")
    if collector.get("presentMonStderrEvidence") is None:
        holds.append("PresentMon stderr evidence is absent")
    if collector.get("lockReleased") is not False or collector.get("releaseAllowed") is not False:
        holds.append("collector lock state is not an explicit held state")
    if coordinator.get("parentCertificatePresent") is not True:
        holds.append("coordinator parent certificate is absent")
    if coordinator.get("parentKernelTerminal") is not True or coordinator.get("parentExitSigned") != 0 or coordinator.get("parentExitDotnet") != 0:
        holds.append("coordinator parent terminal proof is not zero")
    if coordinator.get("status") != "completed":
        holds.append("coordinator status is held")

    # Raw files may corroborate bytes, but cannot manufacture stream sealing.
    raw = {}
    for name in ("presentmon.csv", "presentmon.stderr.txt", "presentmon.stdout.txt", "workload.stdout.txt", "workload.stderr.txt"):
        p = run / name
        if not p.is_file():
            holds.append(f"missing raw stream {name}")
        else:
            raw[name] = {"bytes": p.stat().st_size, "sha256": sha256(p)}
    return {
        "kind": "sr0-display-supplemental-release-v1",
        "status": "held" if holds else "eligible-for-owner-release-review",
        "releaseEligible": not holds,
        "processActions": "none",
        "desktopLockAction": "none",
        "childrenTerminalObserved": launcher.get("aggregateDescendantsQuiesced") is True and launcher.get("aggregateSelfOnly") is True,
        "holds": holds,
        "raw": raw,
        "source": "actual-native-r10c/run/{launcher,collector,coordinator,start}-receipt.json",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--archive-root", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    report = gate(args.archive_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if report["releaseEligible"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
