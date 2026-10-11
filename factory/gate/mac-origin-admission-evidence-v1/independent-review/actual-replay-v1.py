from pathlib import Path
import sys,json,hashlib,importlib.util
ROOT=Path(__file__).resolve().parents[4];sys.path.insert(0,str(ROOT));BASE=ROOT/'factory/oracle/mac/seed-origin-actual-v1'
spec=importlib.util.spec_from_file_location('reviewed_guard',Path(__file__).parent/'source-snapshot-v1/mac_origin_admission.py');g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
def ref(p):
 raw=p.read_bytes();return {'path':str(p),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
manifest=json.loads((BASE/'archive-map.json').read_text());byHash={}
for b in manifest['files']:byHash.setdefault(b['sha256'],BASE/b['path'])
reads=[];cache={}
def reader(v):
 expected=v['sha256']
 if expected in cache:return cache[expected]
 if expected in byHash:p=byHash[expected];mode='pinned-archive-by-exact-byte-hash'
 else:
  p=Path(v['path']);assert str(p).startswith('/Applications/Xcode-27-RC.app/') or str(p)=='/usr/bin/xcrun','Nonarchived non-tool input denied';mode='current-original-tool-by-recorded-exact-hash'
 raw=p.read_bytes();assert 'sha256:'+hashlib.sha256(raw).hexdigest()==expected
 reads.append({'semanticPath':v['path'],'readPath':str(p),'sha256':expected,'mode':mode,'bytes':len(raw)});cache[expected]=raw;return raw
rows=[]
for folder in sorted(BASE.glob('swiftui.*')):
 if not folder.is_dir() or not (folder/'summary.json').exists():continue
 summary=json.loads((folder/'summary.json').read_text());case=BASE/'input-snapshot'/(folder.name+'.json');source=BASE/'archive'/folder.name/'source/Witness.swift';binary=BASE/'archive'/folder.name/'binary/capture-host'
 capture={'platform':'macos','case':summary['case'],'macOrigin':{'version':'1','summary':ref(folder/'summary.json'),'case':ref(case),'source':ref(source),'binary':ref(binary),'compilerReceipt':ref(folder/'compiler-receipt.json'),'auxiliaryAX':{'receipt':ref(BASE/'ax-compiler-receipt.json'),'source':ref(BASE/'archive/auxiliary/source/AXClient.swift'),'binary':ref(BASE/'archive/auxiliary/binary/f5-ax-client')}}}
 try:issues=g.mac_origin_admission_issues(capture,reader);rows.append({'case':folder.name,'issues':issues,'passed':not issues})
 except Exception as e:rows.append({'case':folder.name,'exception':type(e).__name__+': '+str(e)})
print(json.dumps({'kind':'actual-five-archive-mac-origin-compatibility-replay-v1','synthetic':False,'nativeOrCompilerRuns':0,'archiveMapRef':ref(BASE/'archive-map.json'),'readPolicy':'Exact raw-hash archive mapping; original compiler/xcrun tool bytes read only if absent archive, never executed. This is compatibility replay, not integrated reader qualification.','rows':rows,'reads':reads},indent=2))
