#!/usr/bin/env python3
"""Source/receipt controls for workload analyzer v3 calibration split."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", type=Path, required=True)
    args = ap.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    failures: list[str] = []
    if report.get("overall") != "INCOMPLETE":
        failures.append("negative packet unexpectedly qualified")
    reasons = " | ".join(report.get("refusal_reasons", []))
    if "window not displayed" not in reasons:
        failures.append("displayed-row refusal disappeared")
    if "presentmon.console.txt missing" not in reasons:
        failures.append("missing-console fault disappeared")
    for run in ("r1", "r2", "r3"):
        checks = report.get("runs", {}).get(run, {}).get("checks", [])
        cal = [c for c in checks if c.get("id") == "CAL" and "clock correlation" in c.get("name", "")]
        if len(cal) != 1 or cal[0].get("status") != "PASS" or float(cal[0].get("value", 99)) > 2:
            failures.append(f"{run} all-present calibration was not restored")
    failed_ids = {(c.get("id"), c.get("run")) for c in report.get("failed", [])}
    for key in (("W2", "r2"), ("W6", "r2")):
        if key not in failed_ids:
            failures.append(f"genuine {key[0]} {key[1]} fault disappeared")
    if failures:
        for item in failures:
            print(f"FAIL {item}")
        return 1
    print("PASS analyzer-v3: all-present QPC calibration passes; dropped-display, console, W2, W6 faults remain")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
