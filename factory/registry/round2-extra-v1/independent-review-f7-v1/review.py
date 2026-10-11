"""Independent bounded source/identity review, never registry production writes."""
from pathlib import Path
import copy,hashlib,importlib.util,json,sys,subprocess,datetime
ROOT=Path(__file__).resolve().parents[4]
PACKET=ROOT/'factory/registry/round2-extra-v1';OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(PACKET));import verify

def hash_bytes(b):return hashlib.sha256(b).hexdigest()
def main():
 stage_raw=(PACKET/'stage-manifest.json').read_bytes();stage=json.loads(stage_raw);pins=[]
 for row in stage['entries']:
  raw=(ROOT/row['path']).read_bytes()
  if len(raw)!=row['bytes'] or hash_bytes(raw)!=row['sha256']:raise ValueError('Stage pin drift '+row['path'])
  pins.append({'path':row['path'],'sha256':hash_bytes(raw),'bytes':len(raw)})
 catalogue,craw=verify.load(verify.CATALOGUE);manifest,mraw=verify.load(PACKET/'candidate-manifest.json')
 if verify.check(manifest,catalogue,craw):raise ValueError('Actual baseline rejected')
 process=[]
 for name in ['verify.py','test_round2_extra.py']:
  argv=[sys.executable,str(PACKET/name)];started=datetime.datetime.now(datetime.timezone.utc).isoformat();p=subprocess.run(argv,cwd=ROOT,capture_output=True,env={**__import__('os').environ,'PYTHONDONTWRITEBYTECODE':'1'},timeout=90);ended=datetime.datetime.now(datetime.timezone.utc).isoformat()
  (OUT/(name+'.stdout.bin')).write_bytes(p.stdout);(OUT/(name+'.stderr.bin')).write_bytes(p.stderr)
  if p.returncode!=0:raise ValueError(name+' failed')
  process.append({'argv':argv,'cwd':str(ROOT),'startedAt':started,'endedAt':ended,'returnCode':p.returncode,'stdoutHash':hash_bytes(p.stdout),'stderrHash':hash_bytes(p.stderr),'PID':'not recorded by subprocess.run'})
 controls=[]
 mutations=[('omitted-block',lambda m:m['blocks'].pop()),('duplicate-block',lambda m:m['blocks'].__setitem__(1,copy.deepcopy(m['blocks'][0]))),('wrong-USR',lambda m:m['blocks'][0]['symbols'][0].update(selector='usr:s:synthetic-wrong')),('wrong-symbol-hash',lambda m:m['blocks'][0]['symbols'][0].update(symbolEvidenceSha256='0'*64)),('missing-symbol',lambda m:m['blocks'][1]['symbols'].pop()),('duplicate-symbol',lambda m:m['blocks'][1]['symbols'].__setitem__(1,copy.deepcopy(m['blocks'][1]['symbols'][0]))),('promotion',lambda m:m['blocks'][0].update(registryPromotion=True)),('string-false-promotion',lambda m:m['blocks'][0].update(registryPromotion='false')),('native-coverage',lambda m:m['blocks'][0].update(nativeCoverage='qualified')),('coverage-status',lambda m:m['blocks'][0].update(coverageStatus='available')),('unbound-dependency',lambda m:m['blocks'][0].update(semanticDependencies=['swiftui.toggle'])),('active-mutation',lambda m:m.update(activeRegistryMutation=True)),('catalogue-pin',lambda m:m['catalogue'].update(sha256='0'*64)),('wrong-path',lambda m:m['blocks'][0]['symbols'][0].update(path='SwiftUI.View.synthetic'))]
 for name,mutate in mutations:
  bad=copy.deepcopy(manifest);mutate(bad);errors=verify.check(bad,catalogue,craw)
  if not errors:raise ValueError('Fault admitted '+name)
  controls.append({'fault':name,'syntheticMutation':True,'rejected':True,'issues':errors})
 errors=verify.check(manifest,catalogue,craw+b' ')
 if not errors:raise ValueError('Changed catalogue raw admitted')
 controls.append({'fault':'raw-catalogue-drift','syntheticMutation':True,'rejected':True,'issues':errors})
 # Active metadata actual raw joins independently checked, not inferred from verifier labels.
 for key,path in [('activeManifest',verify.ACTIVE_MANIFEST),('activeRegistry',verify.ACTIVE_REGISTRY)]:
  raw=path.read_bytes();obj=json.loads(raw)
  if manifest[key]['sha256']!=hash_bytes(raw) or manifest[key]['blockIds']!=[b['id'] for b in obj['blocks']]:raise ValueError('Active metadata raw join drift')
 symbol_by_usr={s['usr']:s for s in catalogue['symbols']};selected=[]
 for block in manifest['blocks']:
  for entry in block['symbols']:
   obj=symbol_by_usr[entry['selector'][4:]]
   if obj['path']!=entry['path'] or hash_bytes(verify.canonical(obj))!=entry['symbolEvidenceSha256']:raise ValueError('Independent actual symbol join drift')
   selected.append({'block':block['id'],**entry})
 report={'kind':'independent-round2-registry-source-review-f7-v1','decision':'CLEAR-IDENTITY-ONLY','stageHash':hash_bytes(stage_raw),'manifestHash':hash_bytes(mraw),'catalogueHash':hash_bytes(craw),'actualBlocks':5,'actualUSRs':len(selected),'actualSelectedSymbols':selected,'pins':pins,'processes':process,'faultControls':controls,'activeRegistryMutation':False,'qualificationPromotion':False,'nativeRuns':0,'boundary':'Exact raw catalogue/USR identity & candidate statuses only; no native recipe, SDK frontend overload resolution, semantic dependency, behavioral parity, or qualification claim. Verifier does not validate all informational active registry metadata; this review joins actual metadata bytes independently.'}
 (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'decision':report['decision'],'blocks':5,'USRs':len(selected),'independentFaults':len(controls),'reportHash':hash_bytes((OUT/'report.json').read_bytes())}))
if __name__=='__main__':main()
