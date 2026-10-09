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


CANONICAL_FORM = "sr0-a.canonical/v2"


def canonical_digest(path):
    """Canonical form v2 (CONTRACT section 3): group by driver step (steps keep their order), then by node.
    Nodes inside a step may permute (sorted); each node's event sequence keeps its recorded order.
    Must stay identical to qualification/run.py canonical_body. Reported separately from the raw hash."""
    steps = {}
    for line in normalized_lines(path):
        event = json.loads(line)
        nodes = steps.setdefault(event.get("step", ""), {})
        nodes.setdefault(event.get("node_id", ""), []).append(line)
    parts = [CANONICAL_FORM]
    for step, nodes in steps.items():
        groups = sorted("\n".join(seq) for seq in nodes.values())
        parts.append(f"#{step}\n" + "\n".join(groups))
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()


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
