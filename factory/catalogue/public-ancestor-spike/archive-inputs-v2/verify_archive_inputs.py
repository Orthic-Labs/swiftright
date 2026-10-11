#!/usr/bin/env python3
from __future__ import annotations
import argparse,gzip,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]; MAX=100_000_000

def dig(p):
 h=hashlib.sha256();n=0
 with p.open('rb') as f:
  while b:=f.read(1<<20):h.update(b);n+=len(b)
 return n,h.hexdigest()
def fail(x): raise ValueError(x)
def check(d,root=ROOT):
 if d.get('schema')!='factory.public-ancestor.archive-input-mapping.v1' or d.get('kind')!='additive-force-archive-inputs-v2':fail('schema')
 b=d.get('baseMapping',{}); bp=root/b.get('path','')
 if not bp.is_file() or dig(bp)[1]!=b.get('sha256'):fail('base mapping pin')
 if d.get('policy',{}).get('archivePathsRepositoryRelative') is not True or d['policy'].get('maxArchiveBytes')!=MAX:fail('policy')
 for k,hk in [('mainEvidence','mainEvidenceSha256'),('clangGuard','clangGuardSha256'),('swift16Evidence','swift16EvidenceSha256')]:
  p=root/d['sourceScope'][k]
  if not p.is_file() or dig(p)[1]!=d['sourceScope'][hk]:fail('source '+k)
 es=d.get('entries',[])
 if not es or len(es)!=93:fail('entry cardinality')
 seen=set();apseen=set()
 for e in es:
  sem=e.get('semanticPath');a=e.get('archive',{});ap=a.get('path')
  if not isinstance(sem,str) or sem in seen:fail('duplicate semantic')
  seen.add(sem)
  if len(e.get('sha256',''))!=64 or not isinstance(e.get('bytes'),int):fail('semantic pin')
  if not isinstance(ap,str) or ap.startswith('/') or '\\' in ap or any(x in ('','.','..') for x in ap.split('/')):fail('archive path')
  f=(root/ap).resolve()
  if root.resolve() not in f.parents or not f.is_file():fail('archive missing')
  if ap in apseen:fail('archive alias')
  apseen.add(ap)
  n,h=dig(f)
  if n!=a.get('bytes') or h!=a.get('sha256'):fail('archive pin')
  if n>=MAX:fail('archive size')
  c=a.get('compression')
  if c=='none':
   if n!=e['bytes'] or h!=e['sha256']:fail('plain semantic')
  elif c=='gzip':
   hh=hashlib.sha256();nn=0
   try:
    with gzip.open(f,'rb') as z:
     while x:=z.read(1<<20):hh.update(x);nn+=len(x)
   except OSError as ex:fail('gzip '+str(ex))
   if (nn,hh.hexdigest())!=(e['bytes'],e['sha256']) or (a.get('decompressedBytes'),a.get('decompressedSha256'))!=(nn,hh.hexdigest()):fail('gzip semantic')
  else:fail('compression')
  if not e.get('provenance') or not all('source' in x and 'key' in x for x in e['provenance']):fail('provenance')
 return {'entries':len(es),'archives':len(apseen),'baseSha256':b['sha256']}
def main():
 p=argparse.ArgumentParser();p.add_argument('mapping',nargs='?',default=str(Path(__file__).with_name('archive-input-mapping.json')));a=p.parse_args()
 try: print('PASS',json.dumps(check(json.loads(Path(a.mapping).read_text())),sort_keys=True));return 0
 except Exception as e: print('FAIL:',e);return 1
if __name__=='__main__':raise SystemExit(main())
