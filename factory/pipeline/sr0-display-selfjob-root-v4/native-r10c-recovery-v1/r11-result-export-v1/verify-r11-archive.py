#!/usr/bin/env python3
"""Bounded verifier for export-r11-results.ps1; emits raw-export-only JSON."""
import argparse, hashlib, json, os, sys, zipfile
from pathlib import Path
MAX_FILES=256; MAX_FILE=8*1024*1024; MAX_JSON=2*1024*1024; MAX_TOTAL=32*1024*1024

def fail(msg): raise SystemExit(f"sr0 r11 archive rejected: {msg}")
def safe_file(p, limit):
    p=Path(p); st=p.stat()
    if not p.is_file() or st.st_size>limit: fail(f"unsafe/oversize file: {p}")
    if any(part.is_symlink() for part in [p,*p.parents]): fail(f"symlink path: {p}")
    return st
def sha_stream(f, limit):
    h=hashlib.sha256(); n=0
    while True:
        b=f.read(65536)
        if not b: break
        n+=len(b)
        if n>limit: fail("stream cap exceeded")
        h.update(b)
    return n,h.hexdigest()
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--archive",required=True); ap.add_argument("--manifest",required=True); ap.add_argument("--output",required=True); a=ap.parse_args()
    ms=safe_file(a.manifest,MAX_JSON)
    try: manifest=json.loads(Path(a.manifest).read_text(encoding="utf-8-sig"))
    except Exception as e: fail(f"manifest JSON: {e}")
    if manifest.get("kind")!="sr0-display-selfjob-r11-result-export-v1" or manifest.get("qualificationClaim") is not False: fail("manifest kind/qualification claim invalid")
    entries=manifest.get("files") or []
    if not 1<len(entries)<=MAX_FILES: fail("manifest file count")
    expected={}; total=0
    for e in entries:
        name=e.get("archivePath"); n=int(e.get("bytes",-1)); h=str(e.get("sha256",""))
        if not name or name.startswith("/") or ".." in Path(name).parts or n<0 or n>MAX_FILE or len(h)!=64: fail("manifest entry invalid")
        if name in expected: fail("duplicate manifest entry")
        total+=n
        if total>MAX_TOTAL: fail("manifest total cap")
        expected[name]=(n,h.lower())
    if total!=int(manifest.get("totalBytes",-1)): fail("manifest total mismatch")
    with zipfile.ZipFile(a.archive) as z:
        infos=z.infolist()
        if len(infos)!=len(expected): fail("archive/manifest count mismatch")
        seen=set(); actualTotal=0
        for i in infos:
            if i.is_dir() or i.filename not in expected or i.filename in seen or i.filename.startswith("/") or ".." in Path(i.filename).parts: fail("archive member mismatch")
            seen.add(i.filename); wantN,wantH=expected[i.filename]
            if i.file_size>MAX_FILE: fail("archive member cap")
            with z.open(i) as f: n,h=sha_stream(f,MAX_FILE)
            if (n,h)!=(wantN,wantH): fail(f"hash/bytes mismatch: {i.filename}")
            if i.filename.lower().endswith(".json") and n>MAX_JSON: fail("JSON member cap")
            actualTotal+=n
        if actualTotal!=total: fail("archive total mismatch")
    result={"kind":"sr0-display-selfjob-r11-archive-verification-v1","status":"raw-export-verified","qualificationClaim":False,"manifestPath":str(Path(a.manifest).resolve()),"archivePath":str(Path(a.archive).resolve()),"fileCount":len(expected),"totalBytes":actualTotal,"rawHashesVerified":True}
    out=Path(a.output); 
    if out.exists(): fail("fresh output required")
    out.parent.mkdir(parents=True,exist_ok=True); tmp=out.with_name(out.name+".tmp")
    tmp.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8"); os.replace(tmp,out)
if __name__=="__main__": main()
