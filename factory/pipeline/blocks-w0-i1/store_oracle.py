#!/usr/bin/env python3
"""Stores the Mac oracle (mac_oracle.swift output) into ./expected: oracle.json plus <id>.rgba.z (zlib level 9) per case; identical buffers are stored once (oracle.json then carries
"sameAs": the first id with that buffer). usage: store_oracle.py ORACLE_DIR"""
import hashlib, json, sys, zlib
from pathlib import Path
src = Path(sys.argv[1]); dst = Path(__file__).resolve().parent / "expected"
dst.mkdir(exist_ok=True)
for f in dst.iterdir(): f.unlink()
d = json.loads((src / "oracle.json").read_text())
seen = {}
for c in d["cases"]:
    p = src / f"{c['id']}.rgba"
    if not p.exists(): continue
    raw = p.read_bytes(); h = hashlib.sha256(raw).hexdigest(); c["sha256"] = h
    raw_p = src / f"{c['id']}.raw.rgba"
    if raw_p.exists(): (dst / f"{c['id']}.raw.rgba.z").write_bytes(zlib.compress(raw_p.read_bytes(), 9))
    if h in seen: c["sameAs"] = seen[h]; continue
    seen[h] = c["id"]
    (dst / f"{c['id']}.rgba.z").write_bytes(zlib.compress(raw, 9))
(dst / "oracle.json").write_text(json.dumps(d, indent=1, sort_keys=True) + "\n")
print(len(d["cases"]), "cases,", sum(f.stat().st_size for f in dst.iterdir()), "bytes")
