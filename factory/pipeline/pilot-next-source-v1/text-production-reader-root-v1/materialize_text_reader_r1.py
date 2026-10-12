#!/usr/bin/env python3
"""Bounded Text20 archive materializer for production reader review.

It copies only rows named by measured export-manifest.json, builds exact typed
Windows captures, & keeps missing compiler/runtime/source closure explicit.
It never changes raw evidence, grants parity, or invents unavailable bytes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
from pathlib import Path, PurePosixPath
from typing import Any

MAX_JSON = 4 * 1024 * 1024
# Measured Text closure stays below 32 MiB per file & per capture job.
MAX_FILE = 32 * 1024 * 1024
MAX_TOTAL = 32 * 1024 * 1024
COUNT = 20
SHA = "sha256:"
CASE_ID = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418"
CASE_HASH = SHA + "29807aa918aa7c2c1c4a4705eb324b0020f29060be7359d4923694aeb5d437ad"
TUPLE_ID = "sr1-text-paint-v2-r11-paired20-20261012"
SOURCE_HASH = SHA + "4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e"
WINDOWS_EXE = SHA + "33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7"
RENDERER = SHA + "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
COMPILER = SHA + "1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"


class Hold(ValueError):
    pass


def lexical_path(value: Path) -> Path:
    """Make absolute without resolving symlink components."""
    # abspath normalizes lexical ``..`` only; unlike resolve(), it preserves
    # symlink identity for subsequent lstat checks.
    return Path(os.path.abspath(os.fspath(value)))


def reject_symlink_components(value: Path, label: str, *, require_exists: bool) -> Path:
    """Reject symlink roots/parents before any resolve(strict=True) call."""
    path = lexical_path(value)
    current = Path(path.anchor)
    for component in path.parts:
        if component == path.anchor:
            continue
        current = current / component
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            if require_exists:
                raise Hold(f"{label} missing: {path}")
            continue
        if stat.S_ISLNK(mode):
            raise Hold(f"{label} contains symlink: {current}")
    if require_exists and not path.exists():
        raise Hold(f"{label} missing: {path}")
    return path


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise Hold(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def safe_rel(value: Any) -> str:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        raise Hold("unsafe archive path")
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or ".." in parsed.parts or str(parsed) != value:
        raise Hold("unsafe archive path")
    return value


def read_bytes(path: Path, limit: int = MAX_JSON) -> bytes:
    path = reject_symlink_components(path, "input", require_exists=True)
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > limit:
        raise Hold(f"bounded regular file required: {path}")
    chunks: list[bytes] = []
    total = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            if total > limit:
                raise Hold(f"file grew past bound: {path}")
            chunks.append(chunk)
    return b"".join(chunks)


def read_json(path: Path) -> Any:
    try:
        return json.loads(read_bytes(path).decode("utf-8-sig"), object_pairs_hook=reject_duplicate_keys)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Hold(f"invalid JSON: {path}") from exc


def digest(raw: bytes) -> str:
    return SHA + hashlib.sha256(raw).hexdigest()


def file_digest(path: Path) -> tuple[int, str]:
    path = reject_symlink_components(path, "archive file", require_exists=True)
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > MAX_FILE:
        raise Hold(f"bounded archive file required: {path}")
    total = 0
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            total += len(chunk)
            if total > MAX_FILE:
                raise Hold(f"archive file grew past bound: {path}")
            h.update(chunk)
    return total, SHA + h.hexdigest()


def bounded_ref(root: Path, ref: Any, total: list[int], label: str) -> dict[str, Any]:
    """Verify one report reference against its measured file bytes."""
    if not isinstance(ref, dict):
        raise Hold(f"{label} reference missing")
    value = ref.get("path")
    expected_bytes = ref.get("bytes")
    expected_hash = sha_ref(ref.get("sha256"))
    if type(expected_bytes) is not int or expected_bytes < 0 or expected_bytes > MAX_FILE:
        raise Hold(f"{label} reference bytes invalid")
    if not isinstance(value, str) or not value:
        raise Hold(f"{label} reference path missing")
    candidate = Path(value) if Path(value).is_absolute() else root / safe_rel(value)
    try:
        relative = candidate.relative_to(root)
    except ValueError as exc:
        raise Hold(f"{label} reference escapes measured root") from exc
    current = root
    for component in relative.parts:
        current = current / component
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError as exc:
            raise Hold(f"{label} reference missing: {value}") from exc
        if stat.S_ISLNK(mode):
            raise Hold(f"{label} reference contains symlink: {value}")
    actual_bytes, actual_hash = file_digest(candidate)
    if actual_bytes != expected_bytes or actual_hash != expected_hash:
        raise Hold(f"{label} reference hash/bytes drift: {value}")
    total[0] += actual_bytes
    if total[0] > MAX_TOTAL:
        raise Hold("paired report read bound exceeded")
    return {"path": str(relative), "bytes": actual_bytes, "sha256": actual_hash}


def sha_ref(value: Any) -> str:
    if not isinstance(value, str):
        raise Hold("sha256 reference missing")
    value = value.removeprefix(SHA)
    if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
        raise Hold("sha256 reference malformed")
    return SHA + value


def verify_observation_ref(row: dict[str, Any], key: str, filename: str, expected_bytes: int, expected_hash: str) -> None:
    ref = row.get(key)
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str):
        raise Hold(f"observation {key} missing")
    path = ref["path"].replace("\\", "/")
    if path.rsplit("/", 1)[-1] != filename:
        raise Hold(f"observation {key} path mismatch")
    if type(ref.get("bytes")) is not int or ref["bytes"] != expected_bytes or sha_ref(ref.get("sha256")) != expected_hash:
        raise Hold(f"observation {key} hash/bytes mismatch")


def canonical(value: Any) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return digest(raw)


def validate_paired_report(report_path: Path, windows_root: Path) -> dict[str, Any]:
    """Admit measured paired observations while keeping qualification held."""
    report = read_json(report_path)
    if not isinstance(report, dict):
        raise Hold("paired report object required")
    if report.get("kind") != "factory-text-exit-proof-paired20-observed-v1" or report.get("status") != "observed-diagnostic":
        raise Hold("paired report kind/status mismatch")
    if report.get("qualification") is not False or report.get("parity") != "held":
        raise Hold("paired report must remain unqualified/parity-held")
    inputs = report.get("inputs")
    expected_inputs = {
        "macCaptureRoot": "factory/oracle/mac/text-origin-r11-root-v1/observed-paint-mac20-r1",
        "macExitRoot": "factory/oracle/mac/text-origin-r11-root-v1/exit-proof-replay-v1/observed-mac-exit-count20-r1",
        "windowsRoot": "factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1",
    }
    if inputs != expected_inputs:
        raise Hold("paired report input roots mismatch")
    repo = Path(__file__).resolve().parents[4]
    mac_root = repo / expected_inputs["macExitRoot"]
    try:
        if windows_root.relative_to(repo).as_posix() != expected_inputs["windowsRoot"]:
            raise Hold("paired report Windows root mismatch")
    except ValueError as exc:
        raise Hold("paired report Windows root outside repository") from exc
    if not mac_root.is_dir() or not windows_root.is_dir():
        raise Hold("paired report evidence root missing")
    expected_tuple = {
        "id": TUPLE_ID,
        "hostHashes": {
            "macos": SHA + "fb2757beded3e6d1d4d650b508ed28f2080f0168d56948f7a1dac2bc897db84c",
            "windows": WINDOWS_EXE,
        },
        "rendererHash": RENDERER,
        "runtimeCommit": "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b",
    }
    expected_case = {"id": CASE_ID, "hash": CASE_HASH}
    expected_source = SOURCE_HASH
    expected_mac_host = expected_tuple["hostHashes"]["macos"]
    mac = report.get("mac")
    windows = report.get("windows")
    if not isinstance(mac, dict) or not isinstance(windows, dict):
        raise Hold("paired platform records missing")
    for platform, doc, host_hash in (("macos", mac, expected_mac_host), ("windows", windows, WINDOWS_EXE)):
        if doc.get("platform") != platform or doc.get("case") != expected_case or doc.get("sourceHash") != expected_source or doc.get("hostHash") != host_hash or doc.get("rendererHash") != RENDERER or doc.get("tuple", {}).get("id") != TUPLE_ID:
            raise Hold(f"paired {platform} identity mismatch")
        tuple_doc = doc.get("tuple")
        if not isinstance(tuple_doc, dict):
            raise Hold(f"paired {platform} tuple missing")
        for key, value in expected_tuple.items():
            if tuple_doc.get(key) != value:
                raise Hold(f"paired {platform} tuple {key} mismatch")
    mac_rows = mac.get("rows")
    win_rows = windows.get("rows")
    if not isinstance(mac_rows, list) or len(mac_rows) != COUNT or not isinstance(win_rows, list) or len(win_rows) != COUNT:
        raise Hold("paired report requires exactly 20 rows per platform")
    total = [0]
    mac_raw_refs = 0
    win_raw_refs = 0
    exit_proofs = 0
    for run, row in enumerate(mac_rows, 1):
        if not isinstance(row, dict) or row.get("ordinal") != run or row.get("sourceRun") != f"run-{run:03d}":
            raise Hold(f"paired Mac row {run} identity mismatch")
        capture = row.get("capture")
        if not isinstance(capture, dict) or capture.get("case") != expected_case or capture.get("tuple", {}).get("id") != TUPLE_ID or capture.get("source") != "fresh-exit-proof-root" or capture.get("historicalProvenanceOnly") is not True:
            raise Hold(f"paired Mac row {run} provenance mismatch")
        refs = row.get("raw")
        if not isinstance(refs, list) or not refs:
            raise Hold(f"paired Mac row {run} raw refs missing")
        for index, ref in enumerate(refs):
            bounded_ref(mac_root, ref, total, f"Mac row {run} raw {index}")
            mac_raw_refs += 1
        terminal = row.get("terminal")
        if not isinstance(terminal, dict) or terminal.get("exitCode") != 0 or terminal.get("streamsSealed") is not True or terminal.get("waitPidObserved") is not True or terminal.get("proofPath") != f"run-{run:03d}/exit-proof.json":
            raise Hold(f"paired Mac row {run} terminal proof mismatch")
        exit_proof = terminal.get("exitProof")
        if not isinstance(exit_proof, dict):
            raise Hold(f"paired Mac row {run} exit proof missing")
        for role in ("host", "plain", "instrumented", "ax"):
            proof = exit_proof.get(role)
            if not isinstance(proof, dict) or type(proof.get("pid")) is not int or proof.get("pid") <= 0 or proof.get("exitCode") != 0 or proof.get("streamsSealed") is not True or proof.get("waitPidObserved") is not True or proof.get("timedOut") is not False or proof.get("outputLimitExceeded") is not False or proof.get("rssLimitExceeded") is not False:
                raise Hold(f"paired Mac row {run} {role} exit proof mismatch")
            exit_proofs += 1
            for name in ("stdout", "stderr", "png", "events"):
                if name in proof:
                    bounded_ref(mac_root, proof[name], total, f"Mac row {run} {role} {name}")
    for run, row in enumerate(win_rows, 1):
        if not isinstance(row, dict) or row.get("ordinal") != run or row.get("sourceRun") != f"native-{run:02d}":
            raise Hold(f"paired Windows row {run} identity mismatch")
        observation = row.get("observation")
        if not isinstance(observation, dict) or observation.get("sourceHash") != expected_source or observation.get("exeHash") != WINDOWS_EXE.removeprefix(SHA):
            raise Hold(f"paired Windows row {run} observation identity mismatch")
        refs = row.get("raw")
        if not isinstance(refs, list) or not refs:
            raise Hold(f"paired Windows row {run} raw refs missing")
        for index, ref in enumerate(refs):
            bounded_ref(windows_root, ref, total, f"Windows row {run} raw {index}")
            win_raw_refs += 1
        terminal = row.get("terminal")
        if not isinstance(terminal, dict) or terminal.get("exitCode") != 0 or terminal.get("kernelWait") != 0 or terminal.get("originalHandleRetained") is not True or terminal.get("streamDrainComplete") is not True or terminal.get("streamsSealed") is not True:
            raise Hold(f"paired Windows row {run} terminal proof mismatch")
    mac_exit = mac.get("exitProof")
    if not isinstance(mac_exit, dict) or mac_exit.get("runCount") != COUNT or mac_exit.get("receiptCount") != COUNT * 4 or mac_exit.get("allExitCodeZero") is not True:
        raise Hold("paired Mac aggregate exit proof mismatch")
    if exit_proofs != COUNT * 4:
        raise Hold("paired Mac exit-proof count mismatch")
    repeatability = report.get("semantic", {}).get("repeatability")
    if not isinstance(repeatability, dict) or repeatability.get("macPlainExactRepeat") is not True or repeatability.get("windowsPrintWindowExactRepeat") is not True or repeatability.get("windowsScreenExactRepeat") is not True:
        raise Hold("paired image repeatability claim mismatch")
    mac_plain = {ref.get("sha256") for row in mac_rows for ref in row.get("raw", []) if isinstance(ref, dict) and ref.get("path", "").endswith("/plain.png")}
    win_print = {ref.get("sha256") for row in win_rows for ref in row.get("raw", []) if isinstance(ref, dict) and ref.get("path", "").endswith("native.printwindow.png")}
    win_screen = {ref.get("sha256") for row in win_rows for ref in row.get("raw", []) if isinstance(ref, dict) and ref.get("path", "").endswith("native.screen.png")}
    if len(mac_plain) != 1 or len(win_print) != 1 or len(win_screen) != 1:
        raise Hold("paired image repeatability evidence mismatch")
    return {"path": str(report_path), "kind": report["kind"], "macRows": len(mac_rows), "windowsRows": len(win_rows), "macRawRefs": mac_raw_refs, "windowsRawRefs": win_raw_refs, "exitProofs": exit_proofs, "bytesRead": total[0], "qualification": False, "parity": "held"}


def copy_row(src: Path, dst: Path, expected_bytes: int, expected_hash: str, total: list[int], *, hardlink: bool = False) -> dict[str, Any]:
    n, actual = file_digest(src)
    if n != expected_bytes or actual != expected_hash:
        raise Hold(f"export row drift: {src}")
    total[0] += n
    if total[0] > MAX_TOTAL:
        raise Hold("archive read bound exceeded")
    if dst.exists() or dst.is_symlink():
        raise Hold(f"fresh archive collision: {dst}")
    reject_symlink_components(dst.parent, "archive destination", require_exists=False)
    dst.parent.mkdir(parents=True, exist_ok=True)
    linked = False
    if hardlink:
        try:
            os.link(src, dst)
            copied = expected_bytes
            linked = True
        except OSError:
            copied = 0
    else:
        copied = 0
    if not linked:
        with src.open("rb") as inp, dst.open("xb") as out:
            while chunk := inp.read(1024 * 1024):
                copied += len(chunk)
                if copied > expected_bytes:
                    raise Hold(f"archive source grew: {src}")
                out.write(chunk)
    if copied != expected_bytes:
        raise Hold(f"archive copy byte drift: {src}")
    return {"path": str(dst), "source": str(src), "bytes": n, "sha256": actual}


def rows_for(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows or len(rows) > 2048:
        raise Hold("export manifest rows invalid")
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise Hold("export row object required")
        path = safe_rel(row.get("path"))
        if path in result:
            raise Hold(f"duplicate export row: {path}")
        size = row.get("bytes")
        if type(size) is not int or size < 0 or size > MAX_FILE:
            raise Hold(f"export row bytes invalid: {path}")
        result[path] = {"path": path, "bytes": size, "sha256": sha_ref(row.get("sha256"))}
    return result


def copy_named_rows(raw_root: Path, rows: dict[str, dict[str, Any]], archive: Path, total: list[int]) -> dict[str, dict[str, Any]]:
    copied: dict[str, dict[str, Any]] = {}
    for rel, row in rows.items():
        copied[rel] = copy_row(raw_root / rel, archive / rel, row["bytes"], row["sha256"], total)
    return copied


def copy_host_sources(host_root: Path, plan: dict[str, Any], archive: Path, total: list[int], missing: list[str]) -> dict[str, dict[str, Any]]:
    bindings = plan.get("sourceBindings")
    if not isinstance(bindings, list) or not bindings:
        raise Hold("plan sourceBindings missing")
    copied: dict[str, dict[str, Any]] = {}
    for binding in bindings:
        rel = safe_rel(binding.get("path"))
        expected = sha_ref(binding.get("sha256"))
        source = host_root / rel
        if not source.is_file():
            missing.append("host/" + rel)
            continue
        n, actual = file_digest(source)
        if actual != expected:
            raise Hold(f"host source hash drift: {rel}")
        # Host/runtime source trees may remain mutable in shared checkout; keep
        # archive bytes independent while preserving measured hash/size joins.
        copied[rel] = copy_row(source, archive / "host" / rel, n, expected, total)
    return copied


def copy_runtime_sources(runtime_tree: Any, runtime_root: Path, archive: Path, total: list[int], missing: list[str]) -> dict[str, dict[str, Any]]:
    if not isinstance(runtime_tree, list) or not runtime_tree:
        raise Hold("runtime source tree missing")
    copied: dict[str, dict[str, Any]] = {}
    for binding in runtime_tree:
        rel = safe_rel(binding.get("path"))
        expected = sha_ref(binding.get("sha256"))
        source = runtime_root / rel
        if not source.is_file():
            missing.append("runtime/" + rel)
            continue
        n, actual = file_digest(source)
        if actual != expected:
            raise Hold(f"runtime source hash drift: {rel}")
        copied[rel] = copy_row(source, archive / "runtime" / rel, n, expected, total)
    return copied


def copy_tool(source: Path | None, destination: Path, expected_hash: str, total: list[int], missing: list[str], label: str) -> dict[str, Any] | None:
    if source is None:
        missing.append(label)
        return None
    if not source.is_file():
        raise Hold(f"explicit {label} path missing: {source}")
    n, actual = file_digest(source)
    if actual != expected_hash:
        raise Hold(f"explicit {label} hash drift: {source}")
    return copy_row(source, destination, n, expected_hash, total, hardlink=True)


def role_ref(path: str, rows: dict[str, dict[str, Any]], expected: str | None = None) -> dict[str, str]:
    row = rows.get(path)
    if row is not None:
        return {"path": path, "hash": row["sha256"]}
    if expected is None:
        raise Hold(f"role row missing: {path}")
    return {"path": path, "hash": expected}


def make_capture(run: int, observations: list[dict[str, Any]], identities: list[dict[str, Any]], plan: dict[str, Any], compile_doc: dict[str, Any], tuple_doc: dict[str, Any], rows: dict[str, dict[str, Any]], witness_hash: str) -> dict[str, Any]:
    row = observations[run - 1]
    identity = identities[run - 1]
    proof = {
        "outcome": role_ref("capture-outcome.json", rows),
        "observation": role_ref("native-observation.json", rows),
        "owned": role_ref("owned-process.json", rows),
        "close": role_ref("owned-close.json", rows),
        "plan": role_ref("plan.json", rows),
        "compile": role_ref("observation.json", rows),
        "witness": role_ref("Witness.swift", rows, witness_hash),
        "exe": role_ref("FactoryProbe.exe", rows, WINDOWS_EXE),
        "renderer": role_ref("swiftright_render.dll", rows, RENDERER),
        # Runtime receipt/tree are admitted from host source bindings. Their
        # proof paths must match copied host bytes, never absent native rows.
        "runtimeReceipt": role_ref("runtime-source-receipt.json", rows, plan.get("runtimeSourceReceiptHash")),
        "runtimeTree": role_ref("runtime-source-tree.json", rows, plan.get("runtimeSourceTreeFileHash") or plan.get("runtimeSourceTreeHash")),
        "stdout": role_ref("host.stdout.txt", rows),
        "stderr": role_ref("host.stderr.txt", rows),
    }
    observation_hash = rows["native-observation.json"]["sha256"]
    return {
        "platform": "windows",
        "case": plan["case"],
        "tuple": tuple_doc["tuple"],
        "provenance": {"sourceHash": SOURCE_HASH, "captureID": identity.get("captureID"), "imageID": identity.get("imageID"), "producer": "materialize_text_reader_r1", "nativeParity": "hold"},
        "meta": {
            "run": run,
            "host": {"hash": WINDOWS_EXE, "kind": "owned-renderer"},
            "clock": {"correlationHash": observation_hash, "identity": row.get("ownedIdentity")},
            "measuredHostIdentity": identity.get("measuredHostIdentity"),
            "compile": {"request": plan["compileRequest"], "measuredArgv": compile_doc.get("argv"), "planSha256": compile_doc.get("planSha256"), "compileReceiptSha256": row.get("compileReceiptHash")},
            "conditions": {"actualSourceHash": SOURCE_HASH, "actualHostExecutableHash": WINDOWS_EXE, "actualRendererHash": RENDERER, "rawReceiptHash": observation_hash, "nativeParity": "hold", "windowsExitProof": {"version": 1, "files": proof}},
        },
    }


def materialize(args: argparse.Namespace) -> int:
    raw = reject_symlink_components(args.windows_archive, "Windows archive", require_exists=True)
    output = reject_symlink_components(args.output, "output", require_exists=False)
    if output.exists() and any(output.iterdir()):
        raise Hold("output must be fresh")
    export_path = raw / "export-manifest.json"
    manifest = read_json(export_path)
    if manifest.get("kind") != "factory-native-observation-export-v1" or manifest.get("captureStatus") != "completed-source-bound-observation":
        raise Hold("Text export status/kind mismatch")
    if manifest.get("qualified") is not False or manifest.get("lockReleased") is not True or manifest.get("originalParentAtLaunchCertificate") is not True or manifest.get("tupleID") != TUPLE_ID:
        raise Hold("Text export qualification/tuple mismatch")
    rows = rows_for(manifest)
    if manifest.get("count") != len(rows) or len(rows) < COUNT:
        raise Hold("Text export count mismatch")
    plan_path = raw / "native/plan.json"
    compile_path = raw / "native/observation.json"
    tuple_path = raw / "native/candidate-tuple.json"
    binding_path = raw / "native/candidate-binding.json"
    tree_path = raw / "native/runtime-source-tree.json"
    runtime_receipt_path = raw / "native/runtime-source-receipt.json"
    plan_bytes, plan_file_hash = file_digest(plan_path)
    compile_bytes, compile_file_hash = file_digest(compile_path)
    tuple_bytes, tuple_file_hash = file_digest(tuple_path)
    binding_bytes, binding_file_hash = file_digest(binding_path)
    tree_bytes, tree_file_hash = file_digest(tree_path)
    runtime_receipt_bytes, runtime_receipt_hash = file_digest(runtime_receipt_path)
    plan = read_json(plan_path)
    tuple_doc = read_json(tuple_path)
    binding = read_json(binding_path)
    observations = read_json(raw / "native/native-observation.json")
    identities = [read_json(raw / f"native/native-{run:02d}/measured-capture-identity.json") for run in range(1, COUNT + 1)]
    tree = read_json(tree_path)
    compile_doc = read_json(compile_path)
    if not isinstance(observations, list) or len(observations) != COUNT:
        raise Hold("Text observations must contain 20 rows")
    if plan.get("case", {}).get("id") != CASE_ID or plan.get("case", {}).get("hash") != CASE_HASH:
        raise Hold("Text plan case mismatch")
    if plan.get("sourceHash") != SOURCE_HASH or plan.get("expectedHostHash") != WINDOWS_EXE or plan.get("rendererSha256") != RENDERER.removeprefix(SHA) or plan.get("runtimeSourceCommit") != "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b":
        raise Hold("Text plan source/host/renderer/runtime mismatch")
    tuple_value = tuple_doc.get("tuple", {})
    if tuple_value.get("id") != TUPLE_ID or tuple_value.get("hostHashes", {}).get("windows") != WINDOWS_EXE or tuple_value.get("rendererHash") != RENDERER or tuple_value.get("runtimeCommit") != "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b" or binding.get("case") != plan.get("case") or binding.get("renderer", {}).get("sha256") != RENDERER or binding.get("runtime", {}).get("sourceCommit") != "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b" or binding.get("sourceHash") != SOURCE_HASH:
        raise Hold("Text tuple/binding mismatch")
    if compile_doc.get("kind") != "factory-text-owned-compile-v1" or compile_doc.get("sourceHash") != SOURCE_HASH or compile_doc.get("runtimeSourceCommit") != "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b" or compile_doc.get("compilerHash") != COMPILER.removeprefix(SHA) or compile_doc.get("planSha256") != plan_file_hash.removeprefix(SHA) or compile_doc.get("runtimeSourceTreeHash") != plan.get("runtimeSourceTreeHash") or compile_doc.get("exeSha256") != WINDOWS_EXE.removeprefix(SHA) or compile_doc.get("rendererSha256") != RENDERER.removeprefix(SHA) or compile_doc.get("exitCode") != 0 or compile_doc.get("ownedExited") is not True or compile_doc.get("streamsSealed") is not True:
        raise Hold("Text compile receipt identity/terminal mismatch")
    if plan.get("runtimeSourceReceiptHash") != runtime_receipt_hash or plan.get("runtimeSourceTreeFileHash") != tree_file_hash or plan.get("runtimeSourceTreeHash") != tree_file_hash:
        raise Hold("Text runtime receipt/tree hash join mismatch")
    for run, row in enumerate(observations, 1):
        if row.get("index") != run or row.get("case") != plan.get("case") or row.get("sourceHash") != SOURCE_HASH or row.get("exeSha256") != WINDOWS_EXE.removeprefix(SHA) or row.get("rendererSha256") != RENDERER.removeprefix(SHA) or row.get("runtimeSourceCommit") != "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b" or row.get("compileReceiptHash") != compile_file_hash.removeprefix(SHA) or row.get("manifestHash") != plan.get("manifestHash") or row.get("runtimeSourceTreeHash") != tree_file_hash:
            raise Hold(f"Text observation row {run} identity mismatch")
        verify_observation_ref(row, "candidateTupleRef", "candidate-tuple.json", tuple_bytes, tuple_file_hash)
        verify_observation_ref(row, "candidateBindingRef", "candidate-binding.json", binding_bytes, binding_file_hash)
    paired_report = reject_symlink_components(args.mac_report, "Mac report", require_exists=True) if args.mac_report else None
    paired_validation = validate_paired_report(paired_report, raw) if paired_report else None
    output.mkdir(parents=True, exist_ok=True)
    archive_root = output / "windows-archives"
    archive_root.mkdir()
    missing: list[str] = []
    archive_rows = 0
    archive_bytes = 0
    captures: list[dict[str, Any]] = []
    archives: dict[str, str] = {}
    host_root = reject_symlink_components(args.host_source_root, "host source root", require_exists=True) if args.host_source_root else reject_symlink_components(raw / "native", "host source root", require_exists=True)
    runtime_root = reject_symlink_components(args.runtime_source_root, "runtime source root", require_exists=True) if args.runtime_source_root else reject_symlink_components(raw / "native", "runtime source root", require_exists=True)
    witness_binding_hash = next((sha_ref(item.get("sha256")) for item in plan.get("sourceBindings", []) if item.get("path") == "Sources/FactoryProbe/Witness.swift"), None)
    if witness_binding_hash != SOURCE_HASH:
        raise Hold("witness source binding hash mismatch")
    witness_source = host_root / "Sources/FactoryProbe/Witness.swift"
    witness_hash = witness_binding_hash
    if any(identity.get("run") != run or not identity.get("captureID") or not identity.get("imageID") for run, identity in enumerate(identities, 1)):
        raise Hold("measured capture identity rows are not exact 01..20")
    export_bytes, export_hash = file_digest(export_path)
    for run in range(1, COUNT + 1):
        archive = archive_root / f"pending-{run:02d}"
        archive.mkdir()
        total = [0]
        role_rows: dict[str, dict[str, Any]] = {}
        row = observations[run - 1]
        run_dir = raw / f"native/native-{run:02d}"
        raw_refs = row.get("files")
        if not isinstance(raw_refs, list) or not raw_refs:
            raise Hold(f"Text observation row {run} raw files missing")
        for raw_ref in raw_refs:
            rel = safe_rel(raw_ref.get("path"))
            expected = sha_ref(raw_ref.get("sha256"))
            source = run_dir / rel
            n, actual = file_digest(source)
            if actual != expected:
                raise Hold(f"Text row {run} raw hash drift: {rel}")
            copied = copy_row(source, archive / rel, n, expected, total, hardlink=True)
            if rel in {"capture-outcome.json", "owned-process.json", "owned-close.json", "host.stdout.txt", "host.stderr.txt"}:
                role_rows[rel] = copied
        globals_to_copy = (
            ("native-observation.json", raw / "native/native-observation.json", None),
            ("plan.json", raw / "native/plan.json", None),
            ("observation.json", raw / "native/observation.json", None),
            ("candidate-tuple.json", raw / "native/candidate-tuple.json", None),
            ("candidate-binding.json", raw / "native/candidate-binding.json", None),
            ("export-manifest.json", export_path, export_hash),
        )
        for name, source, expected in globals_to_copy:
            n, actual = file_digest(source)
            if expected is not None and actual != expected:
                raise Hold(f"global source hash drift: {name}")
            role_rows[name] = copy_row(source, archive / name, n, actual, total, hardlink=True)
        copy_host_sources(host_root, plan, archive, total, missing)
        copy_runtime_sources(tree, runtime_root, archive, total, missing)
        proof_sources = (
            ("runtime-source-receipt.json", plan.get("runtimeSourceReceiptHash")),
            ("runtime-source-tree.json", plan.get("runtimeSourceTreeFileHash") or plan.get("runtimeSourceTreeHash")),
        )
        for name, expected_value in proof_sources:
            source = host_root / name
            if not source.is_file():
                missing.append(f"run-{run:02d}/" + name)
                continue
            expected = sha_ref(expected_value)
            n, actual = file_digest(source)
            if actual != expected:
                raise Hold(f"runtime proof source hash drift: {name}")
            role_rows[name] = copy_row(source, archive / name, n, expected, total)
        if not witness_source.is_file():
            missing.append(f"run-{run:02d}/Witness.swift")
        else:
            n, actual = file_digest(witness_source)
            if actual != SOURCE_HASH:
                raise Hold("witness proof source hash drift")
            role_rows["Witness.swift"] = copy_row(witness_source, archive / "Witness.swift", n, SOURCE_HASH, total)
        # windows_exit_admission reads this exact mandatory namespace.
        compiler_path = reject_symlink_components(args.compiler_binary, "compiler", require_exists=True) if args.compiler_binary else None
        exe_path = reject_symlink_components(args.exe_binary, "Windows executable", require_exists=True) if args.exe_binary else None
        renderer_path = reject_symlink_components(args.renderer_binary, "renderer", require_exists=True) if args.renderer_binary else None
        compiler_row = copy_tool(compiler_path, archive / "tool" / "compiler.bin", COMPILER, total, missing, "tool/compiler.bin")
        exe_row = copy_tool(exe_path, archive / "FactoryProbe.exe", WINDOWS_EXE, total, missing, "FactoryProbe.exe")
        renderer_row = copy_tool(renderer_path, archive / "swiftright_render.dll", RENDERER, total, missing, "swiftright_render.dll")
        if compiler_row is not None:
            role_rows["tool/compiler.bin"] = compiler_row
        if exe_row is not None:
            role_rows["FactoryProbe.exe"] = exe_row
        if renderer_row is not None:
            role_rows["swiftright_render.dll"] = renderer_row
        capture = make_capture(run, observations, identities, plan, compile_doc, tuple_doc, role_rows, witness_hash)
        cap_hash = canonical(capture).removeprefix(SHA)
        final_archive = archive_root / f"capture-{cap_hash}"
        archive.rename(final_archive)
        archives[cap_hash] = str(final_archive.relative_to(output))
        archive_rows += len(role_rows) + len(raw_refs)
        archive_bytes += total[0]
        captures.append(capture)
    typed = {"kind": "factory-text-production-typed-captures-v1", "typedStatus": "normalized-observational", "captures": captures}
    (output / "typed-captures.json").write_text(json.dumps(typed, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    reader = {"version": 1, "expectedWindows": COUNT, "windowsArchives": archives, "windowsCaptures": "typed-captures.json", "macReport": str(paired_report) if paired_report else None, "macReportValidation": paired_validation, "comparison": {"status": "held-observation-only", "nativeParity": "held", "semantic": "held", "timing": "raw-only"}}
    (output / "reader-input.json").write_text(json.dumps(reader, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    holds = ["qualification/parity remain held"]
    if paired_validation is None:
        holds.append("Mac paired exit-proof report not admitted")
    else:
        holds.append("Mac geometry/export comparison remains held")
    if missing:
        holds.append("Windows production reader remains held until every compiler/runtime/source/tool byte is admitted")
    receipt = {"schema": "factory-text-production-reader-materializer-r1", "status": "typed-observational-only", "qualified": False, "nativeActions": 0, "archiveRows": archive_rows, "archiveBytesRead": archive_bytes, "missingClosure": sorted(set(missing)), "proofFiles": {"runtimeReceipt": "runtime-source-receipt.json", "runtimeTree": "runtime-source-tree.json", "witness": "Witness.swift"}, "pairedReportValidation": paired_validation, "source": {"rawRoot": str(raw), "exportManifest": str(export_path), "tupleID": TUPLE_ID, "caseID": CASE_ID}, "holds": holds}
    (output / "materializer-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--windows-archive", type=Path, required=True)
    ap.add_argument("--host-source-root", type=Path)
    ap.add_argument("--runtime-source-root", type=Path)
    ap.add_argument("--compiler-binary", type=Path)
    ap.add_argument("--exe-binary", type=Path)
    ap.add_argument("--renderer-binary", type=Path)
    ap.add_argument("--mac-report", type=Path)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    try:
        return materialize(args)
    except (Hold, OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "blocked", "error": str(exc)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
