"""Synthetic mutations of archived receipt; reads bytes, never runs binaries."""
import copy,json,tempfile
from pathlib import Path
from review import review,load
ACTUAL=Path(__file__).resolve().parent.parent/'root-build-r1/actual'
def main():
 original=load((ACTUAL/'observation.json').read_bytes());rows=[]
 faults=[('bool-exit',lambda x:x.update(exitCode=False)),('unsignaled-kernel',lambda x:x.update(kernelWait=258)),('wrong-argv',lambda x:x.update(argv=x['argv'].replace('-c release','-c debug'))),('empty-streams',lambda x:x.update(rawStreams=[])),('unclosed-stream',lambda x:x['rawStreams'][0].update(destinationClosed=False)),('wrong-module-hash',lambda x:x['runtimeModules'][0].update(sha256='0'*64)),('wrong-exe',lambda x:x.update(exeSha256='0'*64)),('wrong-runtime',lambda x:x.update(runtimeSourceCommit='0'*40)),('bad-time',lambda x:x.update(processStartedAt='2999-01-01T00:00:00Z')),('malformed-stream',lambda x:x.update(rawStreams=[None,None]))]
 with tempfile.TemporaryDirectory(prefix='padding-receipt-controls-') as folder:
  scratch=Path(folder)
  for path in ACTUAL.rglob('*'):
   if path.is_file() and path.name!='observation.json':
    target=scratch/path.relative_to(ACTUAL);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(path.read_bytes())
  for name,mutate in faults:
   data=copy.deepcopy(original);mutate(data);(scratch/'observation.json').write_text(json.dumps(data))
   result=review(scratch);rows.append({'name':name,'synthetic':True,'rejected':not result['acceptedObservationalCompile'],'issues':result['issues']})
 print(json.dumps({'kind':'synthetic-readonly-review-controls','synthetic':True,'nativeActions':0,'passed':all(x['rejected'] for x in rows),'controls':rows},indent=2))
if __name__=='__main__':main()
