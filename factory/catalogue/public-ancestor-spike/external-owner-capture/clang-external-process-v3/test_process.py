#!/usr/bin/env python3
"""Mutation controls for production evidence validator."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(HERE))
import build_evidence


def must_reject(label: str, evidence: dict) -> None:
    try:
        build_evidence.validate_evidence(evidence)
    except ValueError:
        return
    raise AssertionError(f"validator accepted mutation: {label}")


def main() -> None:
    path = HERE / "raw/clang-external-process-v3.json"
    baseline = json.loads(path.read_text())
    build_evidence.validate_evidence(baseline)
    target = baseline["targets"][0]

    wrong_source = copy.deepcopy(baseline)
    wrong_source["targets"][0]["source"]["path"] = baseline["targets"][1]["source"]["path"]
    must_reject("wrong-source-path", wrong_source)

    wrong_usr = copy.deepcopy(baseline)
    wrong_usr["targets"][0]["usr"] = "c:wrong-owner"
    must_reject("wrong-usr", wrong_usr)

    wrong_kind = copy.deepcopy(baseline)
    wrong_kind["targets"][0]["astKind"] = "RecordDecl"
    must_reject("wrong-kind", wrong_kind)

    wrong_process = copy.deepcopy(baseline)
    wrong_process["processRuns"][0]["returncode"] = 1
    must_reject("wrong-process-returncode", wrong_process)

    wrong_export = copy.deepcopy(baseline)
    wrong_export["moduleMaps"][0]["exportEvidence"] = ["export *"]
    must_reject("wrong-module-export", wrong_export)

    extra_target = copy.deepcopy(baseline)
    extra_target["targets"].append(copy.deepcopy(target))
    must_reject("extra-target", extra_target)

    missing_clang_target = copy.deepcopy(baseline)
    clang_run = next(run for run in missing_clang_target["processRuns"] if run["name"] == "clang-appkit-ast")
    target_index = clang_run["argv"].index("-target")
    del clang_run["argv"][target_index:target_index + 2]
    must_reject("missing-clang-target", missing_clang_target)

    print(json.dumps({"baseline": "accepted", "mutationsRejected": 7, "target": target["target"]}, indent=2))


if __name__ == "__main__":
    main()
