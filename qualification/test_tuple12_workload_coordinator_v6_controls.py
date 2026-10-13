#!/usr/bin/env python3
"""Pure source controls for coordinator v6 CRLF proof normalization; no native execution."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/workload-coordinator-v6/workload-coordinator.ps1"


def fail(name):
    raise SystemExit("WORKLOAD_COORD_V6_CONTROLS_FAIL " + name)


def main():
    source = SRC.read_text(encoding="utf-8")
    functions = ["Semantic-RunProof", "Strict-RunProof", "Started-CleanupProof"]
    for fn in functions:
        start = source.index("function " + fn)
        next_fn = source.find("\nfunction ", start + 10)
        body = source[start:] if next_fn < 0 else source[start:next_fn]
        if '$text = $text -replace "`r`n", "`n"' not in body:
            fail("missing-crlf-normalization:" + fn)
    if "function PresentMon-Proof" not in source or "session_absent=True" not in source:
        fail("presentmon-proof-missing")
    if "cleanupProof=Started-CleanupProof" not in source:
        fail("cleanup-proof-join-missing")

    # Exercise CRLF behavior: .NET-style line anchors see CR before LF unless
    # source normalizes first.
    sample = "pid_exit run=r1 handle=123 kernel_terminal=1 kernel_exit_raw=0 kernel_exit=0 dotnet_exit=0\r\n"
    line_pattern = r"(?m)^pid_exit run=r1 .*kernel_terminal=1 .*kernel_exit_raw=[0-9]+ kernel_exit=-?[0-9]+ dotnet_exit=-?[0-9]+$"
    if re.search(line_pattern, sample):
        fail("crlf-fault-model")
    if not re.search(line_pattern, sample.replace("\r\n", "\n")):
        fail("lf-normalized-model")

    # Mutation removing each normalizer is rejected.
    faults = {}
    for fn in functions:
        start = source.index("function " + fn)
        marker = '  $text = $text -replace "`r`n", "`n"\n'
        pos = source.index(marker, start)
        faults[fn] = source[:pos] + source[pos + len(marker):]
    for name, mutated in faults.items():
        start = mutated.index("function " + name)
        next_fn = mutated.find("\nfunction ", start + 10)
        body = mutated[start:] if next_fn < 0 else mutated[start:next_fn]
        if '$text = $text -replace "`r`n", "`n"' in body:
            fail("fault-accepted:" + name)
    print({
        "kind": "sr0-tuple12-workload-coordinator-v6-controls",
        "status": "passed",
        "sourceSha256": hashlib.sha256(SRC.read_bytes()).hexdigest(),
        "functions": functions,
        "faults": ["remove-semantic-normalizer", "remove-strict-normalizer", "remove-cleanup-normalizer"],
    })


if __name__ == "__main__":
    main()
