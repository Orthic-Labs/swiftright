#!/usr/bin/env python3
"""Source-only controls for Count1 UIA worker fast-exit receipt path.

This packet does not launch PowerShell or a child process. It mutates source text
in memory to model StartTime failure after Process.Handle retention, then checks
that raw-stream, failure-receipt, cleanup, & terminal evidence paths remain.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "uia-worker-invoke-v2.ps1"
MAX_SOURCE_BYTES = 128 * 1024


def bounded_source(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or st.st_size > MAX_SOURCE_BYTES:
        raise RuntimeError("worker overlay source must be regular & <=128KiB")
    data = path.read_bytes()
    if len(data) != st.st_size:
        raise RuntimeError("worker overlay changed while read")
    return data.decode("utf-8")


def source_digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def assert_fast_exit_contract(text: str) -> None:
    handle = text.index("$handle=$p.Handle")
    streams = text.index("$streams[0].source=$p.StandardOutput.BaseStream")
    start_time = text.find("$startedAt=$p.StartTime")
    synthetic_start = text.find("synthetic-fast-exit-before-start-time")
    if start_time < 0 and synthetic_start < 0:
        raise AssertionError("worker must retain StartTime probe or explicit fast-exit fixture")
    if start_time >= 0 and not handle < streams < start_time:
        raise AssertionError("worker handle/raw streams must precede StartTime probe")
    if synthetic_start >= 0 and not handle < streams < synthetic_start:
        raise AssertionError("fast-exit fixture must follow retained handle/raw streams")
    required = (
        "identityStatus",
        "identityError",
        "final-start.json",
        "worker-exit-failure.json",
        "worker-exit.json",
        "final-exit-certificate.json",
        "try{$proof.cleanup=Invoke-FactoryOwnedCleanup",
        "sealed-raw",
    )
    for marker in required:
        if marker not in text:
            raise AssertionError(f"missing fast-exit receipt marker: {marker}")
    if not re.search(r"catch\{\s*\$cleanupError=\[string\]\$_", text):
        raise AssertionError("cleanup helper error must be durably recorded")
    if "Get-Process" in text:
        raise AssertionError("worker overlay must use retained Process handle, not PID lookup")


def expect_reject(text: str, needle: str) -> None:
    try:
        assert_fast_exit_contract(text)
    except (AssertionError, ValueError):
        return
    raise AssertionError(f"fault did not reject: {needle}")


def main() -> int:
    text = bounded_source(SOURCE)
    assert_fast_exit_contract(text)

    # Synthetic fast-exit fault: StartTime fails after handle/stream binding.
    fast_exit = text.replace(
        "try{$startedAt=$p.StartTime.ToUniversalTime().ToString('o')}catch{$startedAt=$null;$identityError=[string]$_}",
        "$startedAt=$null;$identityError='synthetic-fast-exit-before-start-time'",
        1,
    )
    if fast_exit == text:
        raise AssertionError("fast-exit mutation was a no-op")
    assert_fast_exit_contract(fast_exit)

    expect_reject(text.replace("$handle=$p.Handle", "$handle=$null", 1), "missing retained handle")
    expect_reject(text.replace("$streams[0].source=$p.StandardOutput.BaseStream", "$streams[0].source=$null", 1), "raw stream bound after identity")
    expect_reject(text.replace("try{$proof.cleanup=Invoke-FactoryOwnedCleanup", "$proof.cleanup=Invoke-FactoryOwnedCleanup", 1), "unguarded cleanup")
    # Remove every publication reference: changing only first occurrence leaves
    # second path intact & falsely makes missing-terminal fault admissible.
    missing_terminal = text.replace("worker-exit.json", "worker-exit-missing.json")
    if missing_terminal == text:
        raise AssertionError("missing-terminal mutation was a no-op")
    expect_reject(missing_terminal, "missing terminal receipt")

    receipt = {
        "kind": "factory-uia-worker-fast-exit-source-control-v1",
        "source": str(SOURCE),
        "sourceSha256": source_digest(SOURCE),
        "nativeActions": 0,
        "compilerActions": 0,
        "fastExitFixture": "StartTime-failure-after-handle-and-stream-binding",
        "status": "SOURCE_CONTROLS_PASS",
        "faultsRejected": 4,
    }
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
