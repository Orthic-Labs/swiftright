#!/usr/bin/env python3
"""Source-only packer for Circle close-marker incremental diagnostic compile."""
from __future__ import annotations
import argparse, hashlib, json, stat, zipfile
from pathlib import Path

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 32 * 1024 * 1024
MAX_EXTERNAL_TOTAL = 256 * 1024 * 1024
MAX_FILES = 256
CHUNK = 1024 * 1024
DONOR_MAIN_SHA256 = "900b982ac3ee69bc61814fa60eab7df379feaec89e0d2ab0a862a0386cded6e7"
CANDIDATE_MAIN_SHA256 = "b761a826b249e7b918c6a25af8b3d9bccaced7005d1a35253fb3fd618a576a19"


def regular(path: Path, limit: int) -> int:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return st.st_size


def contained(root: Path, path: Path) -> None:
    root = root.absolute(); path = path.absolute()
    try:
        rel = path.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path escapes root: {path}") from exc
    cur = root
    for part in rel.parts:
        cur /= part
        if cur.is_symlink():
            raise ValueError(f"symlink component forbidden: {cur}")


def digest(path: Path, limit: int = MAX_FILE) -> tuple[int, str]:
    size = regular(path, limit)
    h = hashlib.sha256(); total = 0
    with path.open("rb") as src:
        while chunk := src.read(CHUNK):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"streamed file exceeds bound: {path}")
            h.update(chunk)
    if total != size or path.lstat().st_size != size:
        raise ValueError(f"file changed during hash: {path}")
    return size, h.hexdigest()


def load_json(path: Path) -> dict:
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding="utf-8-sig"))


def hvalue(value: object) -> str:
    return str(value).removeprefix("sha256:").lower()


def relpath(value: object) -> Path:
    text = str(value)
    p = Path(text)
    if (not text or "\\" in text or p.is_absolute() or ":" in text
            or any(part in ("", ".", "..") for part in p.parts)):
        raise ValueError(f"unsafe relative path: {text}")
    return p


def copy_verified(src: Path, dst: Path, size: int, total: list[int]) -> None:
    if dst.exists() or dst.is_symlink():
        raise ValueError(f"fresh destination required: {dst}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    copied = 0
    with src.open("rb") as inp, dst.open("xb") as out:
        while chunk := inp.read(CHUNK):
            copied += len(chunk); total[0] += len(chunk)
            if copied > size or total[0] > MAX_TOTAL:
                raise ValueError("bounded package copy exceeded")
            out.write(chunk)
    if copied != size or src.lstat().st_size != size:
        raise ValueError(f"copy size drift: {src}")


def candidate_shape(text: str, actual: str) -> None:
    if actual != CANDIDATE_MAIN_SHA256:
        raise ValueError("candidate main hash is not admitted")
    if text.count("func factoryCloseMarker(_ phase: String)") != 1:
        raise ValueError("marker function drift")
    if text.count("factoryCloseMarker(") != 13:
        raise ValueError("marker count drift")
    for token in (
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
    ):
        if text.count(token) != 1:
            raise ValueError(f"marker missing or duplicated: {token}")
    for token in ("import SwiftRightBridge", "import SwiftRightRuntime"):
        if text.count(token) != 1:
            raise ValueError(f"protected import drift: {token}")
    if text.count('try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)') != 1:
        raise ValueError("bridge dimensions drift")
    if text.count("host.graph?.tearDown()") != 1 or text.count("host.measurer?.releaseAll()") != 1:
        raise ValueError("teardown drift")


def verify_rows(root: Path, rows: list[dict], total_external: list[int], *, copy_root: Path | None = None,
                copy_total: list[int] | None = None) -> list[dict]:
    seen: set[str] = set(); out: list[dict] = []
    if not rows or len(rows) > MAX_FILES:
        raise ValueError("bounded source rows required")
    for row in rows:
        rel = relpath(row.get("path", "")); key = rel.as_posix()
        if key in seen:
            raise ValueError(f"duplicate binding: {key}")
        seen.add(key)
        source = root / rel
        contained(root, source)
        size, actual = digest(source)
        expected = hvalue(row.get("sha256", ""))
        if actual != expected or ("bytes" in row and int(row["bytes"]) != size):
            raise ValueError(f"binding drift: {key}")
        if copy_root is not None:
            assert copy_total is not None
            copy_verified(source, copy_root / rel, size, copy_total)
        total_external[0] += size
        if total_external[0] > MAX_EXTERNAL_TOTAL:
            raise ValueError("external source closure exceeds bound")
        out.append({"path": key, "bytes": size, "sha256": "sha256:" + actual})
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--donor-package", type=Path, required=True)
    ap.add_argument("--donor-plan", type=Path, required=True)
    ap.add_argument("--donor-runtime-root", type=Path, required=True)
    ap.add_argument("--donor-bridge-root", type=Path, required=True)
    ap.add_argument("--donor-compile-receipt", type=Path, required=True)
    ap.add_argument("--baseline-exe", type=Path, required=True)
    ap.add_argument("--candidate-main", type=Path, required=True)
    ap.add_argument("--output-package", type=Path, required=True)
    ap.add_argument("--output-plan", type=Path, required=True)
    ap.add_argument("--output-manifest", type=Path, required=True)
    ap.add_argument("--output-zip", type=Path, required=True)
    ap.add_argument("--stage-root", required=True)
    args = ap.parse_args()

    donor = args.donor_package.absolute(); plan_path = args.donor_plan.absolute()
    runtime = args.donor_runtime_root.absolute(); bridge = args.donor_bridge_root.absolute()
    receipt = args.donor_compile_receipt.absolute(); baseline_exe = args.baseline_exe.absolute()
    candidate = args.candidate_main.absolute(); output = args.output_package.absolute()
    output_plan = args.output_plan.absolute(); output_manifest = args.output_manifest.absolute(); archive = args.output_zip.absolute()
    for root, path in ((donor, plan_path), (runtime, runtime), (bridge, bridge),
                       (receipt.parent, receipt), (baseline_exe.parent, baseline_exe), (candidate.parent, candidate)):
        contained(root, path)
    if any(p.exists() for p in (output, output_plan, output_manifest, archive)):
        raise ValueError("all outputs must be fresh; no overwrite or delete")
    try:
        archive.relative_to(output)
    except ValueError:
        pass
    else:
        raise ValueError("archive must be outside package output")

    plan = load_json(plan_path)
    if plan.get("kind") != "factory-circle-compiler-plan-v1" or plan.get("candidate") != "swiftui.circle.fixed.pilot-next":
        raise ValueError("exact Circle donor plan required")
    if plan.get("phase") != "final" or plan.get("executionEligible") is not True:
        raise ValueError("donor must be measured final compile plan")
    donor_plan_size, donor_plan_sha = digest(plan_path, MAX_JSON)
    receipt_size, receipt_sha = digest(receipt, MAX_JSON)
    baseline_size, baseline_sha = digest(baseline_exe, MAX_FILE)
    expected_baseline = hvalue(plan.get("expectedHostHash", ""))
    if baseline_sha != expected_baseline:
        raise ValueError("baseline EXE hash does not match measured donor plan")
    donor_main = donor / "Sources" / "FactoryProbe" / "main.swift"
    contained(donor, donor_main); donor_main_size, donor_main_sha = digest(donor_main)
    if donor_main_sha != DONOR_MAIN_SHA256:
        raise ValueError("donor main hash drift")
    candidate_size, candidate_sha = digest(candidate)
    candidate_shape(candidate.read_text(encoding="utf-8"), candidate_sha)

    ext_total = [0]; package_total = [0]
    rows = verify_rows(donor, list(plan.get("sourceBindings", [])), ext_total)
    runtime_tree_path = donor / "runtime-source-tree.json"
    runtime_tree_size, runtime_tree_sha = digest(runtime_tree_path, MAX_JSON)
    if runtime_tree_sha != hvalue(plan.get("runtimeSourceTreeHash", "")):
        raise ValueError("runtime source tree manifest hash drift")
    runtime_tree = load_json(runtime_tree_path)
    if not isinstance(runtime_tree, list) or not runtime_tree:
        raise ValueError("runtime source tree rows required")
    runtime_receipt_path = donor / "runtime-source-receipt.json"
    runtime_receipt_size, runtime_receipt_sha = digest(runtime_receipt_path, MAX_JSON)
    if runtime_receipt_sha != hvalue(plan.get("runtimeSourceReceiptHash", "")):
        raise ValueError("runtime source receipt hash drift")
    verify_rows(runtime, runtime_tree, ext_total)
    verify_rows(bridge, list(plan.get("bridgeBindings", [])), ext_total)
    if not any(row["path"] == "Sources/FactoryProbe/main.swift" for row in rows):
        raise ValueError("main.swift binding missing")
    # Verify every donor package row again while copying; replacement is main.swift only.
    output.mkdir(parents=True)
    for row in rows:
        rel = Path(row["path"])
        src = candidate if rel.as_posix() == "Sources/FactoryProbe/main.swift" else donor / rel
        size, actual = digest(src)
        if rel.as_posix() == "Sources/FactoryProbe/main.swift" and actual != candidate_sha:
            raise ValueError("candidate source changed")
        copy_verified(src, output / rel, size, package_total)
    if package_total[0] > MAX_TOTAL:
        raise ValueError("package source copy exceeds 32MiB")

    diagnostic = output / "diagnostic"
    copy_verified(donor_main, diagnostic / "baseline-Sources-FactoryProbe-main.swift", donor_main_size, package_total)
    copy_verified(baseline_exe, diagnostic / "baseline-FactoryProbe.exe", baseline_size, package_total)
    copy_verified(receipt, diagnostic / "donor-compile-receipt.json", receipt_size, package_total)
    if package_total[0] > MAX_TOTAL:
        raise ValueError("diagnostic copy exceeds 32MiB")

    fresh = dict(plan)
    fresh["kind"] = "factory-circle-incremental-compile-plan-v1"
    fresh["candidate"] = "swiftui.circle.fixed.pilot-next.close-diagnostic-r1"
    fresh["phase"] = "prebuild"; fresh["case"] = None; fresh["tuple"] = None
    fresh["expectedHostHash"] = None; fresh["executionEligible"] = False
    fresh["predecessorPlanSha256"] = "sha256:" + donor_plan_sha
    fresh["donorPlanSha256"] = "sha256:" + donor_plan_sha
    # sourceHash retains donor witness semantics; candidate main is separate diagnostic binding.
    fresh_rows = []
    for row in rows:
        updated = dict(row)
        if row["path"] == "Sources/FactoryProbe/main.swift":
            updated["bytes"] = candidate_size; updated["sha256"] = "sha256:" + candidate_sha
        fresh_rows.append(updated)
    fresh["sourceBindings"] = fresh_rows
    fresh["compileRequest"] = dict(fresh["compileRequest"])
    package_win = args.stage_root.rstrip("\\") + r"\package"
    scratch_win = package_win + r"\build-bound-r1\scratch"
    fresh["compileRequest"]["packagePath"] = package_win; fresh["compileRequest"]["scratchPath"] = scratch_win
    fresh["diagnostic"] = {
        "status": "compile-only-diagnostic",
        "baselineMain": {"path": "diagnostic/baseline-Sources-FactoryProbe-main.swift", "bytes": donor_main_size, "sha256": "sha256:" + donor_main_sha},
        "baselineExecutable": {"path": "diagnostic/baseline-FactoryProbe.exe", "bytes": baseline_size, "sha256": "sha256:" + baseline_sha},
        "donorCompileReceipt": {"path": "diagnostic/donor-compile-receipt.json", "bytes": receipt_size, "sha256": "sha256:" + receipt_sha},
        "candidateMain": {"path": "Sources/FactoryProbe/main.swift", "bytes": candidate_size, "sha256": "sha256:" + candidate_sha},
        "transform": "main.swift-only-close-markers; no runtime/bridge/renderer/case/tuple mutation",
    }
    plan_bytes = (json.dumps(fresh, indent=2) + "\n").encode()
    output_plan.parent.mkdir(parents=True, exist_ok=True); output_plan.write_bytes(plan_bytes)
    copy_verified(output_plan, output / "plan-prebuild-v1.json", len(plan_bytes), package_total)

    files = []
    for path in sorted(output.rglob("*")):
        if path.is_file():
            size, sha = digest(path)
            files.append({"path": path.relative_to(output).as_posix(), "bytes": size, "sha256": "sha256:" + sha})
    if len(files) > MAX_FILES or sum(row["bytes"] for row in files) > MAX_TOTAL:
        raise ValueError("package archive exceeds bounded source limit")
    manifest = {
        "kind": "factory-circle-incremental-compile-stage-v1", "status": "SOURCE_ONLY",
        "stageRoot": args.stage_root, "files": files,
        "plan": {"path": "package/plan-prebuild-v1.json", "sha256": "sha256:" + next(row["sha256"] for row in files if row["path"] == "plan-prebuild-v1.json").removeprefix("sha256:")},
        "archive": {"path": str(archive), "sha256": None},
        "sourceLimits": {"files": MAX_FILES, "bytesPerFile": MAX_FILE, "bytesTotal": MAX_TOTAL},
        "effects": {"compilerActions": 0, "nativeActions": 0, "remoteActions": 0, "guiActions": 0, "lockActions": 0},
        "pins": {"donorPlanSha256": "sha256:" + donor_plan_sha, "candidateMainSha256": "sha256:" + candidate_sha,
                 "baselineExeSha256": "sha256:" + baseline_sha, "donorCompileReceiptSha256": "sha256:" + receipt_sha,
                 "runtimeCommit": fresh["runtimeSourceCommit"], "runtimeSourceTreeHash": fresh["runtimeSourceTreeHash"],
                 "rendererSha256": fresh["rendererSha256"], "compilerSha256": fresh["compilerHash"],
                 "maxParallelJobs": 1, "maxFrontendThreads": 1, "memoryCapBytes": 1073741824},
    }
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for row in files:
            zf.write(output / row["path"], "package/" + row["path"])
    _, archive_sha = digest(archive, MAX_FILE)
    manifest["archive"] = {"path": str(archive), "sha256": "sha256:" + archive_sha}
    output_manifest.parent.mkdir(parents=True, exist_ok=True); output_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
