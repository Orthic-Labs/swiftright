#!/usr/bin/env python3
"""Stage Text Windows package from explicit reviewed Swift source rows."""
from __future__ import annotations
import argparse, hashlib, json, os, stat, sys
from pathlib import Path
MAX_JSON = 2 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
CHUNK = 1024 * 1024
class StageError(RuntimeError): pass
def regular(path: Path, limit: int):
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): raise StageError(f"regular non-symlink required: {path}")
    if st.st_size > limit: raise StageError(f"size limit exceeded: {path}")
    return st
def digest(path: Path, limit: int = MAX_SOURCE):
    regular(path, limit); h = hashlib.sha256(); total = 0
    with path.open("rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b: break
            total += len(b); h.update(b)
            if total > limit: raise StageError(f"size grew past limit: {path}")
    return h.hexdigest(), total
def load_json(path: Path):
    _, size = digest(path, MAX_JSON)
    if size > MAX_JSON: raise StageError("JSON limit")
    try: return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as e: raise StageError(f"invalid JSON {path}: {e}")
def safe_rel(raw: str) -> Path:
    if not isinstance(raw, str) or not raw or raw.startswith(("/", "\\")) or ":" in raw: raise StageError(f"unsafe source row: {raw!r}")
    p = Path(raw)
    if any(part in ("", ".", "..") for part in p.parts) or "\\" in raw: raise StageError(f"unsafe source row: {raw!r}")
    return p
def copy_file(src: Path, dst: Path) -> int:
    digest(src, MAX_SOURCE); dst.parent.mkdir(parents=True, exist_ok=True)
    with src.open("rb") as fi, dst.open("xb") as fo:
        total = 0
        while True:
            b = fi.read(CHUNK)
            if not b: break
            total += len(b); fo.write(b)
    return total
def replace_file(src: Path, dst: Path) -> int:
    digest(src, MAX_SOURCE)
    if not dst.is_file() or dst.is_symlink(): raise StageError(f"owned replacement target required: {dst}")
    with src.open("rb") as fi, dst.open("wb") as fo:
        total = 0
        while True:
            b = fi.read(CHUNK)
            if not b: break
            total += len(b); fo.write(b)
    return total
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-package", required=True, type=Path)
    ap.add_argument("--base-manifest", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--witness", required=True, type=Path)
    ap.add_argument("--candidate", default="swiftui.text.layout.baseline.pilot-next")
    ns = ap.parse_args()
    manifest = load_json(ns.base_manifest)
    if manifest.get("kind") not in ("factory-rectangle-source-manifest-v1", "factory-source-manifest-v1", "factory-rectangle-root-stage-v1"): raise StageError("unexpected base manifest kind")
    if ns.output.exists(): raise StageError("fresh output required")
    witness_hash, witness_bytes = digest(ns.witness, MAX_SOURCE)
    rows = manifest.get("rows", manifest.get("files"))
    if not isinstance(rows, list) or not rows: raise StageError("explicit source rows required")
    total = 0; staged = []; base_witness = None
    marker = "factory/native/windows/pilot-rectangle-root-v1/package/"
    # Manifest paths are repository-relative; only explicit package rows accepted.
    for row in rows:
        rel = safe_rel(row.get("path"))
        rel_text = str(rel).replace(os.sep, "/")
        if rel_text.startswith("package/"):
            package_rel = Path(rel_text[len("package/"):])
            src = ns.base_package / package_rel
        elif rel_text.startswith(marker):
            package_rel = Path(rel_text[len(marker):])
            src = ns.base_package / package_rel
        else:
            continue
        actual, size = digest(src, MAX_SOURCE)
        expected = str(row.get("sha256", "")).removeprefix("sha256:").lower()
        if actual != expected or size != int(row.get("bytes", -1)): raise StageError(f"package source drift: {package_rel}")
        dst = ns.output / package_rel; copy_file(src, dst); total += size
        if total > MAX_TOTAL: raise StageError("source closure total limit")
        staged.append({"path": str(package_rel).replace(os.sep, "/"), "bytes": size, "sha256": "sha256:" + actual, "role": row.get("role", "source")})
        if str(package_rel).replace(os.sep, "/") == "Sources/FactoryProbe/Witness.swift": base_witness = (actual, size)
    if not staged: raise StageError("no explicit package rows")
    if base_witness is None: raise StageError("explicit base Witness.swift row required")
    dst_witness = ns.output / "Sources" / "FactoryProbe" / "Witness.swift"
    replace_file(ns.witness, dst_witness)
    staged = [r for r in staged if r["path"] != "Sources/FactoryProbe/Witness.swift"]
    staged.append({"path":"Sources/FactoryProbe/Witness.swift", "bytes":witness_bytes, "sha256":"sha256:"+witness_hash, "role":"text-witness"})
    witness_manifest = ns.output / "witness.manifest.json"
    witness_manifest.write_text(json.dumps({"kind":"factory-text-prebuild-witness-v1", "version":1,
        "candidate":ns.candidate, "case":None, "qualification":"prebuild-no-measured-case",
        "sourceHash":"sha256:"+witness_hash}, indent=2)+"\n", encoding="utf-8")
    witness_manifest_hash, witness_manifest_bytes = digest(witness_manifest, MAX_JSON)
    for r in staged:
        if r["path"] == "witness.manifest.json":
            r.update(bytes=witness_manifest_bytes, sha256="sha256:"+witness_manifest_hash, role="text-witness-manifest")
    main_path = ns.output / "Sources" / "FactoryProbe" / "main.swift"
    regular(main_path, MAX_SOURCE)
    raw = main_path.read_text(encoding="utf-8")
    replacements = {
        "Witness_shapes_rectangle_fill()": "Witness_swiftui_text_layout_baseline()",
        "fontSize: 16, lineHeight: 24": "fontSize: 24, lineHeight: 29",
        'bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)': 'bridge.run(title: "Alchemist FactoryProbe", width: 120, height: 48)',
    }
    for old, new in replacements.items():
        if raw.count(old) != 1: raise StageError(f"expected one transform site: {old}")
        raw = raw.replace(old, new)
    main_path.write_text(raw, encoding="utf-8")
    main_hash, main_bytes = digest(main_path, MAX_SOURCE)
    for r in staged:
        if r["path"] == "Sources/FactoryProbe/main.swift": r.update(bytes=main_bytes, sha256="sha256:"+main_hash)
    package = {"kind":"factory-text-windows-package-source-v1", "version":1, "candidate":ns.candidate,
               "baseManifest": str(ns.base_manifest), "witnessHash":"sha256:"+witness_hash,
               "semanticTransforms":["Text witness", "system regular 24pt", "window 120x48", "background orderBack retained"],
               "rows":staged, "sourceOnly":True, "nativeActions":0}
    out_manifest = ns.output / "text-package-source-manifest.json"
    out_manifest.write_text(json.dumps(package, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status":"staged-source-only", "output":str(ns.output), "rows":len(staged), "bytes":sum(r["bytes"] for r in staged), "manifest":str(out_manifest)}, sort_keys=True))
    return 0
if __name__ == "__main__":
    try: raise SystemExit(main())
    except StageError as e: print(f"stage_text_windows_package: {e}", file=sys.stderr); raise SystemExit(2)
