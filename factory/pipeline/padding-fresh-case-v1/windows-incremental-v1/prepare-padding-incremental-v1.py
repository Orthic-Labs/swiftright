#!/usr/bin/env python3
"""Prepare Padding reuse plan; never invokes compiler, native code, or locks.

Fresh case/tuple metadata comes from an external r3 package. Existing Windows
package, source, runtime, bridge, renderer, compiler, and GUI command stay
byte-bound. Reuse receipt remains pending root execution evidence.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import stat
from pathlib import Path
from typing import Any, Iterable

MAX_JSON = 8 * 1024 * 1024
MAX_REF = 64 * 1024 * 1024
MAX_OUTPUT = 2 * 1024 * 1024
ONE_GIB = 1024 * 1024 * 1024
JOB_MEMORY_FLAG = 0x200
JOB_HELPER_SHA256 = "112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e"


class Hold(ValueError):
    pass


def regular(path: Path, label: str, limit: int) -> os.stat_result:
    try:
        info = path.lstat()
    except OSError as exc:
        raise Hold(f"{label} unavailable: {path}") from exc
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise Hold(f"{label} must be regular & non-reparse: {path}")
    if info.st_size > limit:
        raise Hold(f"{label} exceeds {limit} bytes: {path}")
    return info


def stream_hash(path: Path, label: str, limit: int = MAX_REF) -> tuple[str, int]:
    info = regular(path, label, limit)
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise Hold(f"{label} grew beyond bound: {path}")
            digest.update(chunk)
    if total != info.st_size:
        raise Hold(f"{label} changed during read: {path}")
    return digest.hexdigest(), total


def load_json(path: Path, label: str) -> tuple[dict[str, Any], str, int]:
    digest, size = stream_hash(path, label, MAX_JSON)
    chunks: list[bytes] = []
    total = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_JSON:
                raise Hold(f"{label} grew beyond bound: {path}")
            chunks.append(chunk)
    if total != size:
        raise Hold(f"{label} changed during read: {path}")
    try:
        value = json.loads(b"".join(chunks).decode("utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON: {path}") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} must be JSON object: {path}")
    return value, digest, size


def bare(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise Hold(f"{label} hash missing")
    result = value.removeprefix("sha256:").lower()
    if len(result) != 64 or any(ch not in "0123456789abcdef" for ch in result):
        raise Hold(f"{label} hash malformed")
    return result


def write_json(path: Path, value: dict[str, Any]) -> tuple[str, int]:
    encoded = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if len(encoded) > MAX_OUTPUT:
        raise Hold(f"output JSON exceeds bound: {path}")
    if path.exists() or path.is_symlink():
        raise Hold(f"fresh output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(encoded)
    return hashlib.sha256(encoded).hexdigest(), len(encoded)


def path_value(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise Hold(f"{label} path missing")
    return value


def require_measured_argv(receipt: dict[str, Any]) -> str:
    argv = receipt.get("argv")
    if not isinstance(argv, str) or not argv.strip():
        raise Hold("measured donor receipt argv missing")
    text = argv
    required = ("/MANIFEST:EMBED", "/SUBSYSTEM:WINDOWS", "/ENTRY:mainCRTStartup")
    if any(token not in text for token in required):
        raise Hold("donor GUI linker flags incomplete")
    return argv


def resolve_ref(raw: str, root: Path | None, label: str) -> Path:
    candidate = Path(raw)
    if not candidate.is_absolute():
        if root is None:
            raise Hold(f"{label} needs explicit root")
        candidate = root / candidate
    return candidate


def verify_rows(rows: Any, root: Path, label: str) -> list[dict[str, Any]]:
    if not isinstance(rows, list) or not rows:
        raise Hold(f"{label} rows missing")
    seen: set[str] = set()
    measured: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            raise Hold(f"{label} row malformed")
        rel = row.get("path")
        if not isinstance(rel, str) or not rel or rel in seen:
            raise Hold(f"{label} duplicate/missing path")
        if Path(rel).is_absolute() or ".." in Path(rel).parts:
            raise Hold(f"{label} unsafe path: {rel}")
        seen.add(rel)
        actual, size = stream_hash(root / rel, f"{label} {rel}")
        if actual != bare(row.get("sha256"), f"{label} {rel}") or size != int(row.get("bytes", size)):
            raise Hold(f"{label} byte/hash drift: {rel}")
        measured.append({"path": rel, "sha256": actual, "bytes": size})
    return measured


def require_same(donor: dict[str, Any], fresh: dict[str, Any], field: str) -> Any:
    value = donor.get(field)
    if value is None or fresh.get(field) != value:
        raise Hold(f"fresh {field} differs from reusable donor")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--donor-package", required=True, type=Path)
    parser.add_argument("--donor-plan", required=True, type=Path)
    parser.add_argument("--donor-receipt", required=True, type=Path)
    parser.add_argument("--fresh-package", required=True, type=Path)
    parser.add_argument("--fresh-plan", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--windows-package-path", required=True)
    parser.add_argument("--windows-scratch-path", required=True)
    parser.add_argument("--compiler-path", required=True)
    parser.add_argument("--renderer-path", required=True)
    parser.add_argument("--job-helper-path", required=True, type=Path)
    parser.add_argument("--executable-path", required=True)
    parser.add_argument("--bridge-root", type=Path)
    parser.add_argument("--runtime-root", type=Path)
    args = parser.parse_args()
    try:
        donor_package = args.donor_package.resolve()
        donor_plan_path = args.donor_plan.resolve()
        fresh_package = args.fresh_package.resolve()
        fresh_plan_path = args.fresh_plan.resolve()
        output_root = args.output_root.resolve()
        for path in (donor_package, fresh_package):
            if not path.is_dir() or path.is_symlink():
                raise Hold(f"package root missing/non-directory: {path}")
        if donor_plan_path != donor_package / "plan.json":
            raise Hold("donor plan must be package/plan.json")
        if fresh_plan_path != fresh_package / "plan.json":
            raise Hold("fresh r3 plan must be package/plan.json")
        if output_root.exists() or output_root.is_symlink():
            raise Hold(f"fresh output collision: {output_root}")
        donor, donor_plan_hash, donor_plan_bytes = load_json(donor_plan_path, "donor plan")
        donor_receipt, donor_receipt_hash, donor_receipt_bytes = load_json(args.donor_receipt.resolve(), "donor measured receipt")
        if donor_receipt.get("kind") != "factory-padding-capture-lease-compile-only-owned-handle-v1":
            raise Hold("donor measured receipt kind drift")
        if donor_receipt.get("planSha256") != donor_plan_hash:
            raise Hold("donor measured receipt plan join drift")
        if donor_receipt.get("exitCode") != 0 or donor_receipt.get("timedOut") or not donor_receipt.get("ownedExited") or not donor_receipt.get("streamDrainComplete"):
            raise Hold("donor measured receipt terminal proof incomplete")
        fresh, fresh_plan_hash, fresh_plan_bytes = load_json(fresh_plan_path, "fresh r3 plan")
        donor_request = donor.get("compileRequest")
        if not isinstance(donor_request, dict):
            raise Hold("donor compileRequest missing")
        donor_package_path = path_value(donor_request.get("packagePath"), "donor packagePath")
        donor_scratch_path = path_value(donor_request.get("scratchPath"), "donor scratchPath")
        if donor_package_path != args.windows_package_path:
            raise Hold("operational package path must preserve donor absolute path")
        if donor_scratch_path != args.windows_scratch_path:
            raise Hold("operational scratch path must preserve donor absolute path")
        compile_argv = require_measured_argv(donor_receipt)
        for field in ("sourceHash", "runtimeSourceCommit", "runtimeSourceTreeHash", "rendererSha256", "compilerHash"):
            require_same(donor, fresh, field)
        source_rows = verify_rows(donor.get("sourceBindings"), donor_package, "donor sourceBindings")
        bridge_rows = verify_rows(donor.get("bridgeBindings"), args.bridge_root or donor_package, "donor bridgeBindings")
        runtime_source_rows = [
            row for row in source_rows
            if row["path"].replace("\\", "/") in ("runtime-source-receipt.json", "runtime-source-tree.json")
        ]
        if len(runtime_source_rows) < 2:
            raise Hold("donor runtime receipt/tree byte bindings incomplete")
        runtime_root = args.runtime_root or donor_package
        runtime_rows: list[dict[str, Any]] = []
        for field, label in (("runtimeSourceBindings", "donor runtimeSourceBindings"), ("runtimeBindings", "donor runtimeBindings")):
            if donor.get(field) is not None:
                runtime_rows = verify_rows(donor[field], runtime_root, label)
                break
        if not runtime_rows and not donor.get("runtimeSourceCommit"):
            raise Hold("runtime source closure missing")
        compiler_hash, compiler_bytes = stream_hash(Path(args.compiler_path), "Swift compiler", 256 * 1024 * 1024)
        renderer_hash, renderer_bytes = stream_hash(Path(args.renderer_path), "renderer", 256 * 1024 * 1024)
        helper_hash, helper_bytes = stream_hash(args.job_helper_path, "original-handle job helper")
        if compiler_hash != bare(donor.get("compilerHash"), "donor compiler"):
            raise Hold("compiler bytes differ from donor plan")
        if renderer_hash != bare(donor.get("rendererSha256"), "donor renderer"):
            raise Hold("renderer bytes differ from donor plan")
        if helper_hash != JOB_HELPER_SHA256:
            raise Hold("approved original-handle helper required")
        expected_output = args.executable_path
        donor_expected_output = donor.get("expectedOutput")
        if donor_expected_output is not None and donor_expected_output != expected_output:
            raise Hold("executable path differs from donor expectedOutput")
        exe_hash, exe_bytes = stream_hash(Path(args.executable_path), "existing Padding executable", 256 * 1024 * 1024)
        for field in ("exeSha256", "compiledExeSha256", "admittedExeSha256"):
            if donor.get(field) is not None and exe_hash != bare(donor[field], f"donor {field}"):
                raise Hold(f"existing executable differs from donor {field}")
        # Fresh plan supplies case/tuple/manifest identity. Donor supplies all
        # measured compiler/runtime/bridge/executable closure & GUI command.
        plan = copy.deepcopy(fresh)
        plan["kind"] = "windows-padding-incremental-reuse-plan-v1"
        plan["executionEligible"] = False
        plan["frozenTupleBound"] = False
        plan["compilerHash"] = donor["compilerHash"]
        plan["rendererSha256"] = donor["rendererSha256"]
        plan["runtimeSourceCommit"] = donor["runtimeSourceCommit"]
        plan["runtimeSourceTreeHash"] = donor["runtimeSourceTreeHash"]
        plan["expectedOutput"] = expected_output
        plan["rendererPath"] = donor.get("rendererPath") or donor.get("rendererLoadPath") or args.renderer_path
        plan["compilerPath"] = donor.get("compilerPath") or donor_request.get("compilerPath") or args.compiler_path
        plan["compileCommand"] = {"measuredArgv": compile_argv, "sourceReceipt": {"path": str(args.donor_receipt.resolve()), "sha256": donor_receipt_hash, "bytes": donor_receipt_bytes}}
        plan["compileRequest"] = copy.deepcopy(donor_request)
        plan["incrementalReuse"] = {
            "enabled": True,
            "compilerActions": 0,
            "sourcePlan": {"path": str(donor_plan_path), "sha256": donor_plan_hash, "bytes": donor_plan_bytes},
            "freshPlan": {"path": str(fresh_plan_path), "sha256": fresh_plan_hash, "bytes": fresh_plan_bytes},
            "existingExecutable": {"path": expected_output, "sha256": exe_hash, "bytes": exe_bytes},
            "freshOutputRootRequired": True,
        }
        plan["memoryBudget"] = {
            "bytes": ONE_GIB, "jobLimitFlags": JOB_MEMORY_FLAG,
            "killOnJobClose": False, "helperPath": str(args.job_helper_path),
            "helperSha256": helper_hash,
        }
        plan["sourceClosureMeasured"] = {
            "sourceBindings": source_rows, "bridgeBindings": bridge_rows,
            "runtimeReceiptTreeBindings": runtime_source_rows,
            "runtimeBindings": runtime_rows,
            "compiler": {"path": args.compiler_path, "sha256": compiler_hash, "bytes": compiler_bytes},
            "renderer": {"path": args.renderer_path, "sha256": renderer_hash, "bytes": renderer_bytes},
            "jobHelper": {"path": str(args.job_helper_path), "sha256": helper_hash, "bytes": helper_bytes},
        }
        plan_path = output_root / "plan.json"
        plan_hash, plan_bytes = write_json(plan_path, plan)
        receipt = {
            "schema": "factory-padding-windows-incremental-reuse-v1",
            "status": "source-bound-reuse-pending-root-observation",
            "executionEligible": False, "frozenTupleBound": False,
            "compilerActions": 0, "nativeActions": 0, "lockActions": 0,
            "plan": {"path": "plan.json", "sha256": plan_hash, "bytes": plan_bytes},
            "donorPlan": {"path": str(donor_plan_path), "sha256": donor_plan_hash, "bytes": donor_plan_bytes},
            "freshPlan": {"path": str(fresh_plan_path), "sha256": fresh_plan_hash, "bytes": fresh_plan_bytes},
            "windowsOperationalPaths": {
                "package": donor_package_path, "scratch": donor_scratch_path,
                "compiler": args.compiler_path, "renderer": args.renderer_path,
                "jobHelper": str(args.job_helper_path), "expectedOutput": expected_output,
            },
            "existingExecutable": {"path": expected_output, "sha256": exe_hash, "bytes": exe_bytes},
            "memoryBudget": plan["memoryBudget"],
            "lifecycle": {
                "originalHandleRetained": True, "boundedOutputDrain": True,
                "ownedTerminationOnly": True, "activeJobCountRequired": 0,
                "streamsSealedRequired": True,
            },
        }
        receipt_hash, receipt_bytes = write_json(output_root / "reuse-receipt.json", receipt)
        manifest = {
            "schema": "factory-padding-windows-incremental-source-v1",
            "status": "source-ready-pending-root-reuse-proof", "nativeActions": 0,
            "files": [
                {"path": "plan.json", "sha256": plan_hash, "bytes": plan_bytes},
                {"path": "reuse-receipt.json", "sha256": receipt_hash, "bytes": receipt_bytes},
            ],
            "donorPackagePath": donor_package_path,
            "donorScratchPath": donor_scratch_path,
            "freshPlanPath": str(fresh_plan_path),
            "freshInputRoot": str(fresh_package),
            "historicalPlanUntouched": True,
        }
        write_json(output_root / "source-manifest.json", manifest)
        print(json.dumps({"status": manifest["status"], "planSha256": plan_hash, "receiptSha256": receipt_hash, "compilerActions": 0, "nativeActions": 0}, separators=(",", ":")))
        return 0
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc


if __name__ == "__main__":
    raise SystemExit(main())
