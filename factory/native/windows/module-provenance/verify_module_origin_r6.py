#!/usr/bin/env python3
"""Verify one fresh compiler-only module capture against frozen inputs."""
from __future__ import annotations
import argparse
import calendar
from datetime import datetime
import hashlib
import json
import ntpath
import re
from pathlib import Path, PureWindowsPath
from typing import Any, Callable

EXPECTED_ROOT = r"D:\Claude\factory-swiftright-module-origin-37429120-20261011"
EXPECTED_SOURCE = EXPECTED_ROOT + r"\runtime"
EXPECTED_RUN = EXPECTED_ROOT + r"\module-provenance-run-r4"
EXPECTED_RECEIPT = EXPECTED_ROOT + r"\runtime-source-receipt.json"
EXPECTED_ARCHIVE = EXPECTED_ROOT + r"\runtime-source.tar"
EXPECTED_SCRATCH = EXPECTED_RUN + r"\scratch"
EXPECTED_MODULE_ROOT = EXPECTED_SCRATCH + r"\out\Products\Release-windows-x86_64\SwiftRightRuntime.swiftmodule"
EXPECTED_COMPILER = r"C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe"
EXPECTED_COMPILER_HASH = "sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"
EXPECTED_COMMIT = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
EXPECTED_SOURCE_TREE = "sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e"
EXPECTED_COMPLETE = "sha256:e9af9fcc9e3aedd7590249f4adc0f26d32190d4f50f70b698d73bbf6ab76ed6f"
EXPECTED_RECEIPT_HASH = "sha256:b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7"
EXPECTED_ARCHIVE_HASH = "sha256:b081f6c36766d7c5a272dcaca032af0882ca3099c58cccfbea35739917e330ec"
EXPECTED_TARGET = "x86_64-unknown-windows-msvc"
EXPECTED_MODULE_NAMES = [EXPECTED_TARGET + ".swiftdoc", EXPECTED_TARGET + ".swiftmodule"]
EXPECTED_LAUNCH = 'build -c release --package-path "' + EXPECTED_SOURCE + '" --scratch-path "' + EXPECTED_SCRATCH + '"'
EXPECTED_ARGS = ["build", "-c", "release", "--package-path", EXPECTED_SOURCE, "--scratch-path", EXPECTED_SCRATCH]


def strict_json(value: str) -> Any:
    def pairs(items):
        result = {}
        for key, item in items:
            if key in result: raise ValueError("duplicate-json-key:" + key)
            result[key] = item
        return result
    return json.loads(value, object_pairs_hook=pairs)


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_hash(value: Any) -> str:
    return "sha256:" + hashlib.sha256(json.dumps(value, ensure_ascii=False, allow_nan=False,
        sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def win_inside(child: str, parent: str) -> bool:
    if not isinstance(child, str) or not isinstance(parent, str): return False
    if ntpath.normpath(child) != child or ntpath.normpath(parent) != parent: return False
    if not PureWindowsPath(child).is_absolute() or not PureWindowsPath(parent).is_absolute(): return False
    if any(part in {".", ".."} for part in PureWindowsPath(child).parts): return False
    try:
        PureWindowsPath(child).relative_to(PureWindowsPath(parent))
        return True
    except ValueError:
        return False


def _binding_rows(value: Any) -> list[dict[str, str]]:
    if not isinstance(value, list) or not value: raise ValueError("snapshot-empty")
    paths = []
    for row in value:
        if not isinstance(row, dict) or set(row) != {"path", "sha256"}: raise ValueError("snapshot-binding-shape")
        rel = row["path"]
        if not isinstance(rel, str) or not rel or "\\" in rel or ":" in rel or rel.startswith("/"):
            raise ValueError("snapshot-path-escape")
        if any(part in {"", ".", ".."} for part in rel.split("/")): raise ValueError("snapshot-path-escape")
        digest = row["sha256"]
        if not isinstance(digest, str) or len(digest) != 71 or not digest.startswith("sha256:") or any(c not in "0123456789abcdef" for c in digest[7:]):
            raise ValueError("snapshot-binding-hash")
        paths.append(rel)
    if len(paths) != len(set(p.lower() for p in paths)): raise ValueError("snapshot-duplicate")
    if paths != sorted(paths): raise ValueError("snapshot-unsorted")
    return value


def _time(value: Any) -> int:
    if not isinstance(value, str) or re.fullmatch(
            r"\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,7})?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)", value) is None:
        raise ValueError("compiler-time")
    if value.endswith("-00:00"): raise ValueError("compiler-time-unknown-offset")
    # Parse calendar fields compatibly with Python 3.10; preserve every fractional
    # digit separately as integer UTC 100ns ticks. Raw receipt strings stay exact.
    normalized = re.sub(r"\.(\d{1,7})(?=Z|[+-]\d{2}:\d{2}$)",
                        lambda match: "." + match.group(1)[:6].ljust(6, "0"), value)
    result = datetime.fromisoformat(normalized.replace("Z", "+00:00"))
    if result.tzinfo is None: raise ValueError("compiler-time")
    fraction = re.search(r"\.(\d{1,7})(?=Z|[+-]\d{2}:\d{2}$)", value)
    fractional_ticks = int(fraction.group(1).ljust(7, "0")) if fraction else 0
    return calendar.timegm(result.utctimetuple()) * 10_000_000 + fractional_ticks


def verify_receipt(receipt_path: str | Path, *, resolve_path: Callable[[str], Path] = Path) -> dict[str, Any]:
    """resolve_path is a fixture seam; CLI always resolves actual Windows files."""
    reasons: list[str] = []
    def require(ok: bool, reason: str):
        if not ok: raise ValueError(reason)
    try:
        receipt = strict_json(Path(receipt_path).read_text(encoding="utf-8-sig"))
        require(receipt.get("kind") == "factory-windows-module-origin" and receipt.get("version") == 2, "kind-version")
        require(receipt.get("status") == "success" and receipt.get("error") == "", "compiler-failed")
        require(type(receipt.get("buildExitCode")) is int and receipt["buildExitCode"] == 0, "compiler-exit")
        require(receipt.get("timedOut") is False and receipt.get("testRunnerExecuted") is False, "compiler-timeout-or-test")
        require(receipt.get("runRoot") == EXPECTED_RUN and receipt.get("sourceRoot") == EXPECTED_SOURCE, "owned-roots")
        require(receipt.get("sourceReceipt") == EXPECTED_RECEIPT and receipt.get("sourceArchive", {}).get("path") == EXPECTED_ARCHIVE, "source-input-paths")
        require(receipt.get("sourceCommit") == EXPECTED_COMMIT and receipt.get("sourceTreeHash") == EXPECTED_SOURCE_TREE
                and receipt.get("completeSnapshotHash") == EXPECTED_COMPLETE, "source-pins")
        require(receipt.get("sourceReceiptBeforeHash") == EXPECTED_RECEIPT_HASH and receipt.get("sourceReceiptAfterHash") == EXPECTED_RECEIPT_HASH, "source-receipt-pins")
        source_receipt = resolve_path(EXPECTED_RECEIPT)
        require(source_receipt.is_file() and sha(source_receipt) == EXPECTED_RECEIPT_HASH, "source-receipt-hash")
        snapshot = strict_json(source_receipt.read_text(encoding="utf-8-sig"))
        require(snapshot.get("synthetic") is False and snapshot.get("kind") == "factory-additive-runtime-source"
                and snapshot.get("sourceCommit") == EXPECTED_COMMIT and snapshot.get("runtimePackagePath") == EXPECTED_SOURCE, "snapshot-identity")
        complete = _binding_rows(snapshot.get("completeSnapshotBindings"))
        source = _binding_rows(snapshot.get("sourceBindings"))
        require(snapshot.get("completeSnapshotHash") == EXPECTED_COMPLETE and canonical_hash(complete) == EXPECTED_COMPLETE, "complete-snapshot-hash")
        require(snapshot.get("sourceTreeHash") == EXPECTED_SOURCE_TREE and canonical_hash(source) == EXPECTED_SOURCE_TREE, "source-binding-hash")
        require(source == [r for r in complete if r["path"] == "Package.swift" or r["path"].startswith("Sources/")], "source-binding-coverage")
        require(snapshot.get("snapshotArchiveHash") == EXPECTED_ARCHIVE_HASH, "snapshot-archive-pin")
        archive = resolve_path(EXPECTED_ARCHIVE)
        require(archive.is_file() and sha(archive) == EXPECTED_ARCHIVE_HASH, "source-archive-hash")
        require(receipt["sourceArchive"].get("beforeHash") == EXPECTED_ARCHIVE_HASH
                and receipt["sourceArchive"].get("afterHash") == EXPECTED_ARCHIVE_HASH
                and receipt["sourceArchive"].get("bytes") == archive.stat().st_size, "source-archive-binding")
        source_root = resolve_path(EXPECTED_SOURCE)
        actual_files = sorted(p.relative_to(source_root).as_posix() for p in source_root.rglob("*") if p.is_file())
        require(actual_files == [r["path"] for r in complete], "snapshot-file-coverage")
        expected_rows = []
        for row in complete:
            actual = source_root / row["path"]
            require(not actual.is_symlink() and actual.is_file() and sha(actual) == row["sha256"], "snapshot-source-drift:" + row["path"])
            expected_rows.append({**row, "bytes": actual.stat().st_size})
        require(receipt.get("sourceBefore") == expected_rows and receipt.get("sourceAfter") == expected_rows, "snapshot-before-after")
        compiler = receipt.get("compiler", {})
        require(compiler.get("path") == EXPECTED_COMPILER, "compiler-path")
        executable = resolve_path(EXPECTED_COMPILER)
        require(executable.is_file() and sha(executable) == EXPECTED_COMPILER_HASH, "compiler-hash")
        require(compiler.get("beforeHash") == EXPECTED_COMPILER_HASH and compiler.get("afterHash") == EXPECTED_COMPILER_HASH, "compiler-before-after")
        compiler_copy = resolve_path(EXPECTED_RUN + r"\compiler-input\swift.exe")
        require(compiler_copy.is_file() and sha(compiler_copy) == EXPECTED_COMPILER_HASH
                and compiler.get("archivePath") == EXPECTED_RUN + r"\compiler-input\swift.exe"
                and compiler.get("archiveHash") == EXPECTED_COMPILER_HASH
                and compiler.get("bytes") == compiler_copy.stat().st_size == executable.stat().st_size, "compiler-archive")
        helper = receipt.get("helper", {})
        helper_source = Path(__file__).with_name("module-origin-build-r4.ps1")
        helper_copy = resolve_path(EXPECTED_RUN + r"\module-origin-build-r4.ps1")
        require(helper_copy.is_file() and sha(helper_copy) == sha(helper_source)
                and helper.get("sha256") == sha(helper_source) and helper.get("archivePath") == EXPECTED_RUN + r"\module-origin-build-r4.ps1", "helper-source")
        command = receipt.get("command", {})
        require(command.get("executable") == EXPECTED_COMPILER and command.get("workingDirectory") == EXPECTED_SOURCE
                and command.get("arguments") == EXPECTED_ARGS and command.get("launchArguments") == EXPECTED_LAUNCH
                and command.get("configuration") == "release" and command.get("testRunnerExecuted") is False, "compiler-argv-cwd")
        process = receipt.get("process", {})
        require(type(process.get("pid")) is int and process["pid"] > 0, "owned-pid")
        require(process.get("path") == EXPECTED_COMPILER and process.get("argv") == EXPECTED_ARGS
                and process.get("workingDirectory") == EXPECTED_SOURCE and process.get("startedAt") == receipt.get("startedAt"), "owned-process-join")
        observed = process.get("observedCommandLine")
        require(process.get("observedExecutable") == EXPECTED_COMPILER and isinstance(observed, str), "os-process-observation")
        observed_pattern = r'^(?:"' + re.escape(EXPECTED_COMPILER) + r'"|' + re.escape(EXPECTED_COMPILER) + r')'
        for arg in EXPECTED_ARGS:
            observed_pattern += r'\s+(?:"' + re.escape(arg) + r'"|' + re.escape(arg) + r')'
        require(re.fullmatch(observed_pattern, observed) is not None, "os-process-argv")
        owned_copy = resolve_path(EXPECTED_RUN + r"\owned-process.json")
        require(owned_copy.is_file() and strict_json(owned_copy.read_text(encoding="utf-8-sig")) == process, "owned-process-archive")
        start, end = _time(receipt.get("startedAt")), _time(receipt.get("finishedAt"))
        require(type(process.get("coordinatorPid")) is int and process["coordinatorPid"] > 0
                and process.get("parentPid") == process["coordinatorPid"], "compiler-parent")
        launch_before, observed_at = _time(process.get("launchBefore")), _time(process.get("observedAt"))
        require(launch_before <= observed_at <= end and launch_before - 10_000_000 <= start <= observed_at, "compiler-launch-window")
        launch_copy = resolve_path(EXPECTED_RUN + r"\launch-pid.json")
        require(launch_copy.is_file() and strict_json(launch_copy.read_text(encoding="utf-8-sig")) ==
                {"pid": process["pid"], "launchBefore": process["launchBefore"], "coordinatorPid": process["coordinatorPid"]}, "launch-pid-archive")
        require(0 <= end - start <= 9_000_000_000, "compiler-time-range")
        cleanup = receipt.get("ownedProcessCleanup", {})
        require(cleanup == {"attempted": False, "verifiedExit": True, "action": "child-exited-naturally"}, "owned-cleanup")
        require(receipt.get("moduleSearchRoot") == EXPECTED_MODULE_ROOT
                and receipt.get("moduleCollection") == "immediately-after-successful-owned-compiler-exit", "module-root-collection")
        output = receipt.get("output", {})
        for stream in ("stdout", "stderr"):
            item = output.get(stream, {})
            expected_path = EXPECTED_RUN + "\\build." + stream + ".txt"
            require(item.get("path") == expected_path, "output-path")
            actual = resolve_path(expected_path)
            require(actual.is_file() and item.get("sha256") == sha(actual) and item.get("bytes") == actual.stat().st_size, "output-hash-bytes")
        module_root = resolve_path(EXPECTED_MODULE_ROOT)
        require(module_root.is_dir(), "module-missing")
        names = sorted(p.name for p in module_root.iterdir() if p.is_file())
        require(names == EXPECTED_MODULE_NAMES and not any(p.is_dir() for p in module_root.iterdir()), "module-coverage")
        bindings = receipt.get("moduleBindings")
        require(isinstance(bindings, list) and len(bindings) == len(EXPECTED_MODULE_NAMES), "module-binding-count")
        for name, item in zip(EXPECTED_MODULE_NAMES, bindings):
            require(item.get("sourcePath") == EXPECTED_MODULE_ROOT + "\\" + name
                    and item.get("relativeSourcePath") == name
                    and item.get("archivePath") == EXPECTED_RUN + "\\module-archive\\" + name, "module-path-join")
            actual, copied = module_root / name, resolve_path(item["archivePath"])
            require(actual.is_file() and copied.is_file() and not actual.is_symlink() and not copied.is_symlink(), "module-copy-missing")
            require(actual.stat().st_size > 0 and actual.stat().st_size == copied.stat().st_size == item.get("bytes")
                    and sha(actual) == sha(copied) == item.get("sha256"), "module-copy-hash-bytes")
        copies = resolve_path(EXPECTED_RUN + r"\module-archive")
        require(sorted(p.name for p in copies.iterdir()) == EXPECTED_MODULE_NAMES, "module-archive-coverage")
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError) as exc:
        reasons.append(str(exc))
    return {"accepted": not reasons, "reasons": reasons, "qualification": "observed-owned-compiler-module-origin" if not reasons else None}


def main() -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("receipt"); args = parser.parse_args()
    result = verify_receipt(args.receipt); print(json.dumps(result, sort_keys=True)); return 0 if result["accepted"] else 1

if __name__ == "__main__": raise SystemExit(main())
