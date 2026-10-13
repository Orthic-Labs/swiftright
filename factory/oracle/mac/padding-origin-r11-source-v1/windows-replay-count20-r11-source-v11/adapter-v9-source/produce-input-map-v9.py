#!/usr/bin/env python3
"""Build explicit Count20 adapter inputs from supplied metadata & native archive.

Every archive ref is byte/hash checked. Missing native refs fail closed unless
--allow-pending is supplied; pending output never invents hashes.
"""
from __future__ import annotations
import argparse,copy,json
from pathlib import Path, PurePosixPath
from bounded_io_v9 import ARCHIVE_FILE_LIMIT, bounded_json, beneath, output_path, stream_hash, verify_ref

class Hold(ValueError): pass

def ref(repo,rel,allow_pending=False):
 if isinstance(rel,Path): rel=rel.as_posix()
 if not isinstance(rel,str) or not rel or ':' in rel or '\\' in rel or rel.startswith('/'):
  raise Hold('unsafe local archive path:'+str(rel))
 try:p=beneath(repo,rel)
 except ValueError:raise Hold('archive path escapes repo:'+rel)
 if not p.is_file():
  if allow_pending:return rel
  raise Hold('missing archive ref:'+rel)
 actual,size=stream_hash(p,max_bytes=ARCHIVE_FILE_LIMIT);return {'path':rel,'sha256':actual,'bytes':size}
def replace_roots(v,old_native,new_native,old_meta,new_meta,old_overlay,new_overlay):
 if isinstance(v,str):
  # Template paths are supplied explicitly; no historical root is inferred.
  return (v.replace(old_native,new_native)
           .replace(old_meta,new_meta)
           .replace(old_overlay,new_overlay))
 if isinstance(v,list): return [replace_roots(x,old_native,new_native,old_meta,new_meta,old_overlay,new_overlay) for x in v]
 if isinstance(v,dict): return {k:replace_roots(x,old_native,new_native,old_meta,new_meta,old_overlay,new_overlay) for k,x in v.items()}
 return v

def load(repo,p):
 q=beneath(repo,p.as_posix()); return bounded_json(q)
def build(args):
 repo=args.repo.absolute(); meta=repo/args.metadata_root; native_rel=args.native_root.as_posix(); meta_rel=args.metadata_root.as_posix()
 for label, rel in (('metadata',meta_rel),('native',native_rel)):
  if not rel or rel.startswith('/') or '\\' in rel or ':' in rel:
   raise Hold('unsafe '+label+' root:'+rel)
 try:beneath(repo,rel)
 except ValueError:raise Hold(label+' root escapes repository:'+rel)
 template_native=args.template_native_root.as_posix(); template_meta=args.template_metadata_root.as_posix(); template_overlay=args.template_overlay_root.as_posix()
 overlay_rel=args.overlay_root.as_posix()
 try:manifest_path=beneath(meta,'manifest.json')
 except ValueError:raise Hold('fresh metadata manifest missing')
 manifest=load(repo,args.metadata_root/'manifest.json')
 files=manifest.get('files');
 if manifest.get('kind')!='root-prefixed-canonical-prelaunch-metadata-fetch-v1' or len(files)!=40: raise Hold('fresh metadata manifest must contain exactly 40 files')
 for row in files:
  try:p=beneath(meta,row['path'])
  except ValueError: raise Hold('unsafe fresh metadata path:'+str(row.get('path')))
  try:verify_ref(p,{'sha256':'sha256:'+row['sha256'],'bytes':row['bytes']},max_bytes=ARCHIVE_FILE_LIMIT)
  except ValueError: raise Hold('fresh metadata byte/hash mismatch:'+row['path'])
 issued_rel=args.issued_metadata or args.metadata_root/'coordinator-repeat-r1/issued-metadata.json'
 if issued_rel.is_absolute() or ':' in issued_rel.as_posix() or '\\' in issued_rel.as_posix(): raise Hold('unsafe issued metadata path:'+issued_rel.as_posix())
 try:beneath(repo,issued_rel.as_posix())
 except ValueError:raise Hold('issued metadata escapes repository:'+issued_rel.as_posix())
 issued=load(repo,issued_rel)
 if issued.get('expectedCount')!=20 or issued.get('frozenTupleBound') is not False: raise Hold('fresh issued metadata count/boundary mismatch')
 template=load(repo,args.template)
 if template.get('count')!=20: raise Hold('template Count20 required')
 d=replace_roots(copy.deepcopy(template),template_native,native_rel,template_meta,meta_rel,template_overlay,overlay_rel)
 # Exact fresh metadata/control namespace.
 d['schema']='factory-native-count20-input-map-v9-pending'
 d['pending']={'status':'pending-native-archive' if not (repo/native_rel).exists() else 'ready-for-v6-normalization','count':20,'metadataRoot':meta_rel,'nativeRoot':native_rel,'metadataFiles':40,'missingRequiredClosure':'none-in-pending-builder; strict mode requires every native role ref','qualification':'hold-until-production-proof2-reader'}
 d['executionOverlay']['overlayRoot']=overlay_rel
 d['executionOverlay']['kind']='factory-root-execution-overlay-v1'
 d['executionOverlay']['status']='executed-source-ref-only'
 d['executionOverlay']['files']=[x.replace(template_overlay,overlay_rel) for x in d['executionOverlay']['files']]
 d['executionOverlay']['contract']['kind']='factory-root-execution-overlay-count20-contract-v1'
 d['roles']['issuedMetadata']=str(issued_rel)
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
 d['issuerSource']=args.issuer_source.as_posix()
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
 native_path=beneath(repo,native_rel)
 d['actual']={'kind':'factory-count20-v9-input-map-builder-v1','metadataManifestSha256':ref(repo,args.metadata_root/'manifest.json',args.allow_pending).get('sha256',''),'metadataFileCount':40,'nativeRoot':native_rel,'status':d['pending']['status'],'nativeArchivePresent':native_path.is_dir(),'hashesInvented':False}
 return d

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--template',type=Path,required=True); ap.add_argument('--template-native-root',type=Path,required=True); ap.add_argument('--template-metadata-root',type=Path,required=True); ap.add_argument('--template-overlay-root',type=Path,required=True); ap.add_argument('--metadata-root',type=Path,required=True); ap.add_argument('--native-root',type=Path,required=True); ap.add_argument('--overlay-root',type=Path,required=True); ap.add_argument('--issuer-source',type=Path,required=True); ap.add_argument('--issued-metadata',type=Path); ap.add_argument('--output',type=Path,required=True); ap.add_argument('--repo',type=Path,default=Path('.')); ap.add_argument('--allow-pending',action='store_true'); a=ap.parse_args()
 output_path(a.output)
 try:o=build(a)
 except Exception as e: raise SystemExit('HOLD: '+str(e))
 a.output.parent.mkdir(parents=True,exist_ok=True)
 with a.output.open('x',encoding='utf-8') as handle: json.dump(o,handle,indent=2,sort_keys=True); handle.write('\n')
 print(json.dumps({'status':o['actual']['status'],'metadataFiles':40,'count':20,'nativeArchivePresent':o['actual']['nativeArchivePresent'],'nativeActions':0,'lockActions':0},sort_keys=True))
if __name__=='__main__':main()
