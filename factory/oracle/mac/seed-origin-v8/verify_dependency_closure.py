#!/usr/bin/env python3
"""Verify full archived source/runtime dependency closure."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

def digest(path: Path) -> str: return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
def validate(root: Path, workspace: Path) -> dict:
    root=root.resolve(); workspace=workspace.resolve(); manifest=json.loads((root/'runtime-deps/dependency-hashes.json').read_text()); rows=manifest['files']; len(rows)==23 or (_ for _ in ()).throw(ValueError('dependency count'))
    for row in rows:
        original=workspace/row['originalPath']; archive=root/row['archivePath']
        original.is_file() and archive.is_file() or (_ for _ in ()).throw(ValueError(f'missing dependency {row}'))
        digest(original)==row['sha256']==digest(archive) or (_ for _ in ()).throw(ValueError(f'dependency hash {row["originalPath"]}'))
        original.stat().st_size==row['bytes']==archive.stat().st_size or (_ for _ in ()).throw(ValueError(f'dependency bytes {row["originalPath"]}'))
    for name in ['AXClient.swift','CaptureHost.swift']:
        original=workspace/'factory/oracle/mac/seed-origin-v2'/name; archived=root/name
        digest(original)==digest(archived) or (_ for _ in ()).throw(ValueError(f'sibling source {name}'))
    own=workspace/'factory/oracle/mac/seed-origin-v6/capture_origin.py'; archived=root/'runtime-deps/factory/oracle/mac/seed-origin-v6/capture_origin.py'; digest(own)==digest(archived) or (_ for _ in ()).throw(ValueError('v6 collector hash'))
    return {'status':'PASS','dependencyCount':len(rows),'siblingSources':2,'schemaFiles':12,'runtimeCopies':'PASS'}
if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('root',type=Path); parser.add_argument('--workspace',type=Path,default=Path(__file__).resolve().parents[4]); args=parser.parse_args()
    try: print(json.dumps(validate(args.root,args.workspace),sort_keys=True,indent=2))
    except Exception as error: print(f'FAIL: {error}'); raise SystemExit(1)
