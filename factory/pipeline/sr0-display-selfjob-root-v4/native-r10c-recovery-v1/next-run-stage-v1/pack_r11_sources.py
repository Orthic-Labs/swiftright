#!/usr/bin/env python3
"""Bounded Mac-side source packer; binary files stay external Windows inputs."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, zipfile
from pathlib import Path

MAX_FILE=64*1024*1024
MAX_TOTAL=128*1024*1024

def fail(message: str) -> None: raise SystemExit(f"r11 source pack rejected: {message}")
def digest(path: Path) -> tuple[int,str]:
    if path.is_symlink() or not path.is_file(): fail(f"source is not regular: {path}")
    size=path.stat().st_size
    if size>MAX_FILE: fail(f"source exceeds 64MiB: {path}")
    h=hashlib.sha256()
    with path.open('rb') as stream:
        while block:=stream.read(1024*1024): h.update(block)
    return size,h.hexdigest()
def load_sources(path: Path):
    spec=importlib.util.spec_from_file_location('r11_stage_definition',path)
    if spec is None or spec.loader is None: fail(f"cannot load stage definition: {path}")
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return tuple(module.SOURCES)
def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--repository-root',required=True);ap.add_argument('--stage-definition',required=True)
    ap.add_argument('--source-plan',required=True);ap.add_argument('--output-zip',required=True);ap.add_argument('--metadata-out',required=True)
    args=ap.parse_args();repo=Path(args.repository_root).resolve();definition=Path(args.stage_definition).resolve();plan=json.loads(Path(args.source_plan).read_text(encoding='utf-8'))
    plan_rows={str(row.get('name')):row for row in plan.get('sourceFiles',[]) if row.get('external') is True}
    expected={'workloadExe','rendererDll','presentMonExe'}
    if set(plan_rows)!=expected: fail('source plan must provide exactly three external binary rows')
    rows=[];total=0
    out=Path(args.output_zip)
    if out.exists(): fail(f"output must be fresh: {out}")
    out.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(out,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for name,source_rel,staged_rel in load_sources(definition):
            source=repo/source_rel;size,sha=digest(source);total+=size
            if total>MAX_TOTAL: fail('source bytes exceed 128MiB')
            rows.append({'name':name,'source':source_rel,'path':staged_rel.replace('\\','/'),'bytes':size,'sha256':sha})
            archive.write(source,'source/'+staged_rel.replace('\\','/'))
        metadata={'schema':'sr0-display-selfjob-r11-source-pack','sourceCount':len(rows),'binaryCount':len(plan_rows),'sourceRows':rows,'binaryRows':list(plan_rows.values()),'sourceTotalBytes':total,'nativeActions':0,'qualificationClaim':False}
        raw=(json.dumps(metadata,indent=2)+'\n').encode('utf-8');archive.writestr('source-pack-metadata.json',raw)
    meta=Path(args.metadata_out)
    if meta.exists(): fail(f"metadata must be fresh: {meta}")
    meta.parent.mkdir(parents=True,exist_ok=True);meta.write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':'packed-source-only','sourceCount':len(rows),'binaryCount':len(plan_rows),'sourceTotalBytes':total,'outputZip':str(out),'metadata':str(meta),'nativeActions':0,'qualificationClaim':False}))
    return 0
if __name__=='__main__': raise SystemExit(main())
