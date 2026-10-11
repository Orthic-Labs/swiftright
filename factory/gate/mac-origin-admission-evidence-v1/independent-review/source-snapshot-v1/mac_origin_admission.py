"""Reader-backed Mac compiler-origin admission for F10 captures.

This module is deliberately independent from gate/core.py.  The gate supplies
one capture artifact plus a reader.  ``reader`` receives each reference dict
(``path``, ``sha256`` and optional ``bytes``) and returns exact raw bytes.  It
must not resolve paths from receipt text implicitly; every required input is
bound by ``capture['macOrigin']`` or by hashes inside that bound receipt.

Origin qualification is separate from parity or promotion.  A candidate may
remain observational while this verifier rejects missing or corrupted origin.
"""

from __future__ import annotations

from datetime import datetime
import hashlib
import json
import posixpath
import re
from typing import Any, Callable

from factory.core.artifacts import canonical_hash


Reader = Callable[[dict[str, Any]], bytes]
_HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
_INT_FIELDS = ("pid", "pgid")
_CLEANUP_FIELDS = ("timedOut", "drainTimedOut", "killSent", "termSent", "groupMissing")


def _issue(code: str, detail: str = "") -> str:
    return f"mac-origin:{code}" + (f": {detail}" if detail else "")


def _hash(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def _instant(value: Any, label: str, issues: list[str]) -> datetime | None:
    if not isinstance(value, str):
        issues.append(_issue("bad-time", label))
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        issues.append(_issue("bad-time", label))
        return None
    if parsed.tzinfo is None:
        issues.append(_issue("bad-timezone", label))
        return None
    return parsed


def _ref(value: Any, label: str, issues: list[str]) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        issues.append(_issue("missing-ref", label))
        return None
    path, expected = value.get("path"), value.get("sha256")
    if not isinstance(path, str) or not path or not isinstance(expected, str) or not _HASH.fullmatch(expected):
        issues.append(_issue("bad-ref", label))
        return None
    if "bytes" in value and (not isinstance(value["bytes"], int) or isinstance(value["bytes"], bool) or value["bytes"] < 0):
        issues.append(_issue("bad-ref-size", label))
    return value


def _read(reader: Reader, value: Any, label: str, issues: list[str]) -> bytes | None:
    ref = _ref(value, label, issues)
    if ref is None:
        return None
    try:
        raw = reader(dict(ref))
    except Exception as exc:  # reader owns path policy; verifier stays fail-closed.
        issues.append(_issue("read-failed", f"{label}: {exc}"))
        return None
    if not isinstance(raw, (bytes, bytearray)):
        issues.append(_issue("reader-type", label))
        return None
    raw = bytes(raw)
    if _hash(raw) != ref["sha256"]:
        issues.append(_issue("hash", label))
    if "bytes" in ref and len(raw) != ref["bytes"]:
        issues.append(_issue("size", label))
    return raw


def _json(reader: Reader, value: Any, label: str, issues: list[str]) -> tuple[dict[str, Any] | None, bytes | None]:
    raw = _read(reader, value, label, issues)
    if raw is None:
        return None, None
    try:
        parsed = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError):
        issues.append(_issue("json", label))
        return None, raw
    if not isinstance(parsed, dict):
        issues.append(_issue("json-shape", label))
        return None, raw
    return parsed, raw


def _descriptor(path: Any, expected: Any, size: Any = None) -> dict[str, Any] | None:
    value: dict[str, Any] = {"path": path, "sha256": expected}
    if size is not None:
        value["bytes"] = size
    return value


def _receipt_ref(item: Any, label: str, issues: list[str]) -> dict[str, Any] | None:
    """Turn receipt path/hash fields into reader refs without trusting labels."""
    if not isinstance(item, dict):
        issues.append(_issue("missing-receipt-field", label))
        return None
    return _descriptor(item.get("path"), item.get("sha256"), item.get("bytes"))


def _validate_file_field(reader: Reader, item: Any, label: str, issues: list[str]) -> bytes | None:
    return _read(reader, _receipt_ref(item, label, issues), label, issues)


def _validate_cleanup(process: Any, label: str, issues: list[str]) -> None:
    cleanup = process.get("cleanup") if isinstance(process, dict) else None
    if not isinstance(cleanup, dict):
        issues.append(_issue("cleanup", f"{label} cleanup missing"))
        return
    for key in _CLEANUP_FIELDS:
        if cleanup.get(key) is not False:
            issues.append(_issue("cleanup", f"{label}.{key}"))


def _validate_process(process: Any, label: str, issues: list[str]) -> None:
    if not isinstance(process, dict):
        issues.append(_issue("process", f"{label} missing"))
        return
    for key in _INT_FIELDS:
        value = process.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            issues.append(_issue("process", f"{label}.{key}"))
    if not isinstance(process.get("exitCode"), int) or isinstance(process.get("exitCode"), bool):
        issues.append(_issue("process", f"{label}.exitCode"))
    if process.get("ownedProcessGroup") is not True or process.get("pgid") != process.get("pid"):
        issues.append(_issue("process-owner", label))
    started = _instant(process.get("startedAtUtc"), f"{label}.startedAtUtc", issues)
    ended = _instant(process.get("endedAtUtc"), f"{label}.endedAtUtc", issues)
    if started and ended and ended < started:
        issues.append(_issue("process-time", label))
    _validate_cleanup(process, label, issues)


def _validate_tool(reader: Reader, compiler: dict[str, Any], issues: list[str]) -> None:
    logical = compiler.get("logicalCompilerPath")
    real = compiler.get("realPathBefore")
    if not isinstance(logical, str) or not logical.startswith("/") or not isinstance(real, str) or not real.startswith("/"):
        issues.append(_issue("tool-path", "compiler logical/real path"))
    before = compiler.get("realToolBefore")
    after = compiler.get("realToolAfter")
    if not isinstance(before, dict) or not isinstance(after, dict):
        issues.append(_issue("tool-receipt", "before/after"))
    else:
        if before != after or compiler.get("realToolDrift") is not False:
            issues.append(_issue("tool-drift"))
        if before.get("realPath") != real or before.get("logicalPath") != logical:
            issues.append(_issue("tool-binding"))
        raw = _validate_file_field(reader, _descriptor(real, before.get("sha256"), before.get("bytes")), "compiler real tool", issues)
        if raw is not None and before.get("sha256") != _hash(raw):
            issues.append(_issue("tool-hash"))
    xcrun_path, xcrun_hash = compiler.get("xcrunPath"), compiler.get("xcrunHash")
    if not isinstance(xcrun_path, str) or not xcrun_path.startswith("/") or not isinstance(xcrun_hash, str):
        issues.append(_issue("tool-path", "xcrun"))
    else:
        _validate_file_field(reader, _descriptor(xcrun_path, xcrun_hash), "xcrun", issues)


def _validate_receipt(
    reader: Reader,
    receipt: dict[str, Any],
    *,
    source_hashes: set[str],
    binary_hash: str,
    source_names: set[str] | None,
    label: str,
    issues: list[str],
) -> None:
    if receipt.get("kind") != "swift-compiler-process-receipt" or receipt.get("version") != "2":
        issues.append(_issue("receipt-shape", label))
    if receipt.get("status") != "SUCCESS" or receipt.get("sourceDrift") is not False:
        issues.append(_issue("receipt-status", label))
    if receipt.get("invocationMode") not in {"xcrun", "direct"}:
        issues.append(_issue("invocation-mode", label))
    resolver = receipt.get("resolver")
    _validate_process(resolver, f"{label}.resolver", issues)
    if isinstance(resolver, dict):
        if resolver.get("argv") != ["/usr/bin/xcrun", "--find", "swiftc"]:
            issues.append(_issue("resolver-argv", label))
        if resolver.get("exitCode") != 0:
            issues.append(_issue("resolver-exit", label))
        _validate_file_field(reader, _descriptor(resolver.get("stdoutPath"), resolver.get("stdoutHash")), f"{label} resolver stdout", issues)
        _validate_file_field(reader, _descriptor(resolver.get("stderrPath"), resolver.get("stderrHash")), f"{label} resolver stderr", issues)
    compiler = receipt.get("compiler")
    _validate_process(compiler, f"{label}.compiler", issues)
    if not isinstance(compiler, dict):
        return
    _validate_tool(reader, compiler, issues)
    if compiler.get("exitCode") != 0 or compiler.get("timedOut") is not False:
        issues.append(_issue("compiler-exit", label))
    _validate_file_field(reader, _descriptor(compiler.get("stdoutPath"), compiler.get("stdoutHash")), f"{label} compiler stdout", issues)
    _validate_file_field(reader, _descriptor(compiler.get("stderrPath"), compiler.get("stderrHash")), f"{label} compiler stderr", issues)
    before, after = compiler.get("sourceBefore"), compiler.get("sourceAfter")
    if not isinstance(before, dict) or not isinstance(after, dict) or set(before) != set(after) or set(before) != (source_names or set(before)):
        issues.append(_issue("source-set", label))
    elif before != after:
        issues.append(_issue("source-drift", label))
    source_paths: set[str] = set()
    if isinstance(before, dict):
        for name, item in before.items():
            if not isinstance(item, dict):
                issues.append(_issue("source-field", f"{label}.{name}"))
                continue
            raw = _validate_file_field(reader, item, f"{label} source {name}", issues)
            source_paths.add(item.get("path", ""))
            if raw is not None and item.get("sha256") in source_hashes:
                source_hashes.discard(item.get("sha256"))
    if not source_hashes:
        pass
    else:
        issues.append(_issue("source-join", label))
    cwd = compiler.get("cwd")
    if not isinstance(cwd, str) or not cwd.startswith("/"):
        issues.append(_issue("compiler-cwd", label))
    elif source_paths and any(posixpath.dirname(path) != cwd for path in source_paths):
        issues.append(_issue("compiler-cwd", f"{label} source path"))
    argv = compiler.get("argv")
    output = compiler.get("outputBinary")
    if not isinstance(argv, list) or not all(isinstance(arg, str) for arg in argv) or not isinstance(output, dict):
        issues.append(_issue("compiler-argv", label))
    else:
        if receipt.get("invocationMode") == "xcrun" and argv[:2] != ["/usr/bin/xcrun", "swiftc"]:
            issues.append(_issue("compiler-argv", f"{label} xcrun"))
        if receipt.get("invocationMode") == "direct" and argv[0] != compiler.get("logicalCompilerPath"):
            issues.append(_issue("compiler-argv", f"{label} direct"))
        try:
            output_index = argv.index("-o")
            if output_index + 1 >= len(argv) or argv[output_index + 1] != output.get("path"):
                issues.append(_issue("output-argv", label))
            if not source_paths.issubset(set(argv[output_index + 2:])):
                issues.append(_issue("source-argv", label))
        except ValueError:
            issues.append(_issue("output-argv", label))
    raw = _validate_file_field(reader, output, f"{label} output binary", issues)
    if raw is not None and _hash(raw) != binary_hash:
        issues.append(_issue("binary-join", label))
    if isinstance(output, dict) and output.get("sha256") != binary_hash:
        issues.append(_issue("binary-join", label))


def _origin_refs(capture: dict[str, Any], issues: list[str]) -> dict[str, Any] | None:
    origin = capture.get("macOrigin")
    if not isinstance(origin, dict):
        issues.append(_issue("missing-origin"))
        return None
    if origin.get("version") != "1":
        issues.append(_issue("origin-version"))
    required = ("summary", "case", "source", "binary", "compilerReceipt")
    for key in required:
        _ref(origin.get(key), key, issues)
    return origin


def mac_origin_admission_issues(capture: dict[str, Any], reader: Reader) -> list[str]:
    """Return fail-closed origin issues for one Mac capture.

    ``reader(ref)`` must return raw bytes for exactly supplied ``ref``.  Ref
    dicts must contain ``path`` and ``sha256`` and may contain ``bytes``.  Main
    refs under ``capture['macOrigin']`` are ``summary``, ``case``, ``source``,
    ``binary`` and ``compilerReceipt``.  Optional ``auxiliaryAX`` contains
    ``receipt``, ``source`` and ``binary`` refs.  This callback checks origin
    only; it never grants parity or promotion.
    """
    issues: list[str] = []
    if not isinstance(capture, dict):
        return [_issue("capture-shape")]
    if capture.get("platform") != "macos":
        return [_issue("platform", "macos required")]
    origin = _origin_refs(capture, issues)
    if origin is None:
        return sorted(set(issues))
    summary, _ = _json(reader, origin.get("summary"), "summary", issues)
    case, _ = _json(reader, origin.get("case"), "case", issues)
    receipt, _ = _json(reader, origin.get("compilerReceipt"), "compiler receipt", issues)
    source_raw = _read(reader, origin.get("source"), "source", issues)
    binary_raw = _read(reader, origin.get("binary"), "binary", issues)
    if summary is None or case is None or receipt is None or source_raw is None or binary_raw is None:
        return sorted(set(issues))
    capture_case = capture.get("case")
    if not isinstance(capture_case, dict) or capture_case.get("id") != case.get("id") or capture_case.get("hash") != canonical_hash(case):
        issues.append(_issue("case-join"))
    if not isinstance(capture_case, dict) or capture_case.get("hash") != canonical_hash(case):
        issues.append(_issue("wrong-case"))
    if (not isinstance(summary.get("case"), dict)
            or {key: summary["case"].get(key) for key in ("id", "hash")}
            != {key: capture_case.get(key) for key in ("id", "hash")}):
        issues.append(_issue("summary-case-join"))
    if summary.get("candidateOnly") is not True or summary.get("acceptance") == "accepted":
        issues.append(_issue("candidate-policy"))
    source_ref, binary_ref = origin.get("source"), origin.get("binary")
    source_hash, binary_hash = source_ref.get("sha256"), binary_ref.get("sha256")
    if summary.get("sourceHash") != source_hash:
        issues.append(_issue("source-join", "summary"))
    if summary.get("binaryHash") != binary_hash:
        issues.append(_issue("binary-join", "summary"))
    main_sources = receipt.get("compiler", {}).get("sourceBefore", {}) if isinstance(receipt.get("compiler"), dict) else {}
    if isinstance(main_sources, dict) and summary.get("compiledAdapterHash"):
        adapter = main_sources.get("CaptureHost.swift", {})
        if adapter.get("sha256") != summary.get("compiledAdapterHash"):
            issues.append(_issue("source-join", "summary compiled adapter"))
    if receipt.get("compiler") and receipt["compiler"].get("outputBinary", {}).get("sha256") != binary_hash:
        issues.append(_issue("binary-join", "receipt"))
    embedded = summary.get("compilerReceipt")
    if not isinstance(embedded, dict) or canonical_hash(embedded) != canonical_hash(receipt):
        issues.append(_issue("receipt-join", "summary/compilerReceipt"))
    expected_source_hashes = {source_hash}
    _validate_receipt(reader, receipt, source_hashes=expected_source_hashes, binary_hash=binary_hash,
                      source_names=None, label="main", issues=issues)
    ax = origin.get("auxiliaryAX")
    if ax is not None:
        if not isinstance(ax, dict):
            issues.append(_issue("ax-shape"))
        else:
            for key in ("receipt", "source", "binary"):
                _ref(ax.get(key), f"ax.{key}", issues)
            ax_receipt, _ = _json(reader, ax.get("receipt"), "AX receipt", issues)
            ax_source = _read(reader, ax.get("source"), "AX source", issues)
            ax_binary = _read(reader, ax.get("binary"), "AX binary", issues)
            if ax_receipt is not None and ax_source is not None and ax_binary is not None:
                ax_hashes = {ax.get("source", {}).get("sha256")}
                _validate_receipt(reader, ax_receipt, source_hashes=ax_hashes, binary_hash=ax.get("binary", {}).get("sha256"),
                                  source_names={"AXClient.swift"}, label="AX", issues=issues)
                client = summary.get("freshAXClient", {})
                if (client.get("externalAX") != "AVAILABLE"
                        or client.get("sourceHash") != ax.get("source", {}).get("sha256")
                        or client.get("binaryHash") != ax.get("binary", {}).get("sha256")
                        or client.get("compilerReceiptHash") != ax.get("receipt", {}).get("sha256")
                        or client.get("compilerStatus") != "SUCCESS"
                        or client.get("compilerExitCode") != 0):
                    issues.append(_issue("ax-join"))
    return sorted(set(issues))


def mac_origin_admission_report(capture: dict[str, Any], reader: Reader) -> dict[str, Any]:
    """Return origin-only result while preserving candidate/parity boundaries."""
    issues = mac_origin_admission_issues(capture, reader)
    return {
        "kind": "mac-origin-admission",
        "version": "1",
        "status": "PASS" if not issues else "BLOCKED",
        "originQualified": not issues,
        "candidateOnly": True,
        "parityGranted": False,
        "promotionEligible": False,
        "issues": issues,
    }

