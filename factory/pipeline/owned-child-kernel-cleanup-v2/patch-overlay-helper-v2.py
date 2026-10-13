#!/usr/bin/env python3
"""Bounded prospective overlay rebinder; never mutates donor or overwrites output."""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat
from pathlib import Path
MAX_TEXT=8*1024*1024
MAX_FILE=64*1024*1024
MAX_FILES=256
MAX_TOTAL=256*1024*1024

def safe(root: Path, rel: str) -> Path:
    if not rel or rel.startswith(('/', '\\')) or ':' in rel or '\\' in rel:
        raise ValueError(f'unsafe relative path: {rel!r}')
    p=root.joinpath(*rel.split('/'))
    cur=root
    for part in rel.split('/'):
        cur=cur/part
        if cur.is_symlink(): raise ValueError(f'reparse/symlink path: {rel}')
    if os.path.commonpath((str(root.resolve()),str(p.parent.resolve()))) != str(root.resolve()):
        raise ValueError(f'path escape: {rel}')
    return p

def regular(path: Path, limit: int) -> int:
    s=path.stat(follow_symlinks=False)
    if not stat.S_ISREG(s.st_mode) or path.is_symlink() or s.st_size>limit: raise ValueError(f'unsafe/oversize file: {path}')
    return s.st_size

def digest(path: Path, limit=MAX_FILE):
    n=regular(path,limit); h=hashlib.sha256(); total=0
    with path.open('rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b: break
            total+=len(b); h.update(b)
            if total>limit: raise ValueError(f'growing file exceeds bound: {path}')
    if total!=n: raise ValueError(f'file changed during read: {path}')
    return total,h.hexdigest()

def write_exclusive(path: Path, data: bytes):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as f: f.write(data)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--donor-root',required=True)
    ap.add_argument('--output-root',required=True)
    ap.add_argument('--helper-source',required=True)
    ap.add_argument('--helper-destination',default='producer/support/cleanup.ps1')
    ap.add_argument('--overlay-file',action='append',required=True)
    ap.add_argument('--old-helper-sha256',required=True)
    args=ap.parse_args()
    donor=Path(args.donor_root); out=Path(args.output_root)
    if out.exists(): raise SystemExit(f'fresh output exists: {out}')
    if not re.fullmatch(r'[0-9a-fA-F]{64}',args.old_helper_sha256): raise SystemExit('old helper hash malformed')
    helper=Path(args.helper_source); helper_n,helper_sha=digest(helper)
    if out.exists(): raise SystemExit(f'fresh output exists: {out}')
    records=[]; total=helper_n
    helper_rel=args.helper_destination
    safe(out,helper_rel)
    write_exclusive(out/helper_rel,helper.read_bytes())
    for rel in args.overlay_file:
        src=safe(donor,rel); n=regular(src,MAX_TEXT)
        raw=src.read_bytes()
        if len(raw)!=n: raise ValueError(f'changed source: {rel}')
        try: text=raw.decode('utf-8')
        except UnicodeDecodeError: raise ValueError(f'overlay source is not UTF-8 text: {rel}')
        if args.old_helper_sha256.lower() not in text.lower(): raise ValueError(f'helper pin absent: {rel}')
        text=re.sub(re.escape(args.old_helper_sha256),helper_sha,text,flags=re.IGNORECASE)
        dst=safe(out,rel)
        write_exclusive(dst,text.encode('utf-8'))
        total+=len(text.encode('utf-8'))
        if total>MAX_TOTAL: raise ValueError('staged source exceeds total bound')
        records.append({'path':rel,'bytes':len(text.encode('utf-8')),'helperSha256':helper_sha})
        if len(records)>MAX_FILES: raise ValueError('too many overlay files')
    manifest={'kind':'owned-child-kernel-cleanup-overlay-v2','historicalDonorUnchanged':True,'oldHelperSha256':args.old_helper_sha256.lower(),'newHelper':{'path':helper_rel,'bytes':helper_n,'sha256':helper_sha},'files':records,'totalBytes':total}
    data=json.dumps(manifest,sort_keys=True,separators=(',',':')).encode('utf-8')
    write_exclusive(out/'overlay-rebind-manifest.json',data)
if __name__=='__main__': main()
