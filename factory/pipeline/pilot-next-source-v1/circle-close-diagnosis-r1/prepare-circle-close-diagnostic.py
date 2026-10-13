#!/usr/bin/env python3
"""Create fresh Circle close-diagnostic package bytes from explicit frozen inputs."""
from __future__ import annotations

import argparse
import hashlib
import json
import stat
import zipfile
from pathlib import Path

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_FILES = 256
CHUNK = 1024 * 1024
DONOR_MAIN_SHA256 = "900b982ac3ee69bc61814fa60eab7df379feaec89e0d2ab0a862a0386cded6e7"
CANDIDATE_MAIN_SHA256 = "b761a826b249e7b918c6a25af8b3d9bccaced7005d1a35253fb3fd618a576a19"


def no_symlink_components(root: Path, path: Path) -> None:
    root = root.absolute()
    path = path.absolute()
    try:
        rel = path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path escapes root: {path}") from exc
    current = root
    for part in rel.parts:
        current /= part
        if current.is_symlink():
            raise ValueError(f"symlink component forbidden: {current}")


def regular(path: Path, limit: int) -> int:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return st.st_size


def digest(path: Path, limit: int = MAX_FILE) -> tuple[int, str]:
    size = regular(path, limit)
    h = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"streamed file exceeds bound: {path}")
            h.update(chunk)
    if total != size or path.lstat().st_size != size:
        raise ValueError(f"file changed during hash: {path}")
    return size, h.hexdigest()


def load_json(path: Path) -> dict:
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding="utf-8"))


def hash_value(value: object) -> str:
    return str(value).removeprefix("sha256:").lower()


def safe_relative(value: str) -> Path:
    path = Path(value)
    if (not value or "\\" in value or path.is_absolute() or ":" in value
            or any(part in ("", ".", "..") for part in path.parts)):
        raise ValueError(f"unsafe relative binding: {value}")
    return path


def copy_stream(source: Path, destination: Path, size: int) -> None:
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"fresh destination required: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    copied = 0
    with source.open("rb") as src, destination.open("xb") as dst:
        while chunk := src.read(CHUNK):
            copied += len(chunk)
            if copied > size:
                raise ValueError(f"copy exceeds admitted size: {source}")
            dst.write(chunk)
    if copied != size or source.lstat().st_size != size:
        raise ValueError(f"copy size drift: {source}")


def admit_candidate_main(path: Path, source: str, actual_hash: str) -> None:
    if actual_hash != CANDIDATE_MAIN_SHA256:
        raise ValueError("candidate main hash is not admitted diagnostic source")
    if source.count("func factoryCloseMarker(_ phase: String)") != 1:
        raise ValueError("close-marker function shape mismatch")
    if source.count("factoryCloseMarker(") != 13:
        raise ValueError("close-marker call count mismatch")
    required = (
        'factoryCloseMarker("window-closed-enter")',
        'factoryCloseMarker("before-graph-teardown")',
        'factoryCloseMarker("after-graph-teardown")',
        'factoryCloseMarker("before-measurer-release")',
        'factoryCloseMarker("after-measurer-release")',
        'factoryCloseMarker("before-shutdown-complete")',
        'factoryCloseMarker("after-shutdown-complete")',
        'factoryCloseMarker("shutdown-complete-threw")',
        'factoryCloseMarker("before-bridge-run")',
        'factoryCloseMarker("after-bridge-run")',
        'factoryCloseMarker("mainactor-return")',
        'factoryCloseMarker("before-process-exit")',
    )
    if any(source.count(token) != 1 for token in required):
        raise ValueError("required close marker missing or duplicated")
    if source.count("try bridge.run(title: \"Alchemist FactoryProbe\", width: 320, height: 240)") != 1:
        raise ValueError("Bridge.run admission anchor mismatch")
    if source.count("host.graph?.tearDown()") != 1 or source.count("host.measurer?.releaseAll()") != 1:
        raise ValueError("teardown admission anchor mismatch")
    if source.count("import SwiftRightBridge") != 1 or source.count("import SwiftRightRuntime") != 1:
        raise ValueError("protected import shape drift")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--donor-native-root", type=Path, required=True)
    ap.add_argument("--donor-plan", type=Path, required=True)
    ap.add_argument("--donor-witness-manifest", type=Path, required=True)
    ap.add_argument("--candidate-main", type=Path, required=True)
    ap.add_argument("--output-package", type=Path, required=True)
    ap.add_argument("--output-zip", type=Path, required=True)
    ap.add_argument("--output-plan", type=Path, required=True)
    ap.add_argument("--output-manifest", type=Path, required=True)
    ap.add_argument("--stage-root", default=r"D:\Claude\swiftright\.factory-work\hosts\circle-close-r1")
    args = ap.parse_args()

    donor_root = args.donor_native_root.absolute()
    donor_plan_path = args.donor_plan.absolute()
    donor_witness = args.donor_witness_manifest.absolute()
    candidate_main = args.candidate_main.absolute()
    output = args.output_package.absolute()
    archive = args.output_zip.absolute()
    output_plan = args.output_plan.absolute()
    output_manifest = args.output_manifest.absolute()
    for root, path in ((donor_root, donor_plan_path), (donor_witness.parent, donor_witness),
                       (candidate_main.parent, candidate_main)):
        no_symlink_components(root, path)

    if output.exists() or archive.exists() or output_plan.exists() or output_manifest.exists():
        raise ValueError("all outputs must be fresh")
    plan = load_json(donor_plan_path)
    if plan.get("kind") != "factory-circle-compiler-plan-v1" or plan.get("candidate") != "swiftui.circle.fixed.pilot-next":
        raise ValueError("exact Circle compiler plan required")
    rows = list(plan.get("sourceBindings", []))
    if not rows or len(rows) > MAX_FILES:
        raise ValueError("bounded source binding set required")
    witness_size, witness_hash = digest(donor_witness, MAX_FILE)
    donor_main_path = donor_root / "Sources" / "FactoryProbe" / "main.swift"
    no_symlink_components(donor_root, donor_main_path)
    _, donor_main_hash = digest(donor_main_path, MAX_FILE)
    if donor_main_hash != DONOR_MAIN_SHA256:
        raise ValueError("frozen donor main hash drift")
    candidate_size, candidate_hash = digest(candidate_main, MAX_FILE)
    output.mkdir(parents=True)

    seen: set[str] = set()
    staged_rows: list[dict] = []
    total = 0
    main_seen = False
    witness_seen = False
    for row in rows:
        rel = safe_relative(str(row.get("path", "")))
        key = rel.as_posix()
        if key in seen:
            raise ValueError(f"duplicate source binding: {key}")
        seen.add(key)
        if key == "Sources/FactoryProbe/main.swift":
            if hash_value(row.get("sha256", "")) != DONOR_MAIN_SHA256:
                raise ValueError("frozen donor main binding drift")
            source, size, actual = candidate_main, candidate_size, candidate_hash
            candidate_text = source.read_text(encoding="utf-8")
            admit_candidate_main(source, candidate_text, actual)
            main_seen = True
        elif key == "witness.manifest.json":
            source, size, actual = donor_witness, witness_size, witness_hash
            witness_seen = True
        else:
            source = donor_root / rel
            no_symlink_components(donor_root, source)
            size, actual = digest(source, MAX_FILE)
            expected = hash_value(row.get("sha256", ""))
            if expected != actual or ("bytes" in row and int(row["bytes"]) != size):
                raise ValueError(f"donor binding drift: {key}")
        total += size
        if total > MAX_TOTAL:
            raise ValueError("source binding total exceeds bound")
        destination = output / rel
        copy_stream(source, destination, size)
        staged_rows.append({"path": key, "bytes": size, "sha256": "sha256:" + actual})
    if not main_seen or not witness_seen:
        raise ValueError("main.swift & witness.manifest.json must be explicit bindings")

    fresh_plan = dict(plan)
    fresh_plan["phase"] = "prebuild"
    fresh_plan["case"] = None
    fresh_plan["tuple"] = None
    fresh_plan["expectedHostHash"] = None
    fresh_plan["predecessorPlanSha256"] = "sha256:" + digest(donor_plan_path, MAX_JSON)[1]
    fresh_plan["donorPlanSha256"] = "sha256:" + digest(donor_plan_path, MAX_JSON)[1]
    fresh_plan["manifestHash"] = "sha256:" + witness_hash
    fresh_plan["sourceBindings"] = staged_rows
    fresh_plan["compileRequest"] = dict(fresh_plan["compileRequest"])
    package_win = args.stage_root.rstrip("\\") + r"\package"
    scratch_win = package_win + r"\build-bound-r1\scratch"
    fresh_plan["compileRequest"]["packagePath"] = package_win
    fresh_plan["compileRequest"]["scratchPath"] = scratch_win
    plan_bytes = (json.dumps(fresh_plan, indent=2) + "\n").encode("utf-8")
    output_plan.parent.mkdir(parents=True, exist_ok=True)
    output_plan.write_bytes(plan_bytes)
    copy_stream(output_plan, output / "plan-prebuild-v2.json", len(plan_bytes))

    package_plan_hash = hashlib.sha256(plan_bytes).hexdigest()
    manifest = {
        "kind": "factory-circle-close-diagnostic-stage-v1",
        "status": "SOURCE_ONLY",
        "candidateAdmission": "hash-plus-structural-source-shape",
        "stageRoot": args.stage_root,
        "packageArchive": {"path": str(archive), "sha256": None},
        "plan": {"path": "package/plan-prebuild-v2.json", "sha256": package_plan_hash},
        "files": staged_rows + [{"path": "plan-prebuild-v2.json", "bytes": len(plan_bytes), "sha256": package_plan_hash}],
        "sourceLimits": {"files": MAX_FILES, "bytesPerFile": MAX_FILE, "bytesTotal": MAX_TOTAL},
        "effects": {"compilerActions": 0, "nativeActions": 0, "remoteActions": 0, "guiActions": 0, "lockActions": 0},
        "pins": {
            "runtimeCommit": fresh_plan["runtimeSourceCommit"],
            "runtimeSourceTreeHash": fresh_plan["runtimeSourceTreeHash"],
            "rendererSha256": fresh_plan["rendererSha256"],
            "compilerSha256": fresh_plan["compilerHash"],
            "compileJobs": 1,
            "maxFrontendThreads": 1,
            "compileMemoryCapBytes": 1073741824,
        },
    }
    if archive.parent.exists() is False:
        archive.parent.mkdir(parents=True, exist_ok=True)
    entries = 0
    archive_total = 0
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(output.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(output).as_posix()
            size = regular(path, MAX_FILE)
            entries += 1
            archive_total += size
            if entries > MAX_FILES or archive_total > MAX_TOTAL:
                raise ValueError("archive source bounds exceeded")
            zf.write(path, "package/" + rel)
    _, archive_hash = digest(archive, MAX_TOTAL)
    manifest["packageArchive"] = {"path": str(archive), "sha256": archive_hash}
    output_manifest.parent.mkdir(parents=True, exist_ok=True)
    output_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
