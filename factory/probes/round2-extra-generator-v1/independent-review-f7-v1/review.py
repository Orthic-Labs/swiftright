from pathlib import Path
import sys,json,hashlib,copy,tempfile,shutil,subprocess,os
ROOT=Path(__file__).resolve().parents[4];P=ROOT/'factory/probes/round2-extra-generator-v1';OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(P));import generate as producer

def sha(b):return hashlib.sha256(b).hexdigest()
stage=json.loads((P/'stage-manifest.json').read_bytes())
for row in stage['entries']:
 b=(ROOT/row['path']).read_bytes()
 if sha(b)!=row['sha256'] or len(b)!=row['bytes']:raise ValueError('Stage drift '+row['path'])
packet=producer.load_packet();pairs=[];faults=[]
with tempfile.TemporaryDirectory(prefix='round2-review-',dir='/private/tmp') as tmp:
 d=Path(tmp);result=producer.generate(packet,d)
 for mpath in sorted(d.glob('*.manifest.json')):
  m=json.loads(mpath.read_bytes());s=(d/m['sourceFile']).read_bytes()
  import re
  actual_type=re.search(rb'\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b',s).group(1).decode()
  if m['sourceHash']!='sha256:'+sha(s):raise ValueError('Source hash mismatch')
  pairs.append({'id':m['case']['id'],'block':m['block'],'scenario':m['scenario'],'sourceHash':m['sourceHash'],'recordedWitnessType':m['witnessType'],'actualSourceType':actual_type,'typeMatches':m['witnessType']==actual_type,'executionEligible':m['executionEligible'],'sourceFile':m['sourceFile']})
  shutil.copyfile(mpath,OUT/mpath.name);shutil.copyfile(d/m['sourceFile'],OUT/m['sourceFile'])
 bad=copy.deepcopy(packet);bad['join']['rows'][0]['selectedSourceSymbols']=[]
 try:
  r=producer.generate(bad,d/'empty-source-join')
  faults.append({'name':'empty-selected-source-join','syntheticMutation':True,'accepted':True,'outputs':r['outputs'],'explanation':'Public generate emits empty sourceBindings for affected block, despite frozen source-use join contract.'})
 except producer.GenerationError as e:faults.append({'name':'empty-selected-source-join','accepted':False,'error':str(e)})
controls=[]
for args in [['--check-only']]:
 p=subprocess.run([sys.executable,str(P/'generate.py'),*args],cwd=ROOT,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'},capture_output=True,timeout=60)
 (OUT/'check.stdout.bin').write_bytes(p.stdout);(OUT/'check.stderr.bin').write_bytes(p.stderr)
 if p.returncode!=0:raise ValueError('Actual CLI check failed')
 controls.append({'argv':[sys.executable,str(P/'generate.py'),*args],'returnCode':p.returncode,'stdoutHash':sha(p.stdout),'stderrHash':sha(p.stderr)})
neg=[x for x in pairs if x['scenario']=='negative:must-not-compile'];mismatch=[x for x in neg if not x['typeMatches']]
report={'kind':'round2-extra-generator-independent-review-f7-v1','decision':'HOLD-SOURCE-MANIFEST-BINDING' if mismatch or any(f['accepted'] for f in faults) else 'CLEAR-SOURCE-ONLY','producerStageHash':sha((P/'stage-manifest.json').read_bytes()),'generatorHash':sha((P/'generate.py').read_bytes()),'actualPairs':len(pairs),'pairs':pairs,'actualCLI':controls,'findings':[{'id':'negative-witness-type','affected':len(mismatch),'explanation':'Negative source declares Negative_round2; manifest uses positive Witness_round2_* type & positive witness id/hash/path. Invalid manifest can fail for missing declared witness type instead of intended API misuse. Preserve separate negative id/source hash/path/type.'} ] if mismatch else [],'ownFaultControls':faults,'compilerRuns':0,'nativeRuns':0,'scope':'Actual source generation & manifest joins only; no typecheck/runtime/native/ABI qualification.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'decision':report['decision'],'pairs':len(pairs),'negativeTypeMismatches':len(mismatch),'emptyJoinAccepted':faults[0]['accepted'],'reportHash':sha((OUT/'report.json').read_bytes())}))
