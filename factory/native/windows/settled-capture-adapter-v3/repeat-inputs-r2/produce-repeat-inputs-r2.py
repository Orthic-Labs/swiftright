#!/usr/bin/env python3
"""Produce frozen-v3 adapter inputs from one explicit archived Count20 repeat output map.

This producer never discovers, fabricates, or substitutes files.  Every path is
supplied by caller, resolved below --archive-root, then sealed with SHA256/bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any

ROLE_NAMES = (
    "issuedMetadata", "producerProfile", "capturePlan", "plan", "compile",
    "candidateBinding", "tuple", "case", "manifest", "coordinator", "exe",
    "renderer",
)
RUN_NAMES = (
    "outcome", "owned", "observation", "pixels", "close", "workerExit",
    "measurement", "snapshotOrder", "workerFinal", "workerTerminal", "workerExe",
    "workerContract", "workerConfig", "workerScript", "workerStdout", "workerStderr",
    "rendererFinal", "rendererTerminal", "uia", "stdout", "stderr", "printWindow",
    "printWindowRepeat",
)
EXECUTION_OVERLAY_REPEAT_R4_HASHES = {
    "resume-issued-coordinator-repeat-r4.ps1": "sha256:b2889bac231d337f15c88ad7bb800ba44a2b0330de8be66163fbd2f4b648153b",
    "interactive-task-repeat-r4.ps1": "sha256:02d33efee1cb14f59e6182c63dc5490e06cd380b3f0dd25165b2f76e2ebd79f0",
    "dispatch-repeat-r4.ps1": "sha256:c96c0c8acdf6fd2bc042fd704544c318cecd2dc622eb938474f5eac971fbb695",
    "capture-repeat-r4.ps1": "sha256:52da5743464fc22b2ce5a81bb5099d138ab40a13602798d46f3f2a52bb5a81c5",
    "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
}
EXECUTION_OVERLAY_REPEAT_R2_HASHES = {
    "resume-issued-coordinator-repeat-r2.ps1": "sha256:d4359512dd4f6efe2f13dad301b12d14b5099130185fbfcf9b4572f0ecbef043",
    "interactive-task-repeat-r2.ps1": "sha256:e9d2d2055f8c5e89439046e843cd11e5820aab742da88eda1c6f90ec7305a929",
    "dispatch-repeat-r2.ps1": "sha256:3b61a3d60ef5509ce6852a38e8441cdec44b7e05b989b02c018634f43ee507d1",
    "capture-repeat-r2.ps1": "sha256:45f795f3a41551a2931c50fbfd9763405f0ea6bac249edc93f8f42a12499a5d7",
    "integration-prefixed-ids-r1.ps1": "sha256:d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904",
}
ISSUER_SOURCE_NAME = "issue-before-launch-prefixed-r1.ps1"
ISSUER_SOURCE_HASH = "sha256:ee30fdd3f83459a62a2024fe95b22bf228b1471cf7498642181e49c2d473d66e"
ISSUER_SOURCE_SUFFIX = "/root-metadata-controls-v1/issuer-overlay-r1/" + ISSUER_SOURCE_NAME
ISSUER_PRODUCER = "padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/" + ISSUER_SOURCE_NAME


def fail(message: str) -> "NoReturn":
    raise SystemExit(f"HOLD: {message}")


def obj(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(f"{label} must be object")
    return value


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        fail(f"{label} must be non-empty string")
    return value


def safe_rel(value: Any, label: str) -> str:
    value = text(value, label)
    if "\\" in value or ":" in value or value.startswith("/"):
        fail(f"{label} must be safe POSIX archive-relative path")
    parsed = PurePosixPath(value)
    if str(parsed) != value or parsed.is_absolute() or ".." in parsed.parts or not parsed.parts:
        fail(f"{label} escapes archive root")
    return value


def load_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"{label} unreadable JSON: {exc}")


def sha(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def qualified_hash(value: Any, label: str) -> str:
    value = text(value, label)
    return value if value.startswith("sha256:") else "sha256:" + value


class Archive:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        if not self.root.is_dir():
            fail("archive root is not directory")
        self.refs: dict[str, dict[str, Any]] = {}
        self.raws: dict[str, bytes] = {}

    def ref(self, value: Any, label: str) -> dict[str, Any]:
        rel = safe_rel(value, label)
        if rel in self.refs:
            return dict(self.refs[rel])
        path = self.root / Path(*PurePosixPath(rel).parts)
        try:
            resolved = path.resolve()
            resolved.relative_to(self.root)
            raw = resolved.read_bytes()
        except (OSError, ValueError) as exc:
            fail(f"{label} missing or outside archive: {rel}: {exc}")
        reference = {"path": rel, "sha256": sha(raw), "bytes": len(raw)}
        self.refs[rel] = reference
        self.raws[rel] = raw
        return dict(reference)

    def document(self, value: Any, label: str) -> tuple[dict[str, Any], dict[str, Any]]:
        reference = self.ref(value, label)
        try:
            document = json.loads(self.raws[reference["path"]].decode("utf-8-sig"))
        except (UnicodeError, json.JSONDecodeError) as exc:
            fail(f"{label} must be JSON: {exc}")
        return obj(document, label), reference


def require_keys(mapping: dict[str, Any], names: tuple[str, ...], label: str) -> None:
    missing = [name for name in names if name not in mapping]
    if missing:
        fail(f"{label} missing explicit entries: {', '.join(missing)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive-root", required=True, type=Path)
    parser.add_argument("--input-map", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if args.output.exists():
        fail(f"refusing to overwrite output: {args.output}")
    input_map = obj(load_json(args.input_map, "input map"), "input map")
    archive = Archive(args.archive_root)

    role_paths = obj(input_map.get("roles"), "roles")
    require_keys(role_paths, ROLE_NAMES, "roles")
    roles: dict[str, dict[str, Any]] = {}
    documents: dict[str, dict[str, Any]] = {}
    for role in ROLE_NAMES:
        value = role_paths[role]
        if role in {"exe", "renderer"}:
            roles[role] = archive.ref(value, f"role:{role}")
        else:
            document, reference = archive.document(value, f"role:{role}")
            roles[role] = reference
            documents[role] = document

    issued = documents["issuedMetadata"]
    if issued.get("kind") != "factory-prelaunch-capture-metadata-v2" or issued.get("version") != 2:
        fail("issued metadata is not v2")
    if issued.get("expectedCount") != 20:
        fail("Count20 repeat producer input requires expectedCount=20")
    if issued.get("frozenTupleBound") is not False or issued.get("historicalTemplateTupleClosed") is not False:
        fail("issued metadata is frozen or historical-template bound")
    captures = issued.get("captures")
    if not isinstance(captures, list) or len(captures) != 20 or [row.get("run") for row in captures] != list(range(1, 21)):
        fail("issued metadata lacks exactly one preissued capture")
    if any((row.get("provenance") or {}).get("producer") != ISSUER_PRODUCER for row in captures):
        fail("issued capture provenance does not name prefixed issuer")

    profile = documents["producerProfile"]
    profile_files = profile.get("files")
    if not isinstance(profile_files, list) or not profile_files:
        fail("producer profile has no source files")
    producer_paths = obj(input_map.get("producerSource"), "producerSource")
    producer_source: dict[str, dict[str, Any]] = {}
    for entry in profile_files:
        entry = obj(entry, "producer profile file")
        path = safe_rel(entry.get("path"), "producer profile path")
        if path not in producer_paths:
            fail(f"producerSource omits frozen profile path: {path}")
        reference = archive.ref(producer_paths[path], f"producerSource:{path}")
        expected_hash = entry.get("hash", entry.get("sha256"))
        if reference["sha256"] != expected_hash or reference["bytes"] != entry.get("bytes"):
            fail(f"producer profile byte/hash mismatch: {path}")
        producer_source[path] = reference

    capture_plan = documents["capturePlan"]
    plan_ref = roles["plan"]
    if capture_plan.get("sourcePlanSha256") != plan_ref["sha256"] or capture_plan.get("compiledPlanSha256") != plan_ref["sha256"]:
        fail("capture plan/source plan byte join failed")
    plan = documents["plan"]
    source_paths = obj(input_map.get("source"), "source")
    source_bindings = plan.get("sourceBindings")
    if not isinstance(source_bindings, list) or not source_bindings:
        fail("plan has no sourceBindings")
    source: dict[str, dict[str, Any]] = {}
    for binding in source_bindings:
        binding = obj(binding, "source binding")
        path = safe_rel(binding.get("path"), "source binding path")
        if path not in source_paths:
            fail(f"source map omits plan binding: {path}")
        reference = archive.ref(source_paths[path], f"source:{path}")
        if reference["sha256"] != qualified_hash(binding.get("sha256"), f"source hash:{path}"):
            fail(f"source binding hash mismatch: {path}")
        source[path] = reference

    compile_record = documents["compile"]
    module_paths = obj(input_map.get("runtimeModules"), "runtimeModules")
    runtime_modules: dict[str, dict[str, Any]] = {}
    modules = compile_record.get("runtimeModules")
    if not isinstance(modules, list) or not modules:
        fail("compile record has no runtimeModules")
    for module in modules:
        module = obj(module, "runtime module")
        # Recorded archivePath is Windows producer metadata and may contain a
        # drive prefix/backslashes.  Keep it as exact logical key; caller's
        # mapped archive path still passes strict safe_rel/archive byte gates.
        archive_path = module.get("archivePath")
        if not isinstance(archive_path, str) or not archive_path:
            fail("runtime module archivePath must be non-empty recorded path")
        if archive_path not in module_paths:
            fail(f"runtimeModules omits compile module: {archive_path}")
        reference = archive.ref(module_paths[archive_path], f"runtimeModule:{archive_path}")
        if reference["sha256"] != qualified_hash(module.get("sha256"), f"runtime module hash:{archive_path}") or reference["bytes"] != module.get("bytes"):
            fail(f"runtime module byte/hash mismatch: {archive_path}")
        runtime_modules[archive_path] = reference

    metadata_paths = obj(input_map.get("metadataRecordPaths"), "metadataRecordPaths")
    require_keys(metadata_paths, ("plan", "compile", "exe", "renderer", "manifest", "candidateBinding"), "metadataRecordPaths")
    metadata_fields = {
        "plan": "plan", "compile": "compile", "exe": "exe", "renderer": "renderer",
        "manifest": "recipe", "candidateBinding": "sourceBoundCandidateTuple",
    }
    for output_name, issued_name in metadata_fields.items():
        field = obj(issued.get(issued_name), f"issued.{issued_name}")
        if metadata_paths[output_name] != field.get("path"):
            fail(f"metadataRecordPaths mismatch: {output_name}")
        if field.get("sha256") != roles[output_name if output_name != "manifest" else "manifest"]["sha256"]:
            fail(f"issued metadata hash mismatch: {output_name}")

    # Frozen v3 stores some recorded Windows/absolute source-input paths inside
    # tuple document. Preserve tuple bytes unchanged, while v4 consumes this
    # explicit safe archive-ref sidecar.
    tuple_source_paths = obj(input_map.get("tupleSource"), "tupleSource")
    tuple_source: dict[str, dict[str, Any]] = {}
    original_tuple_sources = documents["tuple"].get("sourceInputs")
    if not isinstance(original_tuple_sources, dict) or not original_tuple_sources:
        fail("tuple has no sourceInputs")
    for key, original_ref in original_tuple_sources.items():
        original_ref = obj(original_ref, f"tuple sourceInput:{key}")
        expected_hash = qualified_hash(original_ref.get("sha256"), f"tuple sourceInput hash:{key}")
        expected_bytes = original_ref.get("bytes")
        if not isinstance(expected_bytes, int) or expected_bytes < 0:
            fail(f"tuple sourceInput bytes missing: {key}")
        if key not in tuple_source_paths:
            fail(f"tupleSource omits: {key}")
        reference = archive.ref(tuple_source_paths[key], f"tupleSource:{key}")
        if reference["sha256"] != expected_hash or reference["bytes"] != expected_bytes:
            fail(f"tuple sourceInput byte/hash mismatch: {key}")
        tuple_source[key] = reference

    overlay_input = obj(input_map.get("executionOverlay"), "executionOverlay")
    overlay_root = safe_rel(overlay_input.get("overlayRoot"), "executionOverlay.overlayRoot")
    base_profile_path = safe_rel(overlay_input.get("baseProducerProfile"), "executionOverlay.baseProducerProfile")
    if base_profile_path != roles["producerProfile"]["path"]:
        fail("execution overlay base profile is not frozen producer profile")
    overlay_paths = overlay_input.get("files")
    if not isinstance(overlay_paths, list) or len(set(overlay_paths)) != len(overlay_paths):
        fail("execution overlay files must be explicit unique list")
    if not (overlay_root.endswith("/repeat-r2") or overlay_root.endswith("/repeat-r4")):
        fail("execution overlay requires exact repeat-r2 or repeat-r4 root")
    expected_overlay_hashes = EXECUTION_OVERLAY_REPEAT_R4_HASHES if overlay_root.endswith("/repeat-r4") else EXECUTION_OVERLAY_REPEAT_R2_HASHES
    overlay_label = "repeat-r4" if overlay_root.endswith("/repeat-r4") else "repeat-r2"
    overlay_names = {PurePosixPath(str(path)).name for path in overlay_paths}
    if any(not safe_rel(path, "executionOverlay file").startswith(overlay_root + "/") for path in overlay_paths):
        fail("execution overlay file escapes exact overlay root")
    if not set(expected_overlay_hashes).issubset(overlay_names):
        fail(f"execution overlay omits one or more Count20 {overlay_label}/prefixed-guard scripts")
    overlay_files = [archive.ref(path, f"executionOverlay:{path}") for path in overlay_paths]
    for name, expected in expected_overlay_hashes.items():
        matches = [ref for ref in overlay_files if PurePosixPath(ref["path"]).name == name]
        if len(matches) != 1 or matches[0]["sha256"] != expected:
            fail(f"execution overlay pinned source mismatch: {name}")
    issuer_source_path = safe_rel(input_map.get("issuerSource"), "issuerSource")
    if not issuer_source_path.endswith(ISSUER_SOURCE_SUFFIX):
        fail("issuerSource must reference prefixed issuer overlay path")
    issuer_source = archive.ref(issuer_source_path, "issuerSource")
    if issuer_source["sha256"] != ISSUER_SOURCE_HASH:
        fail("issuerSource byte/hash mismatch")

    coordinator = documents["coordinator"]
    if coordinator.get("count") not in (None, 20) or coordinator.get("expectedCount") not in (None, 20):
        fail("coordinator is not Count20")

    run_maps = input_map.get("runs")
    if not isinstance(run_maps, list) or len(run_maps) != 20:
        fail("runs must contain exactly twenty explicit Count20 maps")
    runs: list[dict[str, Any]] = []
    for index, run_input in enumerate(run_maps, 1):
        run_input = obj(run_input, f"run {index}")
        require_keys(run_input, RUN_NAMES + ("workerSource",), f"run {index}")
        run: dict[str, Any] = {"run": index}
        for name in RUN_NAMES:
            run[name] = archive.ref(run_input[name], f"run{index}:{name}")
        worker_contract, _ = archive.document(run_input["workerContract"], f"run{index}:workerContract")
        worker_source_paths = obj(run_input["workerSource"], f"run{index}:workerSource")
        contract_bindings = worker_contract.get("sourceBindings")
        if not isinstance(contract_bindings, list) or not contract_bindings:
            fail(f"run {index} worker contract has no sourceBindings")
        worker_source: dict[str, dict[str, Any]] = {}
        for binding in contract_bindings:
            binding = obj(binding, f"run{index} worker binding")
            path = safe_rel(binding.get("path"), f"run{index} worker binding path")
            if path not in worker_source_paths:
                fail(f"run {index} workerSource omits: {path}")
            reference = archive.ref(worker_source_paths[path], f"run{index}:workerSource:{path}")
            if reference["sha256"] != qualified_hash(binding.get("sha256"), f"run{index} worker hash:{path}"):
                fail(f"run {index} worker source hash mismatch: {path}")
            worker_source[path] = reference
        run["workerSource"] = worker_source
        runs.append(run)

    output = {
        "kind": "factory-settled-capture-adapter-inputs-v3",
        "version": 3,
        "count": 20,
        "qualification": "observational-native-only; adapter output remains qualified=false/nativeParity=hold",
        "roles": roles,
        "metadataRecordPaths": {key: metadata_paths[key] for key in ("plan", "compile", "exe", "renderer", "manifest", "candidateBinding")},
        "producerSource": producer_source,
        "source": source,
        "runtimeModules": runtime_modules,
        "tupleSource": tuple_source,
        "runs": runs,
        "executionOverlay": {
            "kind": "factory-root-execution-overlay-v1",
            "status": "executed-source-ref-only",
            "overlayRoot": overlay_root,
            "baseProducerProfile": roles["producerProfile"],
            "files": overlay_files,
            "executionClaim": "overlay provenance is preserved; frozen producer profile is not relabeled as executed",
        },
        "issuerSource": dict(issuer_source, name=ISSUER_SOURCE_NAME),
        "adapterCompatibility": {
            "frozenAdapter": "settled-capture-adapter-v3",
            "executionOverlayExpressedByFrozenAdapter": False,
            "qualification": "hold-until-bounded-adapter-overlay-version",
            "boundedProposal": "adapter-v4-proposal.md",
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        with args.output.open("x", encoding="utf-8") as handle:
            json.dump(output, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except FileExistsError:
        fail(f"refusing to overwrite output: {args.output}")
    print(json.dumps({"status": "produced-source-only", "output": str(args.output), "count": 20, "overlayFiles": len(overlay_files)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
