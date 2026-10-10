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


def _is_f6_completion(event):
    p = event.get("payload") or {}
    return (event.get("fixture") == "F6" and event.get("node_id") == "animation"
            and p.get("phase") == "complete" and p.get("tag") in ("A", "B"))


def f6_unordered_completions(seq):
    """CONTRACT C9 (proposed): the F6 animation A-complete/B-complete pair is unordered.
    Only the two completion events permute: they keep their slots in the node sequence and are re-assigned in
    tag order. Start events, every other event, slot positions, exactly-once and the final state stay exact:
    a duplicate, missing or misplaced completion still changes the sequence. `seq` is a list of normalized
    JSON lines of one node; returns the canonical list."""
    events = [json.loads(line) for line in seq]
    slots = [i for i, e in enumerate(events) if _is_f6_completion(e)]
    if len(slots) < 2:
        return seq
    ordered = sorted((seq[i] for i in slots), key=lambda line: json.loads(line)["payload"]["tag"])
    out = list(seq)
    for i, line in zip(slots, ordered):
        out[i] = line
    return out


def canonical_body(lines):
    steps = {}
    for line in lines:
        event = json.loads(line)
        nodes = steps.setdefault(event.get("step", ""), {})
        nodes.setdefault(event.get("node_id", ""), []).append(line)
    parts = [CANONICAL_FORM]
    for step, nodes in steps.items():
        groups = sorted("\n".join(f6_unordered_completions(seq)) for seq in nodes.values())
        parts.append(f"#{step}\n" + "\n".join(groups))
    return "\n".join(parts)


def canonical_digest(path):
    """Canonical form v2 (CONTRACT section 3): group by driver step (steps keep their order), then by node.
    Nodes inside a step may permute (sorted); each node's event sequence keeps its recorded order.
    Must stay identical to qualification/run.py canonical_body. Reported separately from the raw hash."""
    return hashlib.sha256(canonical_body(normalized_lines(path)).encode("utf-8")).hexdigest()


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
