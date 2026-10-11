#!/usr/bin/env python3
"""Pure controls for adapter-v6 repeat-r7 composed producer/normalizer."""
from __future__ import annotations
import copy,hashlib,importlib.util,json,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent; REPO=next(p for p in HERE.parents if (p/'factory').is_dir())
profile=json.loads((HERE.parent/'adapter-v5-source/repeat-r7-source-profile-v1/source-profile-repeat-r7.json').read_text())
sm=importlib.util.spec_from_file_location('map_v6',HERE/'produce-input-map-v6.py'); map_v6=importlib.util.module_from_spec(sm); assert sm.loader; sm.loader.exec_module(map_v6)
sa=importlib.util.spec_from_file_location('adapter_v6',HERE/'adapter-v6.py'); adapter=importlib.util.module_from_spec(sa); assert sa.loader; sa.loader.exec_module(adapter)

def sha(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 assert adapter.R7_ROOT==profile['overlayRoot'] and adapter.R7_ROOT in adapter.support.OVERLAY_ROOTS[20]
 assert len(adapter.R7_HASHES)==5
 assert profile['inputMapContract']['requiredActualHashes'] is True
 template=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r6/count20-input-map-r6.pending.json'
 meta=Path(map_v6.R7_META); native=Path(map_v6.R7_NATIVE)
 with tempfile.TemporaryDirectory() as td:
  out=Path(td)/'map.json'
  ns=type('Args',(),{'repo':REPO,'template':template,'metadata_root':meta,'native_root':native,'output':out,'allow_pending':True})()
  d=map_v6.build(ns); out.write_text(json.dumps(d));
  assert d['actual']['metadataFileCount']==40 and d['count']==20 and d['actual']['hashesInvented'] is False
  assert len(d['metadataArchive']['files'])==40 and all(isinstance(x,dict) and x['sha256'].startswith('sha256:') for x in d['metadataArchive']['files'])
  assert len(d['runs'])==20 and len(d['runs'][0])==24 and len(d['source'])==13
  assert d['executionOverlay']['overlayRoot']==profile['overlayRoot']
 faults={}
 for label,mut in [('wrong-meta-root',lambda x:setattr(x,'metadata_root',Path('factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-metadata-r1'))),('wrong-native-root',lambda x:setattr(x,'native_root',Path('factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r6'))),('wrong-template-count',lambda x:setattr(x,'template',REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/count1-input-map-r7.actual.json'))]:
  q=type('Args',(),{'repo':REPO,'template':template,'metadata_root':meta,'native_root':native,'output':Path('/tmp/unused'),'allow_pending':True})(); mut(q)
  try: map_v6.build(q)
  except Exception: faults[label]='rejected'
  else: faults[label]='accepted-BUG'
 assert all(v=='rejected' for v in faults.values())
 print(json.dumps({'status':'pass','positive':['adapter-v6-r7-overlay','pending-map-40-metadata-files','20-runs-x-24-roles','13-source-roles'],'faults':faults,'nativeWindowActions':0,'lockActions':0},sort_keys=True))
if __name__=='__main__':main()
