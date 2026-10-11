#!/usr/bin/env python3
"""Guarded internal-disk single-pass Mac release pair for frozen copy-cost packet."""
from __future__ import annotations
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import signal
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "factory/runtime-additions/copy-cost-macos-candidate-v1"
PLAN_PATH = REPO / "factory/runtime-additions/copy-cost-windows-candidate-v1/packet/source-plan.json"
PLAN_SHA = "46e039abb7463e479b424abcfd5bd4ee2aedbb88a31957fe65365435c9c37e09"
CACHE_BASE = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory")
RUN_ROOT = CACHE_BASE / "copy-cost-macos-candidate-v1"
EXPECTED_INTERNAL_DEVICE = 16777232
D_DEVICE = 16777248
TIMEOUT_SECONDS = 900


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def run_capture(argv: list[str], *, cwd: Path | None = None, env=None, timeout=30) -> dict:
    p = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       timeout=timeout, check=False)
    return {"argv": argv, "cwd": str(cwd) if cwd else None, "exitCode": p.returncode,
            "stdout": p.stdout.decode("utf-8", "replace"), "stderr": p.stderr.decode("utf-8", "replace"),
            "stdoutSha256": sha(p.stdout), "stderrSha256": sha(p.stderr)}


def assert_internal(path: Path, *, allow_missing_leaf=False) -> tuple[Path, int]:
    resolved = path.resolve(strict=not allow_missing_leaf)
    base = CACHE_BASE.resolve(strict=True)
    if resolved != base and base not in resolved.parents:
        raise RuntimeError(f"path escaped fixed internal cache: {path} -> {resolved}")
    device = (resolved if resolved.exists() else resolved.parent).stat().st_dev
    if device != EXPECTED_INTERNAL_DEVICE or device == D_DEVICE:
        raise RuntimeError(f"internal disk identity mismatch for {resolved}: {device}")
    return resolved, device


def validate_plan() -> tuple[dict, bytes]:
    raw = PLAN_PATH.read_bytes()
    if sha(raw) != PLAN_SHA:
        raise RuntimeError("frozen Windows source plan hash mismatch")
    plan = json.loads(raw)
    if plan.get("commonPins", {}).get("order") != ["current", "candidate"]:
        raise RuntimeError("source plan order differs")
    common = plan["commonPins"]
    if (common.get("configuration") != "release" or common.get("fullSuite") is not True or
        common.get("sourceTestMethodCount") != 175 or common.get("eachVariantExactlyOnce") is not True or
        common.get("retries") != 0):
        raise RuntimeError("source plan does not bind required full release pair")
    variants = {v["name"]: v for v in plan["variants"]}
    if set(variants) != {"current", "candidate"}:
        raise RuntimeError("source plan variant set differs")
    for name in ("current", "candidate"):
        v = variants[name]
        bindings = v["bindings"]
        canon = json.dumps(bindings, sort_keys=True, separators=(",", ":")).encode()
        if len(bindings) != 52 or v.get("packageFileCount") != 52 or sha(canon) != v.get("bindingsSha256"):
            raise RuntimeError(f"source-plan bindings invalid for {name}")
        paths = [b["path"] for b in bindings]
        if len(paths) != len(set(paths)):
            raise RuntimeError(f"duplicate source path in {name}")
        root = (REPO / v["localRoot"]).resolve(strict=True)
        for binding in bindings:
            rel = PurePosixPath(binding["path"])
            if rel.is_absolute() or ".." in rel.parts:
                raise RuntimeError(f"unsafe source path: {rel}")
            src = root.joinpath(*rel.parts)
            if src.is_symlink() or not src.is_file():
                raise RuntimeError(f"missing/non-regular source file: {src}")
            data = src.read_bytes()
            if len(data) != binding["bytes"] or sha(data) != binding["sha256"]:
                raise RuntimeError(f"source binding mismatch: {name}/{rel}")
        actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()}
        if actual != set(paths):
            raise RuntimeError(f"source tree file set differs for {name}: missing={set(paths)-actual}, extra={actual-set(paths)}")
    if plan.get("onlySourceDifference") != "Sources/SwiftRightRuntime/Graph.swift":
        raise RuntimeError("source plan only-source-difference assertion differs")
    return plan, raw


def tool_info() -> dict:
    names = ["swift", "swiftc", "swift-frontend"]
    tools = {}
    for name in names:
        p = Path(subprocess.check_output(["/usr/bin/xcrun", "--find", name], text=True).strip())
        resolved = p.resolve(strict=True)
        tools[name] = {"reportedPath": str(p), "resolvedPath": str(resolved), "sha256": file_sha(resolved),
                       "bytes": resolved.stat().st_size, "device": resolved.stat().st_dev}
    for command in (["/usr/bin/swift", "--version"], ["/usr/bin/xcrun", "swiftc", "-version"],
                    ["/usr/bin/xcodebuild", "-version"], ["/usr/bin/xcrun", "swift", "-print-target-info"]):
        tools.setdefault("versionCommands", []).append(run_capture(list(command), timeout=30))
    tools["developerDirectory"] = run_capture(["/usr/bin/xcode-select", "-p"])
    tools["host"] = {"system": platform.platform(), "machine": platform.machine(), "uname": list(os.uname())}
    return tools


def copy_variant(v: dict, root: Path) -> dict:
    dest = root / "packages" / v["name"]
    dest.mkdir(parents=True, exist_ok=False)
    source_root = (REPO / v["localRoot"]).resolve(strict=True)
    rows = []
    for b in v["bindings"]:
        src = source_root / b["path"]
        dst = dest / b["path"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        if dst.is_symlink() or dst.stat().st_dev != EXPECTED_INTERNAL_DEVICE or file_sha(dst) != b["sha256"] or dst.stat().st_size != b["bytes"]:
            raise RuntimeError(f"internal copy verification failed: {v['name']}/{b['path']}")
        rows.append({"path": b["path"], "bytes": dst.stat().st_size, "sha256": file_sha(dst)})
    if len(rows) != 52:
        raise RuntimeError("copied package count mismatch")
    return {"name": v["name"], "sourceRoot": str(source_root), "destination": str(dest.resolve()),
            "destinationDevice": dest.stat().st_dev, "files": rows}


def execute_variant(name: str, root: Path) -> dict:
    package = root / "packages" / name
    scratch = root / "scratch" / name
    tmpdir = root / "tmp" / name
    scratch.mkdir(parents=True, exist_ok=False)
    tmpdir.mkdir(parents=True, exist_ok=False)
    for p in (package, scratch, tmpdir):
        resolved, dev = assert_internal(p)
        if dev != EXPECTED_INTERNAL_DEVICE:
            raise RuntimeError(f"unexpected device before compiler invocation: {resolved} {dev}")
    argv = ["/usr/bin/swift", "test", "--package-path", str(package), "--scratch-path", str(scratch), "-c", "release"]
    env = os.environ.copy()
    env.update({"TMPDIR": str(tmpdir), "TMP": str(tmpdir), "TEMP": str(tmpdir), "SWIFTPM_BUILD_DIR": str(scratch)})
    for k in ("SWIFT_EXEC", "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC", "SWIFT_USE_INTEGRATED_DRIVER"):
        env.pop(k, None)
    started = utc()
    started_epoch = time.monotonic()
    out_path = OUT / "evidence" / f"{name}.stdout.bin"
    err_path = OUT / "evidence" / f"{name}.stderr.bin"
    timed_out = False
    with out_path.open("wb") as stdout, err_path.open("wb") as stderr:
        proc = subprocess.Popen(argv, cwd=package, env=env, stdout=stdout, stderr=stderr,
                                start_new_session=True, close_fds=True)
        pid = proc.pid
        try:
            exit_code = proc.wait(timeout=TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                exit_code = proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                exit_code = proc.wait(timeout=10)
    duration = time.monotonic() - started_epoch
    # Source mutation check after build/test; build products stay under scratch.
    post = []
    for b in next(v for v in PLAN["variants"] if v["name"] == name)["bindings"]:
        p = package / b["path"]
        post.append({"path": b["path"], "bytes": p.stat().st_size, "sha256": file_sha(p)})
    if any(r["sha256"] != b["sha256"] or r["bytes"] != b["bytes"] for r, b in zip(post, next(v for v in PLAN["variants"] if v["name"] == name)["bindings"])):
        raise RuntimeError(f"source mutated during test: {name}")
    return {"variant": name, "argv": argv, "cwd": str(package.resolve()), "pid": pid,
            "startedUtc": started, "finishedUtc": utc(), "durationSeconds": round(duration, 6),
            "timeoutSeconds": TIMEOUT_SECONDS, "timedOut": timed_out, "exitCode": exit_code,
            "scratch": str(scratch.resolve()), "scratchDevice": scratch.stat().st_dev,
            "tmpdir": str(tmpdir.resolve()), "tmpdirDevice": tmpdir.stat().st_dev,
            "stdout": {"path": str(out_path.relative_to(REPO)), "bytes": out_path.stat().st_size, "sha256": file_sha(out_path)},
            "stderr": {"path": str(err_path.relative_to(REPO)), "bytes": err_path.stat().st_size, "sha256": file_sha(err_path)},
            "sourcePost": post}


def main() -> int:
    global PLAN
    OUT.mkdir(parents=True, exist_ok=True)
    evidence = OUT / "evidence"
    evidence.mkdir(exist_ok=True)
    # Validate storage before copying and, critically, before launching any compiler process.
    base, dev = assert_internal(CACHE_BASE)
    if dev != EXPECTED_INTERNAL_DEVICE or D_DEVICE == dev:
        raise RuntimeError("trusted internal cache device guard failed")
    if RUN_ROOT.exists():
        raise RuntimeError(f"fresh run root already exists; refusing reuse: {RUN_ROOT}")
    PLAN, plan_bytes = validate_plan()
    (evidence / "source-plan.json").write_bytes(plan_bytes)
    tool_before = tool_info()
    RUN_ROOT.mkdir(parents=True, exist_ok=False)
    rr, rd = assert_internal(RUN_ROOT)
    if rd != EXPECTED_INTERNAL_DEVICE or rd == D_DEVICE:
        raise RuntimeError("fresh run root resolved to wrong volume")
    (RUN_ROOT / "packages").mkdir()
    (RUN_ROOT / "scratch").mkdir()
    (RUN_ROOT / "tmp").mkdir()
    copies = [copy_variant(v, RUN_ROOT) for v in PLAN["variants"]]
    # Final fail-closed recheck immediately before first compile.
    for entry in copies:
        path, device = assert_internal(Path(entry["destination"]))
        if device != EXPECTED_INTERNAL_DEVICE or device == D_DEVICE:
            raise RuntimeError(f"package escaped internal volume: {path}")
    (evidence / "copied-source-bindings.json").write_text(json.dumps(copies, sort_keys=True, indent=2) + "\n")
    runs = []
    for name in ("current", "candidate"):
        runs.append(execute_variant(name, RUN_ROOT))
    tool_after = tool_info()
    receipt = {"schema": "copy-cost-macos-release-pair-v1", "sourcePlanSha256": PLAN_SHA,
               "internalCacheBase": str(base), "internalDevice": dev, "dDevice": D_DEVICE,
               "runRoot": str(rr), "runRootDevice": rd, "sourceCopies": copies,
               "toolchainBefore": tool_before, "runs": runs, "toolchainAfter": tool_after,
               "executionOrder": [r["variant"] for r in runs], "completePair": len(runs) == 2,
               "pass": len(runs) == 2 and all(r["exitCode"] == 0 and not r["timedOut"] for r in runs),
               "interpretation": "Mac release-suite observations only; no causal performance, Windows parity, or native qualification claim."}
    raw = (json.dumps(receipt, sort_keys=True, indent=2) + "\n").encode()
    (evidence / "run-receipt.json").write_bytes(raw)
    print(json.dumps({"receipt": str((evidence / "run-receipt.json").relative_to(REPO)),
                      "sha256": sha(raw), "pass": receipt["pass"],
                      "runs": [{"variant": r["variant"], "exitCode": r["exitCode"], "timedOut": r["timedOut"], "durationSeconds": r["durationSeconds"]} for r in runs]}, indent=2))
    return 0 if receipt["pass"] else 1

if __name__ == "__main__":
    sys.exit(main())
