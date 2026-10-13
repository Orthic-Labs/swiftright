#!/usr/bin/env python3
"""Bounded explicit source packer; does not execute staged sources."""
from __future__ import annotations
import argparse,hashlib,json,stat,zipfile
from pathlib import Path
MAX_FILE=64*1024*1024; MAX_TOTAL=128*1024*1024; MAX_FILES=128
class Hold(ValueError):pass
def ref(p):
 s=p.lstat()
 if not stat.S_ISREG(s.st_mode) or stat.S_ISLNK(s.st_mode) or s.st_size>MAX_FILE:raise Hold('source file bound')
 h=hashlib.sha256();n=0
 with p.open('rb') as f:
  while b:=f.read(1024*1024):n+=len(b);h.update(b)
 if n!=s.st_size:raise Hold('source changed')
 return h.hexdigest(),n
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--inputs',required=True,type=Path);ap.add_argument('--output-zip',required=True,type=Path);ap.add_argument('--metadata',required=True,type=Path);ap.add_argument('--files',nargs='+',required=True,type=Path);a=ap.parse_args();d=json.loads(a.inputs.read_text(encoding='utf-8-sig'))
 if d.get('kind')!='factory-padding-source-inputs-v2':raise Hold('inputs kind')
 if len(a.files)>MAX_FILES:raise Hold('file count')
 rows=[];total=0;seen=set();
 for p in a.files:
  p=p.resolve();h,n=ref(p);key=p.as_posix()
  if key in seen:raise Hold('duplicate source');seen.add(key);total+=n
  if total>MAX_TOTAL:raise Hold('total source bytes')
  rows.append({'path':key,'sha256':h,'bytes':n})
 if a.output_zip.exists() or a.metadata.exists():raise Hold('fresh outputs required')
 a.output_zip.parent.mkdir(parents=True,exist_ok=True);a.metadata.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(a.output_zip,'x',compression=zipfile.ZIP_DEFLATED) as z:
  for p,row in zip(a.files,rows): z.write(p,'sources/'+p.name)
 meta={'kind':'factory-padding-source-pack-v1','sourceInputsPath':str(a.inputs.resolve()),'sourceInputsSha256':hashlib.sha256(a.inputs.read_bytes()).hexdigest(),'count':d.get('count'),'rows':rows,'entryCount':len(rows),'totalBytes':total,'nativeActions':0,'compilerActions':0,'lockActions':0}
 a.metadata.write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(meta,separators=(',',':')))
if __name__=='__main__':
 try:main()
 except Exception as e:raise SystemExit('HOLD: '+str(e))
