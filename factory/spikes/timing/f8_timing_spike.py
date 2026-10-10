#!/usr/bin/env python3
"""Synthetic/unit-evidence F8 timing comparator spike.

This is deliberately not native-parity evidence.  It keeps raw timing per run,
checks semantic event equality/order independently, then evaluates duration,
interruption velocity & presented-frame stalls against declared bounds.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from factory.tools.canonical_json import CanonicalJSONError, dumps as canonical_dumps


class EvidenceError(ValueError):
    pass


@dataclass(frozen=True)
class Bounds:
    minimum: int
    maximum: int

    def contains(self, value: int) -> bool:
        return self.minimum <= value <= self.maximum


def _integer(value: Any, name: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise EvidenceError(f"{name} must be a finite number")
    if isinstance(value, float):
        if not math.isfinite(value):
            raise EvidenceError(f"{name} is nonfinite")
        if not value.is_integer():
            raise EvidenceError(f"{name} must use integral microseconds")
    return int(value)


def _required(mapping: Any, key: str, where: str) -> Any:
    if not isinstance(mapping, dict) or key not in mapping:
        raise EvidenceError(f"missing {where}.{key}")
    return mapping[key]


def _bounds(value: Any, name: str) -> Bounds:
    minimum = _integer(_required(value, "min", name), f"{name}.min")
    maximum = _integer(_required(value, "max", name), f"{name}.max")
    if minimum > maximum:
        raise EvidenceError(f"invalid {name} bounds")
    return Bounds(minimum, maximum)


def _events(value: Any, name: str) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not value:
        raise EvidenceError(f"{name} must be a nonempty event list")
    if not all(isinstance(event, dict) for event in value):
        raise EvidenceError(f"{name} has a non-object event")
    return value


def _same_json(actual: Any, expected: Any, name: str) -> bool:
    """Compare canonical JSON so bool/number & tagged values retain type."""
    try:
        return canonical_dumps(actual) == canonical_dumps(expected)
    except CanonicalJSONError as exc:
        raise EvidenceError(f"{name} is not canonical JSON: {exc}") from exc


def _frame_stall(frame_times: Any, start: int, completion: int, interval: int, run_id: str) -> int:
    if not isinstance(frame_times, list) or len(frame_times) < 2:
        raise EvidenceError(f"{run_id}.presentedFrames needs at least two observations")
    previous = _integer(frame_times[0], f"{run_id}.presentedFrames[0]")
    if previous < start or previous > completion:
        raise EvidenceError(f"{run_id}.presentedFrames falls outside observation window")
    largest_gap = previous - start
    for index, raw_time in enumerate(frame_times[1:], start=1):
        current = _integer(raw_time, f"{run_id}.presentedFrames[{index}]")
        if current <= previous:
            raise EvidenceError(f"{run_id}.presentedFrames is nonmonotonic")
        if current > completion:
            raise EvidenceError(f"{run_id}.presentedFrames falls outside observation window")
        largest_gap = max(largest_gap, current - previous)
        previous = current
    # A stream that ends early cannot hide a terminal presented-frame stall.
    largest_gap = max(largest_gap, completion - previous)
    return max(0, largest_gap - interval)


def compare_case(case: dict[str, Any]) -> dict[str, Any]:
    """Return per-run results or raise for absent/incoherent evidence."""
    case_id = _required(case, "caseId", "case")
    if not isinstance(case_id, str) or not case_id:
        raise EvidenceError("case.caseId must be a nonempty string")
    if _required(case, "evidenceClass", "case") != "synthetic/unit-evidence":
        raise EvidenceError(f"{case_id}.evidenceClass must label synthetic/unit-evidence")
    unit = _required(case, "unit", "case")
    clock = _required(case, "clock", "case")
    if unit != "us" or clock != "monotonic-us":
        raise EvidenceError(f"{case_id} requires us on monotonic-us clock")
    conditions = _required(case, "conditions", "case")
    interval = _integer(_required(conditions, "frameIntervalUs", f"{case_id}.conditions"), "frameIntervalUs")
    jitter = _integer(_required(conditions, "samplingJitterUs", f"{case_id}.conditions"), "samplingJitterUs")
    if interval <= 0:
        raise EvidenceError(f"{case_id}.frameIntervalUs must be positive")
    if jitter < 0:
        raise EvidenceError(f"{case_id}.samplingJitterUs must be nonnegative")
    expected = _required(case, "expected", "case")
    expected_events = _events(_required(expected, "semanticEvents", f"{case_id}.expected"), f"{case_id}.expected.semanticEvents")
    completion_count = sum(event.get("event") == "animation-complete" for event in expected_events)
    if completion_count != 1:
        raise EvidenceError(f"{case_id}.expected.semanticEvents needs exactly one animation-complete event")
    duration_bounds = _bounds(_required(expected, "durationUs", f"{case_id}.expected"), "durationUs")
    velocity_bounds = _bounds(_required(expected, "interruptionVelocityMilli", f"{case_id}.expected"), "interruptionVelocityMilli")
    stall_max = _integer(_required(expected, "maxPresentedFrameStallUs", f"{case_id}.expected"), "maxPresentedFrameStallUs")
    if stall_max < 0:
        raise EvidenceError(f"{case_id}.maxPresentedFrameStallUs must be nonnegative")
    repeats = _integer(_required(expected, "repeats", f"{case_id}.expected"), "repeats")
    if repeats < 20:
        raise EvidenceError(f"{case_id} declares fewer than 20 repeats")
    observations = _required(case, "observations", "case")
    if not isinstance(observations, list) or len(observations) < repeats:
        raise EvidenceError(f"{case_id} has incomplete repeats: need {repeats}")
    if len(observations) != repeats:
        raise EvidenceError(f"{case_id} repeats do not match observation count")

    seen: set[str] = set()
    results: list[dict[str, Any]] = []
    for observation in observations:
        run_id = _required(observation, "runId", case_id)
        if not isinstance(run_id, str) or not run_id:
            raise EvidenceError(f"{case_id}.runId must be a nonempty string")
        if run_id in seen:
            raise EvidenceError(f"{case_id} has duplicate runId {run_id}")
        seen.add(run_id)
        if _required(observation, "unit", run_id) != unit or _required(observation, "clock", run_id) != clock:
            raise EvidenceError(f"{run_id} has inconsistent units or clock")
        if not _same_json(_required(observation, "conditions", run_id), conditions, f"{run_id}.conditions"):
            raise EvidenceError(f"{run_id} has inconsistent conditions")
        actual_events = _events(_required(observation, "semanticEvents", run_id), f"{run_id}.semanticEvents")
        raw = _required(observation, "rawTiming", run_id)
        start = _integer(_required(raw, "startUs", f"{run_id}.rawTiming"), f"{run_id}.startUs")
        completion = _integer(_required(raw, "completionUs", f"{run_id}.rawTiming"), f"{run_id}.completionUs")
        interruption = _integer(_required(raw, "interruptionUs", f"{run_id}.rawTiming"), f"{run_id}.interruptionUs")
        velocity = _integer(_required(raw, "interruptionVelocityMilli", f"{run_id}.rawTiming"), f"{run_id}.interruptionVelocityMilli")
        if start > interruption or interruption > completion:
            raise EvidenceError(f"{run_id}.rawTiming has invalid event chronology")
        stall = _frame_stall(
            _required(observation, "presentedFramesUs", run_id), start, completion, interval, run_id
        )
        duration = completion - start
        checks = {
            "semanticEqualityAndOrder": _same_json(actual_events, expected_events, f"{run_id}.semanticEvents"),
            "durationBounded": duration_bounds.contains(duration),
            "interruptionVelocityBounded": velocity_bounds.contains(velocity),
            "presentedFrameStallBounded": stall <= stall_max,
        }
        results.append(
            {
                "runId": run_id,
                "checks": checks,
                "rawTiming": {
                    "startUs": start,
                    "interruptionUs": interruption,
                    "completionUs": completion,
                    "interruptionVelocityMilli": velocity,
                    "presentedFramesUs": _required(observation, "presentedFramesUs", run_id),
                },
                "derived": {"durationUs": duration, "presentedFrameStallUs": stall},
            }
        )
    return {"caseId": case_id, "status": "pass" if all(all(row["checks"].values()) for row in results) else "fail", "runs": results}


def compare(document: dict[str, Any]) -> dict[str, Any]:
    if document.get("evidenceClass") != "synthetic/unit-evidence":
        raise EvidenceError("document must label synthetic/unit-evidence")
    cases = document.get("cases")
    if not isinstance(cases, list) or not cases:
        raise EvidenceError("document needs nonempty cases")
    ids: set[str] = set()
    results = []
    for case in cases:
        case_id = _required(case, "caseId", "case")
        if case_id in ids:
            raise EvidenceError(f"duplicate caseId {case_id}")
        ids.add(case_id)
        results.append(compare_case(case))
    return {
        "kind": "f8-timing-comparison",
        "evidenceClass": "synthetic/unit-evidence",
        "status": "pass" if all(item["status"] == "pass" for item in results) else "fail",
        "results": results,
    }


def deterministic_example() -> dict[str, Any]:
    events = [
        {"event": "animation-start", "target": "row/7"},
        {"event": "interruption", "target": "row/7"},
        {"event": "animation-complete", "target": "row/7", "completed": True},
    ]
    observations = []
    for index in range(20):
        start = index * 1_000_000
        # ±1 ms duration jitter & 2 ms frame sampling jitter are intentionally bounded.
        duration = 100_000 + (index % 3 - 1) * 1_000
        frames = [
            start,
            start + 16_667,
            start + 33_334,
            start + 50_001,
            start + 66_668,
            start + 83_335,
            start + duration,
        ]
        observations.append(
            {
                "runId": f"run-{index + 1:02d}",
                "unit": "us",
                "clock": "monotonic-us",
                "conditions": {"frameIntervalUs": 16_667, "samplingJitterUs": 2_000},
                "semanticEvents": copy.deepcopy(events),
                "rawTiming": {
                    "startUs": start,
                    "interruptionUs": start + 50_000,
                    "completionUs": start + duration,
                    "interruptionVelocityMilli": 250_000 + (index % 3 - 1) * 1_000,
                },
                "presentedFramesUs": frames,
            }
        )
    return {
        "evidenceClass": "synthetic/unit-evidence",
        "cases": [
            {
                "caseId": "f8-synthetic-bounded-jitter",
                "evidenceClass": "synthetic/unit-evidence",
                "unit": "us",
                "clock": "monotonic-us",
                "conditions": {"frameIntervalUs": 16_667, "samplingJitterUs": 2_000},
                "expected": {
                    "semanticEvents": events,
                    "durationUs": {"min": 97_000, "max": 103_000},
                    "interruptionVelocityMilli": {"min": 247_000, "max": 253_000},
                    "maxPresentedFrameStallUs": 2_000,
                    "repeats": 20,
                },
                "observations": observations,
            }
        ],
    }


def selftest() -> dict[str, Any]:
    base = deterministic_example()
    controls: dict[str, Any] = {"bounded-jitter": base}

    def erase_expected_completion(item: dict[str, Any]) -> None:
        item["cases"][0]["expected"]["semanticEvents"].pop()
        for observation in item["cases"][0]["observations"]:
            observation["semanticEvents"].pop()

    mutations = {
        "wrong-duration": lambda item: item["cases"][0]["observations"][0]["rawTiming"].update(completionUs=120_000),
        "wrong-velocity": lambda item: item["cases"][0]["observations"][0]["rawTiming"].update(interruptionVelocityMilli=270_000),
        "wrong-stall": lambda item: item["cases"][0]["observations"][0]["presentedFramesUs"].__setitem__(slice(None), [0, 16_667, 50_000, 66_667, 83_334]),
        "missing-completion": lambda item: item["cases"][0]["observations"][0]["semanticEvents"].pop(),
        "vacuous-completion": erase_expected_completion,
        "wrong-event-order": lambda item: item["cases"][0]["observations"][0]["semanticEvents"].reverse(),
        "wrong-semantic-type": lambda item: item["cases"][0]["observations"][0]["semanticEvents"][-1].update(completed=1),
        "incomplete-repeats": lambda item: item["cases"][0]["observations"].pop(),
        "duplicate-run-id": lambda item: item["cases"][0]["observations"][1].update(runId="run-01"),
        "missing-channel": lambda item: item["cases"][0]["observations"][0].pop("presentedFramesUs"),
        "truncated-frames": lambda item: item["cases"][0]["observations"][0]["presentedFramesUs"].__delitem__(slice(-3, None)),
        "inconsistent-clock": lambda item: item["cases"][0]["observations"][0].update(clock="wall-us"),
        "inconsistent-conditions": lambda item: item["cases"][0]["observations"][0]["conditions"].update(samplingJitterUs=0),
        "nonmonotonic-frame": lambda item: item["cases"][0]["observations"][0]["presentedFramesUs"].__setitem__(2, 1),
        "nonfinite-timing": lambda item: item["cases"][0]["observations"][0]["rawTiming"].update(completionUs=float("nan")),
    }
    for name, mutate in mutations.items():
        control = copy.deepcopy(base)
        mutate(control)
        controls[name] = control
    outcomes: dict[str, str] = {}
    for name, document in controls.items():
        try:
            report = compare(document)
            outcomes[name] = report["status"]
        except EvidenceError:
            outcomes[name] = "rejected"
    passed = outcomes["bounded-jitter"] == "pass" and all(
        status in {"fail", "rejected"} for name, status in outcomes.items() if name != "bounded-jitter"
    )
    return {"kind": "f8-timing-selftest", "evidenceClass": "synthetic/unit-evidence", "status": "pass" if passed else "fail", "controls": outcomes}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="synthetic F8 timing comparison spike")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--example", action="store_true", help="emit deterministic synthetic input")
    mode.add_argument("--selftest", action="store_true", help="run seeded adversarial controls")
    mode.add_argument("--compare", metavar="FILE", help="compare synthetic evidence JSON")
    arguments = parser.parse_args(argv)
    try:
        if arguments.example:
            result = deterministic_example()
        elif arguments.selftest:
            result = selftest()
        else:
            with open(arguments.compare, encoding="utf-8") as source:
                result = compare(json.load(source))
    except (EvidenceError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"kind": "f8-timing-comparison", "status": "rejected", "error": str(exc)}, sort_keys=True), file=sys.stdout)
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if arguments.example or result.get("status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
