#!/usr/bin/env python3
"""Stage fresh Padding Windows compile inputs; never invokes compiler or native code."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import stat
from pathlib import Path
from typing import Any

MAX_JSON = 8 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_FILES = 256
ONE_GIB = 1024 * 1024 * 1024
JOB_MEMORY_FLAG = 0x200
JOB_HELPER_SHA256 = "112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e"


class Hold(ValueError):
    pass


def regular(path: Path, label: str) -> os.stat_result:
    try:
        info = path.lstat()
    except OSError as exc:
        raise Hold(f"{label} unavailable") from exc
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise Hold(f"{label} must be regular & non-reparse")
    return info


def digest(path: Path, label: str, limit: int = MAX_FILE) -> tuple[str, int]:
    info = regular(path, label)
    if info.st_size > limit:
        raise Hold(f"{label} exceeds {limit} bytes")
    total = 0
    result = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise Hold(f"{label} grew beyond bound")
            result.update(chunk)
    if total != info.st_size:
        raise Hold(f"{label} changed during read")
    return result.hexdigest(), total


def bounded_bytes(path: Path, label: str, limit: int) -> bytes:
    info = regular(path, label)
    if info.st_size > limit:
        raise Hold(f"{label} exceeds {limit} bytes")
    chunks: list[bytes] = []
    total = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise Hold(f"{label} grew beyond bound")
            chunks.append(chunk)
    if total != info.st_size:
        raise Hold(f"{label} changed during read")
    return b"".join(chunks)


def load_json(path: Path, label: str, limit: int = MAX_JSON) -> dict[str, Any]:
    try:
        value = json.loads(bounded_bytes(path, label, limit).decode("utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} object required")
    return value


def write_json(path: Path, value: dict[str, Any]) -> tuple[str, int]:
    encoded = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if len(encoded) > MAX_JSON:
        raise Hold(f"{path} JSON exceeds bound")
    if path.exists() or path.is_symlink():
        raise Hold(f"fresh output exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encoded)
    return hashlib.sha256(encoded).hexdigest(), len(encoded)


def bare(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise Hold(f"{label} hash missing")
    result = value.removeprefix("sha256:").lower()
    if len(result) != 64 or any(ch not in "0123456789abcdef" for ch in result):
        raise Hold(f"{label} hash malformed")
    return result


def canonical_hash(value: Any) -> str:
    """Hash canonical artifact identity separately from raw JSON file bytes."""
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def copy_package(source: Path, destination: Path) -> tuple[int, int]:
    regular(source, "source package") if source.is_file() else None
    if not source.is_dir() or source.is_symlink() or destination.exists() or destination.is_symlink():
        raise Hold("source package must be directory & destination must be fresh")
    destination.mkdir(parents=True)
    files = 0
    total = 0
    for root, dirs, names in os.walk(source, followlinks=False):
        root_path = Path(root)
        kept_dirs: list[str] = []
        for name in dirs:
            child = root_path / name
            if child.is_symlink():
                raise Hold(f"package symlink: {child}")
            kept_dirs.append(name)
        dirs[:] = kept_dirs
        for name in names:
            src = root_path / name
            info = regular(src, "package file")
            rel = src.relative_to(source)
            # Donor plan is measured input only. A fresh plan is written after
            # all new case/compiler/runtime joins; copying donor plan would
            # collide with that exclusive publication.
            if rel.as_posix() == "plan.json":
                continue
            if info.st_size > MAX_FILE or total + info.st_size > MAX_TOTAL:
                raise Hold("package exceeds bounded staging limit")
            if files >= MAX_FILES:
                raise Hold("package file count exceeds bound")
            dst = destination / src.relative_to(source)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            copied_hash, copied_bytes = digest(dst, "copied package file")
            source_hash, source_bytes = digest(src, "source package file")
            if (copied_hash, copied_bytes) != (source_hash, source_bytes):
                raise Hold(f"package copy drift: {src}")
            files += 1
            total += info.st_size
    return files, total


def metadata_ref(path: Path, label: str, destination: Path) -> dict[str, Any]:
    digest_value, size = digest(path, label, MAX_JSON)
    dst = destination / "fresh-inputs" / path.name
    if dst.exists() or dst.is_symlink():
        raise Hold(f"metadata destination collision: {dst}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, dst)
    copied, copied_size = digest(dst, f"copied {label}", MAX_JSON)
    if (copied, copied_size) != (digest_value, size):
        raise Hold(f"metadata copy drift: {label}")
    return {"path": f"fresh-inputs/{path.name}", "sha256": digest_value, "bytes": size}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-package", required=True, type=Path)
    parser.add_argument("--case", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--tuple", required=True, type=Path)
    parser.add_argument("--output-package", required=True, type=Path)
    parser.add_argument("--compiler-path", required=True, type=Path)
    parser.add_argument("--renderer-path", required=True, type=Path)
    parser.add_argument("--job-helper-path", required=True, type=Path)
    parser.add_argument("--windows-package-path", required=True)
    parser.add_argument("--windows-scratch-path", required=True)
    parser.add_argument("--windows-compiler-path", required=True)
    parser.add_argument("--windows-renderer-path", required=True)
    parser.add_argument("--windows-job-helper-path", required=True)
    parser.add_argument("--output-receipt", required=True, type=Path)
    args = parser.parse_args()
    try:
        source_package = args.source_package.resolve()
        output_package = args.output_package.resolve()
        if output_package == source_package or source_package in output_package.parents:
            raise Hold("fresh package must not overlap source package")
        case = load_json(args.case, "fresh case")
        manifest = load_json(args.manifest, "fresh manifest")
        tuple_doc = load_json(args.tuple, "fresh tuple")
        tuple_value = tuple_doc.get("tuple")
        if not isinstance(tuple_value, dict):
            raise Hold("fresh tuple tuple object missing")
        if manifest.get("executionEligible") is not True or manifest.get("kind") != "generated-probe":
            raise Hold("fresh manifest must be final generated probe")
        case_identity_hash = "sha256:" + canonical_hash(case)
        case_raw_hash, case_raw_bytes = digest(args.case, "fresh case", MAX_JSON)
        if manifest.get("case", {}).get("id") != case.get("id") or manifest.get("case", {}).get("hash") != case_identity_hash:
            raise Hold("manifest/case canonical identity drift")
        if tuple_doc.get("case", {}).get("id") != case.get("id") or tuple_doc.get("case", {}).get("hash") != manifest["case"]["hash"]:
            raise Hold("tuple/case identity drift")
        if tuple_value.get("id") != tuple_doc.get("candidateID"):
            raise Hold("candidate tuple identity drift")
        source_hash = bare(manifest.get("sourceHash"), "manifest source")
        tuple_renderer = bare(tuple_value.get("rendererHash"), "tuple renderer")
        tuple_mac = bare(tuple_value.get("hostHashes", {}).get("macos"), "tuple Mac host")
        tuple_win = bare(tuple_value.get("hostHashes", {}).get("windows"), "tuple Windows host")
        runtime = tuple_value.get("runtimeCommit")
        if not isinstance(runtime, str) or len(runtime) != 40 or any(ch not in "0123456789abcdef" for ch in runtime.lower()):
            raise Hold("runtime commit malformed")
        if not isinstance(manifest.get("witness", {}).get("sourceHash"), str) or bare(manifest["witness"]["sourceHash"], "manifest witness") != source_hash:
            raise Hold("manifest witness/source drift")
        source_plan = load_json(source_package / "plan.json", "source plan")
        if bare(source_plan.get("sourceHash"), "source plan source") != source_hash:
            raise Hold("source package witness hash differs")
        witness_hash, witness_bytes = digest(source_package / "Sources/FactoryProbe/Witness.swift", "source witness")
        if witness_hash != source_hash:
            raise Hold("source witness bytes differ")
        compiler_hash, compiler_bytes = digest(args.compiler_path, "Swift compiler", 256 * 1024 * 1024)
        renderer_hash, renderer_bytes = digest(args.renderer_path, "renderer", 256 * 1024 * 1024)
        helper_hash, helper_bytes = digest(args.job_helper_path, "job helper", MAX_FILE)
        if helper_hash != JOB_HELPER_SHA256:
            raise Hold("approved original-handle job helper required")
        if bare(source_plan.get("compilerHash"), "source plan compiler") != compiler_hash:
            raise Hold("compiler bytes differ from measured source plan")
        if bare(source_plan.get("rendererSha256"), "source plan renderer") != tuple_renderer or renderer_hash != tuple_renderer:
            raise Hold("renderer bytes differ from fresh tuple")
        if source_plan.get("runtimeSourceCommit") != runtime:
            raise Hold("runtime source commit differs from fresh tuple")
        files, total = copy_package(source_package, output_package)
        fresh_refs = {
            "case": metadata_ref(args.case, "fresh case", output_package),
            "manifest": metadata_ref(args.manifest, "fresh manifest", output_package),
            "tuple": metadata_ref(args.tuple, "fresh tuple", output_package),
        }
        if fresh_refs["case"]["sha256"] != case_raw_hash or fresh_refs["case"]["bytes"] != case_raw_bytes:
            raise Hold("fresh case raw reference drift")
        plan = copy.deepcopy(source_plan)
        old_plan_hash, old_plan_bytes = digest(source_package / "plan.json", "source plan")
        plan.update({
            "kind": "windows-padding-fresh-compile-plan-v1",
            "case": manifest["case"],
            "caseInputs": manifest.get("caseInputs", {}),
            "manifestHash": manifest["case"]["hash"],
            "sourceHash": "sha256:" + source_hash,
            "candidateID": tuple_doc["candidateID"],
            "expectedHostHashes": {"macos": "sha256:" + tuple_mac, "windows": "sha256:" + tuple_win},
            "runtimeSourceCommit": runtime,
            "rendererSha256": tuple_renderer,
            "compilerPath": args.windows_compiler_path,
            "compilerHash": compiler_hash,
            "rendererPath": args.windows_renderer_path,
            "executionEligible": False,
            "frozenTupleBound": False,
            "hostMode": "renderer",
            "freshInputRefs": fresh_refs,
            "measuredSourceEvidence": {
                "compiler": {"path": str(args.compiler_path), "sha256": compiler_hash, "bytes": compiler_bytes},
                "renderer": {"path": str(args.renderer_path), "sha256": renderer_hash, "bytes": renderer_bytes},
                "jobHelper": {"path": str(args.job_helper_path), "sha256": helper_hash, "bytes": helper_bytes},
            },
            "windowsOperationalPaths": {
                "package": args.windows_package_path,
                "scratch": args.windows_scratch_path,
                "compiler": args.windows_compiler_path,
                "renderer": args.windows_renderer_path,
                "jobHelper": args.windows_job_helper_path,
            },
            "historicalSourcePlan": {"sha256": old_plan_hash, "bytes": old_plan_bytes},
            "memoryBudget": {
                "bytes": ONE_GIB,
                "jobLimitFlags": JOB_MEMORY_FLAG,
                "killOnJobClose": False,
                "helperPath": args.windows_job_helper_path,
                "helperSha256": helper_hash,
            },
        })
        request = plan.get("compileRequest")
        if not isinstance(request, dict):
            raise Hold("source compile request missing")
        request.update({
            "packagePath": args.windows_package_path,
            "scratchPath": args.windows_scratch_path,
            "compilerPath": args.windows_compiler_path,
            "jobHelperPath": args.windows_job_helper_path,
            "configuration": "release",
            "target": "windows-x86_64",
            "jobs": 1,
            "maxFrontendThreads": 1,
        })
        plan["expectedOutput"] = args.windows_scratch_path.rstrip("\\/") + r"\out\Products\Release-windows-x86_64\FactoryProbe.exe"
        plan["compileCommand"] = {
            "toolPath": args.windows_compiler_path,
            "workingDirectory": args.windows_package_path,
            "argv": [
                "build", "--package-path", args.windows_package_path,
                "--scratch-path", args.windows_scratch_path, "-c", "release",
                "-j", "1", "-Xswiftc", "-num-threads", "-Xswiftc", "1",
                "-Xlinker", "/MANIFEST:EMBED",
                "-Xlinker", "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'",
                "-Xlinker", "/SUBSYSTEM:WINDOWS",
                "-Xlinker", "/ENTRY:mainCRTStartup",
            ],
            "compilerSha256": compiler_hash,
            "rendererSha256": tuple_renderer,
            "nativeActions": 0,
        }
        plan_path = output_package / "plan.json"
        plan_hash, plan_bytes = write_json(plan_path, plan)
        receipt = {
            "schema": "factory-padding-fresh-windows-compile-stage-v1",
            "status": "staged-source-bound-compile-pending",
            "executionEligible": False,
            "packagePath": args.windows_package_path,
            "windowsScratchPath": args.windows_scratch_path,
            "plan": {"path": "plan.json", "sha256": plan_hash, "bytes": plan_bytes},
            "freshInputRefs": fresh_refs,
            "measuredSourceEvidence": {
                "compiler": {"path": str(args.compiler_path), "sha256": compiler_hash, "bytes": compiler_bytes},
                "renderer": {"path": str(args.renderer_path), "sha256": renderer_hash, "bytes": renderer_bytes},
                "jobHelper": {"path": str(args.job_helper_path), "sha256": helper_hash, "bytes": helper_bytes},
            },
            "windowsOperationalPaths": {
                "package": args.windows_package_path,
                "scratch": args.windows_scratch_path,
                "compiler": args.windows_compiler_path,
                "renderer": args.windows_renderer_path,
                "jobHelper": args.windows_job_helper_path,
            },
            "case": manifest["case"],
            "candidateID": tuple_doc["candidateID"],
            "expectedHostHashes": {"macos": "sha256:" + tuple_mac, "windows": "sha256:" + tuple_win},
            "source": {"sha256": source_hash, "bytes": witness_bytes},
            "runtimeSourceCommit": runtime,
            "renderer": {"sha256": renderer_hash, "bytes": renderer_bytes},
            "compiler": {"sha256": compiler_hash, "bytes": compiler_bytes},
            "jobHelper": {"sha256": helper_hash, "bytes": helper_bytes, "memoryBytes": ONE_GIB, "jobLimitFlags": JOB_MEMORY_FLAG, "killOnJobClose": False},
            "packageFiles": files + 4,
            "packageBytes": total,
            "compileCommand": plan["compileCommand"],
            "expectedOutput": plan["expectedOutput"],
            "windowsCompilerPath": args.windows_compiler_path,
            "windowsRendererPath": args.windows_renderer_path,
            "windowsJobHelperPath": args.windows_job_helper_path,
            "nativeActions": 0,
            "lockActions": 0,
            "compilerActions": 0,
            "historicalPlanUntouched": True,
        }
        write_json(args.output_receipt, receipt)
        print(json.dumps({"status": receipt["status"], "planSha256": plan_hash, "compilerActions": 0}, sort_keys=True))
        return 0
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc


if __name__ == "__main__":
    raise SystemExit(main())
