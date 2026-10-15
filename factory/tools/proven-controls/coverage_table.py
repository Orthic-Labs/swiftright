#!/usr/bin/env python3
"""A Skip-style graded coverage table, generated from docs/proven-controls.json (never edited by hand).
  python3 factory/tools/proven-controls/coverage_table.py [--check]      writes docs/coverage-table.md (--check: fail when it is stale)

One row per SwiftUI type or member that a delivered block names (manifest symbols and the types/modifiers its case witnesses use), graded by the BEST block that proves it:
  A  delivered: paired with the Mac at N >= 20 on every case, independently reviewed (status `delivered`, no caveats)
  B  delivered with caveats: as A, with listed limits (`delivered-with-caveats`)
  C  delivered-pending-review: passed its deciding gates at N = 20, Oracle has not reviewed it yet (`delivered-pending-review`)
  D  in progress; E  not delivered. APIs no block names are not listed: they are "not proven" (the file's `apisNotCovered` hint).
The grade is about the evidence for the API in the block that proves it, not about every combination of arguments: read the block's caveats for the limits."""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
SRC, OUT = ROOT / "docs/proven-controls.json", ROOT / "docs/coverage-table.md"
GRADE = {"delivered": "A", "delivered-with-caveats": "B", "delivered-pending-review": "C", "in-progress": "D", "not-delivered": "E"}


def build():
    d = json.loads(SRC.read_text())
    best = {}
    for b in d["blocks"]:
        g = GRADE.get(b["status"], "E")
        apis = set(b["apis"]["fromManifest"]) | set(b["apis"]["fromCaseSources"]["types"]) | set(b["apis"]["fromCaseSources"]["modifiersAndMembers"])
        for a in apis:
            cur = best.get(a)
            if cur is None or g < cur[0]: best[a] = (g, b["block"], b.get("casesPassingDecidingGate"))
    lines = ["# SwiftRight coverage table (generated)", "",
             f"Generated from `docs/proven-controls.json` (status date {d['statusDate']}) by `factory/tools/proven-controls/coverage_table.py`. Do not edit by hand.", "",
             "Grades: **A** delivered and independently reviewed; **B** delivered with caveats; **C** delivered, passed N=20 paired gates, not yet reviewed; **D** in progress; **E** not delivered.",
             "The grade is the best block's; read that block's caveats in `docs/proven-controls.json` before relying on an argument combination. An API not listed here is not proven.", "",
             "| API | Grade | Proven by | Cases passing |", "| --- | --- | --- | --- |"]
    for a in sorted(best, key=lambda x: (best[x][0], x.lower())):
        g, blk, n = best[a]
        lines.append(f"| `{a}` | {g} | {blk} | {n} |")
    counts = {}
    for g, _, _ in best.values(): counts[g] = counts.get(g, 0) + 1
    lines += ["", "Totals: " + ", ".join(f"{k}: {counts[k]}" for k in sorted(counts)) + f" ({len(best)} APIs).", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    text = build()
    if "--check" in sys.argv:
        sys.exit(0 if OUT.exists() and OUT.read_text() == text else "docs/coverage-table.md is stale: run coverage_table.py")
    OUT.write_text(text); print("wrote", OUT, len(text.splitlines()), "lines")
