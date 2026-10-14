"""Scan every Swift file of the Pulse Mac notch for AppKit / macOS platform services."""
import json
import re
from pathlib import Path

import lexer


def scan(root, services_json):
    root = Path(root)
    spec = json.loads(Path(services_json).read_text())["services"]
    compiled = [(s, [re.compile(p) for p in s["patterns"]]) for s in spec]
    result = {s["id"]: {"hits": 0, "files": {}, "first": {}, "examples": []} for s in spec}
    for p in sorted(root.rglob("*.swift")):
        rel = str(p.relative_to(root))
        code = lexer.strip(p.read_text(errors="replace"))
        for i, line in enumerate(code.splitlines(), 1):
            for s, rxs in compiled:
                if any(rx.search(line) for rx in rxs):
                    r = result[s["id"]]
                    r["hits"] += 1
                    r["files"][rel] = r["files"].get(rel, 0) + 1
                    r["first"].setdefault(rel, i)
    for r in result.values():
        top = sorted(r["files"].items(), key=lambda kv: (-kv[1], kv[0]))[:3]
        r["examples"] = [(f, r["first"][f]) for f, _ in top]
        del r["first"]
    return spec, result


if __name__ == "__main__":
    import sys
    spec, res = scan(sys.argv[1], sys.argv[2])
    for s in spec:
        r = res[s["id"]]
        print(f'{s["id"]:22} {r["hits"]:4} hits {len(r["files"]):3} files', r["examples"][:2])
