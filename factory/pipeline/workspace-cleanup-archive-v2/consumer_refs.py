#!/usr/bin/env python3
"""Bind current canonical reader & receipt references without changing admission."""
from pathlib import Path
import subprocess,json,hashlib
ROOT=Path('/Volumes/D/claude/swiftright');OUT=Path(__file__).resolve().parent;CACHE='/Users/adrdsouza/Library/Caches/SwiftRightFactory/'
def sha(p):return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
names=subprocess.run(['rg','-l','-F',CACHE,'factory','--glob','*.json','--glob','!workspace-cleanup-archive-v2/**'],cwd=ROOT,text=True,capture_output=True).stdout.splitlines()
refs=[];reader=[];files=[];terminal=[]
def walk(x,source,field=''):
 if isinstance(x,dict):
  path=x.get('path');h=x.get('sha256',x.get('hash'))
  if isinstance(path,str) and path.startswith(CACHE) and isinstance(h,str) and h.startswith('sha256:'):refs.append({'consumer':source,'field':field,'path':path,'sha256':h,'bytes':x.get('bytes')})
  if type(x.get('exitCode')) is int and ('endedAtUtc' in x or 'finishedAt' in x):terminal.append({'consumer':source,'field':field,'exitCode':x['exitCode'],'endedAtUtc':x.get('endedAtUtc',x.get('finishedAt')),'ownedProcessGroup':x.get('ownedProcessGroup'),'pid':x.get('pid'),'pgid':x.get('pgid')})
  for k,v in x.items():walk(v,source,field+'.'+k)
 elif isinstance(x,list):
  for i,v in enumerate(x):walk(v,source,field+f'[{i}]')
for n in names:
 if n.startswith('factory/pipeline/workspace-cleanup-archive-v2/'):continue
 p=ROOT/n
 try:j=json.loads(p.read_text())
 except Exception:continue
 files.append({'path':n,'sha256':sha(p)})
 walk(j,n)
 if 'macPathMap' in j or 'macRoots' in j:reader.append({'consumer':n,'macRoots':j.get('macRoots',[]),'macPathMap':j.get('macPathMap',{})})
r={'scope':'canonical textual refs & exact byte descriptors; not admission or historical process qualification','files':files,'byteReferences':refs,'readerConfigurations':reader,'terminalProcessObservations':terminal}
(OUT/'consumer-references.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n');print(json.dumps({'consumers':len(files),'byteRefs':len(refs),'readerConfigs':len(reader),'terminalObservations':len(terminal)}))
