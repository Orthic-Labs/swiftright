#!/usr/bin/env python3
"""Stage fresh compiler package metadata; never invokes SwiftPM or native code."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
from pathlib import Path
from typing import Any

MAX_JSON = 8 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024


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


def digest(path: Path, label: str, maximum: int = MAX_FILE) -> tuple[str, int]:
    if path.is_symlink() or not path.is_file():
        raise Hold(f"{label} must be regular")
    size = path.stat().st_size
    if size > maximum:
        raise Hold(f"{label} exceeds bound")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest(), size


def bare(value: Any, label: str) -> str:
    if not isinstance(value, str):
        raise Hold(f"{label} hash missing")
    result = value.removeprefix("sha256:").lower()
    if len(result) != 64 or any(c not in "0123456789abcdef" for c in result):
        raise Hold(f"{label} hash malformed")
    return result


def ref(value: Any, label: str) -> dict[str, str]:
    if not isinstance(value, dict) or not isinstance(value.get("id"), str) or not isinstance(value.get("hash"), str):
        raise Hold(f"{label} reference missing")
    return {"id": value["id"], "hash": value["hash"]}


def copy_tree(source: Path, destination: Path) -> tuple[int, int]:
    if not source.is_dir() or source.is_symlink() or destination.exists() or destination.is_symlink():
        raise Hold("source package must be directory & destination must be fresh")
    files = 0
    total = 0
    for root, dirs, names in os.walk(source, followlinks=False):
        root_path = Path(root)
        dirs[:] = [d for d in dirs if not (root_path / d).is_symlink()]
        for name in names:
            src = root_path / name
            if src.is_symlink() or not src.is_file():
                raise Hold(f"package contains unsupported entry: {src}")
            size = src.stat().st_size
            if size > MAX_FILE or total + size > MAX_TOTAL:
                raise Hold("package exceeds bounded staging size")
            rel = src.relative_to(source)
            dst = destination / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            files += 1
            total += size
    return files, total


def find_binding(plan: dict[str, Any], path: str) -> dict[str, Any]:
    for row in plan.get("sourceBindings", []):
        if isinstance(row, dict) and row.get("path") == path:
            return row
    raise Hold(f"source binding missing: {path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case-bindings", required=True, type=Path)
    parser.add_argument("--fresh-plan", required=True, type=Path)
    parser.add_argument("--source-package", required=True, type=Path)
    parser.add_argument("--output-package", required=True, type=Path)
    parser.add_argument("--scratch-path", required=True)
    parser.add_argument("--producer-root", required=True)
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--output-root", required=True)
    parser.add_argument("--compiler-path", required=True, type=Path)
    parser.add_argument("--renderer-path", required=True, type=Path)
    parser.add_argument("--output-receipt", required=True, type=Path)
    args = parser.parse_args()
    if args.output_receipt.exists() or args.output_receipt.is_symlink():
        raise SystemExit("HOLD: stage receipt must be fresh")
    try:
        bindings = read_json(args.case_bindings, "case bindings")
        plan = read_json(args.fresh_plan, "fresh materialized plan")
        if bindings.get("executionEligible") is not False or plan.get("executionEligible") is not False:
            raise Hold("fresh package remains execution-ineligible until root compile admission")
        fresh = ref(bindings.get("freshCase"), "bindings fresh case")
        if ref(plan.get("case"), "fresh plan case") != fresh:
            raise Hold("fresh plan case differs from bindings")
        candidate = plan.get("candidateTuple")
        if not isinstance(candidate, dict) or candidate.get("id") != bindings.get("candidateID"):
            raise Hold("fresh candidate tuple identity differs")
        if ref(plan.get("freshCaseReference"), "fresh case reference") != fresh:
            raise Hold("fresh case reference differs")
        issued_identity = plan.get("issuedMetadataIdentity")
        if not isinstance(issued_identity, dict) or ref(issued_identity.get("case"), "issued identity case") != fresh:
            raise Hold("fresh issued identity case differs")
        if plan.get("sourceHash") != bindings.get("sourceHash"):
            raise Hold("fresh plan source hash differs")
        source_package = args.source_package.resolve()
        output_package = args.output_package.resolve()
        if output_package == source_package or output_package.is_relative_to(source_package):
            raise Hold("fresh package must not overlap immutable source package")
        if not args.compiler_path.is_file() or args.compiler_path.is_symlink() or not args.renderer_path.is_file() or args.renderer_path.is_symlink():
            raise Hold("compiler/renderer regular files required")
        compiler_hash, compiler_bytes = digest(args.compiler_path, "compiler", 256 * 1024 * 1024)
        renderer_hash, renderer_bytes = digest(args.renderer_path, "renderer", 256 * 1024 * 1024)
        if compiler_hash != bare(plan.get("compilerHash"), "plan compiler"):
            raise Hold("current compiler differs from fresh plan")
        if renderer_hash != bare(plan.get("rendererSha256"), "plan renderer"):
            raise Hold("current renderer differs from fresh plan")
        files, total = copy_tree(source_package, output_package)
        staged_plan = copy.deepcopy(plan)
        request = staged_plan.get("compileRequest")
        if not isinstance(request, dict):
            raise Hold("fresh compile request missing")
        request["packagePath"] = str(output_package)
        request["scratchPath"] = args.scratch_path
        staged_plan["compilerPath"] = str(args.compiler_path)
        staged_plan["rendererPath"] = str(args.renderer_path)
        staged_plan["freshPackageRoot"] = str(output_package)
        staged_plan["freshCaseReference"] = fresh
        staged_plan["freshReplay"]["producerRoot"] = args.producer_root
        staged_plan["freshReplay"]["runRoot"] = args.run_root
        staged_plan["freshReplay"]["outputRoot"] = args.output_root
        staged_plan["compileCommand"] = {
            "toolPath": str(args.compiler_path),
            "workingDirectory": str(output_package),
            "argv": [
                "build", "--package-path", str(output_package), "--scratch-path", args.scratch_path,
                "-c", "release", "-Xlinker", "/MANIFEST:EMBED", "-Xlinker",
                "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'",
                "-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup",
            ],
            "pathPrefix": r"C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin",
            "compilerSha256": compiler_hash,
            "rendererSha256": renderer_hash,
            "nativeActions": 0,
            "expectedOutput": str(Path(args.scratch_path) / "out" / "Products" / "Release-windows-x86_64" / "FactoryProbe.exe"),
        }
        witness = find_binding(staged_plan, "Sources/FactoryProbe/Witness.swift")
        witness_hash, witness_bytes = digest(output_package / "Sources/FactoryProbe/Witness.swift", "Witness.swift")
        if witness_hash != bare(witness.get("sha256"), "Witness binding") or witness_hash != bare(staged_plan.get("sourceHash"), "plan source"):
            raise Hold("staged Witness bytes do not bind fresh source hash")
        for filename, field in (("runtime-source-receipt.json", "runtimeSourceReceiptHash"), ("runtime-source-tree.json", "runtimeSourceTreeFileHash")):
            actual, _ = digest(output_package / filename, filename)
            if actual != bare(staged_plan.get(field), field):
                raise Hold(f"staged {filename} hash mismatch")
        plan_path = output_package / "plan.json"
        plan_path.write_text(json.dumps(staged_plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        plan_hash, plan_bytes = digest(plan_path, "staged package plan", MAX_JSON)
        receipt = {
            "kind": "factory-padding-fresh-compile-package-stage-v1",
            "status": "staged-source-bound-compile-pending",
            "executionEligible": False,
            "packagePath": str(output_package),
            "planSha256": plan_hash,
            "planBytes": plan_bytes,
            "case": fresh,
            "candidateID": bindings.get("candidateID"),
            "sourceHash": witness_hash,
            "witness": {"path": str(output_package / "Sources/FactoryProbe/Witness.swift"), "sha256": witness_hash, "bytes": witness_bytes},
            "runtimeSourceCommit": staged_plan.get("runtimeSourceCommit"),
            "renderer": {"path": str(args.renderer_path), "sha256": renderer_hash, "bytes": renderer_bytes},
            "compiler": {"path": str(args.compiler_path), "sha256": compiler_hash, "bytes": compiler_bytes},
            "packageFiles": files,
            "packageBytes": total,
            "compileCommand": staged_plan["compileCommand"],
            "expectedOutput": staged_plan["compileCommand"]["expectedOutput"],
            "nativeActions": 0,
            "compilerActions": 0,
            "historicPlanUntouched": True,
        }
        args.output_receipt.parent.mkdir(parents=True, exist_ok=True)
        args.output_receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps({"status": receipt["status"], "case": fresh, "planSha256": plan_hash, "compilerActions": 0}, sort_keys=True))
        return 0
    except Exception as exc:
        if args.output_package.exists() and not args.output_receipt.exists():
            raise SystemExit("HOLD: staged package exists without receipt; preserve it for root review: " + str(exc)) from exc
        raise SystemExit("HOLD: " + str(exc)) from exc


if __name__ == "__main__":
    raise SystemExit(main())
