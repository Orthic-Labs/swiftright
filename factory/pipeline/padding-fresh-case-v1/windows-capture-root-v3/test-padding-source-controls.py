#!/usr/bin/env python3
"""Pure source admission controls for fresh Padding packet; never launches anything."""
from __future__ import annotations
import argparse,hashlib,json,os,stat
from pathlib import Path
class Hold(ValueError): pass
def filehash(p,limit=2*1024*1024):
 s=p.lstat()
 if not stat.S_ISREG(s.st_mode) or stat.S_ISLNK(s.st_mode) or s.st_size>limit: raise Hold(f'bounded file required: {p}')
 h=hashlib.sha256();n=0
 with p.open('rb') as f:
  while b:=f.read(1024*1024): n+=len(b);h.update(b)
 if n!=s.st_size:return (_ for _ in()).throw(Hold(f'changed: {p}'))
 return h.hexdigest(),n
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--inputs',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);a=ap.parse_args()
 d=json.loads(a.inputs.read_text(encoding='utf-8-sig'))
 if d.get('kind') not in ('factory-padding-source-inputs-v2','factory-padding-source-inputs-v3') or d.get('count') not in (1,20):raise Hold('kind/count')
 if d.get('historicalCaseReuse',False) or not d.get('freshIDsRequired'):raise Hold('fresh identity policy')
 refs=d.get('refs');
 if not isinstance(refs,dict) or len(refs)<10:raise Hold('explicit reference closure missing')
 checked=[]
 for role,r in refs.items():
  p=Path(str(r.get('path','')));h,n=filehash(p,64*1024*1024)
  if h!=r.get('sha256') or n!=r.get('bytes'):raise Hold(f'ref drift {role}')
  checked.append({'role':role,'path':str(p),'sha256':h,'bytes':n})
 if d.get('caseID')=='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258':raise Hold('historical case reused')
 out={'kind':'factory-padding-source-controls-v1','status':'passed-source-only','count':d['count'],'caseID':d['caseID'],'tupleID':d['tupleID'],'sourceHash':d['sourceHash'],'checkedRefs':checked,'nativeActions':0,'compilerActions':0,'lockActions':0}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(out,separators=(',',':')))
if __name__=='__main__':
 try:main()
 except Exception as e: raise SystemExit('HOLD: '+str(e))
