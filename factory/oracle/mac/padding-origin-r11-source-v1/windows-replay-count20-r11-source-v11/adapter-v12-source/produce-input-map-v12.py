#!/usr/bin/env python3
"""Produce strict Count20 inputs from one measured r17 export.

This producer accepts only an explicit export manifest & explicit role paths.
It does not discover, copy, normalize, or relabel prior r16/r17 evidence.
"""
from __future__ import annotations

import argparse
import json
import re
import stat
from pathlib import Path

HERE = Path(__file__).resolve().parent
V9 = HERE.parent / "adapter-v9-source"
import sys

sys.path.insert(0, str(V9))
from bounded_io_v9 import (  # noqa: E402
    ARCHIVE_FILE_LIMIT,
    ARCHIVE_TOTAL_LIMIT,
    bounded_json,
    beneath,
    output_path,
    stream_hash,
)

RUN_RE = re.compile(r"^[0-9a-f]{32}$")
SHA_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
CAPTURE_RE = re.compile(r"^capture/[0-9a-f]{32}$")
IMAGE_RE = re.compile(r"^image/[0-9a-f]{32}$")
REQUIRED_PREFIXES = (
    "coordinator-r1/",
    "actual-inputs/",
    "overlay/",
    "replays/r1/",
)


class Hold(ValueError):
    pass


def repo_rel(repo: Path, value: Path, label: str) -> str:
    if value.is_absolute() or ":" in value.as_posix() or "\\" in value.as_posix():
        raise Hold(f"{label} must be repository-relative")
    rel = value.as_posix()
    beneath(repo, rel)
    return rel


def regular_directory(path: Path, label: str) -> None:
    try:
        info = path.lstat()
    except OSError as exc:
        raise Hold(f"{label} unavailable") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise Hold(f"{label} must be a non-symlink directory")


def ref(repo: Path, rel: str, *, max_bytes: int = ARCHIVE_FILE_LIMIT) -> dict:
    path = beneath(repo, rel)
    digest, size = stream_hash(path, max_bytes=max_bytes)
    return {"path": rel, "sha256": digest, "bytes": size}


def local_ref(repo: Path, value: Path, label: str, *, max_bytes: int = ARCHIVE_FILE_LIMIT) -> dict:
    return ref(repo, repo_rel(repo, value, label), max_bytes=max_bytes)


def require_json(repo: Path, rel: str, label: str) -> tuple[dict, dict]:
    reference = ref(repo, rel, max_bytes=2 * 1024 * 1024)
    value = bounded_json(repo / rel)
    if not isinstance(value, dict):
        raise Hold(f"{label} must be a JSON object")
    return value, reference


def canonical_hash(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise Hold(f"{label} hash missing")
    candidate = value if value.startswith("sha256:") else "sha256:" + value
    if not SHA_RE.fullmatch(candidate):
        raise Hold(f"{label} hash malformed")
    return candidate


def role_path(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise Hold(f"{label} path missing")
    return value


def validate_issued(issued: dict) -> dict:
    if issued.get("expectedCount") != 20 or issued.get("frozenTupleBound") is not False:
        raise Hold("issued metadata count/boundary mismatch")
    run_id = issued.get("runID")
    if not isinstance(run_id, str) or not RUN_RE.fullmatch(run_id):
        raise Hold("issued runID malformed")
    source_hash = canonical_hash(issued.get("sourceHash"), "issued source")
    case = issued.get("case")
    if not isinstance(case, dict) or not isinstance(case.get("id"), str):
        raise Hold("issued case identity missing")
    case_hash = canonical_hash(case.get("hash"), "issued case")
    captures = issued.get("captures")
    if not isinstance(captures, list) or len(captures) != 20:
        raise Hold("issued capture count mismatch")
    capture_ids: set[str] = set()
    image_ids: set[str] = set()
    capture_order: list[str] = []
    image_order: list[str] = []
    pairs: list[dict[str, object]] = []
    for row in captures:
        if not isinstance(row, dict):
            raise Hold("issued capture row malformed")
        capture_id = row.get("captureID")
        image_id = row.get("imageID")
        if not isinstance(capture_id, str) or not CAPTURE_RE.fullmatch(capture_id) or capture_id in capture_ids:
            raise Hold("issued capture ID provenance mismatch")
        if not isinstance(image_id, str) or not IMAGE_RE.fullmatch(image_id) or image_id in image_ids:
            raise Hold("issued image ID provenance mismatch")
        if canonical_hash((row.get("provenance") or {}).get("sourceHash"), "capture source") != source_hash:
            raise Hold("issued capture source provenance mismatch")
        capture_ids.add(capture_id)
        image_ids.add(image_id)
        capture_order.append(capture_id)
        image_order.append(image_id)
        pairs.append({"run": row.get("run", len(pairs) + 1), "captureID": capture_id, "imageID": image_id})
    return {
        "runID": run_id,
        "sourceHash": source_hash,
        "caseID": case["id"],
        "caseHash": case_hash,
        "captureIDs": capture_order,
        "imageIDs": image_order,
        "pairs": pairs,
        "issuedMetadataSha256": "",
    }


def validate_task(task: dict, lineage: dict) -> dict:
    if task.get("status") != "completed-source-bound-observation":
        raise Hold("task result is not completed source-bound observation")
    if canonical_hash(task.get("issuedMetadataHash"), "task issued") != lineage["issuedMetadataSha256"]:
        raise Hold("task issued metadata hash mismatch")
    receipt = task.get("memoryReceipt")
    if not isinstance(receipt, dict) or receipt.get("status") != "passed":
        raise Hold("task memory receipt missing")
    if receipt.get("jobMemoryLimitBytes") != 1073741824 or receipt.get("limitFlags") != 0x200:
        raise Hold("task memory cap mismatch")
    if receipt.get("activeProcessCount") != 1 or receipt.get("killOnJobClose") is not False:
        raise Hold("task memory active-process proof mismatch")
    if receipt.get("runID") not in (None, lineage.get("runID")):
        raise Hold("task memory runID mismatch")
    if receipt.get("parentPid") is not None and (not isinstance(receipt.get("parentPid"), int) or receipt["parentPid"] <= 0):
        raise Hold("task memory parent PID invalid")
    peak = receipt.get("peakJobMemoryUsedBytes")
    if not isinstance(peak, int) or isinstance(peak, bool) or peak < 0 or peak > 1073741824:
        raise Hold("task memory peak invalid")
    return receipt


def validate_memory_controls(controls: dict, receipt: dict) -> dict:
    """Admit active=1 only when controls prove it is supervisor self-only."""
    if controls.get("schema") != "factory-interactive-job-memory-controls-v2" or controls.get("status") != "passed-source-only":
        raise Hold("memory controls status/schema mismatch")
    rows = controls.get("controls")
    if not isinstance(rows, list):
        raise Hold("memory controls rows missing")
    by_name = {row.get("name"): row for row in rows if isinstance(row, dict)}
    if len(by_name) != len(rows):
        raise Hold("memory controls contain duplicate/malformed cases")
    required = ("wrong-memory-limit-flags", "positive-1GiB-memory-job", "live-child-guard-rejects", "self-only-after-child-terminal")
    if set(required) - set(by_name):
        raise Hold("memory controls required cases missing")
    if by_name["wrong-memory-limit-flags"].get("accepted") is not False or by_name["wrong-memory-limit-flags"].get("expectedRejected") is not True:
        raise Hold("wrong memory flags control was not rejected")
    if by_name["positive-1GiB-memory-job"].get("accepted") is not True or by_name["positive-1GiB-memory-job"].get("expectedRejected") is not False:
        raise Hold("positive memory control was not accepted")
    if by_name["live-child-guard-rejects"].get("accepted") is not False or by_name["live-child-guard-rejects"].get("expectedRejected") is not True:
        raise Hold("live-child guard control was not rejected")
    if by_name["self-only-after-child-terminal"].get("accepted") is not True or by_name["self-only-after-child-terminal"].get("expectedRejected") is not False:
        raise Hold("self-only control was not accepted")
    child = controls.get("childProof")
    if not isinstance(child, dict) or child.get("originalHandleRetained") is not True or child.get("terminal") is not True:
        raise Hold("memory child terminal proof missing")
    if controls.get("jobMemoryLimitBytes") != receipt.get("jobMemoryLimitBytes") or controls.get("jobMemoryLimitFlag") != receipt.get("limitFlags"):
        raise Hold("memory controls/receipt limit join mismatch")
    if controls.get("killOnJobClose") is not receipt.get("killOnJobClose"):
        raise Hold("memory controls/receipt close policy mismatch")
    return {
        "pathRole": "memory-controls-v17-r1.json",
        "jobMemoryLimitBytes": controls["jobMemoryLimitBytes"],
        "jobMemoryLimitFlag": controls["jobMemoryLimitFlag"],
        "killOnJobClose": controls["killOnJobClose"],
        "activeProcessCount": receipt["activeProcessCount"],
        "selfOnlyAccepted": True,
        "liveChildRejected": True,
        "childProof": child,
    }


def validate_coordinator(coordinator: dict, lineage: dict, compile: dict, compile_ref: dict, issued: dict) -> dict:
    """Require coordinator-level terminal/quiescence evidence around self-only job."""
    if coordinator.get("kind") != "padding-window-diagnosis-interactive-coordinator" or coordinator.get("status") != "completed-source-bound-observation":
        raise Hold("coordinator status/kind mismatch")
    if coordinator.get("count") != 20 or coordinator.get("sourceHash") != lineage["sourceHash"]:
        raise Hold("coordinator count/source join mismatch")
    if coordinator.get("compileReceiptHash") not in (compile_ref["sha256"], compile_ref["sha256"].removeprefix("sha256:")):
        raise Hold("coordinator compile receipt join mismatch")
    if coordinator.get("exeHash") not in (compile["exeSha256"], compile["exeSha256"].removeprefix("sha256:")):
        raise Hold("coordinator executable join mismatch")
    run_root = str(coordinator.get("runRoot", "")).replace("/", "\\").lower()
    if not run_root.endswith("\\replays\\r1"):
        raise Hold("coordinator run root mismatch")
    bools = ("lockAcquired", "lockReleased", "wholeBatchExitConfirmed", "taskRegistered", "taskStarted", "terminalResultConfirmed")
    if any(coordinator.get(name) is not True for name in bools):
        raise Hold("coordinator terminal/quiescence proof incomplete")
    if coordinator.get("error") != "" or coordinator.get("errorId") != "" or coordinator.get("interactiveError") != "" or coordinator.get("interactiveErrorId") != "" or coordinator.get("cleanupErrors") != []:
        raise Hold("coordinator cleanup errors present")
    if coordinator.get("frozenTupleBound") is not False:
        raise Hold("coordinator tuple boundary mismatch")
    return {
        "status": coordinator["status"],
        "count": coordinator["count"],
        "externalTaskTerminal": True,
        "wholeBatchExitConfirmed": True,
        "lockReleased": True,
        "cleanupErrors": [],
    }


def validate_manifest_document(repo: Path, archive_rel: str, manifest: dict) -> list[dict]:
    if manifest.get("kind") != "root-factory-native-v17-export-v1":
        raise Hold("r17 export manifest kind mismatch")
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows:
        raise Hold("r17 export inventory missing")
    seen: set[str] = set()
    inventory: list[dict] = []
    total = 0
    prefixes = set()
    for row in rows:
        if not isinstance(row, dict):
            raise Hold("r17 inventory row malformed")
        rel = row.get("path")
        if not isinstance(rel, str) or rel in seen:
            raise Hold("r17 inventory path duplicate/missing")
        if rel.startswith("/") or "\\" in rel or ":" in rel:
            raise Hold("r17 inventory path unsafe")
        full_rel = str(Path(archive_rel) / rel)
        expected_bytes = row.get("bytes")
        expected_hash = canonical_hash(row.get("sha256"), f"r17 inventory {rel}")
        if not isinstance(expected_bytes, int) or expected_bytes < 0:
            raise Hold(f"r17 inventory byte count invalid: {rel}")
        actual_hash, actual_bytes = stream_hash(beneath(repo, full_rel), expected_bytes=expected_bytes, max_bytes=ARCHIVE_FILE_LIMIT)
        if actual_hash != expected_hash:
            raise Hold(f"r17 inventory hash mismatch: {rel}")
        total += actual_bytes
        if total > ARCHIVE_TOTAL_LIMIT:
            raise Hold("r17 export exceeds bounded archive total")
        seen.add(rel)
        for prefix in REQUIRED_PREFIXES:
            if rel.startswith(prefix):
                prefixes.add(prefix)
        inventory.append({"path": rel, "sha256": actual_hash, "bytes": actual_bytes})
    missing = [prefix for prefix in REQUIRED_PREFIXES if prefix not in prefixes]
    if missing:
        raise Hold("r17 export layout missing: " + ", ".join(missing))
    return inventory


def validate_manifest(repo: Path, archive_rel: str, manifest_rel: str) -> tuple[dict, list[dict]]:
    manifest, manifest_ref = require_json(repo, manifest_rel, "r17 export manifest")
    inventory = validate_manifest_document(repo, archive_rel, manifest)
    return {"ref": manifest_ref, "kind": manifest["kind"], "fileCount": len(inventory), "totalBytes": sum(row["bytes"] for row in inventory)}, inventory


def archive_ref(inventory: dict[str, dict], rel: str) -> dict:
    try:
        return dict(inventory[rel])
    except KeyError as exc:
        raise Hold(f"r17 archive role missing: {rel}") from exc


def repo_archive_ref(repo: Path, archive_rel: str, inventory: dict[str, dict], rel: str) -> dict:
    """Expose archive evidence using repository-relative paths throughout output."""
    value = archive_ref(inventory, rel)
    return {**value, "path": repo_rel(repo, Path(archive_rel) / rel, "archive evidence")}


def archive_json(repo: Path, archive_rel: str, inventory: dict[str, dict], rel: str, label: str) -> tuple[dict, dict]:
    reference = archive_ref(inventory, rel)
    value = bounded_json(beneath(repo, f"{archive_rel}/{rel}"))
    return value, reference


def canonical_optional(value: object, label: str) -> str:
    if value is None:
        raise Hold(f"{label} missing")
    return canonical_hash(value, label)


def validate_candidate(candidate: dict, lineage: dict, issued_ref: dict) -> dict:
    if candidate.get("kind") != "factory-source-bound-candidate-canonical-tuple-v1" or candidate.get("frozenTupleBound") is not False:
        raise Hold("candidate tuple kind/boundary mismatch")
    if candidate.get("case") != {"id": lineage["caseID"], "hash": lineage["caseHash"]}:
        raise Hold("candidate tuple fresh case mismatch")
    value = candidate.get("tuple")
    if not isinstance(value, dict) or not isinstance(value.get("id"), str):
        raise Hold("candidate tuple value missing")
    hosts = value.get("hostHashes")
    if not isinstance(hosts, dict) or not SHA_RE.fullmatch(str(hosts.get("macos", ""))) or not SHA_RE.fullmatch(str(hosts.get("windows", ""))):
        raise Hold("candidate host hashes missing")
    if not SHA_RE.fullmatch(str(value.get("rendererHash", ""))) or not isinstance(value.get("runtimeCommit"), str):
        raise Hold("candidate renderer/runtime join missing")
    return value


def validate_compile(compile: dict, plan: dict, plan_ref: dict, lineage: dict) -> dict:
    if compile.get("exitCode") != 0 or compile.get("timedOut") is not False or compile.get("sourceHash") != lineage["sourceHash"]:
        raise Hold("compile source/exit admission mismatch")
    for key in ("exeSha256", "rendererSha256", "runtimeSourceTreeHash", "compilerHash"):
        canonical_optional(compile.get(key), f"compile {key}")
    if canonical_hash(compile.get("planSha256"), "compile plan") != plan_ref["sha256"]:
        raise Hold("compile plan hash mismatch")
    if not isinstance(compile.get("runtimeSourceCommit"), str):
        raise Hold("compile runtime commit missing")
    return {
        "exeSha256": canonical_hash(compile["exeSha256"], "compile executable"),
        "rendererSha256": canonical_hash(compile["rendererSha256"], "compile renderer"),
        "runtimeSourceTreeHash": canonical_hash(compile["runtimeSourceTreeHash"], "compile runtime tree"),
        "runtimeSourceCommit": compile["runtimeSourceCommit"],
        "compilerSha256": canonical_hash(compile["compilerHash"], "compile compiler"),
    }


def _doc(repo: Path, archive_rel: str, inventory: dict[str, dict], rel: str, label: str) -> dict:
    value = bounded_json(beneath(repo, f"{archive_rel}/{rel}"))
    if not isinstance(value, dict):
        raise Hold(f"{label} must be object")
    return value


def validate_native(repo: Path, archive_rel: str, native: object, lineage: dict, candidate_ref: dict, compile: dict, inventory: dict[str, dict]) -> list[dict]:
    """Join measured IDs, retained-handle exit, sealed streams, & full raw closure."""
    if not isinstance(native, list) or len(native) != 20:
        raise Hold("r17 native observation count mismatch")
    pairs = lineage["pairs"]
    runs: list[dict] = []
    for index, row in enumerate(native, 1):
        if not isinstance(row, dict) or row.get("index") != index or row.get("hostValid") is not True or row.get("exitCode") != 0:
            raise Hold(f"native run {index} identity/host/exit proof mismatch")
        expected_case = {"id": lineage["caseID"], "hash": lineage["caseHash"]}
        if row.get("case") != expected_case or row.get("sourceHash") != lineage["sourceHash"]:
            raise Hold(f"native run {index} case/source mismatch")
        if (canonical_hash(row.get("exeSha256"), f"native run {index} executable") != compile["exeSha256"]
                or canonical_hash(row.get("rendererSha256"), f"native run {index} renderer") != compile["rendererSha256"]
                or canonical_hash(row.get("runtimeSourceTreeHash"), f"native run {index} runtime tree") != compile["runtimeSourceTreeHash"]
                or row.get("runtimeSourceCommit") != compile["runtimeSourceCommit"]):
            raise Hold(f"native run {index} compiler/runtime/renderer join mismatch")
        if row.get("candidateTupleRef", {}).get("sha256") != candidate_ref["sha256"]:
            raise Hold(f"native run {index} candidate tuple ref mismatch")
        files = row.get("files")
        if not isinstance(files, list) or len(files) != 24:
            raise Hold(f"native run {index} raw closure count mismatch")
        prefix = f"replays/r1/native-{index:02d}/"
        entries = [entry for entry in files if isinstance(entry, dict)]
        local_paths = {entry.get("path") for entry in entries}
        if len(entries) != 24 or len(local_paths) != 24 or any(not isinstance(path, str) or "/" in path or "\\" in path for path in local_paths):
            raise Hold(f"native run {index} row file names malformed")
        row_paths = {path if path in inventory else prefix + path for path in local_paths}
        if len(row_paths) != 24 or any(path not in inventory for path in row_paths):
            raise Hold(f"native run {index} row/archive closure mismatch")
        for entry in entries:
            local_path = entry["path"]
            archive_path = local_path if local_path in inventory else prefix + local_path
            if inventory[archive_path]["sha256"] != canonical_hash(entry.get("sha256"), f"native run {index} row hash {local_path}"):
                raise Hold(f"native run {index} row/archive hash mismatch")
        required = {prefix + name for name in ("capture-outcome.json", "final-exit-certificate.json", "owned-process.json", "owned-close.json", "host.stdout.txt", "host.stderr.txt", "measured-capture-identity.json", "terminal-worker.json")}
        if not required.issubset(row_paths):
            raise Hold(f"native run {index} required raw roles missing")
        measured_rel = prefix + "measured-capture-identity.json"
        measured = _doc(repo, archive_rel, inventory, measured_rel, f"native run {index} measurement")
        pair = pairs[index - 1]
        if (measured.get("kind") != "factory-measured-capture-identity-v1" or measured.get("run") != index
                or measured.get("captureID") != pair["captureID"] or measured.get("imageID") != pair["imageID"]):
            raise Hold(f"native run {index} issued row pair mismatch")
        if canonical_hash(measured.get("issuedMetadataHash"), f"native run {index} issued metadata") != lineage["issuedMetadataSha256"]:
            raise Hold(f"native run {index} issued metadata identity mismatch")
        measured_host = measured.get("measuredHostIdentity")
        if not isinstance(measured_host, dict) or canonical_hash(measured_host.get("hash"), f"native run {index} measured host") != compile["exeSha256"]:
            raise Hold(f"native run {index} measured executable identity mismatch")
        outcome_rel = prefix + "capture-outcome.json"
        outcome = _doc(repo, archive_rel, inventory, outcome_rel, f"native run {index} outcome")
        cleanup = outcome.get("cleanup") or {}
        if outcome.get("primaryError") != "" or outcome.get("streamErrors") != [] or cleanup.get("confirmedOwnedExit") is not True or cleanup.get("kernelExitSignaled") is not True or cleanup.get("kernelWaitResult") != 0:
            raise Hold(f"native run {index} cleanup/stream admission mismatch")
        streams = outcome.get("rawStreams")
        if not isinstance(streams, list) or len(streams) != 2 or {item.get("name") for item in streams} != {"stdout", "stderr"} or any(item.get("sealed") is not True or item.get("hashQualification") != "sealed-raw" for item in streams):
            raise Hold(f"native run {index} raw stream sealing mismatch")
        for name in ("stdout", "stderr"):
            stream_hash = canonical_hash(outcome.get(name + "Sha256"), f"native run {index} {name} outcome hash")
            if inventory[prefix + "host." + name + ".txt"]["sha256"] != stream_hash:
                raise Hold(f"native run {index} {name} stream hash mismatch")
        cert = _doc(repo, archive_rel, inventory, prefix + "final-exit-certificate.json", f"native run {index} final exit")
        sample = cert.get("sample") or {}
        if (cert.get("kind") != "factory-final-exit-certificate-v1" or cert.get("scope") != "owner-release-only"
                or sample.get("waitMilliseconds") != 0 or sample.get("kernelBefore") != 0 or sample.get("kernelAfter") != 0
                or sample.get("getExitCodeSucceeded") is not True or sample.get("exitCode") != 0 or sample.get("errors") != []):
            raise Hold(f"native run {index} final retained-handle certificate mismatch")
        terminal = _doc(repo, archive_rel, inventory, prefix + "terminal-worker.json", f"native run {index} terminal")
        if terminal.get("terminalResultConfirmed") is not True or terminal.get("finalCertificateHash") != inventory[prefix + "final-exit-certificate.json"]["sha256"].removeprefix("sha256:") or terminal.get("originalOutcomeHash") != inventory[outcome_rel]["sha256"].removeprefix("sha256:"):
            raise Hold(f"native run {index} terminal certificate join mismatch")
        raw_closure = [repo_archive_ref(repo, archive_rel, inventory, item["path"]) for item in inventory.values() if item["path"].startswith(prefix)]
        if len(raw_closure) < 36:
            raise Hold(f"native run {index} full raw closure incomplete")
        runs.append({
            "run": index, "captureID": pair["captureID"], "imageID": pair["imageID"],
            "outcome": repo_archive_ref(repo, archive_rel, inventory, outcome_rel),
            "observation": repo_archive_ref(repo, archive_rel, inventory, "replays/r1/native-observation.json"),
            "owned": repo_archive_ref(repo, archive_rel, inventory, prefix + "owned-process.json"),
            "close": repo_archive_ref(repo, archive_rel, inventory, prefix + "owned-close.json"),
            "stdout": repo_archive_ref(repo, archive_rel, inventory, prefix + "host.stdout.txt"),
            "stderr": repo_archive_ref(repo, archive_rel, inventory, prefix + "host.stderr.txt"),
            "measurement": repo_archive_ref(repo, archive_rel, inventory, measured_rel),
            "finalExit": repo_archive_ref(repo, archive_rel, inventory, prefix + "final-exit-certificate.json"),
            "terminal": repo_archive_ref(repo, archive_rel, inventory, prefix + "terminal-worker.json"),
            "rawClosure": raw_closure,
        })
    return runs


def validate_emitted_map(value: object) -> None:
    """Source-control admission used on real producer output & fault mutations."""
    if not isinstance(value, dict) or value.get("schema") != "factory-native-count20-r17-input-map-v12" or value.get("version") != 12:
        raise Hold("v12 emitted map schema mismatch")
    if value.get("status") != "ready-for-r17-adapter-proof-v12" or value.get("qualification") != "held-observation-only":
        raise Hold("v12 emitted map status must remain held")
    roles = value.get("roles")
    required_roles = {"issuedMetadata", "tuple", "candidateBinding", "plan", "compile", "manifest", "coordinator", "memoryControls", "producerProfile", "taskResult", "sourceBinding", "exe", "renderer", "witness", "runtimeReceipt", "runtimeTree"}
    if not isinstance(roles, dict) or not required_roles.issubset(roles): raise Hold("v12 emitted role closure incomplete")
    runs = value.get("runs"); lineage = value.get("lineage") or {}
    if not isinstance(runs, list) or len(runs) != 20 or [run.get("run") for run in runs] != list(range(1, 21)): raise Hold("v12 emitted runs must be ordered 1..20")
    pairs = lineage.get("issuedPairs")
    if not isinstance(pairs, list) or len(pairs) != 20 or [pair.get("run") for pair in pairs] != list(range(1, 21)): raise Hold("v12 emitted ordered pair closure incomplete")
    if any(run.get("captureID") != pair.get("captureID") or run.get("imageID") != pair.get("imageID") for run, pair in zip(runs, pairs)): raise Hold("v12 emitted measured pair join mismatch")
    if any(not isinstance(run.get("rawClosure"), list) or len(run["rawClosure"]) < 36 or not run.get("finalExit") or not run.get("terminal") for run in runs): raise Hold("v12 emitted full raw closure/terminal proof incomplete")
    admission = value.get("cleanupAdmission") or {}
    if (admission.get("activeProcessCount") != 1 or admission.get("selfOnlyAccepted") is not True or admission.get("liveChildRejected") is not True
            or admission.get("externalTaskTerminal") is not True or admission.get("wholeBatchExitConfirmed") is not True
            or admission.get("lockReleased") is not True or admission.get("cleanupErrors") != []):
        raise Hold("v12 self-only cleanup admission incomplete")
    contract = value.get("proofRoleContract") or {}
    if contract.get("count") != 13 or contract.get("perRun") != 20 or len(contract.get("roles", [])) != 13: raise Hold("v12 proof-role contract incomplete")
    overlay = value.get("executionOverlay") or {}
    if overlay.get("status") != "executed-source-ref-only" or not isinstance(overlay.get("files"), list) or not overlay.get("files"): raise Hold("v12 execution overlay admission missing")
    compiler = value.get("compilerAdmission") or {}
    compiler_ref = value.get("compiler") or {}
    if (not SHA_RE.fullmatch(str(compiler.get("sha256"))) or not isinstance(compiler.get("bytes"), int) or compiler["bytes"] <= 0
            or compiler.get("sha256") != compiler_ref.get("sha256") or compiler.get("bytes") != compiler_ref.get("bytes")): raise Hold("v12 compiler byte admission missing")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--export-manifest", required=True, type=Path)
    ap.add_argument("--issued-metadata", required=True, type=Path)
    ap.add_argument("--task-result", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--source-binding", required=True, type=Path)
    ap.add_argument("--candidate-tuple", required=True, type=Path)
    ap.add_argument("--candidate-binding", required=True, type=Path)
    ap.add_argument("--native-observation", required=True, type=Path)
    ap.add_argument("--compile-observation", required=True, type=Path)
    ap.add_argument("--runtime-receipt", required=True, type=Path)
    ap.add_argument("--runtime-tree", required=True, type=Path)
    ap.add_argument("--witness", required=True, type=Path)
    ap.add_argument("--exe", required=True, type=Path)
    ap.add_argument("--renderer", required=True, type=Path)
    ap.add_argument("--compiler", required=True, type=Path)
    ap.add_argument("--host-source-root", required=True, type=Path)
    ap.add_argument("--runtime-source-root", required=True, type=Path)
    ap.add_argument("--runtime-module", action="append", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    try:
        repo = args.repo.absolute()
        archive_rel = repo_rel(repo, args.archive_root, "archive root")
        regular_directory(repo / archive_rel, "r17 archive root")
        manifest_rel = repo_rel(repo, args.export_manifest, "export manifest")
        issued_rel = repo_rel(repo, args.issued_metadata, "issued metadata")
        task_rel = repo_rel(repo, args.task_result, "task result")
        plan_rel = repo_rel(repo, args.plan, "adapter plan")
        binding_rel = repo_rel(repo, args.source_binding, "source binding")
        candidate_rel = repo_rel(repo, args.candidate_tuple, "candidate tuple")
        candidate_binding_rel = repo_rel(repo, args.candidate_binding, "candidate binding")
        native_rel = repo_rel(repo, args.native_observation, "native observation")
        compile_rel = repo_rel(repo, args.compile_observation, "compile observation")
        runtime_receipt_rel = repo_rel(repo, args.runtime_receipt, "runtime receipt")
        runtime_tree_rel = repo_rel(repo, args.runtime_tree, "runtime tree")
        manifest, inventory = validate_manifest(repo, archive_rel, manifest_rel)
        inventory_by_path = {row["path"]: row for row in inventory}
        issued, issued_ref = require_json(repo, issued_rel, "issued metadata")
        lineage = validate_issued(issued)
        lineage["issuedMetadataSha256"] = issued_ref["sha256"]
        plan, plan_ref = archive_json(repo, archive_rel, inventory_by_path, plan_rel.removeprefix(archive_rel + "/"), "adapter source plan")
        candidate, candidate_ref = archive_json(repo, archive_rel, inventory_by_path, candidate_rel.removeprefix(archive_rel + "/"), "candidate tuple")
        candidate_value = validate_candidate(candidate, lineage, issued_ref)
        candidate_binding, candidate_binding_ref = archive_json(repo, archive_rel, inventory_by_path, candidate_binding_rel.removeprefix(archive_rel + "/"), "candidate binding")
        if candidate_binding.get("frozenTupleBound") is not False or candidate_binding.get("canonicalTupleRef", {}).get("sha256") != candidate_ref["sha256"]:
            raise Hold("candidate binding tuple join mismatch")
        compile, compile_ref = archive_json(repo, archive_rel, inventory_by_path, compile_rel.removeprefix(archive_rel + "/"), "compile observation")
        compile_profile = validate_compile(compile, plan, plan_ref, lineage)
        runtime_receipt, runtime_receipt_ref = archive_json(repo, archive_rel, inventory_by_path, runtime_receipt_rel.removeprefix(archive_rel + "/"), "runtime receipt")
        runtime_tree = bounded_json(beneath(repo, runtime_tree_rel))
        runtime_tree_ref = archive_ref(inventory_by_path, runtime_tree_rel.removeprefix(archive_rel + "/"))
        if not isinstance(runtime_tree, list) or len(runtime_tree) != 21:
            raise Hold("runtime source tree must contain 21 rows")
        if runtime_receipt.get("sourceCommit") != compile_profile["runtimeSourceCommit"] or runtime_receipt.get("sourceTreeHash") != compile_profile["runtimeSourceTreeHash"]:
            raise Hold("runtime receipt/compiler join mismatch")
        native, native_ref = archive_json(repo, archive_rel, inventory_by_path, native_rel.removeprefix(archive_rel + "/"), "native observation")
        if not isinstance(native, list):
            raise Hold("native observation must be an array")
        runs = validate_native(repo, archive_rel, native, lineage, candidate_ref, compile_profile, inventory_by_path)
        task, task_ref = require_json(repo, task_rel, "task result")
        memory = validate_task(task, {"issuedMetadataSha256": issued_ref["sha256"], "runID": lineage["runID"]})
        memory_controls, memory_controls_ref = archive_json(repo, archive_rel, inventory_by_path, "memory-controls-v17-r1.json", "memory controls")
        memory_admission = validate_memory_controls(memory_controls, memory)
        coordinator, coordinator_ref = archive_json(repo, archive_rel, inventory_by_path, "coordinator-r1/coordinator.json", "coordinator")
        coordinator_admission = validate_coordinator(coordinator, lineage, compile_profile, compile_ref, issued)
        binding, binding_ref = require_json(repo, binding_rel, "source binding")
        binding_source = (
            binding.get("sourceHash")
            or (binding.get("source") or {}).get("sha256")
            or (binding.get("historicalTemplate") or {}).get("witnessHash")
        )
        if binding_source is None:
            raise Hold("source binding hash missing")
        if canonical_hash(binding_source, "source binding") != lineage["sourceHash"]:
            raise Hold("source binding hash mismatch")
        witness_ref = local_ref(repo, args.witness, "Witness.swift")
        exe_ref = local_ref(repo, args.exe, "FactoryProbe.exe")
        renderer_ref = local_ref(repo, args.renderer, "renderer")
        compiler_ref = local_ref(repo, args.compiler, "compiler")
        if (exe_ref["sha256"] != compile_profile["exeSha256"] or renderer_ref["sha256"] != compile_profile["rendererSha256"]
                or compiler_ref["sha256"] != compile_profile["compilerSha256"]):
            raise Hold("local executable/renderer closure mismatch")
        host_root_rel = repo_rel(repo, args.host_source_root, "host source root")
        runtime_root_rel = repo_rel(repo, args.runtime_source_root, "runtime source root")
        host_bindings = []
        for row in plan.get("sourceBindings", []):
            rel = row.get("path") if isinstance(row, dict) else None
            expected = row.get("sha256") if isinstance(row, dict) else None
            if not isinstance(rel, str) or not isinstance(expected, str):
                raise Hold("source plan binding row malformed")
            source_ref = local_ref(repo, Path(host_root_rel) / rel, f"host source {rel}")
            if source_ref["sha256"] != canonical_hash(expected, f"host source {rel}"):
                raise Hold(f"host source byte mismatch: {rel}")
            host_bindings.append({"path": rel, "source": source_ref})
        runtime_bindings = []
        for row in runtime_tree:
            rel = row.get("path") if isinstance(row, dict) else None
            expected = row.get("sha256") if isinstance(row, dict) else None
            if not isinstance(rel, str) or not isinstance(expected, str):
                raise Hold("runtime tree row malformed")
            source_ref = local_ref(repo, Path(runtime_root_rel) / rel, f"runtime source {rel}")
            if source_ref["sha256"] != canonical_hash(expected, f"runtime source {rel}"):
                raise Hold(f"runtime source byte mismatch: {rel}")
            runtime_bindings.append({"path": rel, "source": source_ref})
        runtime_modules = {}
        for module in args.runtime_module:
            module_ref = local_ref(repo, module, "runtime module")
            runtime_modules[module_ref["path"]] = module_ref
        if not runtime_modules:
            raise Hold("runtime module archive missing")
        produced_modules = issued.get("producedRuntimeModules")
        if not isinstance(produced_modules, list) or not produced_modules:
            raise Hold("issued produced runtime modules missing")
        expected_modules = {
            (canonical_hash(row.get("sha256"), "issued runtime module"), row.get("bytes"))
            for row in produced_modules
            if isinstance(row, dict)
        }
        if any((value["sha256"], value["bytes"]) not in expected_modules for value in runtime_modules.values()):
            raise Hold("runtime module byte/hash join mismatch")
        compile_repo_ref = repo_archive_ref(repo, archive_rel, inventory_by_path, compile_rel.removeprefix(archive_rel + "/"))
        runtime_receipt_repo_ref = repo_archive_ref(repo, archive_rel, inventory_by_path, runtime_receipt_rel.removeprefix(archive_rel + "/"))
        runtime_tree_repo_ref = repo_archive_ref(repo, archive_rel, inventory_by_path, runtime_tree_rel.removeprefix(archive_rel + "/"))
        plan_repo_ref = repo_archive_ref(repo, archive_rel, inventory_by_path, plan_rel.removeprefix(archive_rel + "/"))
        native_repo_ref = repo_archive_ref(repo, archive_rel, inventory_by_path, native_rel.removeprefix(archive_rel + "/"))
        candidate_binding_repo_ref = repo_archive_ref(repo, archive_rel, inventory_by_path, candidate_binding_rel.removeprefix(archive_rel + "/"))
        roles = {
            "issuedMetadata": issued_ref,
            "tuple": repo_archive_ref(repo, archive_rel, inventory_by_path, candidate_rel.removeprefix(archive_rel + "/")),
            "candidateBinding": repo_archive_ref(repo, archive_rel, inventory_by_path, candidate_binding_rel.removeprefix(archive_rel + "/")),
            "plan": repo_archive_ref(repo, archive_rel, inventory_by_path, plan_rel.removeprefix(archive_rel + "/")),
            "compile": compile_repo_ref,
            # source-plan is actual manifest/case/source closure; export manifest
            # remains separate inventory evidence and is never relabeled.
            "manifest": repo_archive_ref(repo, archive_rel, inventory_by_path, "actual-inputs/source-plan.json"),
            "coordinator": repo_archive_ref(repo, archive_rel, inventory_by_path, "coordinator-r1/coordinator.json"),
            "memoryControls": repo_archive_ref(repo, archive_rel, inventory_by_path, "memory-controls-v17-r1.json"),
            "producerProfile": repo_archive_ref(repo, archive_rel, inventory_by_path, "actual-inputs/source-plan.json"),
            "taskResult": task_ref,
            "sourceBinding": binding_ref,
            "exe": exe_ref,
            "renderer": renderer_ref,
            "witness": witness_ref,
            "runtimeReceipt": runtime_receipt_repo_ref,
            "runtimeTree": runtime_tree_repo_ref,
        }
        overlay_files = [repo_archive_ref(repo, archive_rel, inventory_by_path, row["path"]) for row in inventory if row["path"].startswith("overlay/")]
        if not overlay_files:
            raise Hold("r17 overlay closure missing")
        overlay_names = {Path(row["path"]).name for row in overlay_files}
        required_overlay = {"capture-fresh-r11-v17.ps1", "dispatch-fresh-r11-v17.ps1", "first-proof-fresh-r11-v17.ps1", "integration-fresh-r11-v7.ps1", "interactive-task-fresh-r11-v17.ps1", "issue-count20-fresh-r11-v6.ps1", "resume-issued-coordinator-fresh-r11-v17.ps1"}
        if not required_overlay.issubset(overlay_names):
            raise Hold("r17 overlay source closure incomplete")
        proof_roles = ("outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr")
        proof_role_inputs = []
        for run in runs:
            prefix = f"replays/r1/native-{run['run']:02d}/"
            proof_role_inputs.append({
                "run": run["run"],
                "files": {
                    "outcome": run["outcome"],
                    "observation": run["observation"],
                    "owned": run["owned"],
                    "close": run["close"],
                    "plan": roles["plan"],
                    "compile": roles["compile"],
                    "witness": roles["witness"],
                    "exe": roles["exe"],
                    "renderer": roles["renderer"],
                    "runtimeReceipt": roles["runtimeReceipt"],
                    "runtimeTree": roles["runtimeTree"],
                    "stdout": run["stdout"],
                    "stderr": run["stderr"],
                },
                    "rawClosure": run["rawClosure"],
            })
        output = {
            "schema": "factory-native-count20-r17-input-map-v12",
            "version": 12,
            "status": "ready-for-r17-adapter-proof-v12",
            "qualification": "held-observation-only",
            "nativeActions": 0,
            "lockActions": 0,
            "inputRoot": {"archiveRoot": archive_rel, "sourceRoot": repo_rel(repo, Path("."), "repository")},
            "roles": roles,
            "compiler": compiler_ref,
            "compilerAdmission": {"sha256": compiler_ref["sha256"], "source": "actual-inputs/compile-observation.json.compilerHash", "bytes": compiler_ref["bytes"]},
            "hostSourceBindings": host_bindings,
            "runtimeTreeBindings": runtime_bindings,
            "runtimeModules": runtime_modules,
            "executionOverlay": {
                "kind": "factory-root-execution-overlay-v1",
                "status": "executed-source-ref-only",
                "overlayRoot": archive_rel + "/overlay",
                "baseProducerProfile": roles["producerProfile"],
                "files": overlay_files,
            },
            "runs": runs,
            "proofRoleContract": {"roles": list(proof_roles), "count": 13, "perRun": 20},
            "proofRoleInputs": proof_role_inputs,
            "archive": {
                "root": archive_rel,
                "exportManifest": manifest,
                "inventory": inventory,
                "layout": {
                    "coordinator": "coordinator-r1",
                    "actualInputs": "actual-inputs",
                    "overlay": "overlay",
                    "replays": "replays/r1",
                    "nativeRuns": [f"replays/r1/native-{i:02d}" for i in range(1, 21)],
                },
            },
            "lineage": {
                "runID": lineage["runID"],
                "issuedMetadataSha256": issued_ref["sha256"],
                "issuedMetadata": issued_ref,
                "issuedPairs": lineage["pairs"],
                "taskResult": task_ref,
                "memoryReceipt": memory,
                "memoryControls": memory_controls_ref,
                "coordinator": coordinator_ref,
            },
            "cleanupAdmission": {
                "kind": "self-only-job-after-child-terminal-v1",
                "activeProcessCount": memory_admission["activeProcessCount"],
                "selfOnlyAccepted": memory_admission["selfOnlyAccepted"],
                "liveChildRejected": memory_admission["liveChildRejected"],
                "childProof": memory_admission["childProof"],
                "externalTaskTerminal": coordinator_admission["externalTaskTerminal"],
                "wholeBatchExitConfirmed": coordinator_admission["wholeBatchExitConfirmed"],
                "lockReleased": coordinator_admission["lockReleased"],
                "cleanupErrors": coordinator_admission["cleanupErrors"],
                "activeCountMeaning": "supervisor-self-only; no live child remains",
            },
            "freshSourceProfile": {
                "tupleID": candidate_value.get("id"),
                "caseID": lineage["caseID"],
                "caseHash": lineage["caseHash"],
                "sourceHash": lineage["sourceHash"],
                "expectedCount": 20,
                "hostHashes": candidate_value["hostHashes"],
                "rendererHash": candidate_value["rendererHash"],
                "runtimeCommit": candidate_value["runtimeCommit"],
                "captureIDs": lineage["captureIDs"],
                "imageIDs": lineage["imageIDs"],
                "plan": plan_repo_ref,
                "sourceBinding": binding_ref,
                "candidateBinding": candidate_binding_repo_ref,
                "compile": compile_repo_ref,
                "nativeObservation": native_repo_ref,
            },
            "requiredReaderJoins": [
                "20 distinct capture/image IDs from issued metadata",
                "issued run-order capture/image pairs joined by measured identity",
                "case ID/hash, tuple ID, source hash, runtime, renderer, compiler, host, & acceptance refs",
                "13 Windows exit-proof roles per capture",
                "sealed stdout/stderr/raw hashes & worker output refs",
                "actual compiler/source/runtime/renderer bytes from producer evidence",
            ],
            "missingUntilProofBuilder": ["proof-bundle r2 status=proofs-attached", "trusted ArchiveByteReader admission"],
            "normalizerRoute": {"kind": "frozen-v6-composed", "protectedSource": "factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/run-adapter-v6.py", "admission": "adapter-v12 strict r17 overlay/joins"},
        }
        validate_emitted_map(output)
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": output["status"], "count": 20, "inventoryFiles": len(inventory), "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
