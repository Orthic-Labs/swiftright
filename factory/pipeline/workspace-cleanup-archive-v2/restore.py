#!/usr/bin/env python3
"""Verify exact scratch archive; optionally rehydrate into fresh internal directory."""
from pathlib import Path,PurePosixPath
import argparse,json,gzip,hashlib,tarfile,os
CACHE=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory')
def fail(ok,message):
 if not ok:raise ValueError(message)
def sha(data):return 'sha256:'+hashlib.sha256(data).hexdigest()
def hashfile(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  while b:=f.read(1024*1024):h.update(b)
 return 'sha256:'+h.hexdigest()
def safe(value):
 fail(isinstance(value,str) and value and '\\' not in value and '\x00' not in value,'unsafe archive path')
 p=PurePosixPath(value);fail(not p.is_absolute() and '..' not in p.parts and str(p)==value,'unsafe archive path');return value
def load_archive(path,expected):
 fail(hashfile(path)==expected,'descriptor hash differs');d=json.loads(path.read_text());m=d['manifest'];mp=path.parent/safe(m['path'])
 fail(hashfile(mp)==m['sha256'] and mp.stat().st_size==m['bytes'],'compressed manifest differs')
 with gzip.open(mp,'rb') as f:raw=f.read(m['rawBytes']+1)
 fail(len(raw)==m['rawBytes'] and sha(raw)==m['rawSha256'],'raw manifest differs');j=json.loads(raw)
 fail(j['kind']=='owned-scratch-byte-preservation' and j['version']==2,'archive kind/version')
 fail(d['chunks']==j['chunks'] and d['roots']==j['roots'],'descriptor manifest join')
 return d,j

def verify(path,expected,output=None,only=None):
 d,m=load_archive(path,expected);objects=m['objects'];allowed={};digests={};sizes={};parts={};outputs={}
 selected=[r for r in m['files'] if only is None or r['path']==only or r['path'].startswith(only.rstrip('/')+'/')]
 if only is not None:fail(bool(selected),'selected original path absent')
 if output is not None:
  output=output.resolve();fail(output.is_relative_to(CACHE) and output!=CACHE,'rehydration requires fresh internal output')
  fail(not output.exists(),'output must not exist');output.mkdir(parents=True)
  for r in selected:
   original=Path(r['path']);fail(original.is_absolute() and original.is_relative_to(CACHE),'original path outside declared cache')
   fail(any(original.is_relative_to(Path(root)) for root in m['roots']),'original path outside archived roots')
   relative=original.relative_to(CACHE);target=output/relative;outputs.setdefault(r['sha256'],[]).append((target,r))
 for h,obj in objects.items():
  fail(h==obj['sha256'],'object key/hash join');digests[h]=hashlib.sha256();sizes[h]=0;parts[h]=0
  for number,part in enumerate(obj['parts']):
   key=(safe(part['chunk']),safe(part['member']));fail(key not in allowed,'duplicate member binding')
   fail(part['member']==f'objects/{h.removeprefix("sha256:")}/{number:05d}','object part identity');allowed[key]=(h,number,part)
 seen=set();compressed=0
 for chunk in m['chunks']:
  name=safe(chunk['path']);cp=path.parent/name
  fail(hashfile(cp)==chunk['sha256'] and cp.stat().st_size==chunk['bytes'] and chunk['bytes']<=50_000_000,'chunk hash/size differs');compressed+=chunk['bytes'];payload=0;count=0
  with tarfile.open(cp,'r|gz') as tar:
   for member in tar:
    key=(name,safe(member.name));fail(member.isfile() and key in allowed and key not in seen,'unexpected/duplicate/nonregular tar member');seen.add(key)
    h,n,part=allowed[key];fail(parts[h]==n and member.size==part['bytes'],'part order/size differs')
    f=tar.extractfile(member);data=f.read(part['bytes']+1);fail(len(data)==part['bytes'] and sha(data)==part['sha256'],'raw part hash differs')
    digests[h].update(data);sizes[h]+=len(data);parts[h]+=1;payload+=len(data);count+=1
    for target,r in outputs.get(h,[]):
     target.parent.mkdir(parents=True,exist_ok=True)
     with target.open('xb' if n==0 else 'ab') as stream:stream.write(data)
  fail(payload==chunk['payloadBytes'] and count==chunk['members'],'chunk membership totals')
 fail(seen==set(allowed),'missing archive members')
 for h,obj in objects.items():fail('sha256:'+digests[h].hexdigest()==h and sizes[h]==obj['bytes'],'raw object hash/bytes differs')
 mapping={}
 for r in selected:
  fail(r['sha256'] in objects and r['bytes']==objects[r['sha256']]['bytes'],'file/object join')
  if output is not None:
   target=output/Path(r['path']).relative_to(CACHE)
   if r['bytes']==0:target.parent.mkdir(parents=True,exist_ok=True);target.touch(exist_ok=False)
   fail(hashfile(target)==r['sha256'] and target.stat().st_size==r['bytes'],'rehydrated bytes differ');os.chmod(target,r['mode']);mapping[r['path']]=str(target)
 # Symlink metadata retained as evidence; never materialized or followed by trusted reader.
 return {'status':'PASS','candidateOnly':True,'descriptorSha256':expected,'fileCount':len(m['files']),'selectedFiles':len(selected),'uniqueObjects':len(objects),'verifiedChunks':len(m['chunks']),'verifiedCompressedBytes':compressed,'symlinkMetadataCount':len(m['symlinks']),'rehydratedReaderConfig':{'macRoots':[str(output)] if output else [],'macPathMap':mapping,'windowsArchives':{}} if output else None,'nativeExecutions':0,'deletions':0}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--descriptor',type=Path,required=True);p.add_argument('--sha256',required=True);p.add_argument('--output',type=Path);p.add_argument('--only');p.add_argument('--receipt',type=Path,required=True);a=p.parse_args();r=verify(a.descriptor,a.sha256,a.output,a.only)
 fail(a.receipt.parent.resolve()==Path(__file__).resolve().parent,'receipt must stay owned archive packet');a.receipt.write_text(json.dumps(r,indent=2,sort_keys=True)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='rehydratedReaderConfig'}))
