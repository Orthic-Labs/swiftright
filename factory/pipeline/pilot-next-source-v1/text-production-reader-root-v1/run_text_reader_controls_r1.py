#!/usr/bin/env python3
"""Run production Windows exit admission against typed Text20 archive roots.

Controls preserve raw files, mutate only in-memory capture/receipt bytes, &
leave semantic/parity status held. Missing closure stays an explicit blocker.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import stat
import sys
from pathlib import Path, PurePosixPath
from typing import Any

_HERE = Path(__file__).resolve()
_REPO = _HERE.parents[4]
if not ((_REPO / "factory").is_dir()
        and (_REPO / "factory/gate/windows_exit_admission.py").is_file()
        and (_REPO / "factory/pipeline/archive_reader.py").is_file()):
    raise RuntimeError("checked repository anchor missing")
if str(_REPO) not in sys.path:
    sys.path.insert(0, str(_REPO))
from factory.gate.windows_exit_admission import verify_windows_exit_admission
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.core.artifacts import canonical_hash

MAX_JSON = 4 * 1024 * 1024
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
SHA = "sha256:"


def load(path: Path) -> Any:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > MAX_JSON:
        raise ValueError(f"bounded JSON required: {path}")
    chunks = bytearray()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            chunks.extend(chunk)
            if len(chunks) > MAX_JSON:
                raise ValueError(f"JSON grew past bound: {path}")
    return json.loads(bytes(chunks).decode("utf-8-sig"))


def digest(raw: bytes) -> str:
    return SHA + hashlib.sha256(raw).hexdigest()


def evaluate(capture: dict[str, Any], reader: ArchiveByteReader, overrides: dict[str, bytes] | None = None, archive_capture: dict[str, Any] | None = None) -> dict[str, Any]:
    overrides = overrides or {}
    archive_key = canonical_hash(archive_capture or capture).removeprefix(SHA)
    archive_root = reader.windows_archives.get(archive_key)
    if archive_root is None:
        return {"status": "blocked", "issues": ["capture archive binding missing"]}
    # Bind reads to the original admitted archive. The production verifier
    # checks changed proof hashes against these actual bytes; coherent role
    # mutations override only their changed files & observation descriptor.
    bound_capture = archive_capture or capture
    def read(reference: str) -> bytes:
        if reference in overrides:
            return overrides[reference]
        return reader(capture=bound_capture, reference=reference)
    try:
        return verify_windows_exit_admission(capture, read_bytes=read)
    except (ValueError, KeyError, TypeError, OSError, UnicodeError) as exc:
        return {"status": "blocked", "issues": [str(exc)]}


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def rewrite_role(capture: dict[str, Any], reader: ArchiveByteReader, role: str, mutate) -> tuple[dict[str, Any], dict[str, bytes]]:
    """Mutate one owned proof role & reseal every duplicate raw-file binding.

    Production reader intentionally rejects conflicting path bindings. A fault
    fixture must therefore update observation row's raw-file hash for same
    mutated bytes while leaving all unrelated roles untouched.
    """
    changed = copy.deepcopy(capture)
    ref = changed["meta"]["conditions"]["windowsExitProof"]["files"][role]
    raw = reader(capture=capture, reference=ref["path"])
    doc = json.loads(raw.decode("utf-8-sig"))
    mutate(doc)
    new_raw = _json_bytes(doc)
    new_hash = digest(new_raw)
    ref["hash"] = new_hash
    overrides = {ref["path"]: new_raw}
    original_observation_hash = None

    def reseal_observation_hash(observation_hash: str) -> None:
        meta = changed.get("meta", {})
        clock = meta.get("clock")
        if isinstance(clock, dict) and "correlationHash" in clock:
            clock["correlationHash"] = observation_hash
        conditions = meta.get("conditions")
        if isinstance(conditions, dict) and "rawReceiptHash" in conditions:
            conditions["rawReceiptHash"] = observation_hash

    if role == "observation":
        reseal_observation_hash(new_hash)

    # Every proof role is also listed by its native observation row. Reseal
    # that row & observation descriptor so ArchiveByteReader sees one binding.
    if role != "observation":
        observation_ref = changed["meta"]["conditions"]["windowsExitProof"]["files"]["observation"]
        original_observation_hash = observation_ref["hash"]
        observation_raw = reader(capture=capture, reference=observation_ref["path"])
        observation = json.loads(observation_raw.decode("utf-8-sig"))
        rows = observation if isinstance(observation, list) else [observation]
        run = capture["meta"]["run"]
        matches = [row for row in rows if isinstance(row, dict) and row.get("index") == run]
        if len(matches) != 1:
            raise ValueError("fault fixture observation row missing or duplicated")
        row = matches[0]
        # Native observation is one global list20 document. Its run row is
        # primary admission input, but shared role paths can be listed by
        # every row. Reseal every occurrence so reader never sees conflicting
        # bindings while targeted fault reaches its production predicate.
        occurrences = 0
        target_occurrences = 0
        capture_path = PurePosixPath(ref["path"])
        capture_name = capture_path.name
        for candidate_row in rows:
            files = candidate_row.get("files") if isinstance(candidate_row, dict) else None
            if not isinstance(files, list):
                continue
            for item in files:
                item_path = item.get("path") if isinstance(item, dict) else None
                # Native observation stores run-local basenames, while typed
                # captures retain native/<run>/ prefixes. Correlate exact path
                # or a unique suffix instead of requiring impossible equality.
                if (not isinstance(item_path, str)
                        or not (item_path == ref["path"]
                                or (item_path == capture_name
                                    and capture_path.name == capture_name))):
                    continue
                occurrences += 1
                if candidate_row is row:
                    target_occurrences += 1
                item["sha256"] = new_hash.removeprefix(SHA)
                if "bytes" in item:
                    item["bytes"] = len(new_raw)
        if target_occurrences != 1 or occurrences < target_occurrences:
            raise ValueError("fault fixture role has no unique observation file binding")
        new_observation = _json_bytes(observation)
        observation_ref["hash"] = digest(new_observation)
        overrides[observation_ref["path"]] = new_observation
        reseal_observation_hash(observation_ref["hash"])

        # Keep every typed capture-level reference coherent. Some producer
        # revisions carry observation hash in additional raw-input metadata;
        # replacing only clock/rawReceipt leaves reader's first failure at
        # native-observation.json instead of reaching intended fault.
        new_observation_hash = observation_ref["hash"]
        def replace_observation_hash(value: Any) -> None:
            if isinstance(value, dict):
                for key, child in list(value.items()):
                    if child == original_observation_hash:
                        value[key] = new_observation_hash
                    else:
                        replace_observation_hash(child)
            elif isinstance(value, list):
                for child in value:
                    replace_observation_hash(child)
        replace_observation_hash(changed)
    return changed, overrides


def evaluate_role_fault(label: str, capture: dict[str, Any], reader: ArchiveByteReader, role: str, mutate, expected_issue: str) -> dict[str, Any]:
    """Run one in-memory mutation, retaining blocked diagnostics if closure is absent."""
    try:
        changed, override = rewrite_role(capture, reader, role, mutate)
    except (ValueError, KeyError, TypeError, OSError, UnicodeError) as exc:
        return {"name": label, "status": "blocked", "issues": [str(exc)], "controlSetup": "blocked-before-reader"}
    return require_blocked(label, evaluate(changed, reader, override, archive_capture=capture), expected_issue)


def require_blocked(label: str, result: dict[str, Any], expected_issue: str | None = None) -> dict[str, Any]:
    if result.get("status") != "blocked":
        raise ValueError(f"fault accepted: {label}")
    if expected_issue is not None and not any(expected_issue in str(issue) for issue in result.get("issues", [])):
        raise ValueError(f"fault rejected for wrong reason: {label}: {result.get('issues', [])}")
    return {"name": label, "status": result.get("status"), "issues": result.get("issues", [])}


def check_export_state(archive_root: Path) -> None:
    manifest = load(archive_root / "export-manifest.json")
    if manifest.get("qualified") is not False or manifest.get("lockReleased") is not True:
        raise ValueError("export qualification or lock state invalid")


def write_result(path: Path, result: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run(args: argparse.Namespace) -> int:
    reader_doc = load(args.reader_input)
    captures_doc = load(args.captures)
    captures = captures_doc.get("captures") if isinstance(captures_doc, dict) else None
    if reader_doc.get("version") != 1 or reader_doc.get("expectedWindows") != 20 or not isinstance(captures, list) or len(captures) != 20:
        raise ValueError("typed Text20 reader inputs invalid")
    archives = reader_doc.get("windowsArchives")
    if not isinstance(archives, dict) or len(archives) != 20:
        raise ValueError("exact20 archive roots required")
    base = args.reader_input.resolve(strict=True).parent
    resolved_archives = {str(k): str((base / str(v)).resolve(strict=True)) for k, v in archives.items()}
    reader = ArchiveByteReader(windows_archives=resolved_archives, max_bytes=MAX_ARCHIVE_BYTES)
    archive_root = Path(next(iter(resolved_archives.values())))
    check_export_state(archive_root)
    baseline = []
    for capture in captures:
        baseline.append(evaluate(capture, reader))
    baseline_passed = sum(result.get("status") == "pass" for result in baseline)
    if baseline_passed != 20:
        result = {
            "schema": "factory-text-production-reader-controls-r1",
            "status": "blocked",
            "qualified": False,
            "nativeParityGranted": False,
            "baseline": {"count": len(baseline), "passed": baseline_passed, "results": baseline},
            "faults": [],
            "comparison": {"status": "held-observation-only", "semantic": "held", "timing": "raw-only", "nativeParity": "held"},
            "diagnostic": "baseline admission must pass 20/20 before fault controls",
        }
        if reader_doc.get("macReport"):
            result["macReport"] = {"path": reader_doc["macReport"], "status": "held", "terminalEvidence": "Mac original-process exit/cleanup evidence absent"}
        write_result(args.output, result)
        print(json.dumps({"status": "blocked", "baselinePassed": baseline_passed, "faultCount": 0}, sort_keys=True))
        return 2
    faults: list[dict[str, Any]] = []
    first = captures[0]
    try:
        source_fault = copy.deepcopy(first)
        source_fault["provenance"]["sourceHash"] = SHA + "0" * 64
        faults.append(require_blocked("wrong-source", evaluate(source_fault, reader, archive_capture=first), "Witness source identity mismatch"))
        plan_fault = copy.deepcopy(first)
        plan_fault["meta"]["conditions"]["windowsExitProof"]["files"]["plan"]["hash"] = SHA + "0" * 64
        faults.append(require_blocked("wrong-plan-hash", evaluate(plan_fault, reader, archive_capture=first), "raw proof hash mismatch"))
        faults.append(evaluate_role_fault("retained-handle-identity", first, reader, "owned", lambda doc: doc.__setitem__("pid", int(doc.get("pid", 0)) + 1), "owned process identity mismatch"))
        faults.append(evaluate_role_fault("terminal-kernel-wait", first, reader, "outcome", lambda doc: doc.get("cleanup", {}).__setitem__("kernelWaitResult", 258), "terminal retained kernel signal0 required"))
        faults.append(evaluate_role_fault("lock-owner-proof", first, reader, "outcome", lambda doc: doc.__setitem__("lockOwner", ""), "lock owner proof missing"))
        hash_fault = copy.deepcopy(first)
        hash_fault["meta"]["conditions"]["windowsExitProof"]["files"]["stdout"]["hash"] = SHA + "0" * 64
        faults.append(require_blocked("stdout-proof-hash", evaluate(hash_fault, reader, archive_capture=first), "raw proof hash mismatch"))
    except (ValueError, KeyError, TypeError, OSError, UnicodeError) as exc:
        partial = {
            "schema": "factory-text-production-reader-controls-r1",
            "status": "blocked",
            "qualified": False,
            "nativeParityGranted": False,
            "baseline": {"count": len(baseline), "passed": baseline_passed, "results": baseline},
            "faults": faults,
            "comparison": {"status": "held-observation-only", "semantic": "held", "timing": "raw-only", "nativeParity": "held"},
            "diagnostic": str(exc),
        }
        write_result(args.output, partial)
        print(json.dumps({"status": "blocked", "baselinePassed": baseline_passed, "faultCount": len(faults), "diagnostic": str(exc)}, sort_keys=True))
        return 2
    result = {
        "schema": "factory-text-production-reader-controls-r1",
        "status": "reader-verified",
        "qualified": False,
        "nativeParityGranted": False,
        "baseline": {"count": len(baseline), "passed": baseline_passed, "results": baseline},
        "faults": faults,
        "comparison": {"status": "held-observation-only", "semantic": "held", "timing": "raw-only", "nativeParity": "held"},
    }
    if reader_doc.get("macReport"):
        result["macReport"] = {"path": reader_doc["macReport"], "status": "paired-observation-only", "terminalEvidence": "Fresh Mac20 original-process proofs validated by materializer; this invocation verifies Windows admission"}
    write_result(args.output, result)
    print(json.dumps({"status": result["status"], "baselinePassed": baseline_passed, "faultCount": len(faults)}, sort_keys=True))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reader-input", type=Path, required=True)
    ap.add_argument("--captures", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    try:
        return run(args)
    except (ValueError, KeyError, TypeError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "blocked", "error": str(exc)}))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
