#!/usr/bin/env python3
"""Build explicit Count20 repeat-r7 adapter inputs from fresh metadata & native archive.

Every archive ref is byte/hash checked. Missing native refs fail closed unless
--allow-pending is supplied; pending output never invents hashes.
"""
from __future__ import annotations
import argparse,copy,hashlib,json
from pathlib import Path, PurePosixPath

R7_NATIVE='factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r7'
R7_META='factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-count20-metadata-r7'
R6_NATIVE='factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r6'
R6_META='factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-metadata-r1'
OLD_R3_NATIVE='factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/observed-native-r3/actual-repeat-r1'
OVERLAY_R7='factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r7'
OVERLAY_R6='factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6'

class Hold(ValueError): pass

def digest(raw): return 'sha256:'+hashlib.sha256(raw).hexdigest()
def ref(repo,rel,allow_pending=False):
 if isinstance(rel,Path): rel=rel.as_posix()
 if not isinstance(rel,str) or not rel or ':' in rel or '\\' in rel or rel.startswith('/'):
  raise Hold('unsafe local archive path:'+str(rel))
 p=(repo/rel).resolve()
 try:p.relative_to(repo.resolve())
 except ValueError:raise Hold('archive path escapes repo:'+rel)
 if not p.is_file():
  if allow_pending:return rel
  raise Hold('missing archive ref:'+rel)
 raw=p.read_bytes();return {'path':rel,'sha256':digest(raw),'bytes':len(raw)}
def replace_roots(v,old_native,new_native,old_meta,new_meta):
 if isinstance(v,str):
  # r6 template carries source paths from r3's actual-controls archive.  For
  # this fresh Count20 run, those exact source bytes are archived beside r7's
  # measured repeat, so bind them to that archive before hashing.
  return (v.replace(old_native,new_native)
           .replace(OLD_R3_NATIVE,new_native+'/actual-repeat-r1')
           .replace(old_meta,new_meta)
           .replace(OVERLAY_R6,OVERLAY_R7).replace('repeat-r6','repeat-r7'))
 if isinstance(v,list): return [replace_roots(x,old_native,new_native,old_meta,new_meta) for x in v]
 if isinstance(v,dict): return {k:replace_roots(x,old_native,new_native,old_meta,new_meta) for k,x in v.items()}
 return v

def load(repo,p):
 q=repo/p; return json.loads(q.read_text(encoding='utf-8-sig'))
def build(args):
 repo=args.repo.resolve(); meta=repo/args.metadata_root; native_rel=args.native_root.as_posix(); meta_rel=args.metadata_root.as_posix()
 if meta_rel!=R7_META: raise Hold('fresh Count20 metadata root must be exact r7 root')
 if native_rel!=R7_NATIVE: raise Hold('Count20 native root must be exact r7 root')
 manifest_path=meta/'manifest.json'
 if not manifest_path.is_file(): raise Hold('fresh metadata manifest missing')
 manifest=load(repo,args.metadata_root/'manifest.json')
 files=manifest.get('files');
 if manifest.get('kind')!='root-prefixed-canonical-prelaunch-metadata-fetch-v1' or len(files)!=40: raise Hold('fresh metadata manifest must contain exactly 40 files')
 for row in files:
  p=meta/row['path'];
  if not p.is_file(): raise Hold('fresh metadata file missing:'+row['path'])
  raw=p.read_bytes()
  if digest(raw)!='sha256:'+row['sha256'] or len(raw)!=row['bytes']: raise Hold('fresh metadata byte/hash mismatch:'+row['path'])
 issued_rel=args.metadata_root/'coordinator-repeat-r1/issued-metadata.json'; issued=load(repo,issued_rel)
 if issued.get('expectedCount')!=20 or issued.get('frozenTupleBound') is not False: raise Hold('fresh issued metadata count/boundary mismatch')
 template=load(repo,args.template)
 if template.get('count')!=20: raise Hold('template Count20 required')
 d=replace_roots(copy.deepcopy(template),R6_NATIVE,native_rel,R6_META,meta_rel)
 # Exact fresh metadata/control namespace.
 d['schema']='factory-native-count20-input-map-r7-pending'
 d['pending']={'status':'pending-native-archive' if not (repo/native_rel).exists() else 'ready-for-v6-normalization','count':20,'metadataRoot':meta_rel,'nativeRoot':native_rel,'metadataFiles':40,'missingRequiredClosure':'none-in-pending-builder; strict mode requires every native role ref','qualification':'hold-until-production-proof2-reader'}
 d['executionOverlay']['overlayRoot']=OVERLAY_R7
 d['executionOverlay']['kind']='factory-root-execution-overlay-v1'
 d['executionOverlay']['status']='executed-source-ref-only'
 d['executionOverlay']['files']=[x.replace(OVERLAY_R6,OVERLAY_R7).replace('repeat-r6','repeat-r7') for x in d['executionOverlay']['files']]
 d['executionOverlay']['contract']['kind']='factory-root-execution-overlay-repeat-r7-contract-v1'
 for x in list(d['executionOverlay']['contract'].get('sha256Files',{})):
  d['executionOverlay']['contract']['sha256Files'][x.replace('r6','r7')]='pending-builder-byte-seal'
  if x != x.replace('r6','r7'): d['executionOverlay']['contract']['sha256Files'].pop(x,None)
 d['roles']['issuedMetadata']=str(args.metadata_root/'coordinator-repeat-r1/issued-metadata.json')
 d['roles']['tuple']=str(args.metadata_root/'coordinator-repeat-r1/candidate-tuple.json')
 d['roles']['candidateBinding']=str(args.metadata_root/'coordinator-repeat-r1/candidate-binding.json')
 d['roles']['coordinator']=str(args.native_root/'coordinator-repeat-r1/coordinator.json')
 d['roles']['plan']=str(args.native_root/'actual-repeat-r1/plan.json')
 d['roles']['compile']=str(args.native_root/'actual-repeat-r1/observation.json')
 # Issuer names recipe/sourceBoundCandidateTuple fields; adapter role names
 # remain manifest/candidateBinding. Preserve recorded Windows paths verbatim.
 d['metadataRecordPaths']={
  'candidateBinding': issued['sourceBoundCandidateTuple']['path'],
  'compile': issued['compile']['path'],
  'exe': issued['exe']['path'],
  'manifest': issued['recipe']['path'],
  'plan': issued['plan']['path'],
  'renderer': issued['renderer']['path'],
 }
 d['issuerSource']='factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/issue-before-launch-prefixed-r1.ps1'
 # Bind every fresh metadata archive file as explicit role evidence.
 d['metadataArchive']={'manifest':ref(repo,args.metadata_root/'manifest.json',args.allow_pending),'files':[ref(repo,args.metadata_root/row['path'],args.allow_pending) for row in files]}
 # Turn known archive path strings into exact refs. Windows recorded paths remain strings.
 def convert(value, context=''):
  if isinstance(value,str):
   if ':' in value or '\\' in value or value.startswith('/') : return value
   if context in {'metadataRecordPaths'}: return value
   try:return ref(repo,Path(value),args.allow_pending)
   except Hold:
    if args.allow_pending:return value
    raise
  if isinstance(value,list):return [convert(x,context) for x in value]
  if isinstance(value,dict):return {k:convert(x,context) for k,x in value.items()}
  return value
 # Convert only fields consumed as archive refs; preserve metadataRecordPaths Windows paths.
 for key in ('roles','producerSource','source','tupleSource','runtimeModules','runs'):
  if key in d:d[key]=convert(d[key],key)
 # Overlay/base-profile join is byte-bound to same explicit producer ref.
 d['executionOverlay']['baseProducerProfile']=d['roles']['producerProfile']
 # Overlay files & issuer are consumed as refs by adapter.
 d['executionOverlay']['files']=convert(d['executionOverlay']['files'],'overlay')
 issuer_path=d['issuerSource']; d['issuerSource']={'name':Path(issuer_path).name,'path':issuer_path,**({k:v for k,v in ref(repo,issuer_path,args.allow_pending).items() if k!='path'})}
 # Every native role is explicit after strict archive transfer; pending leaves path strings.
 d['actual']={'kind':'factory-count20-r7-input-map-builder-v1','metadataManifestSha256':digest(manifest_path.read_bytes()),'metadataFileCount':40,'nativeRoot':native_rel,'status':d['pending']['status'],'nativeArchivePresent':(repo/native_rel).is_dir(),'hashesInvented':False}
 return d

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--template',type=Path,required=True); ap.add_argument('--metadata-root',type=Path,required=True); ap.add_argument('--native-root',type=Path,required=True); ap.add_argument('--output',type=Path,required=True); ap.add_argument('--repo',type=Path,default=Path('.')); ap.add_argument('--allow-pending',action='store_true'); a=ap.parse_args()
 if a.output.exists(): raise SystemExit('HOLD: refusing to overwrite output')
 try:o=build(a)
 except Exception as e: raise SystemExit('HOLD: '+str(e))
 a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(o,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':o['actual']['status'],'metadataFiles':40,'count':20,'nativeArchivePresent':o['actual']['nativeArchivePresent'],'nativeActions':0,'lockActions':0},sort_keys=True))
if __name__=='__main__':main()
