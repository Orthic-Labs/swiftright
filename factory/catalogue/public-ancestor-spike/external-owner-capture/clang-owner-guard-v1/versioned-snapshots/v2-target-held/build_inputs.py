"""Archive actual existing producer inputs only; never execute compiler tools."""
import hashlib,json,pathlib,shutil
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[4]
PRODUCER=HERE.parent/'clang-external-process-v2'
def sha(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
def build():
 evidence=json.loads((PRODUCER/'raw/clang-external-process-v2.json').read_bytes())
 paths={'processes':PRODUCER/'raw/process-runs.json','probe':PRODUCER/'probes/owners.swift','request':PRODUCER/'requests/owners.yaml','index':PRODUCER/'raw/owners.index.txt'}
 for r in evidence['processRuns']:
  paths['stdout:'+r['name']]=ROOT/r['stdout'];paths['stderr:'+r['name']]=ROOT/r['stderr']
  paths['tool:'+r['name']]=pathlib.Path(r['toolIdentityPath'])
  if r['name'].startswith('clang-'):paths['probe:'+r['name']]=pathlib.Path(r['argv'][-1])
 for t in evidence['targets']:paths['source:'+t['target']]=pathlib.Path(t['source']['path'])
 for m in evidence['moduleMaps']:
  p=pathlib.Path(m['path']);paths['map:'+m['module']]=p
  umbrella={'AppKit':'AppKit.h','Foundation':'Foundation.h','CoreFoundation':'CoreFoundation.h','Spatial':'Spatial.h'}[m['module']]
  hdr=p.parent.parent/'Headers'/umbrella if m['module']!='Spatial' else p.parent/umbrella
  paths['umbrella:'+m['module']]=hdr
 paths['source:Spatial.Base']=pathlib.Path(evidence['sdk']['path'])/'usr/include/Spatial/Base.h'
 paths['tool:xcrun']=pathlib.Path('/usr/bin/xcrun')
 paths['tool:sourcekitd']=pathlib.Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd')
 result={}
 for key,p in paths.items():
  b=p.read_bytes();result[key]={'path':str(p),'sha256':sha(b),'bytes':len(b)}
 (HERE/'capture-inputs.json').write_text(json.dumps(result,indent=2)+'\n')
 pre=HERE/'producer-preimage-v2';pre.mkdir(exist_ok=True)
 for p in [PRODUCER/'raw/process-runs.json',PRODUCER/'raw/clang-external-process-v2.json',PRODUCER/'run_capture.py',PRODUCER/'build_evidence.py']:
  q=pre/p.name
  if q.exists() and q.read_bytes()!=p.read_bytes():raise ValueError('preimage already frozen')
  if not q.exists():shutil.copyfile(p,q)
 print(sha((HERE/'capture-inputs.json').read_bytes()),len(paths))
if __name__=='__main__':build()
