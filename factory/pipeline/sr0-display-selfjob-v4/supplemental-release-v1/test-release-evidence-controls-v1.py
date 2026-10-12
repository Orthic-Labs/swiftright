#!/usr/bin/env python3
"""Controls for supplemental release gate; mutations call production evaluate()."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("sr0_release_gate", HERE / "validate-release-evidence-v1.py")
if _spec is None or _spec.loader is None:
    raise SystemExit("production release gate import failed")
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)
evaluate, read_json = _module.evaluate, _module.read_json


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--collector", required=True)
    ap.add_argument("--launcher", required=True)
    ap.add_argument("--observer", required=True)
    ap.add_argument("--output", required=True)
    ns = ap.parse_args()
    base = (read_json(ns.collector), read_json(ns.launcher), read_json(ns.observer))
    cases = [("baseline", lambda c, l, o: None)]
    cases += [(f"collector-{field}", lambda c, l, o, f=field: c.__setitem__(f, False)) for field in ("parentOriginalHandleAcquired", "presentMonSessionAbsent", "presentMonStreamsSealed", "activeSelfOnly")]
    cases += [("collector-active-two", lambda c, l, o: c.__setitem__("activeAfter", 2)), ("collector-workload-exit-one", lambda c, l, o: c.__setitem__("workloadExit", 1)), ("collector-peak-over-cap", lambda c, l, o: c.__setitem__("peakJobMemoryAfterBytes", 1_073_741_825)), ("launcher-descendants-live", lambda c, l, o: l.__setitem__("aggregateDescendantsQuiesced", False)), ("observer-worker-terminal-missing", lambda c, l, o: o.__setitem__("workerKernelTerminal", False))]
    outcomes = []
    for name, mutate in cases:
        c, l, o = (copy.deepcopy(value) for value in base)
        mutate(c, l, o)
        result = evaluate(c, l, o)
        expected = name == "baseline"
        outcomes.append({"name": name, "passed": result["releaseEligible"] is expected, "releaseEligible": result["releaseEligible"], "failedChecks": result["failedChecks"]})
    report = {"kind": "sr0-display-selfjob-v4-supplemental-release-controls-v1", "status": "passed-source-controls" if all(item["passed"] for item in outcomes) else "failed-source-controls", "cases": outcomes, "nativeActions": 0, "processActions": 0}
    supplied_out = Path(ns.output)
    if supplied_out.is_symlink():
        raise SystemExit(f"output must be fresh non-symlink: {ns.output}")
    out = supplied_out.resolve()
    if out.exists():
        raise SystemExit(f"output must be fresh: {out}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["status"] == "passed-source-controls" else 1


if __name__ == "__main__":
    raise SystemExit(main())
