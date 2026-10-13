#!/usr/bin/env python3
"""Pack explicitly named sources with bounded streaming hashes; never executes them."""
from __future__ import annotations
import argparse, hashlib, json, stat, zipfile
from pathlib import Path

MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 128 * 1024 * 1024
MAX_FILES = 128
MAX_INPUTS = 2 * 1024 * 1024
class Hold(ValueError): pass

def digest(path: Path):
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode): raise Hold(f"not regular: {path}")
    if st.st_size > MAX_FILE: raise Hold(f"file bound: {path}")
    h = hashlib.sha256(); n = 0
    with path.open("rb") as src:
        while True:
            block = src.read(1024 * 1024)
            if not block: break
            n += len(block); h.update(block)
            if n > MAX_FILE: raise Hold(f"file grew: {path}")
    if n != st.st_size: raise Hold(f"file changed: {path}")
    return h.hexdigest(), n

def read_inputs(path: Path):
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > MAX_INPUTS: raise Hold("inputs metadata bound")
    raw = path.read_bytes()
    if len(raw) != st.st_size: raise Hold("inputs metadata changed")
    try: return json.loads(raw.decode("utf-8-sig")), raw
    except Exception as exc: raise Hold("inputs metadata invalid JSON") from exc

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--inputs", required=True, type=Path)
    ap.add_argument("--root", required=True, type=Path)
    ap.add_argument("--output-zip", required=True, type=Path)
    ap.add_argument("--metadata", required=True, type=Path)
    ap.add_argument("--files", nargs="+", required=True, type=Path)
    a = ap.parse_args()
    data, raw_inputs = read_inputs(a.inputs)
    if data.get("kind") not in ("factory-padding-source-inputs-v2", "factory-padding-source-inputs-v3"): raise Hold("inputs kind")
    if len(a.files) > MAX_FILES: raise Hold("file count")
    root = a.root.resolve()
    rows = []; total = 0; seen = set()
    for supplied in a.files:
        supplied_abs = supplied.absolute()
        if supplied_abs.is_symlink(): raise Hold(f"symlink source: {supplied}")
        path = supplied_abs.resolve()
        try: rel = path.relative_to(root)
        except ValueError: raise Hold(f"source outside root: {path}")
        if not rel.parts or any(part in ("", ".", "..") for part in rel.parts): raise Hold("unsafe relative path")
        key = rel.as_posix()
        if key in seen: raise Hold(f"duplicate source: {key}")
        seen.add(key)
        sha, n = digest(path)
        total += n
        if total > MAX_TOTAL: raise Hold("total source bytes")
        rows.append({"path": str(path), "relativePath": key, "zipPath": "sources/" + key, "sha256": sha, "bytes": n})
    if a.output_zip.exists() or a.metadata.exists(): raise Hold("fresh outputs required")
    a.output_zip.parent.mkdir(parents=True, exist_ok=True); a.metadata.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(a.output_zip, "x", compression=zipfile.ZIP_DEFLATED) as z:
        for supplied, row in zip(a.files, rows): z.write(supplied.resolve(), row["zipPath"])
    meta = {"kind": "factory-padding-source-pack-v2", "sourceInputsPath": str(a.inputs.resolve()),
            "sourceInputsSha256": hashlib.sha256(raw_inputs).hexdigest(), "count": data.get("count"),
            "rows": rows, "entryCount": len(rows), "totalBytes": total, "nativeActions": 0,
            "compilerActions": 0, "lockActions": 0}
    a.metadata.write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(meta, separators=(",", ":")))

if __name__ == "__main__":
    try: main()
    except Exception as exc: raise SystemExit("HOLD: " + str(exc))
