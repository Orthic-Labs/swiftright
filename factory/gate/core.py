"""Fail-closed F10 gate checks for immutable factory artifacts.

This module validates evidence supplied by host runners. It never builds a
runtime, captures a platform, or promotes a golden itself.
"""

from __future__ import annotations

import argparse
import json
import random
import re
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable

try:  # Works as both ``python -m factory.gate`` and ``python -m gate``.
    from factory.tools.canonical_json import CanonicalJSONError, sha256
    from factory.recipes.cases import expand_cases
except ImportError:  # pragma: no cover - alternate package root
    from ..tools.canonical_json import CanonicalJSONError, sha256
    from ..recipes.cases import expand_cases

MIN_RUNS = 20


def _ref_hash(artifact: dict[str, Any]) -> str:
    return sha256(artifact)


def _same_tuple(actual: Any, expected: dict[str, Any]) -> bool:
    return isinstance(actual, dict) and sha256(actual) == sha256(expected)


def _case_refs(cases: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
    return sorted(
        ({"id": case["id"], "hash": _ref_hash(case)} for case in cases),
        key=lambda ref: (ref["id"], ref["hash"]),
    )


def _case_set_hash(cases: Iterable[dict[str, Any]]) -> str:
    """Hash expanded case identity + inputs; avoids a self-referential artifact hash."""
    manifest = [
        {"id": case["id"], "inputs": case.get("inputs", {}), "coverage": case.get("coverage")}
        for case in cases
    ]
    return sha256(sorted(manifest, key=lambda row: (row["id"], sha256(row["inputs"]))))


def _case_projection(case: dict[str, Any]) -> dict[str, Any]:
    """Return all case identity except provenance & tuple binding.

    Provenance timestamps can differ between archived snapshots; tuple is checked
    separately against the measured tuple, including its acceptance-config hash.
    No behavior, obligation, input, or recipe field is omitted.
    """
    return {key: value for key, value in case.items() if key not in ("provenance", "tuple")}


def baseline_case_refs(cases: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
    """Build config-safe baseline refs without a tuple/config hash cycle."""
    return sorted(
        ({"id": case["id"], "projectionHash": sha256(_case_projection(case))} for case in cases),
        key=lambda ref: (ref["id"], ref["projectionHash"]),
    )


def _check_protected_baseline(
    recipe: dict[str, Any], tuple_value: dict[str, Any], cases: list[dict[str, Any]],
    expected_cases: list[dict[str, Any]] | None, acceptance_config: dict[str, Any] | None,
    issues: list[str],
) -> None:
    if not isinstance(acceptance_config, dict):
        return
    review = acceptance_config.get("review")
    accepted = review == "accepted" or (isinstance(review, dict) and review.get("decision") == "accepted")
    if not accepted:
        issues.append("acceptance configuration lacks accepted review")
    profile = acceptance_config.get("baseline")
    if (not isinstance(profile, dict) or set(profile) != {"version", "recipes"}
            or profile.get("version") != "1" or not isinstance(profile.get("recipes"), list)):
        issues.append("protected baseline profile version 1 with recipe projections is required")
        return
    recipe_ref = {"id": recipe.get("id"), "hash": _ref_hash(recipe)}
    profiles = profile["recipes"]
    if any(
        not isinstance(item, dict) or set(item) != {"recipe", "seed", "cases"}
        or not isinstance(item.get("recipe"), dict)
        or set(item["recipe"]) != {"id", "hash"}
        or not isinstance(item["recipe"].get("id"), str)
        or not isinstance(item["recipe"].get("hash"), str)
        for item in profiles
    ):
        issues.append("protected baseline recipe profile is invalid")
        return
    profile_refs = [item["recipe"] for item in profiles]
    if len({(ref["id"], ref["hash"]) for ref in profile_refs}) != len(profile_refs):
        issues.append("protected baseline contains duplicate recipe profiles")
        return
    matches = [item for item in profiles if item["recipe"] == recipe_ref]
    if len(matches) != 1:
        issues.append("protected baseline profile for exact recipe ID and hash is missing")
        return
    selected = matches[0]
    baseline_seed = selected.get("seed")
    if not isinstance(baseline_seed, int) or isinstance(baseline_seed, bool):
        issues.append("protected baseline seed must be an integer")
        return
    refs = selected.get("cases")
    if (not isinstance(refs, list)
            or any(not isinstance(ref, dict) or set(ref) != {"id", "projectionHash"}
                   or not isinstance(ref.get("id"), str)
                   or not isinstance(ref.get("projectionHash"), str)
                   or not re.fullmatch(r"sha256:[0-9a-f]{64}", ref.get("projectionHash", ""))
                   for ref in refs)):
        issues.append("protected baseline case projections are invalid")
        return
    if refs != sorted(refs, key=lambda ref: (ref["id"], ref["projectionHash"])):
        issues.append("protected baseline case projections must be canonically sorted")
    try:
        expansion = expand_cases(recipe, tuple_value, seed=baseline_seed)
        expanded = expansion["cases"]
        expanded_refs = baseline_case_refs(expanded)
    except Exception as exc:
        issues.append(f"trusted baseline recipe expansion failed: {exc}")
        return
    if refs != expanded_refs:
        issues.append("protected baseline projections differ from complete trusted recipe expansion")
    if baseline_case_refs(cases) != expanded_refs:
        issues.append("supplied baseline cases differ from complete trusted recipe expansion")
    if expected_cases is not None and baseline_case_refs(expected_cases) != expanded_refs:
        issues.append("caller expected cases differ from complete trusted recipe expansion")


def _check_recipe_profile_closure(
    acceptance_config: dict[str, Any], tuple_value: dict[str, Any], issues: list[str],
) -> None:
    """Require config recipe refs & protected profiles to form one closed set.

    Every protected profile is expanded from its trusted checked-in recipe using
    its pinned seed. This prevents an omitted/extra/duplicate profile from
    narrowing or redefining acceptance denominator while one recipe is evaluated.
    """
    recipe_refs = acceptance_config.get("recipeRefs")
    baseline = acceptance_config.get("baseline")
    profiles = baseline.get("recipes") if isinstance(baseline, dict) else None
    if not isinstance(recipe_refs, list) or not isinstance(profiles, list):
        issues.append("acceptance recipeRefs & protected baseline profiles are required")
        return

    def valid_ref(value: Any) -> bool:
        return (
            isinstance(value, dict) and set(value) == {"id", "hash"}
            and isinstance(value["id"], str)
            and isinstance(value["hash"], str)
            and re.fullmatch(r"sha256:[0-9a-f]{64}", value["hash"]) is not None
        )

    if any(not valid_ref(ref) for ref in recipe_refs):
        issues.append("acceptance recipeRefs contain invalid recipe reference")
        return
    profile_refs: list[dict[str, str]] = []
    for profile in profiles:
        ref = profile.get("recipe") if isinstance(profile, dict) else None
        if not valid_ref(ref):
            issues.append("protected baseline profile contains invalid recipe reference")
            return
        profile_refs.append(ref)
    ref_key = lambda ref: (ref["id"], ref["hash"])
    config_keys = [ref_key(ref) for ref in recipe_refs]
    profile_keys = [ref_key(ref) for ref in profile_refs]
    if len(set(config_keys)) != len(config_keys):
        issues.append("acceptance recipeRefs contain duplicate recipe profiles")
    if len(set(profile_keys)) != len(profile_keys):
        issues.append("protected baseline contains duplicate recipe profiles")
    if set(config_keys) != set(profile_keys):
        issues.append("acceptance recipeRefs & protected baseline profile membership differ")
    if len(set(ref["id"] for ref in recipe_refs)) != len(recipe_refs):
        issues.append("acceptance recipeRefs contain duplicate recipe IDs")
    if len(set(ref["id"] for ref in profile_refs)) != len(profile_refs):
        issues.append("protected baseline contains duplicate recipe IDs")

    try:
        from factory.recipes.recipes import load_recipes
        trusted = {recipe["id"]: recipe for recipe in load_recipes()}
    except Exception as exc:
        issues.append(f"trusted recipe catalogue load failed: {exc}")
        return
    for profile in profiles:
        ref = profile["recipe"]
        recipe = trusted.get(ref["id"])
        if recipe is None:
            issues.append(f"protected baseline references unknown trusted recipe {ref['id']}")
            continue
        if _ref_hash(recipe) != ref["hash"]:
            issues.append(f"protected baseline recipe hash differs for {ref['id']}")
            continue
        seed = profile.get("seed")
        if not isinstance(seed, int) or isinstance(seed, bool):
            issues.append(f"protected baseline seed must be an integer for {ref['id']}")
            continue
        refs = profile.get("cases")
        try:
            expanded_refs = baseline_case_refs(expand_cases(recipe, tuple_value, seed=seed)["cases"])
        except Exception as exc:
            issues.append(f"trusted baseline recipe expansion failed for {ref['id']}: {exc}")
            continue
        if refs != expanded_refs:
            issues.append(f"protected baseline projections differ from complete trusted expansion for {ref['id']}")


def _semantic_projection(capture: dict[str, Any]) -> dict[str, Any]:
    """Keep semantic channels; exclude timestamps and presentation timing."""
    return {
        "layout": capture.get("layout", []),
        "ax": capture.get("ax", []),
        "events": [
            {k: event[k] for k in ("id", "kind", "payload") if k in event}
            for event in capture.get("events", [])
        ],
        "anim": [
            {
                "id": animation.get("id"),
                "samples": [sample.get("value") for sample in animation.get("samples", [])],
                "presentedFrames": [
                    {k: frame[k] for k in ("imageHash", "dropped") if k in frame}
                    for frame in animation.get("presentedFrames", [])
                ],
            }
            for animation in capture.get("anim", [])
        ],
        "images": capture.get("images", []),
        "text": capture.get("text", []),
    }


def _check_case_manifest(
    cases: list[dict[str, Any]], expected_cases: list[dict[str, Any]] | None,
    issues: list[str],
) -> list[dict[str, str]]:
    refs = _case_refs(cases)
    if len({ref["id"] for ref in refs}) != len(refs):
        issues.append("case manifest contains duplicate case IDs")
    if expected_cases is not None and refs != _case_refs(expected_cases):
        issues.append("case manifest is incomplete or differs from recipe expansion")
    manifest_hash = _case_set_hash(cases)
    for case in cases:
        if case.get("kind") != "case" or case.get("version") != "0.1":
            issues.append(f"{case.get('id', '<unknown>')}: invalid case artifact")
        if case.get("expectedCaseSetHash") != manifest_hash:
            issues.append(f"{case.get('id', '<unknown>')}: expected case-set hash mismatch")
    return refs


def _capture_issues(
    cases: list[dict[str, Any]], captures: list[dict[str, Any]], tuple_value: dict[str, Any],
    issues: list[str],
) -> tuple[dict[str, dict[str, list[dict[str, Any]]]], dict[str, Any]]:
    by_case: dict[str, dict[str, list[dict[str, Any]]]] = {
        case["id"]: {"macos": [], "windows": []} for case in cases
    }
    case_hashes = {case["id"]: _ref_hash(case) for case in cases}
    all_ids: set[str] = set()
    all_hashes: dict[str, str] = {}
    run_evidence_hashes: set[str] = set()
    for capture in captures:
        cid = capture.get("id")
        if not isinstance(cid, str) or cid in all_ids:
            issues.append("capture IDs must be present and unique")
            continue
        all_ids.add(cid)
        capture_hash = _ref_hash(capture)
        all_hashes[cid] = capture_hash
        platform = capture.get("platform")
        case_ref = capture.get("case", {})
        case_id = case_ref.get("id") if isinstance(case_ref, dict) else None
        if platform not in ("macos", "windows"):
            issues.append(f"{cid}: platform must be macos or windows")
            continue
        if case_id not in by_case:
            issues.append(f"{cid}: unknown case reference")
            continue
        if case_ref.get("hash") != case_hashes[case_id]:
            issues.append(f"{cid}: capture case hash does not bind to case artifact")
        if not _same_tuple(capture.get("tuple"), tuple_value):
            issues.append(f"{cid}: tuple mismatch")
        meta = capture.get("meta", {})
        conditions = meta.get("conditions", {}) if isinstance(meta, dict) else {}
        if not isinstance(conditions, dict):
            conditions = {}
        if conditions.get("independentRun") is not True or conditions.get("resetVerified") is not True:
            issues.append(f"{cid}: independent run and verified reset evidence required")
        provenance = capture.get("provenance", {})
        producer = str(provenance.get("producer", "")).lower() if isinstance(provenance, dict) else ""
        if conditions.get("synthetic") is True or conditions.get("specExample") is True or "synthetic" in producer:
            issues.append(f"{cid}: synthetic capture evidence cannot qualify for F10")
        run_evidence_hash = conditions.get("runEvidenceHash")
        if (not isinstance(run_evidence_hash, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", run_evidence_hash)
                or run_evidence_hash in run_evidence_hashes):
            issues.append(f"{cid}: unique run evidence hash required")
        else:
            run_evidence_hashes.add(run_evidence_hash)
        by_case[case_id][platform].append(capture)
    for case_id, sides in by_case.items():
        for platform, runs in sides.items():
            numbers = [r.get("meta", {}).get("run") for r in runs]
            if any(not isinstance(n, int) or isinstance(n, bool) or n < 1 for n in numbers):
                issues.append(f"{case_id}: {platform} has invalid run number")
                continue
            if len(runs) < MIN_RUNS:
                issues.append(f"{case_id}: {platform} has {len(runs)} runs; {MIN_RUNS} required")
            if len(set(numbers)) != len(numbers):
                issues.append(f"{case_id}: {platform} run numbers are not unique")
            if len(runs) >= MIN_RUNS and not set(range(1, MIN_RUNS + 1)).issubset(set(numbers)):
                issues.append(f"{case_id}: {platform} run numbers must include 1..{MIN_RUNS}")
    return by_case, {"ids": sorted(all_ids), "hashes": all_hashes}


def _fault_control_issues(
    rules: list[dict[str, Any]], runner: Callable[..., dict[str, Any]] | None, issues: list[str],
) -> None:
    for rule in rules:
        rid = rule.get("id", "<unknown>")
        control_hash = rule.get("faultControlHash")
        if not control_hash or not callable(runner):
            issues.append(f"normalizer {rid}: required fault control missing")
            continue
        try:
            observed = runner(rule=rule, control_hash=control_hash)
        except Exception as exc:
            issues.append(f"normalizer {rid}: fault control runner failed: {exc}")
            continue
        if not isinstance(observed, dict):
            issues.append(f"normalizer {rid}: fault control runner returned invalid result")
            continue
        if observed.get("hash") != control_hash:
            issues.append(f"normalizer {rid}: fault control hash mismatch")
        if observed.get("ruleActive") is not True or observed.get("faultRejected") is not True:
            issues.append(f"normalizer {rid}: fault control did not reject mutation with rule active")


def _promotion_check(request: Any, tuple_value: dict[str, Any], issues: list[str]) -> dict[str, Any]:
    if request is None:
        return {"requested": False, "promoted": False}
    fields = ("reviewer", "at", "decision", "candidateHash", "diffHash", "tupleHash")
    if not isinstance(request, dict) or any(not request.get(field) for field in fields):
        issues.append("promotion request lacks maintainer review binding")
        return {"requested": True, "promoted": False}
    if request.get("decision") != "accepted":
        issues.append("promotion review is not accepted")
    if request.get("tupleHash") != sha256(tuple_value):
        issues.append("promotion review tuple binding mismatch")
    # Gate verifies review evidence only; promotion remains a separate maintainer action.
    return {"requested": True, "promoted": False, "reviewAccepted": request.get("decision") == "accepted"}


def expand_gate_seeded_cases(recipe: dict[str, Any], tuple_value: dict[str, Any], seed: int) -> list[dict[str, Any]]:
    """Generate one gate-owned randomized variant from declared recipe axes."""
    axes = recipe.get("axes", [])
    if not axes:
        return []
    rng = random.Random(seed)
    inputs = {axis["id"]: rng.choice(axis["values"]) for axis in axes if axis.get("values")}
    if len(inputs) != len(axes):
        return []
    case = {
        "kind": "case", "version": "0.1",
        "id": f"{recipe['id']}.gate-seeded.{seed:016x}",
        "provenance": {
            "sourceHash": _ref_hash(recipe),
            "createdAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "producer": "factory.gate/0.1",
        },
        "recipe": {"id": recipe["id"], "hash": _ref_hash(recipe)},
        "block": recipe["block"], "inputs": inputs, "expectedCaseSetHash": "",
        "coverage": "gate-seeded", "seed": seed, "tuple": tuple_value,
    }
    case["expectedCaseSetHash"] = _case_set_hash([case])
    return [case]


def evaluate_gate(
    *, recipe: dict[str, Any], cases: list[dict[str, Any]], captures: list[dict[str, Any]],
    tuple_value: dict[str, Any], acceptance_config: dict[str, Any] | None = None,
    normalizer_rules: list[dict[str, Any]] | None = None,
    fault_control_runner: Callable[..., dict[str, Any]] | None = None, timing: dict[str, Any] | None = None,
    expected_cases: list[dict[str, Any]] | None = None, seed: int | None = None,
    random_case_factory: Callable[[int], list[dict[str, Any]]] | None = None,
    seeded_capture_runner: Callable[..., list[dict[str, Any]]] | None = None,
    semantic_comparator: Callable[..., dict[str, Any]] | None = None,
    timing_comparator: Callable[..., dict[str, Any]] | None = None,
    trusted_rebuild: dict[str, Any] | None = None, merged_commit: str | None = None,
    sr0_closed: bool = False, promotion_request: dict[str, Any] | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    """Validate F10 evidence and return fail-closed report plus receipt.

    ``seed`` is only for deterministic tests. Production callers omit it so
    the gate chooses a fresh 64-bit seed using ``secrets``.
    """
    issues: list[str] = []
    if recipe.get("kind") != "recipe":
        issues.append("recipe artifact missing or invalid")
    if not isinstance(tuple_value, dict) or tuple_value.get("acceptanceConfigHash") is None:
        issues.append("tuple acceptance configuration binding missing")
    if not isinstance(acceptance_config, dict):
        issues.append("protected acceptance configuration unavailable")
    elif not isinstance(tuple_value, dict) or sha256(acceptance_config) != tuple_value.get("acceptanceConfigHash"):
        issues.append("protected acceptance configuration hash differs from tuple")
    protected_rules = acceptance_config.get("normalizers", []) if isinstance(acceptance_config, dict) else []
    if normalizer_rules != protected_rules:
        issues.append("normalizer rules differ from protected acceptance configuration")
    if isinstance(acceptance_config, dict):
        _check_recipe_profile_closure(acceptance_config, tuple_value, issues)
    cases = list(cases or [])
    expected_cases = list(expected_cases) if expected_cases is not None else None
    _check_case_manifest(cases, expected_cases, issues)
    _check_protected_baseline(recipe, tuple_value, cases, expected_cases, acceptance_config, issues)
    recipe_hash = _ref_hash(recipe)
    for case in cases:
        ref = case.get("recipe", {})
        if ref != {"id": recipe.get("id"), "hash": recipe_hash}:
            issues.append(f"{case.get('id', '<unknown>')}: recipe hash binding mismatch")
        if case.get("block") != recipe.get("block"):
            issues.append(f"{case.get('id', '<unknown>')}: recipe block mismatch")
        if not _same_tuple(case.get("tuple"), tuple_value):
            issues.append(f"{case.get('id', '<unknown>')}: case tuple mismatch")

    actual_seed = secrets.randbits(64) if seed is None else seed
    if not isinstance(actual_seed, int) or actual_seed < 0 or actual_seed >= 2**64:
        issues.append("gate seed must be unsigned 64-bit integer")
    seeded_cases: list[dict[str, Any]] = []
    generator = random_case_factory or (lambda value: expand_gate_seeded_cases(recipe, tuple_value, value))
    try:
        seeded_cases = list(generator(actual_seed))
    except Exception as exc:  # hold the lane with useful diagnostic
        issues.append(f"gate-seeded case generation failed: {exc}")
    if not seeded_cases:
        issues.append("gate-seeded case generator produced no cases")
    for case in seeded_cases:
        if case.get("coverage") != "gate-seeded" or case.get("seed") != actual_seed:
            issues.append(f"{case.get('id', '<unknown>')}: generated case seed/coverage mismatch")
        if case.get("recipe") != {"id": recipe.get("id"), "hash": recipe_hash}:
            issues.append(f"{case.get('id', '<unknown>')}: seeded recipe hash binding mismatch")
        if not _same_tuple(case.get("tuple"), tuple_value):
            issues.append(f"{case.get('id', '<unknown>')}: seeded tuple mismatch")
    all_cases = cases + seeded_cases
    all_case_ids = [case.get("id") for case in all_cases]
    if len(set(all_case_ids)) != len(all_case_ids):
        issues.append("duplicate case IDs across recipe and gate-seeded cases")
    # Seeded cases form separate, gate-owned batch; they cannot alter recipe coverage.
    refs = _case_refs(all_cases)
    combined_set_hash = _case_set_hash(all_cases)
    if seeded_cases:
        seeded_hash = _case_set_hash(seeded_cases)
        for case in seeded_cases:
            if case.get("expectedCaseSetHash") != seeded_hash:
                issues.append(f"{case.get('id', '<unknown>')}: seeded case-set hash mismatch")

    captures = list(captures or [])
    if seeded_cases:
        if not callable(seeded_capture_runner):
            issues.append("gate-seeded Mac and Windows capture runner unavailable")
        else:
            try:
                extra_captures = seeded_capture_runner(cases=seeded_cases, seed=actual_seed, tuple_value=tuple_value)
                captures.extend(extra_captures)
            except Exception as exc:
                issues.append(f"gate-seeded capture runner failed: {exc}")

    by_case, capture_ids = _capture_issues(all_cases, captures, tuple_value, issues)
    # Semantic equality and timing are separate dimensions. Captured channels are
    # compared byte-for-byte here; host comparators may attach explicit results.
    semantic_results: dict[str, bool] = {}
    for case_id, sides in by_case.items():
        for platform, runs in sides.items():
            projections = [sha256(_semantic_projection(run)) for run in runs]
            semantic_results[f"{case_id}:{platform}"] = bool(projections) and len(set(projections)) == 1
            if not semantic_results[f"{case_id}:{platform}"]:
                issues.append(f"{case_id}: {platform} semantic captures are not exactly repeatable")
        observed_hashes = sorted(
            _ref_hash(run) for platform_runs in sides.values() for run in platform_runs
        )
        comparison = None
        if callable(semantic_comparator):
            try:
                comparison = semantic_comparator(
                    case=next(case for case in all_cases if case["id"] == case_id),
                    macos=sides["macos"], windows=sides["windows"], tuple_value=tuple_value,
                )
            except Exception as exc:
                issues.append(f"{case_id}: trusted semantic comparator failed: {exc}")
        if (not isinstance(comparison, dict) or comparison.get("status") != "pass"
                or not comparison.get("evidenceHash")
                or comparison.get("captureHashes") != observed_hashes
                or comparison.get("tupleHash") != sha256(tuple_value)
                or comparison.get("normalizerConfigHash") != tuple_value.get("acceptanceConfigHash")
                or comparison.get("caseHash") != _ref_hash(next(case for case in all_cases if case["id"] == case_id))
                or comparison.get("recipeHash") != recipe_hash
                or comparison.get("assertedChannels") != sorted({
                    assertion["channel"] for assertion in recipe.get("assertions", [])
                    if assertion.get("observability", "available") == "available"
                })
                or comparison.get("missingChannels") != []):
            issues.append(f"{case_id}: cross-platform semantic comparator evidence unavailable or failed")
    timing_result = timing
    if callable(timing_comparator):
        try:
            timing_result = timing_comparator(captures=captures, tuple_value=tuple_value)
        except Exception as exc:
            timing_result = None
            issues.append(f"trusted timing comparator failed: {exc}")
    observed_capture_hashes = sorted(_ref_hash(capture) for capture in captures)
    if (not callable(timing_comparator) or not isinstance(timing_result, dict) or timing_result.get("status") != "pass"
            or not timing_result.get("evidence")
            or timing_result.get("captureHashes") != observed_capture_hashes
            or timing_result.get("tupleHash") != sha256(tuple_value)):
        issues.append("separate bounded timing comparison evidence unavailable or failed")

    _fault_control_issues(normalizer_rules or [], fault_control_runner, issues)
    if not callable(trusted_rebuild):
        issues.append("trusted merged-commit rebuild evidence unavailable; native parity held")
    else:
        try:
            build = trusted_rebuild(merged_commit=merged_commit, tuple_value=tuple_value)
        except Exception as exc:
            build = None
            issues.append(f"trusted rebuild callback failed: {exc}")
        if (not isinstance(build, dict) or build.get("status") != "pass"
                or build.get("mergedCommit") != merged_commit
                or build.get("runtimeCommit") != tuple_value.get("runtimeCommit")
                or build.get("rendererHash") != tuple_value.get("rendererHash")
                or not build.get("evidenceHash") or not merged_commit):
            issues.append("trusted rebuild callback did not attest exact merged commit and tuple binaries")
    if not sr0_closed:
        issues.append("SR0 closure is required before frozen tuple parity")

    promotion = _promotion_check(promotion_request, tuple_value, issues)
    status = "pass" if not issues else "blocked"
    started = (now or datetime.now(timezone.utc)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    artifact_hashes = [*(_ref_hash(case) for case in all_cases), *(capture_ids["hashes"][cid] for cid in capture_ids["ids"])]
    gate_id = f"gate.f10.{actual_seed:016x}"
    report = {
        "kind": "gate-report", "version": "0.1", "id": gate_id, "status": status,
        "seed": actual_seed, "recipe": {"id": recipe.get("id", "unknown"), "hash": _ref_hash(recipe)},
        "tuple": tuple_value, "caseSetHash": combined_set_hash, "cases": refs,
        "captureIds": capture_ids["ids"], "semanticRepeatability": semantic_results,
        "timing": timing_result if isinstance(timing_result, dict) else {"status": "blocked"},
        "faultControlsPassed": not any("fault control" in item or "fault-control" in item for item in issues),
        "promotion": promotion, "parityGranted": status == "pass", "issues": sorted(set(issues)),
    }
    report["reportHash"] = sha256(report)
    receipt = {
        "kind": "receipt", "version": "0.1", "id": f"{gate_id}.receipt",
        "provenance": {"sourceHash": report["reportHash"], "createdAt": started, "producer": "factory.gate/0.1"},
        "operation": "gate", "status": status, "tuple": tuple_value,
        "inputs": [{"id": f"case.input.{i}", "hash": h} for i, h in enumerate(artifact_hashes)],
        "outputs": [{"id": gate_id, "hash": report["reportHash"]}],
        "startedAt": started, "finishedAt": started, "seed": actual_seed,
    }
    return {"report": report, "receipt": receipt}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Evaluate F10 gate evidence")
    parser.add_argument("input", nargs="?", help="JSON input; defaults to stdin")
    parser.add_argument("-o", "--output", help="write JSON result to this path")
    args = parser.parse_args(argv)
    try:
        path = Path(args.input).read_text() if args.input else sys.stdin.read()
        data = json.loads(path)
        result = evaluate_gate(**data)
    except (OSError, ValueError, TypeError, KeyError, CanonicalJSONError) as exc:
        print(f"factory.gate: invalid input: {exc}", file=sys.stderr)
        return 2
    payload = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(payload)
    else:
        sys.stdout.write(payload)
    return 0 if result["report"]["status"] == "pass" else 3


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
