from pathlib import Path
import sys,json,hashlib,copy,tempfile,shutil,subprocess,os,re
ROOT=Path(__file__).resolve().parents[4];P=ROOT/'factory/probes/round2-extra-generator-v2';OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(P));import generate as producer
sha=lambda b:hashlib.sha256(b).hexdigest()
stage_raw=(P/'stage-manifest.json').read_bytes();stage=json.loads(stage_raw)
for row in stage['entries']:
 b=(ROOT/row['path']).read_bytes()
 if sha(b)!=row['sha256'] or len(b)!=row['bytes']:raise ValueError('Stage drift '+row['path'])
packet=producer.load_packet();pairs=[];faults=[];processes=[]
for script,args in [('generate.py',['--check-only']),('test_generator.py',[])]:
 argv=[sys.executable,str(P/script),*args];p=subprocess.run(argv,cwd=ROOT,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'},capture_output=True,timeout=90)
 (OUT/(script+'.stdout.bin')).write_bytes(p.stdout);(OUT/(script+'.stderr.bin')).write_bytes(p.stderr)
 if p.returncode!=0:raise ValueError('Actual producer controls failed '+script)
 processes.append({'argv':argv,'returnCode':p.returncode,'stdoutHash':sha(p.stdout),'stderrHash':sha(p.stderr)})
with tempfile.TemporaryDirectory(prefix='round2-v2-review-',dir='/private/tmp') as tmp:
 d=Path(tmp);result=producer.generate(packet,d)
 manifests=[]
 for mpath in sorted(d.glob('*.manifest.json')):
  m=json.loads(mpath.read_bytes());s=(d/m['sourceFile']).read_bytes();producer.validate_output_manifest(m,packet)
  actual_type=re.search(rb'\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b',s).group(1).decode()
  raw=(ROOT/m['witness']['resourcePath']).read_bytes()
  if m['sourceHash']!='sha256:'+sha(s) or m['witness']['sourceHash']!='sha256:'+sha(raw) or m['witnessType']!=actual_type:raise ValueError('Actual source/manifest drift')
  if m['case']['id']!=m['case']['descriptor']['id'] or m['executionEligible'] is not False or m['registryPromotion'] is not False:raise ValueError('Actual descriptor/policy drift')
  pairs.append({'id':m['case']['id'],'block':m['block'],'scenario':m['scenario'],'sourceHash':m['sourceHash'],'witness':m['witness'],'witnessType':actual_type,'typeMatches':True,'executionEligible':False})
  manifests.append(m);shutil.copyfile(mpath,OUT/mpath.name);shutil.copyfile(d/m['sourceFile'],OUT/m['sourceFile'])
 for name,mutate in [('empty-source-use',lambda p:p['join']['rows'][0].update(selectedSourceSymbols=[])),('duplicate-source-use',lambda p:p['join']['rows'][1]['selectedSourceSymbols'].append(copy.deepcopy(p['join']['rows'][1]['selectedSourceSymbols'][0]))),('reordered-source-use',lambda p:p['join']['rows'][1]['selectedSourceSymbols'].reverse()),('omitted-join-block',lambda p:p['join']['rows'].pop())]:
  bad=copy.deepcopy(packet);mutate(bad)
  try:producer.generate(bad,d/name)
  except producer.GenerationError as e:faults.append({'name':name,'syntheticMutation':True,'rejected':True,'error':str(e)})
  else:raise ValueError('Source fault admitted '+name)
 m=next(x for x in manifests if x['scenario']=='candidate-projection')
 for name,mutate in [('wrong-source-hash',lambda x:x.update(sourceHash='sha256:'+'0'*64)),('misbound-case-id',lambda x:x['case'].update(id='swiftui.synthetic.case'))]:
  bad=copy.deepcopy(m);mutate(bad)
  try:producer.validate_output_manifest(bad,packet)
  except producer.GenerationError as e:faults.append({'name':name,'syntheticMutation':True,'rejected':True,'error':str(e)})
  else:faults.append({'name':name,'syntheticMutation':True,'rejected':False,'explanation':'Public output validator accepts metadata differing from actual source/frozen descriptor.'})
accepted=[x for x in faults if x['rejected'] is False]
report={'kind':'independent-round2-generator-v2-review-f7-v1','decision':'HOLD-OUTPUT-BINDING' if accepted else 'CLEAR-SOURCE-ONLY','producerStageHash':sha(stage_raw),'generatorHash':sha((P/'generate.py').read_bytes()),'actualPairs':len(pairs),'negativePairs':sum(x['scenario']=='negative:must-not-compile' for x in pairs),'allActualTypesAndRawHashesCorrect':True,'priorEmptyJoinFaultRejected':True,'pairs':pairs,'actualProducerControls':processes,'producerFaultCount':12,'ownFaultControls':faults,'compilerRuns':0,'nativeRuns':0,'scope':'Source-only held proposal; no ABI/native/overload/qualification claim. V1 HOLD preserved.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'decision':report['decision'],'pairs':len(pairs),'priorFaultsResolved':True,'acceptedOwnOutputFaults':[x['name'] for x in accepted],'reportHash':sha((OUT/'report.json').read_bytes())}))
