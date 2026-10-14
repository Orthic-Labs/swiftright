"""Block coverage from the SR1 manifest: which SwiftUI names a delivered block lists.

The manifest (`factory/registry/manifest.json`) holds precise USRs per block.  A USR such as
`usr:s:7SwiftUI4ViewPAAE7overlay9alignment7contentQr...` is parsed into its length-prefixed
identifiers: [SwiftUI, View, overlay, alignment, content].  The first identifier after the module is
the owning type (or a free function), the second the member (or an initializer label).
"""
import json
import re
from collections import defaultdict
from pathlib import Path


def idents(usr):
    s = usr.split(":", 2)[-1] if usr.startswith("usr:") else usr
    if s.startswith("s:"):
        s = s[2:]
    out, i, n = [], 0, len(s)
    while i < n:
        j = i
        while j < n and s[j].isdigit():
            j += 1
        if j > i and j < n and (s[j].isalpha() or s[j] == "_"):
            ln = int(s[i:j])
            if j + ln <= n:
                out.append(s[j:j + ln])
                i = j + ln
                continue
        i += 1
    return out


def load(manifest_path):
    m = json.loads(Path(manifest_path).read_text())
    types = defaultdict(set)       # type name -> blocks
    members = defaultdict(set)     # (ctx, member) -> blocks
    labels = defaultdict(set)      # type -> init labels / member names seen in its USRs
    blocks = []
    for b in m["blocks"]:
        blocks.append({"id": b["id"], "symbols": len(b["symbols"]), "progress": b.get("progress"),
                       "status": b.get("inventoryStatus")})
        for u in b["symbols"]:
            t = [x for x in idents(u) if x not in ("SwiftUI", "SwiftUICore")]
            if not t:
                continue
            types[t[0]].add(b["id"])
            if len(t) > 1:
                members[(t[0], t[1])].add(b["id"])
                for x in t[1:4]:
                    labels[t[0]].add(x)
    return {"types": types, "members": members, "labels": labels, "blocks": blocks, "id": m.get("id")}


def witness_files(pipeline, roots):
    """Witness.swift sources of delivered cases (mac-source copies, never run directories)."""
    out = []
    pipeline = Path(pipeline)
    for pat in roots:
        for p in sorted(pipeline.glob(pat)):
            if "/runs/" in str(p):
                continue
            out.append(p)
    return out
