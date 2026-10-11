#!/usr/bin/env python3
"""Source control capsule for supervise-job-v2.

This capsule is intentionally additive: each case writes into its own fresh
control directory and leaves every receipt available for review.  It checks
inventory faults, owned-group cleanup, and retained wall/log/RSS budgets.
Run this capsule itself under supervise-job-v2 or supervise-job.py so its
control process is bounded too.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


MAX_JSON = 1024 * 1024
V2 = Path(__file__).with_name("supervise-job-v2.py")


def read_json(path: Path) -> dict:
    stat = path.stat()
    if not path.is_file() or stat.st_size > MAX_JSON:
        raise RuntimeError(f"bounded JSON input rejected: {path}")
    with path.open("rb") as stream:
        value = json.loads(stream.read(MAX_JSON + 1))
    if not isinstance(value, dict):
        raise RuntimeError(f"receipt is not an object: {path}")
    return value


def run_case(root: Path, name: str, child: str, *, seconds: int = 5,
             rss_mib: int = 128, log_mib: int = 1,
             fault: str = "none") -> dict:
    output = root / name
    command = [
        sys.executable, str(V2), "--seconds", str(seconds),
        "--rss-mib", str(rss_mib), "--log-mib", str(log_mib),
        "--out", str(output), "--test-inventory-fault", fault, "--",
        sys.executable, "-c", child,
    ]
    completed = subprocess.run(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20, check=False,
    )
    receipt = read_json(output / "receipt.json")
    if completed.stdout == "":
        raise RuntimeError(f"{name}: supervisor emitted no receipt line")
    return receipt


def require(value: bool, message: str) -> None:
    if not value:
        raise RuntimeError(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--control-root", type=Path, required=True)
    args = parser.parse_args()
    args.control_root.mkdir(parents=True, exist_ok=False)

    sleep_short = "import time; time.sleep(0.8)"
    sleep_long = "import time; time.sleep(30)"
    fork_and_wait = (
        "import subprocess,sys,time; "
        "subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
        "time.sleep(30)"
    )
    orphaned_descendant = (
        "import subprocess,sys,time; "
        "subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)']); "
        "time.sleep(0.2)"
    )
    noisy = "import sys; sys.stdout.write('x'*(2*1024*1024)); sys.stdout.flush()"
    memory = "import time; payload=bytearray(16*1024*1024); payload[0]=1; time.sleep(5)"

    receipts = {
        "baseline": run_case(args.control_root, "baseline", sleep_short),
        "live-retry": run_case(args.control_root, "live-retry", sleep_short, fault="live-retry"),
        "after-exit": run_case(args.control_root, "after-exit", sleep_short, fault="after-exit"),
        "live-timeout": run_case(args.control_root, "live-timeout", fork_and_wait, seconds=1, fault="live-timeout"),
        "orphaned-descendant": run_case(args.control_root, "orphaned-descendant", orphaned_descendant),
        "log-budget": run_case(args.control_root, "log-budget", noisy, seconds=5, log_mib=1),
        "wall-budget": run_case(args.control_root, "wall-budget", sleep_long, seconds=1),
        "rss-budget": run_case(args.control_root, "rss-budget", memory, seconds=5, rss_mib=1),
    }

    baseline = receipts["baseline"]
    require(baseline["kind"] == "factory-supervised-local-job-v2", "baseline kind")
    require(baseline["budgetFailure"] is None, "baseline unexpectedly failed budget")
    require(baseline["quiescenceKnown"] and baseline["ownedGroupQuiescent"], "baseline not quiescent")

    retry = receipts["live-retry"]
    require(retry["budgetFailure"] is None, "live retry unexpectedly failed")
    require(retry["inventory"]["attempts"] >= 3, "live retry did not retry inventory")
    require(retry["quiescenceKnown"] and retry["ownedGroupQuiescent"], "live retry not quiescent")

    after_exit = receipts["after-exit"]
    require(after_exit["budgetFailure"] == "inventory-unavailable", "post-exit fault not fail-closed")
    require(not after_exit["quiescenceKnown"] and not after_exit["ownedGroupQuiescent"], "unknown inventory was certified")
    require(after_exit["inventory"]["errors"], "post-exit inventory fault was not recorded")

    live_timeout = receipts["live-timeout"]
    require(live_timeout["budgetFailure"] == "inventory-unavailable", "live timeout did not fail closed")
    require(live_timeout["termination"], "live timeout produced no owned termination record")
    require(live_timeout["quiescenceKnown"] and live_timeout["ownedGroupQuiescent"], "owned descendants not cleaned")

    orphaned = receipts["orphaned-descendant"]
    require(orphaned["budgetFailure"] == "owned-group-not-quiescent", "known residual group was not rejected")
    require(orphaned["termination"], "known residual group produced no termination record")
    require(orphaned["quiescenceKnown"] and orphaned["ownedGroupQuiescent"], "known residual group was not cleaned")

    require(receipts["log-budget"]["budgetFailure"] == "log-budget", "log budget missing")
    require(receipts["wall-budget"]["budgetFailure"] == "wall-time-budget", "wall budget missing")
    require(receipts["rss-budget"]["budgetFailure"] == "rss-budget", "RSS budget missing")

    summary = {
        "kind": "supervise-job-v2-controls-source",
        "cases": {name: {"budgetFailure": receipt["budgetFailure"], "quiescenceKnown": receipt["quiescenceKnown"], "ownedGroupQuiescent": receipt["ownedGroupQuiescent"]} for name, receipt in receipts.items()},
        "nativeActions": 0,
    }
    (args.control_root / "controls-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
