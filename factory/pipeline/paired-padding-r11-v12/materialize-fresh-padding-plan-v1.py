#!/usr/bin/env python3
"""Materialize append-only Windows padding replay plan bound to fresh case identity."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from factory.core.artifacts import canonical_hash

MAX_JSON = 8 * 1024 * 1024
SOURCE_PLAN_KIND = "windows-padding-capture-lease-source-plan"


class Hold(ValueError):
    pass


def bounded_json(path: Path, label: str) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON:
        raise Hold(f"{label} unavailable or exceeds bounded read")

    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Hold(f"{label} duplicate JSON key")
            result[key] = value
        return result

    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"), object_pairs_hook=pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} object required")
    return value


def case_ref(case: dict) -> dict:
    if case.get("kind") != "case" or case.get("version") != "0.1":
        raise Hold("fresh v0.1 case required")
    hash_input = dict(case)
    hash_input.pop("hash", None)
    value = {"id": case.get("id"), "hash": canonical_hash(hash_input)}
    supplied = case.get("hash")
    if supplied is not None and supplied not in {value["hash"], value["hash"].removeprefix("sha256:")}:
        raise Hold("fresh case supplied hash differs from canonical case hash")
    if not isinstance(value["id"], str) or not value["id"]:
        raise Hold("fresh case identity malformed")
    return value


def require_ref(value: object, label: str) -> dict:
    if not isinstance(value, dict) or not isinstance(value.get("path"), str) or not isinstance(value.get("sha256"), str):
        raise Hold(f"{label} reference missing")
    return value


def materialize(case: dict, source_plan: dict, candidate: dict, issued: dict,
                package_path: str | None, scratch_path: str | None,
                compiler_path: str | None, renderer_path: str | None,
                producer_root: str, run_root: str, output_root: str) -> dict:
    fresh = case_ref(case)
    if source_plan.get("kind") != SOURCE_PLAN_KIND or source_plan.get("executionEligible") is not False:
        raise Hold("immutable source plan kind/hold changed")
    if candidate.get("case") != fresh or issued.get("case") != fresh:
        raise Hold("issued/candidate case does not equal fresh case")
    if issued.get("expectedCount") != 20 or issued.get("measurementStatus") not in (None, "pending-actual-launch-joins"):
        raise Hold("issued Count20 metadata invalid")
    source_hash = source_plan.get("sourceHash")
    if not isinstance(source_hash, str) or issued.get("sourceHash") != source_hash:
        raise Hold("source hash join missing")
    tuple_value = candidate.get("tuple")
    if not isinstance(tuple_value, dict) or candidate.get("candidateID") != tuple_value.get("id"):
        raise Hold("candidate tuple identity missing")
    exe = require_ref(issued.get("exe"), "measured executable")
    renderer = require_ref(issued.get("renderer"), "measured renderer")
    if tuple_value.get("hostHashes", {}).get("windows") != exe.get("sha256"):
        raise Hold("candidate Windows host hash differs from measured executable")
    if tuple_value.get("rendererHash") != renderer.get("sha256"):
        raise Hold("candidate renderer hash differs from measured renderer")
    if source_plan.get("rendererSha256") not in {renderer.get("sha256"), str(renderer.get("sha256", "")).removeprefix("sha256:")}:
        raise Hold("source plan renderer hash differs from measured renderer")
    if source_plan.get("runtimeSourceCommit") != tuple_value.get("runtimeCommit"):
        raise Hold("runtime commit differs from candidate tuple")
    source_bindings = source_plan.get("sourceBindings")
    if not isinstance(source_bindings, list) or not source_bindings:
        raise Hold("source bindings missing")
    if not any(item.get("path") == "Sources/FactoryProbe/Witness.swift" and item.get("sha256") in {source_hash, source_hash.removeprefix("sha256:")} for item in source_bindings if isinstance(item, dict)):
        raise Hold("exact padding Witness.swift binding missing")
    compiler_hash = source_plan.get("compilerHash")
    if not isinstance(compiler_hash, str) or len(compiler_hash) != 64:
        raise Hold("compiler hash missing")
    compile_request = source_plan.get("compileRequest")
    if not isinstance(compile_request, dict):
        raise Hold("source compile request missing")
    package = package_path or compile_request.get("packagePath")
    scratch = scratch_path or compile_request.get("scratchPath")
    compiler = compiler_path or source_plan.get("compilerPath")
    renderer_target = renderer_path or source_plan.get("rendererPath")
    if not all(isinstance(item, str) and item for item in (package, scratch, compiler, renderer_target)):
        raise Hold("fresh package/scratch/compiler/renderer paths required")
    # Fresh capture must compile from same measured inputs.  Separate replay roots
    # are allowed; package, scratch, compiler, & renderer paths are source-plan
    # bindings & cannot silently move to an unmeasured tree.
    for label, supplied, measured in (
        ("package", package, compile_request.get("packagePath")),
        ("scratch", scratch, compile_request.get("scratchPath")),
        ("compiler", compiler, source_plan.get("compilerPath")),
        ("renderer", renderer_target, source_plan.get("rendererPath")),
    ):
        if not isinstance(measured, str) or supplied != measured:
            raise Hold(f"fresh {label} path must retain immutable measured binding")
    scripts_root = "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v17"
    source_map = {
        "coordinator": {"path": scripts_root + "/resume-issued-coordinator-fresh-r11-v17.ps1", "sha256": "sha256:2732867535c50f418dfcd13c5ec632622efb0ca38a44289b6233bed5f4d8b7fa", "bytes": 21854},
        "interactive": {"path": scripts_root + "/interactive-task-fresh-r11-v17.ps1", "sha256": "sha256:a309be3f3f080c316cdde5e7c9a2fcfb46f2581061c4d404695bffb57f55b2dc", "bytes": 4713},
        "dispatch": {"path": scripts_root + "/dispatch-fresh-r11-v17.ps1", "sha256": "sha256:320880918b17295f7cf798c4e38b15e61b24175b8021eab19678682942ed531f", "bytes": 5746},
        "capture": {"path": scripts_root + "/capture-fresh-r11-v17.ps1", "sha256": "sha256:8d0475d3e5e91f6a162867a3cb72900eaab50203b1f254c1fb8a7be4c8fa61a6", "bytes": 40754},
        "firstProof": {"path": scripts_root + "/first-proof-fresh-r11-v17.ps1", "sha256": "sha256:910ae4369d62bdbe50510b9f35db9f09a1536563aebce216459ff6d71735c902", "bytes": 12988},
        "workerOutputPreflight": {"path": scripts_root + "/worker-output-preflight-v17.ps1", "sha256": "sha256:04972768a8efd0371651cc873e46aae0b15f81a5401828f36694ec036a94d9f0", "bytes": 1543},
        "workerOutputControls": {"path": scripts_root + "/test-worker-output-preflight-v17.ps1", "sha256": "sha256:6df91bcfd73ba73256ff9ebba1a51914dd25367d1795ca6429ea3f599dc788bd", "bytes": 2016},
        "README": {"path": scripts_root + "/README.md", "sha256": "sha256:5782ea768740eb2fe7d3d4e13a9a4b1aad87a23058304d5ff699e90b9704382f", "bytes": 1744},
        "integrationGuard": {"path": "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v13/integration-fresh-r11-v7.ps1", "sha256": "sha256:4e7bac792ab47d7acc35795262edb7c75cae36d7749a0bedc85814d814d76e98", "bytes": 33166},
        "memoryHelper": {"path": "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v15/Sr0OwnedJobProcess-v15.cs", "sha256": "sha256:89ce3d84f565180c89ad43a753f7c9e44319dca206f3c5d6d5ba80ac5e05197a", "bytes": 6495},
        "memoryControls": {"path": "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v15/test-memory-bound-controls-v15.ps1", "sha256": "sha256:aadae11b0b093ff62622bbae4394b46ef3fbb21b4fcd38c9e105d74269a0d83b", "bytes": 3586},
        "v16SourceMap": {"path": "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v16/source-map-v16.json", "sha256": "sha256:d7c028af6014d26de8927cf7e73c9315abead306ea67ec441a2e12eac6a106e4", "bytes": 3501},
    }
    plan = copy.deepcopy(source_plan)
    plan.update({
        "status": "pending-native-compile-replay",
        "executionEligible": False,
        "frozenTupleBound": False,
        "case": fresh,
    })
    plan["compileRequest"] = copy.deepcopy(compile_request)
    plan["compileRequest"]["packagePath"] = package
    plan["compileRequest"]["scratchPath"] = scratch
    plan["compilerPath"] = compiler
    plan["rendererPath"] = renderer_target
    plan["freshCaseReference"] = fresh
    plan["candidateTuple"] = tuple_value
    plan["issuedMetadataIdentity"] = {
        "case": issued["case"], "expectedCount": issued["expectedCount"],
        "sourceHash": issued["sourceHash"], "exe": exe, "renderer": renderer,
    }
    plan["freshReplay"] = {
        "producerRoot": producer_root,
        "runRoot": run_root,
        "outputRoot": output_root,
        "replays": 1,
        "count": 20,
        "coordinatorConcurrency": 1,
        "totalDeadlineSeconds": 10800,
        "coordinatorDeadlineSeconds": 1200,
        "hostArguments": source_plan.get("hostArguments", []),
        "effects": {"compilerActions": 0, "nativeWindowActions": 0, "remoteActions": 0, "lockActions": 0},
        "compilerArgvTemplate": "build --package-path \"{packagePath}\" --scratch-path \"{scratchPath}\" -c release -Xlinker /MANIFEST:EMBED -Xlinker \"/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup",
        "compilerArgvSource": "replays/r1/observation.json argv; no unverified concurrency environment claim",
    }
    plan["entryScripts"] = {
        "issue": "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v14/issue-count20-fresh-r11-v6.ps1",
        "issueSha256": "sha256:1765bb2fec928fe4ce8ace61417fd7baf72b06aba57544c508b95f4443392c02",
        "issueBytes": 9758,
        **source_map,
    }
    plan["sourceMap"] = "factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v17/source-map-v17.json"
    plan["requiredJoins"] = [
            "plan.case == issuedMetadata.case == candidateTuple.case == everyCapture.case == Mac case reference",
            "issuedMetadata.sourceHash == sourceHash == sourceBindings.Witness.swift sha256",
            "plan.sourceHash == sourceHash; compileReceipt.exeSha256 == issuedMetadata.exe.sha256",
            "candidateTuple.tuple.hostHashes.windows == measuredExecutable.sha256",
            "candidateTuple.tuple.rendererHash == measuredRenderer.sha256",
            "every run has unique captureID/imageID, numeric exit certificate, raw stdout/stderr closure, active=0 & streams drained",
            "renderer/source/runtime/compiler bytes remain pinned before any native replay",
    ]
    plan["lineage"] = {"basePlanKind": source_plan.get("kind"), "basePlanHash": source_plan.get("basePlanHash"), "basePlanCanonicalHash": canonical_hash(source_plan), "historicalPlanCase": source_plan.get("case"), "historicalRawUntouched": True}
    plan["guards"] = {"relabelHistoricalRecords": False, "parity": "hold", "goldenFreeze": "hold"}
    return plan


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in ("case", "source-plan", "candidate-tuple", "issued-metadata", "output"):
        parser.add_argument("--" + name, required=True, type=Path)
    parser.add_argument("--package-path")
    parser.add_argument("--scratch-path")
    parser.add_argument("--compiler-path")
    parser.add_argument("--renderer-path")
    parser.add_argument("--producer-root", required=True)
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--output-root", required=True)
    args = parser.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: fresh plan output must be new")
    try:
        result = materialize(
            bounded_json(args.case, "fresh case"), bounded_json(args.source_plan, "source plan"),
            bounded_json(args.candidate_tuple, "candidate tuple"), bounded_json(args.issued_metadata, "issued metadata"),
            args.package_path, args.scratch_path, args.compiler_path, args.renderer_path,
            args.producer_root, args.run_root, args.output_root,
        )
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "case": result["case"], "count": 20, "sourcePlanKind": result["kind"], "nativeActions": 0, "compilerActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
