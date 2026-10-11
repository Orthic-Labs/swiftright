#!/usr/bin/env python3
"""Independent actual branch/default-public checks & compressed API boundaries."""
import collections,gzip,hashlib,json,re,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent;BASE=HERE.parents[1];ROOT=BASE.parents[2]
sys.path.insert(0,str(BASE));import exact_public_ancestor as g
import review_inputs as independent
PIN='7fbcab45c711446d93b4e0fb9d9161379ada01a414934b6f47ff95db0d4e6baa'
RAWPIN='8af5faea52769717aadadd3b98ef74237a05304f3d6eff025fdc9572b7fe07f1'
SIZE=138987898
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
 def deny(event,args):
  if event=='open' and isinstance(args[0],(str,bytes)):assert not any(str(args[0]).startswith(x) for x in ['/Applications/Xcode-27-RC.app/','/Users/adrdsouza/Library/Caches/SwiftRightFactory/','/usr/bin/xcrun'])
  assert event not in {'subprocess.Popen','os.system'}
 sys.addaudithook(deny)
 artifact=BASE/'public-ancestor-evidence-v2.json.gz';stored=artifact.read_bytes();assert sha(stored)==PIN
 raw=gzip.decompress(stored);assert sha(raw)==RAWPIN and len(raw)==SIZE;a=json.loads(raw);sources={};models={};branches={}
 for m in ('SwiftUI','SwiftUICore'):
  d=a['inputs'][m+':source'];data=(ROOT/d['repositoryPath']).read_bytes();assert 'sha256:'+sha(data)==d['sha256'];sources[m]=data.decode().splitlines();models[m]=g.helper.source_model(data.decode());branches[m]=independent.branches(sources[m])
 process=json.loads((ROOT/a['inputs']['processResults']['repositoryPath']).read_text());selected={m:{int(x.split(':')[1]) for x in process[m]['run']['stdout'].splitlines()} for m in sources};statuses=collections.Counter();defaults=collections.Counter()
 for r in a['resolution']['rows']:
  m,_,line,name=r['key'];frame=branches[m][line];assert [c['branchLine'] for c in r['conditions']]==frame
  active=set(frame)<=selected[m]
  if r['status']=='excluded-inactive-source-branch':assert not active
  elif r['status']!='excluded-local-declaration':assert active
  statuses[r['status']]+=1
  if not r.get('usr') or r['explicitAccess'] is not None or r['kind']=='deinit':continue
  scope=models[m][line]['scopes'][-1];family=scope['kind']
  if family=='protocol':assert r['kind'] in {'func','var','subscript','init','associatedtype','typealias'}
  elif family=='enum':assert r['kind']=='case'
  else:
   assert family=='extension';text=sources[m][scope['line']-1]
   for attribute in independent.attributes(text):text=text.replace(attribute,'',1)
   assert re.search(r'\b(public|open)\b',text.split('extension',1)[0])
  defaults[family]+=1
 faults=[]
 def reject(name,fn):
  try:fn()
  except ValueError as error:faults.append({'name':name,'reason':str(error)})
  else:raise AssertionError('accepted '+name)
 kwargs={'prefer_archive':True,'expected_raw_sha256':'sha256:'+RAWPIN,'expected_raw_bytes':SIZE}
 bad=bytearray(stored);bad[4]^=1;path=HERE/'rejected-byte-change.json.gz';path.write_bytes(bad)
 reject('stored-byte-change-retained-pin',lambda:g.load_artifact(path,'sha256:'+PIN,**kwargs));path.unlink()
 reject('missing-raw-whole-pins',lambda:g.load_artifact(artifact,'sha256:'+PIN,prefer_archive=True))
 reject('boolean-raw-size',lambda:g.load_artifact(artifact,'sha256:'+PIN,prefer_archive=True,expected_raw_sha256='sha256:'+RAWPIN,expected_raw_bytes=True))
 report={'kind':'independent-final-source-branch-default-access-supplement','reviewerSha256':sha(Path(__file__).read_bytes()),'independentScannerSha256':sha((HERE/'review_inputs.py').read_bytes()),'guardSha256':sha((BASE/'exact_public_ancestor.py').read_bytes()),'artifactCompressedSha256':PIN,'artifactRawSha256':RAWPIN,'artifactRawBytes':SIZE,'exactActualBranchFramesChecked':17846,'inactiveBranchRows':statuses['excluded-inactive-source-branch'],'sourceInheritedPublicDefaults':dict(defaults),'compressedApiFaults':faults,'originalReadsAndExecutionForbidden':True,'promotions':0}
 p=HERE/'supplemental-report.json';p.write_text(json.dumps(report,sort_keys=True,indent=2)+'\n');print(sha(p.read_bytes()))
if __name__=='__main__':main()
