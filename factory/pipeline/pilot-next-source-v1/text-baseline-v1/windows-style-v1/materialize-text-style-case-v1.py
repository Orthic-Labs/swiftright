#!/usr/bin/env python3
"""Build fresh Text tuple/case/final plan from measured Windows receipt + archived Mac capture.

This source-only materializer never relabels archived observations.  It requires a
successful, byte-bound Windows prebuild receipt and emits a held fresh candidate.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import stat
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from factory.core.artifacts import canonical_hash, write_artifact

PACKET = Path(__file__).resolve().parent.parent
MAX_JSON = 2 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
MAX_COMPILER = 512 * 1024 * 1024
SHA = re.compile(r"sha256:[0-9a-f]{64}\Z")
RAW_SHA = re.compile(r"[0-9a-f]{64}\Z")
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RENDERER = "sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
COMPILER = "1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"
CANDIDATE = "swiftui.text.layout.baseline.pilot-next"
RECIPE_ID = "swiftui.text.layout.baseline.recipe"
RECIPE_HASH = "sha256:ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d"
WITNESS_HASH = "sha256:4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e"
TEXT_INPUTS = {
    "text": "Aa",
    "font": {"family": "system", "size": 24, "weight": "regular", "design": "default"},
    "foreground": "primary",
    "colorScheme": "light",
    "viewport": {"width": 120, "height": 48, "alignment": "center"},
}


def _regular(path: Path, limit: int, label: str) -> int:
    try:
        st = path.lstat()
    except OSError as exc:
        raise ValueError(f"{label} is unreadable: {path}") from exc
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular {label} required: {path}")
    return st.st_size


def bounded_json(path: Path) -> dict[str, Any]:
    _regular(path, MAX_JSON, "JSON")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid bounded JSON: {path}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def file_hash(path: Path, limit: int = MAX_SOURCE) -> str:
    _regular(path, limit, "file")
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"file grew past bound: {path}")
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def raw_hash(value: Any, field: str) -> str:
    if not isinstance(value, str) or not RAW_SHA.fullmatch(value.lower()):
        raise ValueError(f"{field} must be bare lowercase sha256")
    return "sha256:" + value.lower()


def prefixed_hash(value: Any, field: str) -> str:
    if not isinstance(value, str) or not SHA.fullmatch(value.lower()):
        raise ValueError(f"{field} must be sha256:<64 lowercase hex>")
    return value.lower()


def same_hash(value: Any, expected: str, field: str) -> None:
    got = value
    want = expected
    if isinstance(got, str) and RAW_SHA.fullmatch(got.lower()):
        got = "sha256:" + got.lower()
    if isinstance(want, str) and RAW_SHA.fullmatch(want.lower()):
        want = "sha256:" + want.lower()
    if got != want:
        raise ValueError(f"{field} mismatch")


def _required_tuple(value: dict[str, Any]) -> None:
    required = {"id", "sdk", "macosBuild", "toolchains", "runtimeCommit", "rendererHash", "hostHashes", "factoryVersion", "acceptanceConfigHash"}
    if set(value) != required:
        raise ValueError("tuple keys must match common schema")
    if not isinstance(value["id"], str) or not value["id"].strip():
        raise ValueError("fresh tuple id required")
    if value["runtimeCommit"] != RUNTIME:
        raise ValueError("tuple runtime drift")
    if value["rendererHash"] != RENDERER:
        raise ValueError("tuple renderer drift")
    hosts = value["hostHashes"]
    if not isinstance(hosts, dict) or set(hosts) != {"macos", "windows"}:
        raise ValueError("both measured host hashes required")
    for name, host in hosts.items():
        prefixed_hash(host, f"tuple hostHashes.{name}")
    prefixed_hash(value["acceptanceConfigHash"], "tuple acceptanceConfigHash")
    for key in ("sdk", "macosBuild", "factoryVersion"):
        if not isinstance(value[key], str) or not value[key].strip():
            raise ValueError(f"tuple {key} required")
    if not isinstance(value["toolchains"], dict) or not value["toolchains"].get("macSwift") or not value["toolchains"].get("winSwift"):
        raise ValueError("measured toolchains required")


def _plan_values(plan: dict[str, Any], witness_hash: str, recipe_hash: str) -> None:
    if plan.get("kind") != "factory-text-compiler-plan-v1" or plan.get("candidate") != CANDIDATE or plan.get("phase") != "prebuild":
        raise ValueError("Windows prebuild plan identity mismatch")
    if plan.get("case") is not None or plan.get("executionEligible") is not False:
        raise ValueError("prebuild plan must have no case or execution eligibility")
    same_hash(plan.get("sourceHash"), witness_hash, "plan source")
    if plan.get("runtimeSourceCommit") != RUNTIME:
        raise ValueError("plan runtime drift")
    same_hash(plan.get("rendererSha256"), RENDERER, "plan renderer")
    if plan.get("compilerHash") != COMPILER:
        raise ValueError("plan compiler drift")
    if plan.get("runtimeSourceTreeHash") != "sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e":
        raise ValueError("plan runtime source tree drift")
    recipe = plan.get("recipe")
    if not isinstance(recipe, dict) or recipe.get("id") != RECIPE_ID or recipe.get("hash") != recipe_hash:
        raise ValueError("plan recipe join mismatch")
    request = plan.get("compileRequest")
    if not isinstance(request, dict) or any(request.get(key) != 1 for key in ("jobs", "maxParallelJobs", "maxFrontendThreads")):
        raise ValueError("single-threaded compile request required")
    if request.get("target") != "windows-x86_64" or request.get("configuration") != "release":
        raise ValueError("Windows release compile request required")


def _receipt_values(receipt: dict[str, Any], plan: dict[str, Any], plan_hash: str) -> str:
    if receipt.get("kind") != "factory-text-owned-compile-v1" or receipt.get("phase") != "prebuild":
        raise ValueError("Windows receipt identity mismatch")
    same_hash(receipt.get("planSha256"), plan_hash, "receipt plan")
    for field in ("sourceHash", "runtimeSourceTreeHash", "rendererSha256"):
        same_hash(receipt.get(field), plan.get(field), f"receipt {field}")
    if receipt.get("runtimeSourceCommit") != plan.get("runtimeSourceCommit") or receipt.get("compilerHash") != plan.get("compilerHash"):
        raise ValueError("receipt compile closure mismatch")
    if receipt.get("exitCode") != 0 or receipt.get("timedOut") is not False or receipt.get("outputCapExceeded") is not False:
        raise ValueError("Windows compile did not complete cleanly")
    if receipt.get("ownedExited") is not True or receipt.get("streamsSealed") is not True or receipt.get("streamDrainComplete") is not True:
        raise ValueError("Windows compile ownership/streams not sealed")
    if receipt.get("jobActiveReadable") is not True or receipt.get("jobActiveCount") != 0 or receipt.get("nativeActions") != 0:
        raise ValueError("Windows compile quiescence/native gate mismatch")
    exe = raw_hash(receipt.get("exeSha256"), "receipt exeSha256")
    if not isinstance(receipt.get("exeBytes"), int) or receipt["exeBytes"] <= 0:
        raise ValueError("Windows executable bytes missing")
    return exe


def _mac_values(capture: dict[str, Any], witness_hash: str, recipe_hash: str) -> tuple[dict[str, Any], dict[str, Any]]:
    if capture.get("kind") != "capture" or capture.get("platform") != "macos":
        raise ValueError("archived Mac capture identity mismatch")
    old_tuple = capture.get("tuple")
    old_case = capture.get("case")
    if not isinstance(old_tuple, dict) or not isinstance(old_case, dict):
        raise ValueError("archived Mac tuple/case required")
    _required_tuple(old_tuple)
    if old_tuple["runtimeCommit"] != RUNTIME or old_tuple["rendererHash"] != RENDERER:
        raise ValueError("archived Mac runtime/renderer mismatch")
    provenance = capture.get("provenance")
    if not isinstance(provenance, dict):
        raise ValueError("Mac provenance required")
    prefixed_hash(provenance.get("sourceHash"), "Mac capture provenance source")
    capture_inputs = provenance.get("inputs")
    if not isinstance(capture_inputs, list) or not any(isinstance(item, dict) and item.get("id") == "macos.capture.binary" and item.get("hash") == old_tuple["hostHashes"]["macos"] for item in capture_inputs):
        raise ValueError("Mac measured binary input join mismatch")
    conditions = capture.get("meta", {}).get("conditions", {}).get("caseInputs")
    if conditions != TEXT_INPUTS:
        raise ValueError("archived Mac Text inputs mismatch")
    if not isinstance(old_case.get("id"), str) or not isinstance(old_case.get("hash"), str):
        raise ValueError("archived Mac case lineage missing")
    # Old Windows host is historical donor metadata only; only Mac host may seed fresh tuple.
    prefixed_hash(old_tuple["hostHashes"]["macos"], "archived Mac host")
    return old_tuple, old_case


def validate_inputs(plan: dict[str, Any], receipt: dict[str, Any], capture: dict[str, Any], *, tuple_id: str, acceptance_hash: str, plan_hash: str, witness_hash: str, recipe_hash: str) -> tuple[dict[str, Any], dict[str, Any], str, dict[str, Any]]:
    if not isinstance(capture, dict) or not isinstance(capture.get("tuple"), dict) or not isinstance(capture.get("case"), dict):
        raise ValueError("archived Mac tuple/case required")
    if tuple_id == capture["tuple"].get("id") or tuple_id == capture["case"].get("id"):
        raise ValueError("fresh tuple must not reuse archived identity")
    prefixed_hash(acceptance_hash, "fresh acceptance config")
    _plan_values(plan, witness_hash, recipe_hash)
    exe_hash = _receipt_values(receipt, plan, plan_hash)
    old_tuple, old_case = _mac_values(capture, witness_hash, recipe_hash)
    if exe_hash == old_tuple["hostHashes"]["windows"]:
        raise ValueError("fresh Windows executable reuses archived Windows host")
    if exe_hash == old_tuple["hostHashes"]["macos"]:
        raise ValueError("fresh Windows executable equals archived Mac host")
    fresh_tuple = copy.deepcopy(old_tuple)
    fresh_tuple["id"] = tuple_id
    fresh_tuple["hostHashes"] = {"macos": old_tuple["hostHashes"]["macos"], "windows": exe_hash}
    fresh_tuple["acceptanceConfigHash"] = acceptance_hash
    _required_tuple(fresh_tuple)
    return fresh_tuple, old_case, exe_hash, old_tuple


def materialize(args: argparse.Namespace) -> dict[str, Any]:
    recipe_path = PACKET / "recipe.json"
    witness_path = PACKET / "witness.swift"
    recipe = bounded_json(recipe_path)
    if recipe.get("kind") != "recipe" or recipe.get("id") != RECIPE_ID:
        raise ValueError("Text recipe identity drift")
    recipe_hash = canonical_hash(recipe)
    if recipe_hash != RECIPE_HASH:
        raise ValueError("Text canonical recipe bytes drift")
    witness_hash = file_hash(witness_path)
    if witness_hash != WITNESS_HASH:
        raise ValueError("Text witness source drift")
    plan = bounded_json(args.windows_plan)
    receipt = bounded_json(args.windows_receipt)
    capture = bounded_json(args.mac_capture)
    plan_hash = file_hash(args.windows_plan)
    fresh_tuple, old_case, exe_hash, old_tuple = validate_inputs(
        plan, receipt, capture, tuple_id=args.tuple_id, acceptance_hash=args.acceptance_config_hash,
        plan_hash=plan_hash, witness_hash=witness_hash, recipe_hash=recipe_hash,
    )
    tuple_hash = canonical_hash(fresh_tuple)
    suffix = tuple_hash.split(":", 1)[1][:16]
    case_id = f"swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.{suffix}"
    case = {
        "kind": "case", "version": "0.1", "id": case_id, "block": "swiftui.text.layout.baseline",
        "inputs": TEXT_INPUTS, "coverage": "declared",
        "expectedCaseSetHash": canonical_hash([{"id": case_id, "inputs": TEXT_INPUTS, "coverage": "declared"}]),
        "provenance": {"sourceHash": recipe_hash, "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "producer": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/windows-style-v1"},
        "recipe": {"id": RECIPE_ID, "hash": recipe_hash}, "tuple": fresh_tuple,
        "witness": {"path": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/witness.swift", "sourceHash": witness_hash},
    }
    case_hash = canonical_hash(case)
    final_plan = copy.deepcopy(plan)
    final_plan["phase"] = "final"
    final_plan["executionEligible"] = True
    final_plan["qualification"] = "final-compile-bound-native-capture-held"
    final_plan["case"] = {"id": case_id, "hash": case_hash}
    final_plan["tuple"] = fresh_tuple
    final_plan["recipe"] = {"id": RECIPE_ID, "hash": recipe_hash}
    final_plan["expectedHostHash"] = exe_hash
    final_plan["dispatch"] = {"first": {"count": 1}, "repeat": {"count": 20}}
    manifest = {
        "kind": "generated-probe", "version": "0.1", "block": "swiftui.text.layout.baseline",
        "candidate": CANDIDATE, "qualification": "held-until-fresh-native-capture", "executionEligible": True,
        "compileExpectation": "success", "scenario": "baseline", "tuple": {"id": fresh_tuple["id"], "hash": tuple_hash},
        "case": {"id": case_id, "hash": case_hash}, "caseInputs": TEXT_INPUTS,
        "environmentInputs": {"colorScheme": "light", "font": TEXT_INPUTS["font"], "viewport": TEXT_INPUTS["viewport"]},
        "recipe": {"id": RECIPE_ID, "hash": recipe_hash},
        "recipeFile": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/recipe.json",
        "sourceHash": witness_hash,
        "sourceFile": "witness.swift", "sourceRepositoryPath": "factory/pipeline/pilot-next-source-v1/text-baseline-v1/witness.swift",
        "witness": {"id": "swiftui.text.layout.baseline.witness", "sourceHash": witness_hash}, "witnessType": "Witness_swiftui_text_layout_baseline", "tupleId": fresh_tuple["id"],
        "channels": {"assertionChannels": ["layout", "paint", "text-observation"], "geometry": [{"channel": "layout", "hostHookRequired": True, "probeTag": "swiftui.text.layout.baseline", "viewInstrumentationInserted": False}], "text": {"rawAXPreserved": True, "rawUIAPreserved": True, "fallbackFamilyMeasured": True, "baselineMeasured": True}, "viewport": TEXT_INPUTS["viewport"], "font": TEXT_INPUTS["font"], "native": [], "provider": [], "transparency": {"channels": ["layout", "paint", "text-observation"], "enabled": False, "viewIsolatedFromInstrumentation": True}},
        "lineage": {"archivedMacCapture": {"path": str(args.mac_capture), "case": old_case, "tupleId": old_tuple["id"], "tupleHash": canonical_hash(old_tuple)}, "windowsPrebuild": {"planPath": str(args.windows_plan), "planSha256": plan_hash, "receiptPath": str(args.windows_receipt), "exeSha256": exe_hash}},
        "replays": {"first": 1, "repeat": 20},
    }
    output = args.output.expanduser().resolve()
    if output.exists():
        raise ValueError("output must be a fresh directory")
    output.mkdir(parents=True)
    write_artifact(output / "manifest.json", manifest)
    final_plan["manifestHash"] = file_hash(output / "manifest.json")
    write_artifact(output / "tuple.json", fresh_tuple)
    write_artifact(output / "cases" / f"{case_id}.json", case)
    write_artifact(output / "plan-final.json", final_plan)
    (output / "witness.swift").write_bytes(witness_path.read_bytes())
    (output / "recipe.json").write_bytes(recipe_path.read_bytes())
    write_artifact(output / "source-bindings.json", {"witness": {"path": "witness.swift", "sha256": witness_hash}, "recipe": {"path": "recipe.json", "sha256": recipe_hash}, "windowsPlan": {"path": str(args.windows_plan), "sha256": plan_hash}, "windowsReceipt": {"path": str(args.windows_receipt), "sha256": file_hash(args.windows_receipt)}})
    return {"status": "held", "caseId": case_id, "caseHash": case_hash, "tupleId": fresh_tuple["id"], "tupleHash": tuple_hash, "windowsHostHash": exe_hash, "recipeHash": recipe_hash, "witnessHash": witness_hash, "output": str(output)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--windows-plan", type=Path, required=True)
    parser.add_argument("--windows-receipt", type=Path, required=True)
    parser.add_argument("--mac-capture", type=Path, required=True)
    parser.add_argument("--tuple-id", required=True)
    parser.add_argument("--acceptance-config-hash", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(materialize(args), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
