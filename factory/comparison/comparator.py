"""Compare v0.1 case captures without claiming unqualified native parity."""

from __future__ import annotations

import argparse
import json
from decimal import Decimal, InvalidOperation
from pathlib import Path
import re
from typing import Any

from factory.core.artifacts import artifact_ref, canonical_hash, provenance, validate_artifact

CHANNELS = ("layout", "ax", "events", "anim", "images", "text")
PLATFORMS = ("macos", "windows")
OBSERVATION_KEYS = {
    "layout": ("rootLayout",), "ax": ("externalAX",), "events": ("events",),
    "anim": ("animation",), "images": ("offscreenPaint", "compositorPaint"), "text": ("textRenderer",),
}
_ZERO_HASH = "sha256:" + "0" * 64
_HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")


def _is_ref(value: Any) -> bool:
    return isinstance(value, dict) and isinstance(value.get("id"), str) and bool(value["id"]) and isinstance(value.get("hash"), str) and bool(_HASH.fullmatch(value["hash"]))


class ComparisonError(ValueError):
    """Input artifacts cannot be bound to one canonical case and tuple."""


def _ref(artifact: dict[str, Any]) -> dict[str, str]:
    return {"id": artifact["id"], "hash": canonical_hash(artifact)}


def _same(left: Any, right: Any) -> bool:
    return canonical_hash(left) == canonical_hash(right)


def _validate_inputs(case: dict[str, Any], captures: list[dict[str, Any]]) -> None:
    if not isinstance(case, dict) or case.get("kind") != "case" or case.get("version") != "0.1":
        raise ComparisonError("case must be a v0.1 case artifact")
    if not isinstance(captures, list):
        raise ComparisonError("captures must be a list")
    try:
        validate_artifact(case)
    except (ValueError, KeyError) as exc:
        raise ComparisonError(f"invalid case artifact: {exc}") from exc
    case_hash = canonical_hash(case)
    ids: set[str] = set()
    run_keys: set[tuple[str, int]] = set()
    for capture in captures:
        if not isinstance(capture, dict) or capture.get("kind") != "capture" or capture.get("version") != "0.1":
            raise ComparisonError("each input must be a v0.1 capture artifact")
        try:
            validate_artifact(capture)
        except (ValueError, KeyError) as exc:
            raise ComparisonError(f"invalid capture artifact: {exc}") from exc
        cid = capture.get("id")
        if not isinstance(cid, str) or cid in ids:
            raise ComparisonError("capture IDs must be present and unique")
        ids.add(cid)
        case_ref = capture.get("case")
        if case_ref != {"id": case["id"], "hash": case_hash}:
            raise ComparisonError(f"{cid}: capture does not bind to canonical case hash")
        if not _same(capture.get("tuple"), case["tuple"]):
            raise ComparisonError(f"{cid}: tuple differs from case tuple")
        platform = capture.get("platform")
        if platform not in PLATFORMS:
            raise ComparisonError(f"{cid}: unsupported platform {platform!r}")
        run = capture.get("meta", {}).get("run")
        if isinstance(run, bool) or not isinstance(run, int) or run < 1:
            raise ComparisonError(f"{cid}: invalid run number")
        key = (platform, run)
        if key in run_keys:
            raise ComparisonError(f"{cid}: duplicate {platform} run number {run}")
        run_keys.add(key)


def _semantic_projection(capture: dict[str, Any]) -> dict[str, Any]:
    """Discard sampling clocks only; preserve all meaningful channel values."""
    return {
        "layout": capture["layout"],
        "ax": capture["ax"],
        "events": [{k: e[k] for k in ("id", "kind", "payload") if k in e} for e in capture["events"]],
        "anim": [
            {
                "id": a["id"],
                "samples": [s["value"] for s in a["samples"]],
                "presentedFrames": [{k: f[k] for k in ("imageHash", "dropped") if k in f} for f in a["presentedFrames"]],
            }
            for a in capture["anim"]
        ],
        # IDs identify local capture products; compare pixels and dimensions, not IDs.
        "images": [{k: image[k] for k in ("hash", "widthPx", "heightPx", "captureScale", "maskHash") if k in image}
                   for image in capture["images"]],
        "text": capture["text"],
    }


def _channel_values(capture: dict[str, Any], channel: str) -> Any:
    projection = _semantic_projection(capture)
    return projection[channel]


def _repeatability(runs: list[dict[str, Any]]) -> tuple[bool, list[dict[str, str]]]:
    refs = [_ref(run) for run in sorted(runs, key=lambda item: item["meta"]["run"])]
    projections = [_semantic_projection(run) for run in runs]
    agreement = len(runs) >= 2 and all(_same(projections[0], projection) for projection in projections[1:])
    return agreement, refs


def _channel_status(channel: str, mac: list[dict[str, Any]], win: list[dict[str, Any]], config: dict[str, Any]) -> tuple[str, str | None]:
    # Both sides need observed values. Empty/missing channels cannot become parity.
    if not mac or not win or any(not _channel_values(item, channel) for item in mac + win):
        return "blocked", None
    for capture in mac + win:
        conditions = capture.get("meta", {}).get("conditions", {})
        statuses = conditions.get("channelStatus") if isinstance(conditions, dict) else None
        if isinstance(statuses, dict):
            for key in OBSERVATION_KEYS[channel]:
                if not str(statuses.get(key, "")).startswith("OBSERVED"):
                    return "blocked", None
    if channel == "images" and not config.get("paintQualification"):
        return "blocked", None
    normalizer = config.get("normalizers", {}).get(channel) if isinstance(config.get("normalizers"), dict) else None
    if normalizer:
        # A named mapping without an implemented, review-bound projection is not applied.
        return "blocked", None
    mac_values = [_channel_values(item, channel) for item in mac]
    win_values = [_channel_values(item, channel) for item in win]
    if any(not _same(mac_values[0], value) for value in mac_values[1:]) or any(
        not _same(win_values[0], value) for value in win_values[1:]
    ):
        # A cross-platform match from one selected run cannot mask unstable repeats.
        return "fail", canonical_hash({"mac": mac_values, "windows": win_values})
    left, right = mac_values[0], win_values[0]
    digest = canonical_hash({"mac": left, "windows": right})
    return ("pass" if _same(left, right) else "fail"), digest


def _number(value: Any) -> Decimal | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        try:
            return Decimal(str(value))
        except InvalidOperation:
            return None
    if isinstance(value, dict) and set(value) == {"$decimal"}:
        try:
            return Decimal(value["$decimal"])
        except (TypeError, ValueError):
            return None
    return None


def _timing(captures: list[dict[str, Any]], config: dict[str, Any]) -> tuple[str, list[dict[str, str]], str, str | None]:
    refs = [_ref(c) for c in sorted(captures, key=lambda item: (item["platform"], item["meta"]["run"]))]
    bounds_hash = canonical_hash(config if config else {"unconfigured": True})
    if (not config or config.get("reviewed") is not True or config.get("faultControlsPassed") is not True
            or not _is_ref(config.get("reviewEvidence")) or not _is_ref(config.get("faultControlEvidence"))):
        return "blocked", refs, bounds_hash, None
    duration = config.get("durationNs", {})
    velocity = config.get("velocityMilliPerSecond", {})
    stalls = config.get("presentedFrameStallNs", {})
    required = (duration, velocity, stalls)
    if any(not isinstance(row, dict) or not {"min", "max"}.issubset(row) for row in required):
        return "blocked", refs, bounds_hash, None
    if any(any(isinstance(row.get(key), bool) or not isinstance(row.get(key), int) for key in ("min", "max"))
           or row["min"] > row["max"] for row in required):
        return "blocked", refs, bounds_hash, None
    if (not isinstance(duration.get("startKind"), str) or not duration["startKind"]
            or not isinstance(duration.get("endKind"), str) or not duration["endKind"]
            or isinstance(stalls.get("frameIntervalNs"), bool)
            or not isinstance(stalls.get("frameIntervalNs"), int) or stalls["frameIntervalNs"] <= 0):
        return "blocked", refs, bounds_hash, None
    if not captures:
        return "blocked", refs, bounds_hash, None
    details: list[dict[str, Any]] = []
    for capture in captures:
        events = capture["events"]
        clock_id = capture["meta"]["clock"]["clockId"]
        start_kind, end_kind = duration.get("startKind"), duration.get("endKind")
        starts = [e for e in events if e["kind"] == start_kind]
        ends = [e for e in events if e["kind"] == end_kind]
        if len(starts) != 1 or len(ends) != 1:
            return "blocked", refs, bounds_hash, None
        if starts[0].get("clockId") != clock_id or ends[0].get("clockId") != clock_id:
            return "blocked", refs, bounds_hash, None
        elapsed = ends[0]["timeNs"] - starts[0]["timeNs"]
        if elapsed < 0:
            return "fail", refs, bounds_hash, canonical_hash({"invalidDuration": elapsed})
        slopes: list[int] = []
        for animation in capture["anim"]:
            samples = animation["samples"]
            for previous, current in zip(samples, samples[1:]):
                dt = current["timeNs"] - previous["timeNs"]
                first, second = _number(previous["value"]), _number(current["value"])
                if dt <= 0 or first is None or second is None:
                    continue
                slopes.append(int(abs(second - first) * Decimal(1_000_000_000_000) / Decimal(dt)))
        animation_stalls: list[int] = []
        for animation in capture["anim"]:
            sample_times = [sample["timeNs"] for sample in animation["samples"]]
            frame_times = [frame["timeNs"] for frame in animation["presentedFrames"]]
            if any(b <= a for a, b in zip(sample_times, sample_times[1:])):
                return "blocked", refs, bounds_hash, None
            if len(frame_times) < 2 or any(b <= a for a, b in zip(frame_times, frame_times[1:])):
                return "blocked", refs, bounds_hash, None
            animation_stalls.append(max(0, max(b - a for a, b in zip(frame_times, frame_times[1:])) - stalls["frameIntervalNs"]))
        if not animation_stalls:
            return "blocked", refs, bounds_hash, None
        observed = {"durationNs": elapsed, "velocityMilliPerSecond": max(slopes) if slopes else None,
                    "presentedFrameStallNs": max(animation_stalls)}
        details.append(observed)
        if observed["velocityMilliPerSecond"] is None:
            return "blocked", refs, bounds_hash, None
    passed = all(
        duration["min"] <= row["durationNs"] <= duration["max"]
        and velocity["min"] <= row["velocityMilliPerSecond"] <= velocity["max"]
        and stalls["min"] <= row["presentedFrameStallNs"] <= stalls["max"]
        for row in details
    )
    return ("pass" if passed else "fail"), refs, bounds_hash, canonical_hash(details)


def compare_case(case: dict[str, Any], captures: list[dict[str, Any]],
                 acceptance_config: dict[str, Any] | None = None,
                 holds: list[str] | None = None) -> dict[str, Any]:
    """Return schema-valid observational verdict; candidate evidence always stays blocked."""
    _validate_inputs(case, captures)
    config = acceptance_config if isinstance(acceptance_config, dict) else {}
    tuple_value = case["tuple"]
    if canonical_hash(config) != tuple_value["acceptanceConfigHash"]:
        config = {}
    by_platform = {p: [c for c in captures if c["platform"] == p] for p in PLATFORMS}
    mac_agree, mac_refs = _repeatability(by_platform["macos"])
    win_agree, win_refs = _repeatability(by_platform["windows"])
    result_rows = []
    for channel in CHANNELS:
        status, digest = _channel_status(channel, by_platform["macos"], by_platform["windows"], config)
        row: dict[str, Any] = {"channel": channel, "status": status}
        if digest:
            row["differenceHash"] = digest
        result_rows.append(row)
    semantic_status = "pass" if result_rows and all(row["status"] == "pass" for row in result_rows) else (
        "fail" if any(row["status"] == "fail" for row in result_rows) else "blocked")
    timing_status, timing_refs, bounds_hash, result_hash = _timing(captures, config.get("timing", {}))

    holds_list = list(holds or [])
    if len(by_platform["macos"]) < 20:
        holds_list.append("20 independent macOS runs required")
    if len(by_platform["windows"]) < 20:
        holds_list.append("20 independent Windows runs required")
    if not config:
        holds_list.append("protected acceptance configuration is unavailable or tuple hash does not match")
    if not config.get("reviewedBounds"):
        holds_list.append("reviewed comparison bounds and fault-control evidence required")
    if not config.get("sr0Closed"):
        holds_list.append("SR0 closure bound required")
    if not _is_ref(config.get("paintQualification")):
        holds_list.append("paint qualification required")
    if not _is_ref(config.get("sr0Closed")):
        holds_list.append("SR0 closure artifact reference required")
    if not _is_ref(config.get("reviewedBounds")):
        holds_list.append("reviewed bounds artifact reference required")
    for platform in PLATFORMS:
        runs = by_platform[platform]
        run_hashes: set[str] = set()
        for capture in runs:
            conditions = capture["meta"]["conditions"]
            evidence_hash = conditions.get("runEvidenceHash")
            if (conditions.get("independentRun") is not True or conditions.get("resetVerified") is not True
                    or conditions.get("candidateOnly") is True or conditions.get("synthetic") is True
                    or not isinstance(evidence_hash, str) or not evidence_hash.startswith("sha256:")
                    or evidence_hash in run_hashes):
                holds_list.append(f"{platform} run qualification evidence required")
            elif len(evidence_hash) == 71:
                run_hashes.add(evidence_hash)
            else:
                holds_list.append(f"{platform} run evidence hash is invalid")
        if len(runs) >= 20 and not set(range(1, 21)).issubset({capture["meta"]["run"] for capture in runs}):
            holds_list.append(f"{platform} runs 1 through 20 required")
    for channel in CHANNELS:
        if any(row["channel"] == channel and row["status"] == "blocked" for row in result_rows):
            holds_list.append(f"observed, qualified {channel} channel required")
    status = "fail" if semantic_status == "fail" or timing_status == "fail" else "blocked"
    if not holds_list and semantic_status == "pass" and timing_status == "pass" and len(by_platform["macos"]) >= 20 and len(by_platform["windows"]) >= 20 and mac_agree and win_agree:
        status = "pass"
    verdict: dict[str, Any] = {
        "kind": "verdict", "version": "0.1", "id": f"{case['id'][:145]}.comparison",
        "provenance": provenance({"case": _ref(case), "captures": sorted([_ref(c) for c in captures], key=lambda r: (r["id"], r["hash"]))},
                                 producer="factory/comparison"),
        "case": _ref(case), "tuple": tuple_value,
        "macCaptures": mac_refs, "windowsCaptures": win_refs,
        "repeatability": {
            "mac": {"runs": len(mac_refs), "semanticAgreement": mac_agree, "evidence": mac_refs},
            "windows": {"runs": len(win_refs), "semanticAgreement": win_agree, "evidence": win_refs},
        },
        "semantic": {"status": semantic_status,
                     "normalizerConfig": {"id": f"{case['id']}.normalizers", "hash": canonical_hash(config.get("normalizers", {}))},
                     "results": result_rows},
        "timing": {"status": timing_status, "rawEvidence": timing_refs, "boundsHash": bounds_hash},
        "status": status,
    }
    if result_hash:
        verdict["timing"]["resultHash"] = result_hash
    try:
        validate_artifact(verdict)
    except (ValueError, KeyError) as exc:
        raise ComparisonError(f"comparator produced invalid verdict: {exc}") from exc
    return verdict


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path)
    parser.add_argument("captures", type=Path, help="JSON array of v0.1 capture artifacts")
    parser.add_argument("--acceptance-config", type=Path)
    parser.add_argument("--holds", type=Path, help="optional JSON array of hold strings")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    case = json.loads(args.case.read_text())
    captures = json.loads(args.captures.read_text())
    config = json.loads(args.acceptance_config.read_text()) if args.acceptance_config else None
    holds = json.loads(args.holds.read_text()) if args.holds else None
    verdict = compare_case(case, captures, config, holds)
    rendered = json.dumps(verdict, sort_keys=True, separators=(",", ":"))
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered)
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())
