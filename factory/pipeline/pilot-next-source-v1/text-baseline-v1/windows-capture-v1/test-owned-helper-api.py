#!/usr/bin/env python3
"""Offline API compatibility check for Text compiler's retained-handle helper."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

MAX = 64 * 1024
EXPECTED = "sha256:112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e"
REQUIRED = (
    "CreateJob", "ConfigureJobWithFlags", "BuildCommandLine", "CreateSuspended",
    "AssignProcessToJobObject", "ResumeThread", "WaitForSingleObject",
    "GetExitCodeProcess", "ReadActiveProcessCount", "TerminateJobObject",
    "TerminateProcess", "CloseHandle",
)

def read_bounded(path: Path) -> bytes:
    st = path.stat()
    if path.is_symlink() or not path.is_file() or st.st_size > MAX:
        raise ValueError("bounded regular helper source required")
    return path.read_bytes()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=Path(__file__).with_name("Sr0OwnedJobProcess.cs"))
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    data = read_bounded(args.source)
    text = data.decode("utf-8")
    digest = "sha256:" + hashlib.sha256(data).hexdigest()
    checks = {name: (f" {name}(" in text or f" {name} " in text) for name in REQUIRED}
    checks["exact audited helper"] = digest == EXPECTED
    checks["retained suspended launch API"] = "CreateNoWindow" in text and "CREATE_SUSPENDED" in text or "CreateSuspendedFlag" in text
    status = "PASS" if all(checks.values()) else "HELD"
    result = {"kind": "factory-text-owned-helper-api-controls-v1", "status": status, "controlOnly": True, "nativeActions": 0, "compilerActions": 0, "source": {"path": str(args.source), "bytes": len(data), "sha256": digest}, "checks": checks}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if status == "PASS" else 1

if __name__ == "__main__":
    raise SystemExit(main())
