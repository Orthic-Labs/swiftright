"""Read-only narrow v4 delta replay against frozen reviewed v3."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[5];A=R/'factory/native/windows/round1-native-v3';B=A.with_name('round1-native-v4')
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check():
 m=json.loads((B/'root-stage-manifest.json').read_text())
 for x in m['files']:
  f=R/x['path'];assert f.stat().st_size==x['bytes'] and h(f)==x['sha256'],x['path']
 for n in ['cleanup.ps1','namespace.ps1','test-cleanup.ps1','test-namespace.ps1','stream-seal.ps1','test-stream-seal.ps1','repeat-task.ps1','parse-controls.ps1']:assert (A/n).read_bytes()==(B/n).read_bytes(),n
 oldc=json.loads((A/'contract.json').read_text());newc=json.loads((B/'contract.json').read_text())
 normalized=json.loads((A/'contract.json').read_text().replace('round1-native-v3','round1-native-v4'))
 normalized['kind']=newc['kind']
 for old,new in zip(normalized['hosts'],newc['hosts']):
  if old['label']=='scroll-view':old['receiptRelative']='build-v3-r1\\observation.json'
  for x,y in zip(old['bindings'],new['bindings']):
   if x['path'].endswith('capture-repeat.ps1') or x['path'].endswith('run-repeat.ps1'):x['sha256']=y['sha256']
   relative=y['path'].split('\\swiftright\\',1)[1].replace('\\','/');assert h(R/relative)==y['sha256']
 assert normalized==newc
 old=(A/'capture-repeat.ps1').read_text().replace('round1-native-v3','round1-native-v4')
 lines=old.splitlines();scroll=[i for i,x in enumerate(lines) if 'round1-scroll-host-v1\\package' in x];assert len(scroll)==1
 lines[scroll[0]]=lines[scroll[0]].replace('build-v2-r1','build-v3-r1');assert '\n'.join(lines)+'\n'==(B/'capture-repeat.ps1').read_text()
 assert (A/'run-repeat.ps1').read_text().replace('round1-native-v3','round1-native-v4')==(B/'run-repeat.ps1').read_text()
 assert (A/'run-batch.ps1').read_text().replace('round1-native-v3','round1-native-v4').replace(h(A/'contract.json'),h(B/'contract.json'))==(B/'run-batch.ps1').read_text()
 reserved=[]
 for x in m['files']:
  f=R/x['path']
  if f.suffix!='.ps1' or '/preimages/' in str(f) or '/lineage-' in str(f):continue
  for n,line in enumerate(f.read_text().splitlines(),1):
   if re.search(r'\$(host|pid|input)\s*(?:[+*/-]?=|\+\+|--)|foreach\s*\(\s*\$(host|pid|input)\s+in',line,re.I):reserved.append([x['path'],n,line])
 assert not reserved
 return {'status':'v4-narrow-source-clear','stage':h(B/'root-stage-manifest.json'),'verifiedPins':len(m['files']),'delta':'Fresh v4 namespace/current source pins; scroll-only build-v3-r1 receipt route; four other routes unchanged; no broad fallback','helpers':'Exact byte-equal actual-passed v3 cleanup/namespace/stream/helper controls','reservedWrites':reserved,'nativeRuns':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
