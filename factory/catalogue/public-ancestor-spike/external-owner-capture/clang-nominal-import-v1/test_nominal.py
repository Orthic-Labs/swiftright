#!/usr/bin/env python3
"""Nonvacuous mutation controls for inferred nominal evidence."""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_evidence


def reject(label: str, evidence: dict) -> None:
    try:
        build_evidence.validate(evidence)
    except (ValueError, IndexError):
        return
    raise AssertionError(f"accepted mutation: {label}")


def main() -> None:
    evidence = json.loads((HERE / "raw/clang-nominal-import-v1.json").read_text())
    build_evidence.validate(evidence)
    first = evidence["owners"][0]

    wrong_source = copy.deepcopy(evidence)
    wrong_source["owners"][0]["sourceToken"]["line"] += 1
    reject("wrong source token", wrong_source)

    wrong_variable_usr = copy.deepcopy(evidence)
    wrong_variable_usr["owners"][0]["variableUSR"] = "s:wrong"
    reject("wrong variable USR", wrong_variable_usr)

    wrong_nominal_usr = copy.deepcopy(evidence)
    wrong_nominal_usr["owners"][0]["nominalUSR"] = "c:wrong"
    reject("wrong nominal USR", wrong_nominal_usr)

    wrong_type = copy.deepcopy(evidence)
    wrong_type["owners"][0]["compilerType"] = "Wrong.Type"
    reject("wrong compiler type", wrong_type)

    wrong_demangle = copy.deepcopy(evidence)
    wrong_demangle["owners"][0]["demangleBlock"] = wrong_demangle["owners"][0]["demangleBlock"].replace("NSWindow", "WrongOwner")
    reject("wrong demangle tree", wrong_demangle)

    wrong_process_target = copy.deepcopy(evidence)
    run = next(item for item in wrong_process_target["processRuns"] if item["name"] == "swift-typecheck")
    i = run["argv"].index("-target")
    run["argv"][i + 1] = "arm64-apple-macosx26.0"
    reject("wrong process target", wrong_process_target)

    wrong_v3_pin = copy.deepcopy(evidence)
    wrong_v3_pin["frozenV3"]["evidence"]["sha256"] = "sha256:wrong"
    reject("wrong frozen v3 pin", wrong_v3_pin)

    print(json.dumps({"baseline": "accepted", "mutationsRejected": 7, "owner": first["target"]}, indent=2))


if __name__ == "__main__":
    main()
