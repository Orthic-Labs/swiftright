#!/usr/bin/env python3
"""Prepare append-only case joins before fresh Windows padding compilation."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from factory.core.artifacts import canonical_hash

MAX_JSON = 8 * 1024 * 1024


class Hold(ValueError):
    pass


def read_json(path: Path, label: str) -> dict[str, Any]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON:
        raise Hold(f"{label} unavailable, symlinked, or exceeds bound")
    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} object required")
    return value


def ref(value: Any, label: str) -> dict[str, str]:
    if not isinstance(value, dict) or not isinstance(value.get("id"), str) or not isinstance(value.get("hash"), str):
        raise Hold(f"{label} reference missing")
    return {"id": value["id"], "hash": value["hash"]}


def case_ref(case: dict[str, Any], label: str) -> dict[str, str]:
    if case.get("kind") != "case" or case.get("version") != "0.1":
        raise Hold(f"{label} must be case v0.1")
    body = dict(case)
    supplied = body.pop("hash", None)
    result = {"id": str(case.get("id", "")), "hash": canonical_hash(body)}
    if not result["id"] or (supplied is not None and supplied not in {result["hash"], result["hash"].removeprefix("sha256:")}):
        raise Hold(f"{label} canonical identity invalid")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True, type=Path)
    parser.add_argument("--mac-report", required=True, type=Path)
    parser.add_argument("--source-plan", required=True, type=Path)
    parser.add_argument("--capture-plan", required=True, type=Path)
    parser.add_argument("--candidate-tuple", required=True, type=Path)
    parser.add_argument("--issued-metadata", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        case = read_json(args.case, "fresh case")
        mac = read_json(args.mac_report, "Mac report")
        source = read_json(args.source_plan, "immutable source plan")
        capture = read_json(args.capture_plan, "immutable capture plan")
        candidate = read_json(args.candidate_tuple, "candidate tuple")
        issued = read_json(args.issued_metadata, "issued metadata")
        fresh = case_ref(case, "fresh case")
        mac_case = ref(mac.get("case"), "Mac report case")
        candidate_case = ref(candidate.get("case"), "candidate case")
        issued_case = ref(issued.get("case"), "issued case")
        for label, value in (("Mac", mac_case), ("candidate", candidate_case), ("issued", issued_case)):
            if value != fresh:
                raise Hold(f"{label} case does not equal fresh case")
        if issued.get("expectedCount") != 20:
            raise Hold("issued Count20 metadata required")
        if source.get("kind") != "windows-padding-capture-lease-source-plan" or source.get("executionEligible") is not False:
            raise Hold("immutable source plan kind/hold changed")
        source_case = ref(source.get("case"), "source plan case")
        capture_case = ref(capture.get("case"), "capture plan case")
        if source_case != capture_case:
            raise Hold("immutable source/capture plan lineage already differs")
        if source_case == fresh:
            raise Hold("fresh rebuild must prove changed legacy case identity")
        tuple_value = candidate.get("tuple")
        if not isinstance(tuple_value, dict) or candidate.get("candidateID") != tuple_value.get("id"):
            raise Hold("candidate tuple identity missing")
        source_hash = source.get("sourceHash")
        if not isinstance(source_hash, str) or issued.get("sourceHash") != source_hash:
            raise Hold("source hash does not join issued metadata")
        exe = issued.get("exe");renderer = issued.get("renderer")
        if not isinstance(exe, dict) or not isinstance(renderer, dict):
            raise Hold("issued executable/renderer refs missing")
        if tuple_value.get("hostHashes", {}).get("windows") != exe.get("sha256"):
            raise Hold("candidate Windows host differs from measured executable")
        if tuple_value.get("rendererHash") != renderer.get("sha256"):
            raise Hold("candidate renderer differs from measured renderer")
        output = {
            "kind": "factory-padding-case-rebuild-bindings-v1",
            "status": "source-bound-ready-fresh-compile-required",
            "executionEligible": False,
            "freshCase": fresh,
            "macCase": mac_case,
            "candidateCase": candidate_case,
            "issuedCase": issued_case,
            "legacySourcePlanCase": source_case,
            "legacyCapturePlanCase": capture_case,
            "immutableSourcePlanPath": str(args.source_plan),
            "immutableCapturePlanPath": str(args.capture_plan),
            "sourceHash": source_hash,
            "candidateID": candidate["candidateID"],
            "expectedCount": 20,
            "measuredExecutable": exe,
            "measuredRenderer": renderer,
            "runtimeCommit": tuple_value.get("runtimeCommit"),
            "next": {
                "freshPlanMaterializer": "factory/pipeline/paired-padding-r11-v12/materialize-fresh-padding-plan-v1.py",
                "freshCaptureMaterializer": "factory/pipeline/paired-padding-r11-v12/materialize-fresh-capture-plan-v1.py",
                "requiredEquality": "fresh plan.case == freshCase == issued.case == candidate.case == Mac report.case == every new capture.case",
                "historicEvidence": "legacy source/capture plans remain unchanged and are never relabeled",
            },
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"status": output["status"], "case": fresh, "expectedCount": 20}, sort_keys=True))
        return 0
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc


if __name__ == "__main__":
    raise SystemExit(main())
