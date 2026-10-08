#!/usr/bin/env python3
"""Normalize a fixture JSONL trace (drop mono_ns, sorted keys) and print its stable SHA-256.

Usage: normalize-hash.py <trace.jsonl> [...]  |  --canonical <trace.jsonl> [...]  |  --diff A B
Prints "<sha256>  <path>  <line-count>" per file. Uses hashlib, never Python's salted hash().
With --diff A B, prints a unified diff of the normalized lines of two traces.
"""
import difflib
import hashlib
import json
import sys


def normalized_lines(path):
    lines = []
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            event = json.loads(raw)
            event.pop("mono_ns", None)
            lines.append(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return lines


def canonical_digest(path):
    """Order-insensitive within each driver step: sibling lifecycle/effect events inside one step may
    interleave differently in SwiftUI's internal pass order. Reported separately from the raw hash."""
    groups = {}
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            event = json.loads(raw)
            event.pop("mono_ns", None)
            groups.setdefault(event.get("step", ""), []).append(json.dumps(event, sort_keys=True, separators=(",", ":")))
    body = "\n".join(f"#{step}\n" + "\n".join(sorted(lines)) for step, lines in groups.items())
    return hashlib.sha256(body.encode("utf-8")).hexdigest()


def main(argv):
    if len(argv) >= 3 and argv[1] == "--canonical":
        for path in argv[2:]:
            print(f"{canonical_digest(path)}  {path}")
        return 0
    if len(argv) == 4 and argv[1] == "--diff":
        a, b = normalized_lines(argv[2]), normalized_lines(argv[3])
        for line in difflib.unified_diff(a, b, "run-a", "run-b", lineterm="", n=1):
            print(line)
        return 0
    for path in argv[1:]:
        lines = normalized_lines(path)
        digest = hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()
        print(f"{digest}  {path}  {len(lines)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
