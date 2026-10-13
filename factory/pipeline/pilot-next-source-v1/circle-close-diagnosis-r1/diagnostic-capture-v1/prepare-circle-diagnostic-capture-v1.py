#!/usr/bin/env python3
"""Bounded source-only staging for Circle diagnostic Count1.
No compiler/native/remote action. Existing destination is always rejected.
"""
from __future__ import annotations
import argparse, hashlib, json, stat
from pathlib import Path
MAX_FILES=256; MAX_FILE=64*1024*1024; MAX_TOTAL=256*1024*1024; BUF=1024*1024

def regular(p: Path, limit=MAX_FILE):
    st=p.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size>limit: raise RuntimeError(f'unsafe/big source: {p}')
    return st

def digest(p: Path, limit=MAX_FILE):
    st=regular(p,limit); h=hashlib.sha256(); n=0
    with p.open('rb') as f:
        while True:
            b=f.read(BUF)
            if not b: break
            n+=len(b)
            if n>limit: raise RuntimeError(f'source grew past limit: {p}')
            h.update(b)
    if regular(p,limit).st_size!=n: raise RuntimeError(f'source changed while read: {p}')
    return h.hexdigest(),n

def copy_one(src,dst):
    h,n=digest(src); dst.parent.mkdir(parents=True,exist_ok=True)
    with src.open('rb') as r, dst.open('xb') as w:
        while True:
            b=r.read(BUF)
            if not b: break
            w.write(b)
    if digest(dst)!=(h,n): raise RuntimeError(f'copy verification failed: {src}')
    return h,n

def bounded_json(p):
    h,n=digest(p,2*1024*1024)
    return json.loads(p.read_text(encoding='utf-8-sig')),h,n

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--donor-root',required=True); ap.add_argument('--output-root',required=True); ap.add_argument('--source-inputs',required=True); ap.add_argument('--diagnostic-overlay',required=True); ap.add_argument('--output-source-inputs',required=True); a=ap.parse_args()
    donor,out,si,overlay,outsi=map(Path,(a.donor_root,a.output_root,a.source_inputs,a.diagnostic_overlay,a.output_source_inputs))
    if out.exists(): raise RuntimeError('fresh destination already exists')
    if not donor.is_dir() or not overlay.is_dir(): raise RuntimeError('source roots missing')
    source,_,_=bounded_json(si)
    if source.get('kind')!='factory-circle-source-inputs-diagnostic-v1' or source.get('count')!=1: raise RuntimeError('diagnostic source-input kind/count required')
    count=total=0
    for src in sorted(p for p in donor.rglob('*') if p.is_file()):
        rel=src.relative_to(donor)
        if rel.is_absolute() or any(x in ('','.','..') for x in rel.parts): raise RuntimeError('unsafe donor path')
        if count>=MAX_FILES: raise RuntimeError('file-count cap')
        _,n=copy_one(src,out/rel); count+=1; total+=n
        if total>MAX_TOTAL: raise RuntimeError('source-total cap')
    names=('diagnostic-profile.ps1','integration-fresh-circle-diagnostic-v1.ps1','final-plan-eligibility-diagnostic-v1.ps1','capture-circle-diagnostic-single-v1.ps1','dispatch-circle-diagnostic-single-v1.ps1','coordinator-count1-diagnostic-v1.ps1','capture-build-preflight-diagnostic-v1.ps1','issue-circle-diagnostic-metadata-v1.ps1')
    for name in names:
        src=overlay/name
        if not src.is_file(): raise RuntimeError(f'missing diagnostic overlay: {name}')
        _,n=copy_one(src,out/'overlay'/name); count+=1; total+=n
        if count>MAX_FILES or total>MAX_TOTAL: raise RuntimeError('diagnostic source cap')
    copy_one(si,outsi)
    print(json.dumps({'status':'staged-source-only','files':count,'bytes':total,'sourceInputs':str(outsi),'nativeActions':0,'compilerActions':0,'remoteActions':0,'lockActions':0},sort_keys=True))
if __name__=='__main__': main()
