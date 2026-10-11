#!/usr/bin/env python3
"""Create fresh case/manifest binding actual internal host bytes."""
from __future__ import annotations
import argparse, hashlib, json, shutil
from pathlib import Path
from factory.core.artifacts import canonical_hash, validate_artifact

def digest(path: Path) -> str:
 return 'sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--base-case',type=Path,required=True); ap.add_argument('--base-manifest',type=Path,required=True); ap.add_argument('--host-receipt',type=Path,required=True); ap.add_argument('--output-case',type=Path,required=True); ap.add_argument('--output-manifest',type=Path,required=True); ap.add_argument('--output-tuple',type=Path,required=True); a=ap.parse_args()
 base=json.loads(a.base_case.read_text()); bm=json.loads(a.base_manifest.read_text()); host=json.loads(a.host_receipt.read_text())
 if host.get('status') != 'internal-host-built-no-native-launch': raise SystemExit('host build not source-ready')
 actual=host.get('binary',{}).get('sha256'); expected=host.get('tupleTemplate',{}).get('hostHashes',{}).get('macos')
 if not isinstance(actual,str) or not actual.startswith('sha256:'): raise SystemExit('missing actual host hash')
 short=actual.removeprefix('sha256:')[:12]; new_id='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h'+short
 case=dict(base); case['id']=new_id; case['tuple']=dict(base['tuple']); case['tuple']['id']='sr1-source-bound-r11-mac20-host-'+short+'-20261011'; case['tuple']['hostHashes']=dict(base['tuple']['hostHashes']); case['tuple']['hostHashes']['macos']=actual; case['provenance']=dict(base['provenance']); case['provenance']['producer']='factory/native/macos/r11-host-bound-candidate'; case['provenance']['inputs']=[{'id':base['id'],'hash':canonical_hash(base)},{'id':'mac-host-build-r1','hash':canonical_hash(host)}]
 validate_artifact(case); ref={'id':new_id,'hash':canonical_hash(case)}; manifest=dict(bm); manifest['case']=ref
 for p in (a.output_case,a.output_manifest,a.output_tuple):
  if p.exists(): raise SystemExit('output must be fresh: '+str(p))
 source_name = bm.get('sourceFile')
 if not isinstance(source_name,str) or Path(source_name).name != source_name:
  raise SystemExit('manifest sourceFile must be basename')
 base_source = a.base_manifest.parent / source_name
 if not base_source.is_file(): raise SystemExit('base manifest source missing: '+str(base_source))
 if 'sourceHash' in bm and digest(base_source) != bm['sourceHash']:
  raise SystemExit('base manifest source hash mismatch')
 target_source = a.output_manifest.parent / source_name
 if target_source.exists(): raise SystemExit('source output must be fresh: '+str(target_source))
 a.output_case.parent.mkdir(parents=True,exist_ok=True); a.output_manifest.parent.mkdir(parents=True,exist_ok=True); a.output_tuple.parent.mkdir(parents=True,exist_ok=True)
 a.output_case.write_text(json.dumps(case,sort_keys=True,indent=2)+'\n'); a.output_manifest.write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')
 shutil.copy2(base_source,target_source)
 tuple_packet={'schema':'factory-macos-r11-host-bound-candidate-tuple-v1','status':'source-ready-native-pending','candidateID':'sr1-source-bound-r11-mac20-host-'+short+'-20261011','case':ref,'tuple':case['tuple'],'hostBuild':{'path':str(a.host_receipt.resolve()),'sha256':'sha256:'+hashlib.sha256(a.host_receipt.read_bytes()).hexdigest(),'bytes':a.host_receipt.stat().st_size},'baseCase':{'id':base['id'],'hash':canonical_hash(base)},'expectedTemplateMacHostHash':expected,'effects':{'nativeWindowActions':0,'compilerActions':0,'remoteActions':0,'lockActions':0}}
 a.output_tuple.write_text(json.dumps(tuple_packet,sort_keys=True,indent=2)+'\n'); print(json.dumps({'status':tuple_packet['status'],'candidateID':tuple_packet['candidateID'],'case':ref,'actualHostHash':actual,'templateHostHash':expected}))
if __name__=='__main__': main()
