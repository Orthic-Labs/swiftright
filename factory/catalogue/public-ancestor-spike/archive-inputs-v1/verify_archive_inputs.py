#!/usr/bin/env python3
"""Strict offline verifier for archive-input-mapping.json."""
from __future__ import annotations
import argparse, gzip, hashlib, json, os, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
MAX = 100_000_000

def digest(path):
    h=hashlib.sha256(); n=0
    with open(path,'rb') as f:
        while b:=f.read(1<<20): h.update(b); n+=len(b)
    return n,h.hexdigest()

def fail(msg): raise ValueError(msg)
def check(doc, root=ROOT):
    if doc.get('schema') != 'factory.public-ancestor.archive-input-mapping.v1': fail('schema')
    policy=doc.get('policy',{})
    if policy.get('archivePathsRepositoryRelative') is not True: fail('archive path policy')
    if policy.get('maxArchiveBytes') != MAX: fail('archive size policy')
    dirs=doc.get('directoryPrerequisites'); entries=doc.get('entries')
    if not isinstance(dirs,list) or not isinstance(entries,list) or len(entries) != 30: fail('entry cardinality')
    seen=set(); archive_seen=set()
    for d in dirs:
        if d.get('kind') != 'directory' or d.get('semanticPath') != '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk': fail('directory prereq')
        if d.get('archive') is not None: fail('SDK copied')
        if d.get('bytes') is not None or d.get('sha256') is not None: fail('SDK whole hash')
    for e in entries:
        sem=e.get('semanticPath'); a=e.get('archive');
        if not isinstance(sem,str) or not sem.startswith('/') or sem in seen: fail('duplicate semantic path')
        seen.add(sem)
        if not isinstance(e.get('bytes'),int) or e['bytes'] < 0 or not isinstance(e.get('sha256'),str) or len(e['sha256']) != 64: fail(f'bad semantic pin {sem}')
        if not isinstance(a,dict): fail(f'missing archive {sem}')
        ap=a.get('path')
        if not isinstance(ap,str) or ap.startswith('/') or '\\' in ap or any(part in ('','.','..') for part in ap.split('/')): fail(f'noncanonical archive path {ap}')
        full=(root/ap).resolve()
        if root.resolve() not in full.parents: fail(f'archive escape {ap}')
        if not full.is_file(): fail(f'missing archive {ap}')
        if ap in archive_seen: fail(f'duplicate archive alias {ap}')
        archive_seen.add(ap)
        if a.get('bytes') != full.stat().st_size or a.get('sha256') != digest(full)[1]: fail(f'archive pin {sem}')
        if full.stat().st_size >= MAX: fail(f'archive too large {ap}')
        comp=a.get('compression')
        if comp == 'none':
            if a['bytes'] != e['bytes'] or a['sha256'] != e['sha256']: fail(f'raw archive mismatch {sem}')
        elif comp == 'gzip':
            if a.get('decompressedBytes') != e['bytes'] or a.get('decompressedSha256') != e['sha256']: fail(f'gzip whole pin {sem}')
            h=hashlib.sha256(); n=0
            try:
                with gzip.open(full,'rb') as f:
                    while b:=f.read(1<<20): h.update(b); n+=len(b)
            except OSError as ex: fail(f'gzip unreadable {ap}: {ex}')
            if (n,h.hexdigest()) != (e['bytes'],e['sha256']): fail(f'gzip content {sem}')
        else: fail(f'compression {sem}')
        # Live observations bind source bytes when original is present; inaccessible cache origins remain archive-only.
        obs=e.get('observedLive')
        if obs:
            if obs.get('bytes') != e['bytes'] or obs.get('sha256') != e['sha256']: fail(f'live pin {sem}')
    # Source descriptors are caller pins, not trusted archive aliases.
    for k in ('nominalStage','nominalStageSha256'),('clangOwnerGuard','clangOwnerGuardSha256'),('swift16Manifest','swift16ManifestSha256'),('destructorManifest','destructorManifestSha256'):
        p,h=k; fp=root/doc['sourceScope'][p]
        if not fp.is_file() or digest(fp)[1] != doc['sourceScope'][h]: fail(f'source manifest {p}')
    return {'entries':len(entries),'directories':len(dirs),'archives':len(archive_seen)}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('mapping',nargs='?',default=str(Path(__file__).with_name('archive-input-mapping.json'))); ns=ap.parse_args()
    try:
        out=check(json.loads(Path(ns.mapping).read_text()))
    except Exception as e:
        print('FAIL:',e); return 1
    print('PASS',json.dumps(out,sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
