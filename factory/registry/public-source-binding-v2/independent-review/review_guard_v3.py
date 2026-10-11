#!/usr/bin/env python3
import contextlib,hashlib,io,json,sys,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4];HERE=Path(__file__).resolve().parent;V2=HERE.parent;V1=V2.parent/'public-source-binding-v1';G=V2/'versioned-snapshots/comparator-guard-v3';C=ROOT/'factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json'
def sha(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def pin(p):raw=p.read_bytes();return {'path':str(p.relative_to(ROOT)),'sha256':sha(raw),'bytes':len(raw)}
def main():
 source=(G/'compare_final_candidate.py').read_bytes();assert sha(source)=='sha256:ffcccfcdfb2307efd859421316267d7b9bf479a55037f0d74fc9860fe82a6e76';(HERE/'preimages/compare_final_candidate.py.ffcccfc').write_bytes(source)
 stages=[];historical_mismatches=[]
 for stage in sorted(V2.glob('versioned-snapshots/*/stage-manifest.json')):
  d=json.loads(stage.read_bytes())
  for e in d.get('entries',[])+d.get('trackedDependencies',[]):
   actual=pin(ROOT/e['path'])
   if actual['sha256']!=e['sha256'] or actual['bytes']!=e['bytes']:
    assert stage.parent.name=='comparator-guard-v2' and e['path'].endswith('/fault-controls.json'),e['path']
    historical_mismatches.append({'stage':pin(stage),'entry':e,'current':actual})
  stages.append(pin(stage))
 v1=json.loads((V1/'archive-manifest.json').read_bytes());entries=v1['entries']
 for e in entries:
  p=V1/e['path'];actual=pin(p);assert actual['sha256']==e['sha256'] and actual['bytes']==e['bytes']
 assert len(entries)==16
 candidate_raw=C.read_bytes();assert sha(candidate_raw)=='sha256:fd453b6345f83b49931c7194c2e1127538e2de4ceb0de4c25f715ac6d85ac4f2';cat=json.loads(candidate_raw);by={}
 for s in cat['symbols']:by.setdefault(s['usr'],[]).append(s)
 mpath=V1/'manifest-usr-v1.json';epath=V1/'expected-registry-membership.json';m=json.loads(mpath.read_bytes());expected=json.loads(epath.read_bytes());rows=[{'blockId':b['id'],'symbolIndex':i,'usr':u.removeprefix('usr:')} for b in m['blocks'] for i,u in enumerate(b['symbols'])]
 assert rows==expected['blocks'] and len(rows)==65 and len(m['blocks'])==10
 assert len(by)==len(cat['symbols'])==111576 and all(len(by[r['usr']])==1 and by[r['usr']][0]['status']=='inventory' for r in rows)
 proc=json.loads((G/'final-process-v3.json').read_bytes());receipt=json.loads((G/'final-candidate-comparison-fd453b63-v3.json').read_bytes())
 assert proc['returncode']==0 and proc['comparatorSha256']==sha(source) and proc['candidateSha256']==sha(candidate_raw)
 for name in ('stdout','stderr'):
  assert sha((ROOT/proc[name+'Path']).read_bytes())==proc[name+'Sha256']
 stdout=json.loads((ROOT/proc['stdoutPath']).read_bytes());assert {k:v for k,v in stdout.items() if k!='createdAt'}=={k:v for k,v in receipt.items() if k!='createdAt'}
 assert receipt['candidate']['sha256']==sha(candidate_raw) and receipt['candidate']['rawBytes']==len(candidate_raw) and receipt['candidate']['symbolCount']==111576 and receipt['manifest']['selectorCount']==65 and receipt['actualBlockCount']==10 and receipt['membershipEqual']
 owner_faults=json.loads((G/'fault-controls.json').read_bytes());assert owner_faults['status']=='controls-pass' and all(x['passed'] for x in owner_faults['controls'])
 scope={'__name__':'independent_guard_review','__file__':str(G/'compare_final_candidate.py')};exec(compile(source,scope['__file__'],'exec'),scope)
 faults=[]
 with tempfile.TemporaryDirectory(prefix='f2-independent-review-') as tmp:
  tmp=Path(tmp);small=dict(cat);small['symbols']=[by[r['usr']][0] for r in rows];candidate=tmp/'candidate.json';candidate.write_text(json.dumps(small));read=Path.read_bytes
  def invoke(output):
   sys.argv=['guard',str(candidate),'--output',str(output)]
   try:
    with contextlib.redirect_stdout(io.StringIO()):return scope['main'](),''
   except SystemExit as ex:return 1,str(ex)
  for path,fragment in ((mpath,'consumed frozen manifest bytes mismatch'),(epath,'consumed frozen expected membership bytes mismatch')):
   count=[0]
   def changed(p):
    if p.resolve()==path.resolve():
     count[0]+=1
     if count[0]>1:return read(p)+b' '
    return read(p)
   Path.read_bytes=changed;out=tmp/(path.name+'.out')
   try:code,error=invoke(out)
   finally:Path.read_bytes=read
   assert code!=0 and fragment in error and not out.exists() and count[0]==2
   faults.append({'name':'consumed-'+path.name,'reason':fragment,'passed':True})
  dep=ROOT/'factory/registry/registry.py';Path.read_bytes=lambda p:b'changed dependency' if p.resolve()==dep else read(p)
  out=tmp/'dependency.out'
  try:code,error=invoke(out)
  finally:Path.read_bytes=read
  assert code!=0 and 'pinned dependency mismatch' in error and not out.exists();faults.append({'name':'resolver-dependency-bytes','passed':True})
  code,error=invoke(V1/'final-candidate-resolution.json');assert code!=0 and 'output must not already exist' in error;faults.append({'name':'reserved-pending-output','passed':True})
  for status in ('INVALID_SCHEMA_STATUS',None):
   bad=json.loads(candidate.read_bytes());bad['symbols'][0]['status']=status;candidate.write_text(json.dumps(bad));out=tmp/(str(status)+'.out');code,error=invoke(out);assert code!=0 and 'candidate catalogue schema errors' in error and not out.exists();faults.append({'name':'invalid-selected-status-'+str(status),'passed':True})
  output=HERE/'independent-final-comparison.json';assert not output.exists()
  result=subprocess.run([sys.executable,str(G/'compare_final_candidate.py'),str(C),'--output',str(output)],cwd=ROOT,capture_output=True);assert result.returncode==0 and not result.stderr
  independent=json.loads(output.read_bytes());assert independent==json.loads(result.stdout)
  normalized=lambda x:{k:v for k,v in x.items() if k!='createdAt'}
  assert normalized(independent)==normalized(receipt)
 report={'status':'CLEAR','scope':'exact supplied F1 candidate schema & frozen v1 65 USR selectors across10 blocks','reviewer':pin(Path(__file__)),'guard':pin(G/'compare_final_candidate.py'),'candidate':pin(C),'candidateSymbols':111576,'originalV1EntriesVerified':16,'membershipRows':65,'blocks':10,'ownerFaultsVerified':len(owner_faults['controls']),'independentFaults':faults,'independentReplay':pin(output),'ownerComparison':pin(G/'final-candidate-comparison-fd453b63-v3.json'),'ownerProcess':pin(G/'final-process-v3.json'),'stagesVerified':stages,'historicalStageMismatches':historical_mismatches,'productionEdits':0}
 report_path=HERE/'final-guard-v3-review.json';report_path.write_text(json.dumps(report,indent=2)+'\n');print(pin(report_path))
if __name__=='__main__':main()
