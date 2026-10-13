#!/usr/bin/env python3
"""Bounded r10 source graph/ZIP builder; donor is never changed or overwritten."""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat, sys, zipfile
from pathlib import Path
MAX_FILE=64*1024*1024; MAX_TOTAL=256*1024*1024; MAX_FILES=256; MAX_TEXT=8*1024*1024
OLD='a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'
ROOT=Path(__file__).resolve().parents[3]
MTA=ROOT/'factory/pipeline/pilot-next-source-v1/mta-pilot-count20-stage-v1'
sys.path.insert(0,str(MTA)); sys.path.insert(0,str(MTA.parent/'mta-pilot-stage-v1'))
from stage_mta_count20 import reseal_binding, overlay_rows
from stage_mta_count1_r5 import reseal_candidate_graph, refresh_local_identity_refs, make_installer

def regular(p:Path, lim:int):
 s=p.stat(follow_symlinks=False)
 if not stat.S_ISREG(s.st_mode) or p.is_symlink() or s.st_size>lim: raise ValueError(f'unsafe/oversize: {p}')
 return s.st_size

def safe(root:Path, rel:str):
 if not rel or rel.startswith(('/', '\\')) or ':' in rel or '\\' in rel: raise ValueError(f'unsafe rel: {rel}')
 cur=root
 for part in rel.split('/'):
  cur=cur/part
  if cur.is_symlink(): raise ValueError(f'reparse path: {rel}')
 p=root.joinpath(*rel.split('/'))
 if os.path.commonpath((str(root.resolve()),str(p.parent.resolve())))!=str(root.resolve()): raise ValueError(f'escape: {rel}')
 return p

def stream(p:Path, lim=MAX_FILE):
 n=regular(p,lim); h=hashlib.sha256(); out=bytearray() if n<=MAX_TEXT else None; count=0
 with p.open('rb') as f:
  while True:
   b=f.read(1024*1024)
   if not b: break
   count+=len(b); h.update(b)
   if out is not None: out.extend(b)
   if count>lim: raise ValueError(f'grew beyond bound: {p}')
 if count!=n: raise ValueError(f'changed while read: {p}')
 return count,h.hexdigest(),(bytes(out) if out is not None else None)

def write(path:Path,data:bytes):
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb') as f: f.write(data)

def transform(rel,text,newhash):
 oldcount=text.lower().count(OLD)
 text=text.replace(OLD,newhash).replace(OLD.upper(),newhash)
 if rel.endswith(('capture-text-count20-v1.ps1','capture-text-single-v3.ps1')):
  for old in ('$ownedStartedAt','$startedAt'):
   text=text.replace('Invoke-FactoryOwnedCleanup $p $exe '+old+' -KnownStartedIdentity','Invoke-FactoryOwnedCleanup $p $exe '+old+' -ExpectedExeHash $ExeHash -KnownStartedIdentity')
 if rel.endswith(('uia-worker-invoke-v2.ps1','invoke-worker-mta.ps1','invoke-worker.ps1')):
  for old in ('$startedAt','$ownedStartedAt'):
   text=text.replace('Invoke-FactoryOwnedCleanup $p $exe '+old+' -KnownStartedIdentity','Invoke-FactoryOwnedCleanup $p $exe '+old+' -ExpectedExeHash $exeHash -KnownStartedIdentity')
   text=text.replace('Invoke-FactoryOwnedCleanup $p $exe '+old, 'Invoke-FactoryOwnedCleanup $p $exe '+old+' -ExpectedExeHash $exeHash')
 return text,oldcount

def reseal_local(stage:Path):
 """Use admitted graph reseal helpers, then refresh every transformed local edge."""
 reseal_candidate_graph(stage)
 contract_path=stage/'producer'/'dependencies'/'uia-worker'/'worker-contract.json'
 contract=json.loads(contract_path.read_text(encoding='utf-8'))
 rows=contract.get('sourceBindings') if isinstance(contract,dict) else None
 if not isinstance(rows,list) or not rows: raise ValueError('worker contract sourceBindings missing')
 seen=set()
 for row in rows:
  rel=row.get('path') if isinstance(row,dict) else None
  if not isinstance(rel,str) or not rel or rel in seen or '\\' in rel or ':' in rel or '..' in rel.split('/'):
   raise ValueError('unsafe worker contract binding')
  seen.add(rel); q=safe(stage/'producer'/'dependencies'/'uia-worker',rel); n,h,_=stream(q);row['bytes']=n;row['sha256']=h
 contract_path.write_text(json.dumps(contract,sort_keys=True,separators=(',',':')),encoding='utf-8')
 reseal_binding(stage)
 si_path=stage/'admission'/'source-inputs.json';si=json.loads(si_path.read_text(encoding='utf-8'))
 refresh_local_identity_refs(stage,si)
 cleanup=stage/'producer'/'support'/'cleanup.ps1';uia_cleanup=stage/'producer'/'dependencies'/'uia-worker'/'support'/'cleanup.ps1'
 for name,path in (('cleanupHelperHash',cleanup),('uiaCleanupHelperHash',uia_cleanup)):
  if path.is_file(): si[name]=stream(path)[1]
 si['overlaySourceBindings']=overlay_rows(stage)
 si['overlaySourceBindingsHash']=hashlib.sha256(json.dumps(si['overlaySourceBindings'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
 si_path.write_text(json.dumps(si,sort_keys=True,separators=(',',':')),encoding='utf-8')

def refresh_rows(rows,out):
 for row in rows:
  p=safe(out,row['path']);row['bytes'],row['sha256'],_=stream(p)

def refresh_stage_manifest(out):
 p=out/'stage-manifest.json'
 if not p.is_file(): return
 doc=json.loads(p.read_text(encoding='utf-8'))
 if not isinstance(doc,dict) or not isinstance(doc.get('files'),list): return
 for row in doc['files']:
  if isinstance(row,dict) and isinstance(row.get('path'),str):
   q=out/row['path']
   if q.is_file(): row['bytes'],row['sha256'],_=stream(q)
 p.write_text(json.dumps(doc,sort_keys=True,separators=(',',':')),encoding='utf-8')

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--donor-root',required=True);ap.add_argument('--output-root',required=True);ap.add_argument('--source-list',required=True);ap.add_argument('--helper-source',required=True);ap.add_argument('--zip-path');ap.add_argument('--installer-path');ap.add_argument('--namespace',default='text-mta-r11-count20-r10');ap.add_argument('--old-namespace',default='text-mta-r11-count20-r9');ap.add_argument('--profile',default='text-count20-r10-kernel-authority-v1');args=ap.parse_args()
 donor=Path(args.donor_root);out=Path(args.output_root);helper=Path(args.helper_source);source_list=Path(args.source_list)
 if out.exists(): raise SystemExit(f'fresh output exists: {out}')
 if not re.fullmatch(r'[0-9a-f]{64}',OLD): raise SystemExit('frozen helper hash malformed')
 n,h,helper_data=stream(helper); assert helper_data is not None
 list_n,_,list_data=stream(source_list,1*1024*1024);rels=json.loads(list_data.decode('utf-8'))
 if not isinstance(rels,list) or len(rels)>MAX_FILES: raise ValueError('invalid source list')
 rows=[]; total=0; transformed=0
 for rel in rels:
  src=safe(donor,rel); size,oldh,data=stream(src); assert data is not None
  if rel=='producer/support/cleanup.ps1' and oldh.lower()!=OLD: raise ValueError(f'frozen cleanup helper hash mismatch: {oldh}')
  replaced=False
  if rel.endswith('/support/cleanup.ps1'):
   data=helper_data; transformed+=1; replaced=True
  elif rel.endswith(('.ps1','.json','.cs','.py','.md')):
   try:
    txt=data.decode('utf-8'); before=txt; txt,count=transform(rel,txt,h)
    for old,new in ((args.old_namespace,args.namespace),): txt=re.sub(r'(?<![A-Za-z0-9_.-])'+re.escape(old)+r'(?![A-Za-z0-9_.-])',lambda _m,value=new:value,txt)
    data=txt.encode('utf-8'); replaced=(before!=txt); transformed+=int(replaced)
   except UnicodeDecodeError: pass
  dst=safe(out,rel); write(dst,data); total+=len(data)
  if total>MAX_TOTAL: raise ValueError('source graph exceeds 256 MiB')
  rows.append({'path':rel,'donorBytes':size,'donorSha256':oldh,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'transformed':replaced})
 # Reseal candidate tuple/context/binding, integration bindings, source-inputs,
 # & overlay rows after every transformation. These bytes are source evidence,
 # not a qualification claim.
 reseal_local(out);refresh_stage_manifest(out);refresh_rows(rows,out)
 stale=[]
 for p in out.rglob('*'):
  if p.is_file() and p.suffix.lower() in ('.ps1','.json'):
   raw=stream(p)[2]
   if raw is not None and OLD in raw.decode('utf-8',errors='ignore').lower(): stale.append(str(p))
 if stale: raise ValueError('stale frozen cleanup hash remains in staged call graph: '+','.join(stale[:4]))
 if total>MAX_TOTAL: raise ValueError('source graph exceeds bound')
 graph={'kind':'factory-text-count20-r10-kernel-source-graph-v1','profile':args.profile,'historicalDonor':str(donor),'frozenHelperSha256':OLD,'successorHelperSha256':h,'successorHelperBytes':n,'count':20,'nativeWindowActions':0,'rendererDeadlineSeconds':30,'exitDeadlineSeconds':15,'streamDrainMilliseconds':5000,'donorMutated':False,'transformedFileCount':transformed,'files':rows}
 graph_bytes=json.dumps(graph,sort_keys=True,separators=(',',':')).encode();write(out/'r10-source-graph.json',graph_bytes)
 seal={'kind':'factory-text-count20-r10-reseal-plan-v1','status':'requires-root-measured-reseal','helperRefs':[{'path':'producer/support/cleanup.ps1','sha256':'sha256:'+h,'bytes':n},{'path':'producer/dependencies/uia-worker/support/cleanup.ps1','sha256':'sha256:'+h,'bytes':n}],'sourceGraphRef':{'path':'r10-source-graph.json','sha256':'sha256:'+hashlib.sha256(graph_bytes).hexdigest(),'bytes':len(graph_bytes)},'requiredReseals':['admission/source-inputs.json','producer/integration-bindings.json','stage-manifest.json','overlay/capture-build-preflight.ps1','overlay/capture-text-count20-v1.ps1','overlay/capture-text-single-v3.ps1','overlay/uia-worker-invoke-v2.ps1','producer/dependencies/uia-worker/invoke-worker-mta.ps1','producer/dependencies/uia-worker/support/cleanup.ps1'],'freshNamespaceRequired':True,'historicalSourcePreserved':True}
 write(out/'r10-reseal-plan.json',json.dumps(seal,sort_keys=True,separators=(',',':')).encode())
 if args.zip_path:
  zp=Path(args.zip_path)
  if zp.exists(): raise SystemExit(f'fresh ZIP exists: {zp}')
  zp.parent.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(zp,'x',compression=zipfile.ZIP_DEFLATED) as z:
   for row in rows:
    p=out/row['path']; z.write(p,row['path'])
   z.write(out/'r10-source-graph.json','r10-source-graph.json');z.write(out/'r10-reseal-plan.json','r10-reseal-plan.json')
  if args.installer_path:
   cert=out/'admission'/'count1-certificate.json'
   if not cert.is_file(): raise ValueError('Count1 certificate missing for installer')
   cert_bytes=cert.read_bytes(); cert_ref={'sha256':hashlib.sha256(cert_bytes).hexdigest(),'bytes':len(cert_bytes)}
   template=out/'stage-manifest.json'; template_sha=hashlib.sha256(template.read_bytes()).hexdigest() if template.is_file() else hashlib.sha256(graph_bytes).hexdigest()
   installer=make_installer(args.profile.split('-')[0],args.namespace,hashlib.sha256(zp.read_bytes()).hexdigest(),cert_ref,hashlib.sha256((out/'admission'/'source-inputs.json').read_bytes()).hexdigest(),template_sha)
   ip=Path(args.installer_path);ip.parent.mkdir(parents=True,exist_ok=True);write(ip,installer.encode())
if __name__=='__main__': main()
