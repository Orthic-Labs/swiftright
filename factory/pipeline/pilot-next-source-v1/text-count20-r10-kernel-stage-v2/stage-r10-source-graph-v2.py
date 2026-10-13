#!/usr/bin/env python3
"""Bounded r10 source graph/ZIP builder; donor is never changed or overwritten."""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat, sys, zipfile
from pathlib import Path
MAX_FILE=64*1024*1024; MAX_TOTAL=256*1024*1024; MAX_FILES=256; MAX_TEXT=8*1024*1024
OLD='a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7'
ROOT=Path(__file__).resolve().parents[4]
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

def load_json_bounded(p:Path, lim=MAX_TEXT):
 n,h,data=stream(p,lim)
 if data is None: raise ValueError(f'JSON exceeds bounded text limit: {p}')
 try: value=json.loads(data.decode('utf-8'))
 except (UnicodeDecodeError,json.JSONDecodeError) as exc: raise ValueError(f'invalid JSON: {p}') from exc
 return value,n,h

def write(path:Path,data:bytes):
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb') as f: f.write(data)

def copy_stream(src:Path,dst:Path,expected_size:int,expected_hash:str):
 dst.parent.mkdir(parents=True,exist_ok=True)
 if dst.exists(): raise ValueError(f'fresh destination collision: {dst}')
 h=hashlib.sha256();n=0
 with src.open('rb') as r,dst.open('xb') as w:
  while True:
   b=r.read(1024*1024)
   if not b: break
   n+=len(b)
   if n>MAX_FILE: raise ValueError(f'copy exceeds bound: {src}')
   h.update(b);w.write(b)
 if n!=expected_size or h.hexdigest()!=expected_hash: raise ValueError(f'copy drift: {src}')

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
 contract,_,_=load_json_bounded(contract_path)
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
 si_path=stage/'admission'/'source-inputs.json';si,_,_=load_json_bounded(si_path)
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
 doc,_,_=load_json_bounded(p)
 if not isinstance(doc,dict) or not isinstance(doc.get('files'),list): return
 for row in doc['files']:
  if isinstance(row,dict) and isinstance(row.get('path'),str):
   q=out/row['path']
   if q.is_file(): row['bytes'],row['sha256'],_=stream(q)
 p.write_text(json.dumps(doc,sort_keys=True,separators=(',',':')),encoding='utf-8')

def validate_graph(graph, source_root=None):
 if not isinstance(graph,dict) or graph.get('kind')!='factory-text-count20-r10-kernel-source-graph-v1' or graph.get('profile')!='text-count20-r10-kernel-authority-v1' or graph.get('count')!=20:
  raise ValueError('r10 graph identity/count mismatch')
 if graph.get('donorMutated') is not False or graph.get('nativeWindowActions')!=0 or graph.get('compilerActions')!=0 or graph.get('lockActions')!=0:
  raise ValueError('r10 graph action state mismatch')
 if graph.get('count1FirstRequired') is not True or graph.get('count1CertificateRequired') is not True:
  raise ValueError('r10 Count1 admission prerequisite missing')
 if graph.get('rendererDeadlineSeconds')!=30 or graph.get('exitDeadlineSeconds')!=15 or graph.get('streamDrainMilliseconds')!=5000:
  raise ValueError('r10 lifecycle budget drift')
 for field in ('frozenHelperSha256','successorHelperSha256'):
  if not re.fullmatch(r'[0-9a-f]{64}',str(graph.get(field,'')).lower().replace('sha256:','')):
   raise ValueError('r10 helper hash missing')
 if not re.fullmatch(r'[0-9a-f]{64}',str(graph.get('expectedExeHash','')).lower().replace('sha256:','')):
  raise ValueError('r10 measured executable hash missing')
 if not isinstance(graph.get('sourceListSha256'),str) or not re.fullmatch(r'[0-9a-f]{64}',graph['sourceListSha256'].lower().replace('sha256:','')):
  raise ValueError('r10 source-list hash missing')
 if int(graph.get('sourceListBytes',-1))<0 or int(graph.get('sourceListCount',-1))<1:
  raise ValueError('r10 source-list bounds missing')
 rows=graph.get('files')
 if not isinstance(rows,list) or not rows or len(rows)>MAX_FILES: raise ValueError('r10 graph rows invalid')
 if int(graph.get('sourceListCount',-1))!=len(rows): raise ValueError('r10 source-list count drift')
 seen=set();total=0
 for row in rows:
  rel=row.get('path') if isinstance(row,dict) else None
  if not isinstance(rel,str) or rel in seen or '\\' in rel or ':' in rel or '..' in rel.split('/'):
   raise ValueError('r10 unsafe/duplicate row')
  if not re.fullmatch(r'[0-9a-f]{64}',str(row.get('sha256','')).lower().replace('sha256:','')):
   raise ValueError('r10 row hash invalid')
  n=int(row.get('bytes',-1));
  if n<0 or n>MAX_FILE: raise ValueError('r10 row byte bound invalid')
  seen.add(rel);total+=n
  if total>MAX_TOTAL: raise ValueError('r10 graph total bound exceeded')
  if source_root is not None:
   p=safe(Path(source_root),rel);size,got,_=stream(p)
   if size!=n or got!=str(row['sha256']).lower().replace('sha256:',''): raise ValueError('r10 output row drift')
 if int(graph.get('aggregateBytes',-1))!=total: raise ValueError('r10 aggregate byte drift')
 return True

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--donor-root',required=True);ap.add_argument('--output-root',required=True);ap.add_argument('--source-list',required=True);ap.add_argument('--helper-source',required=True);ap.add_argument('--zip-path');ap.add_argument('--installer-path');ap.add_argument('--namespace',default='text-mta-r11-count20-r10');ap.add_argument('--old-namespace',default='text-mta-r11-count20-r9');ap.add_argument('--profile',default='text-count20-r10-kernel-authority-v1');args=ap.parse_args()
 donor=Path(args.donor_root);out=Path(args.output_root);helper=Path(args.helper_source);source_list=Path(args.source_list)
 if out.exists(): raise SystemExit(f'fresh output exists: {out}')
 if not re.fullmatch(r'[0-9a-f]{64}',OLD): raise SystemExit('frozen helper hash malformed')
 n,h,helper_data=stream(helper); assert helper_data is not None
 list_n,list_hash,list_data=stream(source_list,1*1024*1024);rels=json.loads(list_data.decode('utf-8'))
 if not isinstance(rels,list) or len(rels)>MAX_FILES: raise ValueError('invalid source list')
 rows=[]; total=0; transformed=0
 for rel in rels:
  src=safe(donor,rel); size,oldh,data=stream(src)
  if rel=='producer/support/cleanup.ps1' and oldh.lower()!=OLD: raise ValueError(f'frozen cleanup helper hash mismatch: {oldh}')
  replaced=False
  if rel.endswith('/support/cleanup.ps1'):
   data=helper_data; transformed+=1; replaced=True
  elif data is not None and rel.endswith(('.ps1','.json','.cs','.py','.md')):
   try:
    txt=data.decode('utf-8'); before=txt; txt,count=transform(rel,txt,h)
    for old,new in ((args.old_namespace,args.namespace),): txt=re.sub(r'(?<![A-Za-z0-9_.-])'+re.escape(old)+r'(?![A-Za-z0-9_.-])',lambda _m,value=new:value,txt)
    data=txt.encode('utf-8'); replaced=(before!=txt); transformed+=int(replaced)
   except UnicodeDecodeError: pass
  dst=safe(out,rel)
  if data is None:
   copy_stream(src,dst,size,oldh);out_size,out_hash=size,oldh
  else:
   write(dst,data);out_size,out_hash=len(data),hashlib.sha256(data).hexdigest()
  total+=out_size
  if total>MAX_TOTAL: raise ValueError('source graph exceeds 256 MiB')
  rows.append({'path':rel,'donorBytes':size,'donorSha256':oldh,'bytes':out_size,'sha256':out_hash,'transformed':replaced})
 # Bind measured EXE before graph reseal so every dependent edge sees final SI bytes.
 si_path=out/'admission'/'source-inputs.json'
 if not si_path.is_file(): raise ValueError('source-inputs missing before reseal')
 si,_,_=load_json_bounded(si_path)
 exe_hash=str(si.get('exeHash','')).lower().replace('sha256:','')
 if not re.fullmatch(r'[0-9a-f]{64}',exe_hash): raise ValueError('measured executable hash missing from source inputs')
 si['expectedExeHash']=exe_hash
 si_path.write_text(json.dumps(si,sort_keys=True,separators=(',',':')),encoding='utf-8')
 # Reseal candidate tuple/context/binding, integration bindings, source-inputs,
 # & overlay rows after every transformation. These bytes are source evidence,
 # not a qualification claim.
 reseal_local(out);refresh_stage_manifest(out);refresh_rows(rows,out)
 stale=[]
 for row in rows:
  p=out/row['path']
  raw=stream(p)[2]
  if raw is not None and OLD in raw.decode('utf-8',errors='ignore').lower(): stale.append(str(p))
 if stale: raise ValueError('stale frozen cleanup hash remains in staged call graph: '+','.join(stale[:4]))
 refresh_rows(rows,out)
 if total>MAX_TOTAL: raise ValueError('source graph exceeds bound')
 graph={'kind':'factory-text-count20-r10-kernel-source-graph-v1','profile':args.profile,'historicalDonor':str(donor),'frozenHelperSha256':OLD,'successorHelperSha256':h,'successorHelperBytes':n,'expectedExeHash':exe_hash,'sourceListSha256':list_hash,'sourceListBytes':list_n,'sourceListCount':len(rels),'aggregateBytes':sum(int(row['bytes']) for row in rows),'count':20,'count1FirstRequired':True,'count1CertificateRequired':True,'nativeWindowActions':0,'compilerActions':0,'lockActions':0,'rendererDeadlineSeconds':30,'exitDeadlineSeconds':15,'streamDrainMilliseconds':5000,'donorMutated':False,'transformedFileCount':transformed,'files':rows}
 validate_graph(graph,out)
 graph_bytes=json.dumps(graph,sort_keys=True,separators=(',',':')).encode();write(out/'r10-source-graph.json',graph_bytes)
 seal={'kind':'factory-text-count20-r10-reseal-plan-v1','status':'requires-root-measured-reseal','helperRefs':[{'path':'producer/support/cleanup.ps1','sha256':'sha256:'+h,'bytes':n},{'path':'producer/dependencies/uia-worker/support/cleanup.ps1','sha256':'sha256:'+h,'bytes':n}],'sourceGraphRef':{'path':'r10-source-graph.json','sha256':'sha256:'+hashlib.sha256(graph_bytes).hexdigest(),'bytes':len(graph_bytes)},'requiredReseals':['admission/source-inputs.json','producer/integration-bindings.json','stage-manifest.json','overlay/capture-build-preflight.ps1','overlay/capture-text-count20-v1.ps1','overlay/capture-text-single-v3.ps1','overlay/uia-worker-invoke-v2.ps1','producer/dependencies/uia-worker/invoke-worker-mta.ps1','producer/dependencies/uia-worker/support/cleanup.ps1'],'freshNamespaceRequired':True,'historicalSourcePreserved':True}
 write(out/'r10-reseal-plan.json',json.dumps(seal,sort_keys=True,separators=(',',':')).encode())
 if args.zip_path:
  zp=Path(args.zip_path)
  if zp.exists(): raise SystemExit(f'fresh ZIP exists: {zp}')
  zp.parent.mkdir(parents=True,exist_ok=True)
  payload=[(out/row['path'],row['path']) for row in rows]+[(out/'r10-source-graph.json','r10-source-graph.json'),(out/'r10-reseal-plan.json','r10-reseal-plan.json')]
  inv=[];total_zip=0
  for p,rel in payload:
   n,h,_=stream(p);total_zip+=n
   if total_zip>MAX_TOTAL: raise ValueError('ZIP payload exceeds bound')
   inv.append({'path':rel,'bytes':n,'sha256':h})
  if len(payload)+1>MAX_FILES: raise ValueError('ZIP file count exceeds bound')
  inv_doc={'kind':'factory-text-count20-r10-zip-inventory-v1','files':inv,'fileCount':len(inv),'payloadBytes':total_zip,'inventorySelfExcluded':True,'maxFiles':MAX_FILES,'maxTotalBytes':MAX_TOTAL,'nativeActions':0,'compilerActions':0,'lockActions':0}
  inv_bytes=json.dumps(inv_doc,sort_keys=True,separators=(',',':')).encode();write(out/'r10-zip-inventory.json',inv_bytes)
  payload.append((out/'r10-zip-inventory.json','r10-zip-inventory.json'));inv_doc['inventoryBytes']=len(inv_bytes)
  with zipfile.ZipFile(zp,'x',compression=zipfile.ZIP_DEFLATED) as z:
   for p,rel in payload: z.write(p,rel)
  zip_bytes,zip_hash,_=stream(zp,MAX_TOTAL)
  if args.installer_path:
   cert=out/'admission'/'count1-certificate.json'
   if not cert.is_file(): raise ValueError('Count1 certificate missing for installer')
   cert_n,cert_hash,_=stream(cert,MAX_TEXT); cert_ref={'sha256':cert_hash,'bytes':cert_n}
   template=out/'stage-manifest.json'; template_sha=stream(template,MAX_TEXT)[1] if template.is_file() else hashlib.sha256(graph_bytes).hexdigest()
   installer=make_installer(args.profile.split('-')[0],args.namespace,zip_hash,cert_ref,stream(out/'admission'/'source-inputs.json')[1],template_sha)
   ip=Path(args.installer_path);ip.parent.mkdir(parents=True,exist_ok=True);write(ip,installer.encode())
if __name__=='__main__': main()
