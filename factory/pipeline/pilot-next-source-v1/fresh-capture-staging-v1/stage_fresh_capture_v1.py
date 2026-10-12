#!/usr/bin/env python3
"""Stage source-bound native-capture inputs for fresh Text or Circle candidates.

Only measured plan/receipt/case/tuple bytes are admitted. This helper writes
source/config JSON; it never creates a native run, lock, worker, or compiler job.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import stat
from pathlib import Path
from typing import Any

from factory.core.artifacts import canonical_hash, write_artifact

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
MAX_JSON = 2 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
MAX_COMPILER = 512 * 1024 * 1024
SHA = re.compile(r"sha256:[0-9a-f]{64}\Z")
RAW = re.compile(r"[0-9a-f]{64}\Z")
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
TEXT = "swiftui.text.layout.baseline.pilot-next"
CIRCLE = "swiftui.circle.fixed.pilot-next"
TEXT_PLAN = "factory-text-compiler-plan-v1"
CIRCLE_PLAN = "factory-circle-fixed-plan-v1"
RECTANGLE = "swiftui.shapes.fill-stroke.pilot-next"
REQUIRED_UIA = "factory/pipeline/pilot-next-source-v1/count1-lifecycle-v3/uia-worker-invoke-v2.ps1"


def regular(path: Path, limit: int) -> int:
    try:
        st = path.lstat()
    except OSError as exc:
        raise ValueError(f"unreadable path: {path}") from exc
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return st.st_size


def json_file(path: Path) -> dict[str, Any]:
    size = regular(path, MAX_JSON)
    data = bytearray()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            data.extend(chunk)
            if len(data) > MAX_JSON:
                raise ValueError(f"JSON grew beyond bound: {path}")
    if len(data) != size:
        raise ValueError(f"JSON changed while read: {path}")
    try:
        value = json.loads(bytes(data).decode("utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid JSON: {path}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def file_hash(path: Path, limit: int = MAX_SOURCE) -> str:
    size = regular(path, limit)
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"file grew beyond bound: {path}")
            digest.update(chunk)
    if total != size:
        raise ValueError(f"file changed while hashed: {path}")
    return "sha256:" + digest.hexdigest()


def normalize_hash(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise ValueError(f"{field} hash missing")
    value = value.lower()
    if SHA.fullmatch(value):
        return value
    if RAW.fullmatch(value):
        return "sha256:" + value
    raise ValueError(f"{field} hash malformed")


def require_hash(value: Any, expected: str, field: str) -> None:
    if normalize_hash(value, field) != normalize_hash(expected, field):
        raise ValueError(f"{field} mismatch")


def require_text(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} required")
    return value


def bare_hash(value: str) -> str:
    """Return bare digest form required by legacy Windows source-inputs."""
    return value[7:] if value.startswith("sha256:") else value


def ref(path: Path, role: str, limit: int) -> dict[str, Any]:
    return {"role": role, "path": str(path), "bytes": regular(path, limit), "sha256": file_hash(path, limit)}


def validate_tuple(tuple_value: dict[str, Any], *, expected_id: str | None = None) -> None:
    keys = {"id", "sdk", "macosBuild", "toolchains", "runtimeCommit", "rendererHash", "hostHashes", "factoryVersion", "acceptanceConfigHash"}
    if set(tuple_value) != keys:
        raise ValueError("tuple common-schema keys mismatch")
    if expected_id is not None and tuple_value.get("id") != expected_id:
        raise ValueError("tuple ID mismatch")
    if tuple_value.get("runtimeCommit") != RUNTIME or not RAW.fullmatch(str(tuple_value.get("runtimeCommit"))):
        raise ValueError("tuple runtime mismatch")
    normalize_hash(tuple_value.get("rendererHash"), "tuple renderer")
    if normalize_hash(tuple_value["rendererHash"], "tuple renderer") != normalize_hash("sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93", "renderer"):
        raise ValueError("tuple renderer value mismatch")
    hosts = tuple_value.get("hostHashes")
    if not isinstance(hosts, dict) or set(hosts) != {"macos", "windows"}:
        raise ValueError("tuple host hashes incomplete")
    for key in hosts:
        normalize_hash(hosts[key], f"tuple host {key}")
    normalize_hash(tuple_value.get("acceptanceConfigHash"), "tuple acceptance")
    for key in ("id", "sdk", "macosBuild", "factoryVersion"):
        require_text(tuple_value.get(key), f"tuple {key}")
    if not isinstance(tuple_value.get("toolchains"), dict) or not tuple_value["toolchains"]:
        raise ValueError("tuple toolchains missing")


def validate_candidate(profile: str, plan: dict[str, Any], manifest: dict[str, Any], case: dict[str, Any], tuple_value: dict[str, Any], recipe: dict[str, Any], receipt: dict[str, Any], *, plan_hash: str, case_hash: str, tuple_hash: str, recipe_hash: str, receipt_hash: str, exe_hash: str, witness_hash: str) -> None:
    candidate = TEXT if profile == "text-style" else CIRCLE
    plan_kind = str(plan.get("kind", ""))
    if not re.fullmatch(r"factory-[a-z0-9-]+-plan-v[0-9]+", plan_kind) or plan.get("phase") != "final" or plan.get("candidate") != candidate:
        raise ValueError("final plan identity mismatch")
    if manifest.get("kind") != "generated-probe" or manifest.get("candidate") != candidate:
        raise ValueError("generated manifest identity mismatch")
    if manifest.get("executionEligible") not in (True, False):
        raise ValueError("manifest execution eligibility missing")
    if not isinstance(manifest.get("case"), dict) or manifest["case"].get("id") != case.get("id") or normalize_hash(manifest["case"].get("hash"), "manifest case") != case_hash:
        raise ValueError("manifest/case join mismatch")
    if not isinstance(manifest.get("tuple"), dict) or manifest["tuple"].get("id") != tuple_value.get("id") or normalize_hash(manifest["tuple"].get("hash"), "manifest tuple") != tuple_hash:
        raise ValueError("manifest/tuple join mismatch")
    if manifest.get("tupleId") != tuple_value.get("id"):
        raise ValueError("manifest tupleId mismatch")
    if isinstance(plan.get("tuple"), dict):
        if plan["tuple"].get("id") != tuple_value.get("id"):
            raise ValueError("final plan tuple ID mismatch")
        if "hash" in plan["tuple"]:
            require_hash(plan["tuple"].get("hash"), tuple_hash, "final plan tuple")
        elif canonical_hash(plan["tuple"]) != tuple_hash:
            raise ValueError("final plan tuple bytes mismatch")
    if plan.get("manifestHash") is not None:
        normalize_hash(plan.get("manifestHash"), "plan manifest hash")
    if case.get("tuple", {}).get("id") != tuple_value.get("id"):
        raise ValueError("case tuple ID mismatch")
    if canonical_hash(case.get("tuple")) != tuple_hash or case.get("tuple") != tuple_value:
        raise ValueError("case tuple bytes mismatch")
    if case.get("recipe", {}).get("id") != recipe.get("id"):
        raise ValueError("case recipe ID mismatch")
    require_hash(case.get("recipe", {}).get("hash"), recipe_hash, "case recipe")
    if manifest.get("recipe", {}).get("id") != recipe.get("id"):
        raise ValueError("manifest recipe ID mismatch")
    require_hash(manifest.get("recipe", {}).get("hash"), recipe_hash, "manifest recipe")
    recipe_file = manifest.get("recipeFile")
    if not isinstance(recipe_file, str) or not recipe_file.startswith("factory/") or recipe_file.endswith("/"):
        raise ValueError("manifest recipeFile missing or outside factory")
    if canonical_hash(recipe) != recipe_hash:
        raise ValueError("recipe bytes mismatch")
    require_hash(manifest.get("sourceHash"), witness_hash, "manifest witness source")
    require_hash(plan.get("sourceHash"), witness_hash, "plan witness source")
    plan_case = plan.get("case")
    if not isinstance(plan_case, dict) or plan_case.get("id") != case.get("id"):
        raise ValueError("final plan case identity mismatch")
    if "hash" in plan_case:
        require_hash(plan_case.get("hash"), case_hash, "final plan case")
    elif canonical_hash(plan_case) != case_hash:
        raise ValueError("final plan case bytes mismatch")
    require_hash(plan.get("expectedHostHash"), exe_hash, "final expected host")
    if plan.get("runtimeSourceCommit") and plan.get("runtimeSourceCommit") != tuple_value.get("runtimeCommit"):
        raise ValueError("plan/tuple runtime mismatch")
    if receipt.get("kind") != ("factory-text-owned-compile-v1" if profile == "text-style" else "factory-circle-owned-compile-v1") or receipt.get("phase") != "final":
        raise ValueError("compile receipt identity mismatch")
    require_hash(receipt.get("planSha256"), plan_hash, "receipt plan")
    require_hash(receipt.get("sourceHash"), plan.get("sourceHash"), "receipt source")
    if receipt.get("exitCode") != 0 or receipt.get("timedOut") is not False or receipt.get("outputCapExceeded") is not False or receipt.get("ownedExited") is not True:
        raise ValueError("compile receipt unsuccessful")
    if receipt.get("streamDrainComplete") is not True or receipt.get("streamsSealed") is not True or receipt.get("jobActiveReadable") is not True or receipt.get("jobActiveCount") != 0:
        raise ValueError("compile receipt closure incomplete")
    if receipt.get("nativeActions") != 0:
        raise ValueError("compile receipt contains native action")
    require_hash(receipt.get("exeSha256"), exe_hash, "receipt executable")
    require_hash(receipt.get("rendererSha256"), plan.get("rendererSha256"), "receipt renderer")


def validate_inputs(args: argparse.Namespace) -> dict[str, Any]:
    profile = args.profile
    plan = json_file(args.final_plan); manifest = json_file(args.manifest); case = json_file(args.case); tuple_value = json_file(args.tuple); recipe = json_file(args.recipe); receipt = json_file(args.compile_receipt)
    validate_tuple(tuple_value)
    plan_hash = file_hash(args.final_plan, MAX_JSON); manifest_hash = file_hash(args.manifest, MAX_JSON); case_hash = canonical_hash(case); tuple_hash = canonical_hash(tuple_value); recipe_hash = canonical_hash(recipe); receipt_hash = file_hash(args.compile_receipt, MAX_JSON); exe_hash = file_hash(args.executable, MAX_COMPILER); witness_hash = file_hash(args.witness, MAX_SOURCE)
    actual_case_hash = canonical_hash(case)
    if plan.get("manifestHash") is not None and normalize_hash(plan.get("manifestHash"), "plan manifest hash") != manifest_hash:
        raise ValueError("final plan/manifest raw hash mismatch")
    if normalize_hash(manifest.get("case", {}).get("hash"), "manifest case") != actual_case_hash:
        raise ValueError("manifest case canonical hash drift")
    if normalize_hash(manifest.get("tuple", {}).get("hash"), "manifest tuple") != tuple_hash:
        raise ValueError("manifest tuple canonical hash drift")
    if args.uia_overlay is None:
        raise ValueError("uia overlay required for generated Text/Circle staging")
    uia_ref = ref(args.uia_overlay, "required-uia-worker-overlay", MAX_SOURCE)
    serializer_ref = ref(args.serializer_control, "serializer-control", MAX_JSON)
    validate_candidate(profile, plan, manifest, case, tuple_value, recipe, receipt, plan_hash=plan_hash, case_hash=case_hash, tuple_hash=tuple_hash, recipe_hash=recipe_hash, receipt_hash=receipt_hash, exe_hash=exe_hash, witness_hash=witness_hash)
    source_rows = plan.get("sourceBindings") or plan.get("files")
    if not isinstance(source_rows, (list, dict)) or not source_rows:
        raise ValueError("final plan source bindings missing")
    return {"profile": profile, "candidate": TEXT if profile == "text-style" else CIRCLE, "plan": plan, "manifest": manifest, "case": case, "tuple": tuple_value, "planHash": plan_hash, "manifestHash": manifest_hash, "caseHash": case_hash, "tupleHash": tuple_hash, "recipeHash": recipe_hash, "receiptHash": receipt_hash, "exeHash": exe_hash, "witnessHash": witness_hash, "uia": uia_ref, "serializer": serializer_ref, "sourceBindings": copy.deepcopy(source_rows), "refs": {"finalPlan": ref(args.final_plan, "final-plan", MAX_JSON), "manifest": ref(args.manifest, "generated-manifest", MAX_JSON), "case": ref(args.case, "fresh-case", MAX_JSON), "tuple": ref(args.tuple, "fresh-tuple", MAX_JSON), "recipe": ref(args.recipe, "exact-recipe-bytes", MAX_JSON), "witness": ref(args.witness, "witness-source", MAX_SOURCE), "compileReceipt": ref(args.compile_receipt, "final-compile-receipt", MAX_JSON), "executable": ref(args.executable, "compiled-host-executable", MAX_COMPILER)}}


RECTANGLE_SOURCE_KEYS = (
    "bindingHash", "bindingRef", "buildPreflightHash", "buildPreflightPath",
    "capturePlanHash", "capturePlanPath", "caseHash", "caseID",
    "compileReceiptHash", "compileReceiptPath", "compileRef", "compiledHostPackagePath",
    "contextRef", "count", "exeHash", "exeRef", "integrationBindingsHash",
    "integrationBindingsRef", "kind", "planHash", "planRef", "recipeHash",
    "recipeRef", "rendererPath", "rendererRef", "rendererSha256",
    "runtimeSourceCommit", "serializerControlSha256", "serializerRef", "sourceHash",
    "tupleHash", "tupleID", "tupleRef",
)

RECTANGLE_TRANSPORT_FIELDS = {
    "contextRef": "admission/context.json",
    "tupleRef": "admission/candidate-tuple.json",
    "bindingRef": "admission/candidate-binding.json",
    "recipeRef": "admission/recipe.json",
    "planRef": "package/plan.json",
    "compileRef": "package/observation.json",
    "exeRef": "package/FactoryProbe.exe",
    "rendererRef": "inputs/renderer/swiftright_render.dll",
    "integrationBindingsRef": "producer/integration-bindings.json",
    "serializerRef": "producer/serializer-control.json",
}


def rectangle_transport_rows(donor: dict[str, Any]) -> list[dict[str, Any]]:
    """Emit explicit byte/hash transport obligations; never discover files."""
    rows: list[dict[str, Any]] = []
    for field, destination in RECTANGLE_TRANSPORT_FIELDS.items():
        value = donor.get(field)
        if not isinstance(value, dict):
            raise ValueError(f"Rectangle donor {field} reference missing")
        path = require_text(value.get("path"), f"Rectangle donor {field} path")
        digest = normalize_hash(value.get("sha256"), f"Rectangle donor {field} hash")
        size = value.get("bytes")
        if not isinstance(size, int) or size < 0:
            raise ValueError(f"Rectangle donor {field} byte count missing")
        rows.append({"field": field, "role": value.get("role", field), "sourcePath": path,
                     "bytes": size, "sha256": digest, "destination": destination,
                     "copyMode": "exact-bytes-before-hash", "archiveOnly": True})
    preflight = require_text(donor.get("buildPreflightPath"), "Rectangle donor preflight path")
    preflight_hash = normalize_hash(donor.get("buildPreflightHash"), "Rectangle donor preflight hash")
    rows.append({"field": "buildPreflightPath", "role": "build preflight source", "sourcePath": preflight,
                 "bytes": None, "sha256": preflight_hash, "destination": "producer/preflight-capture-v2.ps1",
                 "copyMode": "exact-bytes-before-hash", "archiveOnly": True,
                 "bytesRequired": "measure-before-copy"})
    return rows


def materialize_rectangle_donor(args: argparse.Namespace) -> dict[str, Any]:
    """Rebase admitted Count1 Rectangle source bytes into fresh Count20 paths.

    Donor refs remain byte/hash evidence; only run/count/output namespace changes.
    No historical result is relabeled or copied as native observation.
    """
    donor = json_file(args.donor_source_inputs)
    missing = [key for key in RECTANGLE_SOURCE_KEYS if key not in donor]
    if missing:
        raise ValueError("admitted Rectangle source-input fields missing: " + ",".join(missing))
    if donor.get("kind") != "factory-rectangle-source-inputs-v1" or donor.get("count") != 1:
        raise ValueError("Rectangle donor must be admitted Count1 source-inputs v1")
    donor_plan = json_file(args.donor_capture_plan)
    if donor_plan.get("kind") != "factory-rectangle-native-capture-plan-v1":
        raise ValueError("Rectangle donor capture-plan kind mismatch")
    dispatch = donor_plan.get("dispatch")
    if not isinstance(dispatch, dict) or dispatch.get("first", {}).get("count") != 1 or dispatch.get("repeat", {}).get("count") != 20:
        raise ValueError("Rectangle donor must declare first=1 & repeat=20")
    require_text(donor.get("caseID"), "Rectangle donor case ID")
    require_text(donor.get("tupleID"), "Rectangle donor tuple ID")
    require_hash(donor_plan.get("sourceHash"), donor.get("sourceHash"), "Rectangle donor source")
    if donor_plan.get("case", {}).get("id") != donor.get("caseID") or normalize_hash(donor_plan.get("case", {}).get("hash"), "Rectangle donor case") != normalize_hash(donor.get("caseHash"), "Rectangle donor case"):
        raise ValueError("Rectangle donor case join mismatch")
    if donor_plan.get("tuple", {}).get("id") != donor.get("tupleID"):
        raise ValueError("Rectangle donor tuple join mismatch")
    donor_config = json_file(args.donor_config_template)
    for name in ("integration_guard_hash", "issued_metadata_hash", "serializer_control_sha256"):
        value = getattr(args, name)
        if value is not None and not RAW.fullmatch(value.lower()):
            raise ValueError(f"{name} must be bare 64-hex")
    if donor_config.get("count") != 1 or not isinstance(donor_config.get("sourceBindings"), list) or len(donor_config["sourceBindings"]) < 5:
        raise ValueError("Rectangle donor config lacks full source bindings")
    successor_overlay = None
    if args.successor_overlay_map is not None:
        successor_overlay = json_file(args.successor_overlay_map)
        if not isinstance(successor_overlay.get("overlaySources"), list) or not successor_overlay["overlaySources"]:
            raise ValueError("Count20 overlay source map lacks explicit rows")
    out = args.output.expanduser().resolve()
    if out.exists():
        raise ValueError("fresh output namespace required")
    out.mkdir(parents=True)
    transport_rows = rectangle_transport_rows(donor)
    first_root = require_text(args.first_run_root, "first run root")
    repeat_root = require_text(args.repeat_run_root, "repeat run root")
    if first_root == repeat_root:
        raise ValueError("first/repeat run roots must differ")
    capture_plan = copy.deepcopy(donor_plan)
    capture_plan["dispatch"]["first"]["runRoot"] = first_root
    capture_plan["dispatch"]["repeat"]["runRoot"] = repeat_root
    capture_plan["dispatch"]["repeat"]["firstProofRequired"] = True
    capture_plan["sourceAdmission"] = "fresh-count20-successor-from-admitted-count1-donor"
    capture_plan["nativeActions"] = 0
    capture_path = out / "capture-plan.json"
    write_artifact(capture_path, capture_plan)
    capture_hash = file_hash(capture_path, MAX_JSON)
    source = copy.deepcopy(donor)
    source["count"] = 20
    source["capturePlanPath"] = str(capture_path)
    source["capturePlanHash"] = bare_hash(capture_hash)
    source["firstRunRoot"] = first_root
    source["repeatRunRoot"] = repeat_root
    source["sourceBindings"] = copy.deepcopy(donor_config["sourceBindings"])
    source["integrationBindingsHash"] = donor.get("integrationBindingsHash")
    source["integrationBindingsRef"] = copy.deepcopy(donor.get("integrationBindingsRef"))
    source["bindingHash"] = donor.get("bindingHash")
    source["bindingRef"] = copy.deepcopy(donor.get("bindingRef"))
    uia_path = REPO / REQUIRED_UIA
    if uia_path.exists():
        source["requiredUiaOverlay"] = ref(uia_path, "required-uia-worker-overlay", MAX_SOURCE)
    source["successorOf"] = {"count": 1, "sourceInputsHash": file_hash(args.donor_source_inputs, MAX_JSON), "capturePlanHash": donor.get("capturePlanHash")}
    source["nativeActions"] = 0
    source["transportRows"] = copy.deepcopy(transport_rows)
    source_path = out / "source-inputs.json"
    write_artifact(source_path, source)
    source_hash = file_hash(source_path, MAX_JSON)
    config = copy.deepcopy(donor_config)
    config.update({"count": 20, "replays": 20, "firstRunRoot": first_root, "repeatRunRoot": repeat_root, "runRoot": repeat_root, "outputRoot": require_text(args.output_root or str(out / "native"), "output root"), "sourceInputsPath": str(source_path), "sourceInputsHash": bare_hash(source_hash), "capturePlanPath": str(capture_path), "capturePlanHash": bare_hash(capture_hash), "nativeActions": 0, "successorOf": "admitted-count1", "sourceInputsKind": source["kind"], "requiredUiaOverlay": source.get("requiredUiaOverlay")})
    config["transportRows"] = copy.deepcopy(transport_rows)
    if successor_overlay is not None:
        config["successorOverlaySources"] = copy.deepcopy(successor_overlay["overlaySources"])
        source["successorOverlaySources"] = copy.deepcopy(successor_overlay["overlaySources"])
        write_artifact(source_path, source)
        source_hash = file_hash(source_path, MAX_JSON)
        config["sourceInputsHash"] = bare_hash(source_hash)
    if args.control_root:
        config["controlRoot"] = args.control_root
    if args.admission_root:
        config["admissionRoot"] = args.admission_root
    if args.overlay_root:
        config["overlayRoot"] = args.overlay_root
    if args.producer_root:
        config["producerRoot"] = args.producer_root
    if args.integration_guard_path:
        config["integrationGuardPath"] = args.integration_guard_path
    if args.integration_guard_hash:
        config["integrationGuardHash"] = args.integration_guard_hash
    if args.issued_metadata_path:
        config["issuedMetadataPath"] = args.issued_metadata_path
    if args.issued_metadata_hash:
        config["issuedMetadataHash"] = args.issued_metadata_hash
    if args.serializer_control_sha256:
        config["serializerControlSha256"] = args.serializer_control_sha256
    config_path = out / "config-template.json"
    write_artifact(config_path, config)
    source_map = {"kind": "factory-rectangle-count20-source-map-v1", "donor": {"sourceInputs": source["successorOf"], "historicalRebind": False}, "capturePlan": ref(capture_path, "fresh-count20-capture-plan", MAX_JSON), "sourceInputs": ref(source_path, "fresh-count20-source-inputs", MAX_JSON), "configTemplate": ref(config_path, "fresh-count20-config-template", MAX_JSON), "donorSourceInputs": ref(args.donor_source_inputs, "admitted-count1-source-inputs", MAX_JSON), "donorCapturePlan": ref(args.donor_capture_plan, "admitted-count1-capture-plan", MAX_JSON), "successorOverlayMap": ref(args.successor_overlay_map, "count20-overlay-source-map", MAX_JSON) if args.successor_overlay_map else None, "transportRows": copy.deepcopy(transport_rows), "nativeActions": 0}
    write_artifact(out / "source-map.json", source_map)
    return {"status": "source-admission-held", "profile": "rectangle", "candidate": RECTANGLE, "count": 20, "caseId": source["caseID"], "tupleId": source["tupleID"], "capturePlanHash": capture_hash, "sourceInputsHash": source_hash, "output": str(out), "nativeActions": 0}


def materialize(args: argparse.Namespace) -> dict[str, Any]:
    if args.profile == "rectangle":
        required = (args.donor_source_inputs, args.donor_capture_plan, args.donor_config_template)
        if any(value is None for value in required):
            raise ValueError("Rectangle profile requires admitted donor source-inputs, capture-plan, & config-template")
        return materialize_rectangle_donor(args)
    if args.first_count != 1 or args.repeat_count != 20:
        raise ValueError("capture counts must be first=1 & repeat=20")
    data = validate_inputs(args)
    out = args.output.expanduser().resolve()
    if out.exists():
        raise ValueError("fresh output namespace required")
    out.mkdir(parents=True)
    profile = data["profile"]
    plan = data["plan"]
    candidate = data["candidate"]
    producer_root = require_text(args.producer_root, "producer root")
    overlay_root = require_text(args.overlay_root, "overlay root")
    first_root = require_text(args.first_run_root, "first run root")
    repeat_root = require_text(args.repeat_run_root, "repeat run root")
    if first_root == repeat_root:
        raise ValueError("first/repeat run roots must differ")
    capture_kind = "factory-text-capture-plan-v1" if profile == "text-style" else "factory-circle-capture-plan-v1"
    source_kind = "factory-text-source-inputs-v1" if profile == "text-style" else "factory-circle-source-inputs-v1"
    capture_plan = {
        "kind": capture_kind, "version": 1, "candidate": candidate, "phase": "source-admission",
        "case": {"id": data["case"]["id"], "hash": data["caseHash"]}, "tuple": {"id": data["tuple"]["id"], "hash": data["tupleHash"]},
        "sourceHash": data["witnessHash"], "sourcePlanSha256": data["planHash"], "manifestSha256": data["manifestHash"], "recipeSha256": data["recipeHash"],
        "compileReceiptSha256": data["receiptHash"], "exeSha256": data["exeHash"], "rendererSha256": normalize_hash(plan.get("rendererSha256"), "plan renderer"), "runtimeSourceCommit": plan.get("runtimeSourceCommit"),
        "recipeFile": data["manifest"]["recipeFile"], "recipe": data["manifest"]["recipe"], "count1ThenCount20": True,
        "dispatch": {"first": {"count": args.first_count, "runRoot": first_root}, "repeat": {"count": args.repeat_count, "runRoot": repeat_root, "firstProofRequired": True}},
        "producerRoot": producer_root, "overlayRoot": overlay_root, "requiredUiaOverlay": data["uia"], "serializerControl": data["serializer"],
        "nativeActions": 0, "qualification": "source-admission-held-until-fresh-capture", "sourceBindings": data["sourceBindings"],
    }
    capture_path = out / "capture-plan.json"
    source_path = out / "source-inputs.json"
    config_path = out / "config-template.json"
    write_artifact(capture_path, capture_plan)
    capture_raw_hash = file_hash(capture_path, MAX_JSON)
    source_inputs = {"kind": source_kind, "candidate": candidate, "count": args.first_count, "tupleID": data["tuple"]["id"], "tupleHash": bare_hash(data["tupleHash"]), "caseID": data["case"]["id"], "caseHash": data["caseHash"], "sourceHash": data["witnessHash"], "planHash": bare_hash(data["planHash"]), "manifestHash": bare_hash(data["manifestHash"]), "recipeHash": bare_hash(data["recipeHash"]), "compileReceiptHash": bare_hash(data["receiptHash"]), "exeHash": bare_hash(data["exeHash"]), "rendererSha256": bare_hash(capture_plan["rendererSha256"]), "runtimeSourceCommit": data["tuple"]["runtimeCommit"], "recipeFile": data["manifest"]["recipeFile"], "capturePlanHash": bare_hash(capture_raw_hash), "capturePlanPath": str(capture_path), "planRef": data["refs"]["finalPlan"], "manifestRef": data["refs"]["manifest"], "caseRef": data["refs"]["case"], "tupleRef": data["refs"]["tuple"], "recipeRef": data["refs"]["recipe"], "witnessRef": data["refs"]["witness"], "compileRef": data["refs"]["compileReceipt"], "compileReceiptPath": data["refs"]["compileReceipt"]["path"], "exeRef": data["refs"]["executable"], "uiaOverlayRef": data["uia"], "serializerRef": data["serializer"], "serializerControlSha256": bare_hash(data["serializer"]["sha256"]), "sourceBindings": data["sourceBindings"], "nativeActions": 0}
    source_inputs.update({key: plan[key] for key in ("bindingHash", "bindingRef", "buildPreflightHash", "buildPreflightPath", "contextRef", "integrationBindingsHash", "integrationBindingsRef", "compiledHostPackagePath", "rendererPath", "rendererRef") if key in plan})
    write_artifact(source_path, source_inputs)
    source_raw_hash = file_hash(source_path, MAX_JSON)
    config = {"kind": f"factory-{profile}-capture-config-v1", "candidate": candidate, "count": args.first_count, "replays": args.repeat_count, "admissionRoot": producer_root, "controlRoot": overlay_root, "producerRoot": producer_root, "overlayRoot": overlay_root, "firstRunRoot": first_root, "repeatRunRoot": repeat_root, "outputRoot": producer_root, "runRoot": first_root, "package": plan.get("packagePath"), "capturePlanPath": str(capture_path), "capturePlanHash": bare_hash(capture_raw_hash), "sourceInputsPath": str(source_path), "sourceInputsHash": bare_hash(source_raw_hash), "issuedMetadataRequired": True, "freshCaptureIDsRequired": True, "nativeActions": 0}
    source_map = {"kind": "factory-fresh-capture-source-map-v1", "candidate": candidate, "rows": data["refs"] | {"uiaOverlay": data["uia"], "serializerControl": data["serializer"]}, "sourceBindings": data["sourceBindings"], "lineage": {"freshTuple": data["tuple"]["id"], "historicalCaseRebind": False, "historicalTupleRebind": False}, "nativeActions": 0}
    write_artifact(config_path, config); write_artifact(out / "source-map.json", source_map)
    return {"status": "source-admission-held", "profile": profile, "candidate": candidate, "caseId": data["case"]["id"], "tupleId": data["tuple"]["id"], "capturePlanHash": canonical_hash(capture_plan), "sourceInputsHash": canonical_hash(source_inputs), "output": str(out), "nativeActions": 0}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", choices=("text-style", "circle", "rectangle"), required=True)
    for name in ("final-plan", "manifest", "case", "tuple", "recipe", "compile-receipt", "executable", "witness", "serializer-control"):
        ap.add_argument("--" + name, dest=name.replace("-", "_"), type=Path)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--uia-overlay", dest="uia_overlay", type=Path)
    ap.add_argument("--producer-root", required=True); ap.add_argument("--overlay-root", required=True); ap.add_argument("--first-run-root", required=True); ap.add_argument("--repeat-run-root", required=True)
    ap.add_argument("--control-root"); ap.add_argument("--admission-root"); ap.add_argument("--output-root")
    ap.add_argument("--integration-guard-path"); ap.add_argument("--integration-guard-hash")
    ap.add_argument("--issued-metadata-path"); ap.add_argument("--issued-metadata-hash")
    ap.add_argument("--serializer-control-sha256")
    ap.add_argument("--donor-source-inputs", type=Path); ap.add_argument("--donor-capture-plan", type=Path); ap.add_argument("--donor-config-template", type=Path)
    ap.add_argument("--successor-overlay-map", type=Path)
    ap.add_argument("--first-count", type=int, default=1); ap.add_argument("--repeat-count", type=int, default=20)
    args = ap.parse_args()
    if args.profile != "rectangle":
        missing = [name for name in ("final_plan", "manifest", "case", "tuple", "recipe", "compile_receipt", "executable", "witness", "serializer_control", "uia_overlay") if getattr(args, name, None) is None]
        if missing:
            raise SystemExit("Text/Circle profile requires: " + ", ".join(missing))
    print(json.dumps(materialize(args), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
