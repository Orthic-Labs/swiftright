"""Prepare light centered custom Layout source packet for root compile staging.

Source-only: validates bounded package bytes, recipe-derived case joins, current
runtime/renderer tuple & complete source bindings. It performs no build/native
action & does not rewrite historical evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

MAX_FILES = 128
MAX_TOTAL = 16 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
CHUNK = 1024 * 1024
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RENDERER = "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
CASE_ID = "swiftui.custom-layout.recipe/case/b30ed0b185e8cb29"
CASE_HASH = "sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a"


class PreparationError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise PreparationError(message)


def digest(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        fail(f"unsafe/missing file: {path}")
    if path.stat().st_size > MAX_FILE:
        fail(f"file exceeds cap: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            h.update(chunk)
    return h.hexdigest()


def read_json(path: Path) -> dict:
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_FILE:
        fail(f"unsafe JSON input: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail(f"invalid JSON {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"JSON object required: {path}")
    return value


def bounded_files(package: Path) -> dict[str, Path]:
    if package.is_symlink() or not package.is_dir():
        fail(f"package directory missing: {package}")
    files: dict[str, Path] = {}
    total = 0
    for path in sorted(package.rglob("*")):
        if path.is_symlink():
            fail(f"symlink forbidden: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            fail(f"non-regular package entry: {path}")
        rel = path.relative_to(package).as_posix()
        if Path(rel).is_absolute() or ".." in Path(rel).parts:
            fail(f"unsafe package path: {rel}")
        size = path.stat().st_size
        if size > MAX_FILE:
            fail(f"package file exceeds cap: {rel}")
        total += size
        if len(files) + 1 > MAX_FILES or total > MAX_TOTAL:
            fail("package file/byte cap exceeded")
        files[rel] = path
    return files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[4]
    source = args.source_root or repo / "factory/pipeline/pilot-delivery-five-v1/stack-layout/custom-layout-host-v2/light-centered-delivery-v1/package"
    output = args.output or repo / "factory/pipeline/pilot-delivery-five-v1/root-execution/custom-layout-light-centered-compile-r1"
    if output.exists():
        fail(f"fresh output required: {output}")
    files = bounded_files(source)
    required = {"Package.swift", "case.json", "plan.json", "runtime-source-receipt.json", "runtime-source-tree.json", "witness.manifest.json"}
    if not required.issubset(files):
        fail(f"package schema missing: {sorted(required - set(files))}")
    plan = read_json(files["plan.json"])
    case = read_json(files["case.json"])
    if plan.get("kind") != "windows-custom-layout-lifecycle-source-plan" or plan.get("executionEligible") is not False or plan.get("nativeParity") != "hold":
        fail("source-only plan scope mismatch")
    if plan.get("environmentInputs", {}).get("colorScheme") != "light":
        fail("light color scheme join missing")
    if plan.get("hostCorrection", {}).get("kind") != "intrinsic-subtree-centering-v1":
        fail("intrinsic subtree centering adapter missing")
    if plan.get("runtimeSourceCommit") != RUNTIME or plan.get("rendererSha256") != RENDERER:
        fail("runtime/renderer tuple mismatch")
    if plan.get("case") != {"id": CASE_ID, "hash": CASE_HASH} or case.get("case") != plan["case"]:
        fail("recipe-derived case join mismatch")
    if plan.get("tuple", {}).get("abiVersion") != "0.6":
        fail("renderer ABI tuple mismatch")
    bindings = plan.get("sourceBindings")
    if not isinstance(bindings, list) or not bindings:
        fail("complete source bindings missing")
    seen: set[str] = set()
    for row in bindings:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str) or row["path"] in seen:
            fail("duplicate/malformed source binding")
        rel = row["path"]
        if rel not in files or Path(rel).is_absolute() or ".." in Path(rel).parts:
            fail(f"source binding path invalid: {rel}")
        path = files[rel]
        measured = digest(path)
        if row.get("bytes") != path.stat().st_size or row.get("sha256") != "sha256:" + measured:
            fail(f"source binding drift: {rel}")
        seen.add(rel)
    expected_sources = {rel for rel in files if rel == "Package.swift" or rel.startswith("Sources/") or rel in {"case.json", "witness.manifest.json"}}
    if seen != expected_sources:
        fail("source bindings do not cover exact package source set")
    out_package = output / "package"
    out_package.mkdir(parents=True)
    for rel, path in files.items():
        target = out_package / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    rows = [{"path": rel, "bytes": path.stat().st_size, "sha256": "sha256:" + digest(path)} for rel, path in sorted(files.items())]
    (output / "source-manifest.json").write_text(json.dumps({"kind": "factory-custom-layout-light-centered-source-manifest-v1", "files": rows, "nativeActions": 0, "compilerActions": 0}, indent=2) + "\n")
    preparation = {"kind": "factory-custom-layout-light-centered-preparation-v1", "status": "SOURCE_READY_ROOT_COMPILE_REQUEST", "sourceRoot": str(source), "packagePath": str(out_package), "planSha256": digest(files["plan.json"]), "case": plan["case"], "runtimeSourceCommit": RUNTIME, "rendererSha256": RENDERER, "rendererABI": "0.6", "sourceBindings": len(bindings), "nativeActions": 0, "compilerActions": 0, "memoryCapBytes": MAX_TOTAL, "qualification": "pending-root-compile-and-native-count1"}
    (output / "preparation.json").write_text(json.dumps(preparation, indent=2) + "\n")
    print(json.dumps(preparation, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreparationError as exc:
        raise SystemExit(f"preparation failed: {exc}")
