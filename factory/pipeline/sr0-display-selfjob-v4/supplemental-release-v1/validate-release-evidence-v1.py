#!/usr/bin/env python3
"""Release-only evidence gate for parser-failed, process-terminal Windows runs.

This gate never qualifies display data & never changes lock state. It computes
whether owner CAS may release a held lock after receipt evidence proves terminal
original handles, sealed streams, absent PM session, & self-only job state.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

JSON_LIMIT = 2 * 1024 * 1024
KERNEL_ACTIVE_LIMIT = 1_073_741_824
JOB_MEMORY_ONLY = 512


def fail(message: str) -> None:
    raise SystemExit(message)


def read_json(path: str) -> dict[str, Any]:
    supplied = Path(path)
    if supplied.is_symlink():
        fail(f"receipt must be regular non-symlink file: {path}")
    item = supplied.resolve()
    if not item.is_file():
        fail(f"receipt must be regular non-symlink file: {path}")
    if item.stat().st_size > JSON_LIMIT:
        fail(f"receipt exceeds {JSON_LIMIT} bytes: {path}")
    try:
        value = json.loads(item.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"invalid receipt {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"receipt must be JSON object: {path}")
    return value


def is_bool(value: Any, expected: bool = True) -> bool:
    return isinstance(value, bool) and value is expected


def is_int(value: Any, expected: int | None = None) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and (expected is None or value == expected)


def check(checks: list[dict[str, Any]], name: str, ok: bool, detail: str) -> None:
    checks.append({"name": name, "passed": bool(ok), "detail": detail})


def evaluate(collector: dict[str, Any], launcher: dict[str, Any], observer: dict[str, Any]) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    check(checks, "collector-kind", collector.get("kind") == "sr0-display-collector-v5", "sr0-display-collector-v5")
    check(checks, "launcher-kind", launcher.get("kind") == "sr0-display-launcher-v5", "sr0-display-launcher-v5")
    check(checks, "observer-kind", observer.get("kind") == "sr0-display-selfjob-v5-fresh-observer-r1", "fresh observer v5 r1")
    names = {collector.get("taskName"), collector.get("tag"), launcher.get("taskName"), launcher.get("tag")}
    check(checks, "owner-task-tag-join", len(names) == 1 and None not in names, "collector/launcher taskName & tag agree")
    check(checks, "collector-hold-preserved", collector.get("lockHeld") is True and collector.get("lockReleased") is False, "lock remains held")
    check(checks, "collector-not-qualified", collector.get("captureComplete") is False and collector.get("qualificationHeld") is False, "qualification remains false")

    for key in ("parentOriginalHandleRetained", "parentOriginalHandleAcquired", "sessionMatch", "desktopAvailable", "desktopNameRead"):
        check(checks, f"collector-{key}", is_bool(collector.get(key)), f"{key}=true")
    check(checks, "collector-desktop", collector.get("desktopName") == "Default" and is_int(collector.get("desktopLastError"), 0), "Default desktop, lastError 0")
    for key in ("presentMonHandleAcquired", "presentMonTerminal", "presentMonExitIdentity", "presentMonSessionAbsent", "presentMonStreamsSealed", "workloadHandleAcquired", "workloadTerminal", "workloadExitIdentity", "activeReadableAfter", "activeSelfOnly"):
        check(checks, f"collector-{key}", is_bool(collector.get(key)), f"{key}=true")
    check(checks, "collector-pm-forced-stop", collector.get("presentMonStopMode") == "forced-owned" and is_bool(collector.get("presentMonForcedStopAttempted")), "forced-owned stop attempted")
    check(checks, "collector-pm-exit", is_int(collector.get("presentMonExit"), -1) and is_int(collector.get("presentMonExitRaw"), 4_294_967_295) and is_int(collector.get("presentMonExitSigned"), -1), "PM exit raw/signed join is -1")
    check(checks, "collector-pm-stop-exit", is_int(collector.get("presentMonStopExit"), 0), "logman stop exit 0")
    check(checks, "collector-pm-stderr", isinstance(collector.get("presentMonStderrEvidence"), dict) and is_bool(collector["presentMonStderrEvidence"].get("exactBenignWarning")) and is_int(collector["presentMonStderrEvidence"].get("bytes"), 65), "exact bounded benign stderr")
    check(checks, "collector-workload-exit", is_int(collector.get("workloadExit"), 0) and is_int(collector.get("workloadExitRaw"), 0), "workload exit 0")
    check(checks, "collector-no-faults", collector.get("streamFault") is None and collector.get("outputExceeded") is False and collector.get("timedOut") is False, "no stream/output/deadline fault")
    for key in ("presentMonStdoutBytes", "presentMonStderrBytes", "presentMonStopStdoutBytes", "presentMonStopStderrBytes", "presentMonQueryStdoutBytes", "presentMonQueryStderrBytes", "workloadStdoutBytes", "workloadStderrBytes"):
        check(checks, f"collector-{key}", is_int(collector.get(key)) and 0 <= collector[key] <= 8 * 1024 * 1024, f"bounded {key}")
    check(checks, "collector-job-active", is_int(collector.get("activeAfter"), 1) and is_int(collector.get("jobMemoryLimitBytes"), KERNEL_ACTIVE_LIMIT) and is_int(collector.get("limitFlagsAfter"), JOB_MEMORY_ONLY), "self-only 1 GiB job")
    peak = collector.get("peakJobMemoryAfterBytes")
    check(checks, "collector-job-peak", is_int(peak) and 0 <= peak <= KERNEL_ACTIVE_LIMIT, "peak within 1 GiB")

    check(checks, "launcher-self-only", is_int(launcher.get("aggregateActiveAfter"), 1) and is_bool(launcher.get("aggregateDescendantsQuiesced")) and is_bool(launcher.get("aggregateCleanupSelfOnly")), "launcher self-only descendants quiesced")
    check(checks, "launcher-cap", launcher.get("aggregateMemoryCapExceeded") is False and is_int(launcher.get("aggregateJobMemoryLimitBytes"), KERNEL_ACTIVE_LIMIT), "launcher memory cap respected")
    for role in ("coordinator", "collector"):
        check(checks, f"launcher-{role}-terminal", is_bool(launcher.get(f"{role}HandleAcquired")) and is_bool(launcher.get(f"{role}Terminal")) and is_bool(launcher.get(f"{role}ExitIdentity")), f"{role} original handle terminal")
    check(checks, "launcher-no-termination", launcher.get("terminationAttempted") is False, "launcher did not terminate unrelated processes")

    check(checks, "observer-deadline", is_bool(observer.get("overallWithinDeadline")) and is_bool(observer.get("scheduleStreamsSealed")), "observer within deadline & streams sealed")
    check(checks, "observer-schedule", is_bool(observer.get("scheduleHandleAcquired")) and is_bool(observer.get("scheduleTerminal")) and is_bool(observer.get("scheduleExitIdentity")), "schedule original handle terminal")
    check(checks, "observer-worker", is_bool(observer.get("workerOriginalHandleAcquired")) and is_bool(observer.get("workerKernelTerminal")) and is_bool(observer.get("workerExitIdentity")) and is_bool(observer.get("workerSessionMatch")), "worker original handle terminal")
    check(checks, "observer-transport-self-only", is_int(observer.get("transportFinalActive"), 1) and is_int(observer.get("transportFinalLimitFlags"), JOB_MEMORY_ONLY), "observer transport self-only")

    passed = all(item["passed"] for item in checks)
    return {
        "kind": "sr0-display-selfjob-v4-supplemental-release-v1",
        "status": "release-eligible-held" if passed else "release-held",
        "releaseEligible": passed,
        "lockReleaseDecision": "owner-cas-eligible-release-only" if passed else "retain-held",
        "releaseOnly": True,
        "qualification": "blocked",
        "qualificationClaim": False,
        "lockMutationPerformed": False,
        "evidenceMode": "bounded-receipt-fields; no lock or process mutation",
        "checks": checks,
        "failedChecks": [item["name"] for item in checks if not item["passed"]],
        "reason": "process/parser qualification failed; release gate evaluates ownership cleanup only",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--collector", required=True)
    ap.add_argument("--launcher", required=True)
    ap.add_argument("--observer", required=True)
    ap.add_argument("--output", required=True)
    ns = ap.parse_args()
    result = evaluate(read_json(ns.collector), read_json(ns.launcher), read_json(ns.observer))
    supplied_out = Path(ns.output)
    if supplied_out.is_symlink():
        fail(f"output must be fresh non-symlink: {ns.output}")
    out = supplied_out.resolve()
    if out.exists():
        fail(f"output must be fresh: {out}")
    out.parent.mkdir(parents=True, exist_ok=True)
    temp = out.with_name(f".{out.name}.{os.getpid()}.tmp")
    payload = (json.dumps(result, indent=2, sort_keys=True) + "\n").encode("utf-8")
    with temp.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, out)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["releaseEligible"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
