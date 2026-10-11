"""Verify production proof replay without original SDK/tool/cache or execution."""
import sys,json,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import exact_public_ancestor as g
side=json.loads((g.HERE/'public-ancestor-artifact-v2.json').read_text())
blocked=[];exec_calls=[]
original={name:getattr(Path,name) for name in ('open','stat','resolve','read_bytes')}
def wrap(name):
 def guarded(self,*args,**kwargs):
  if str(self).startswith(('/Applications/Xcode-27-RC.app/','/Users/adrdsouza/Library/Caches/SwiftRightFactory/','/usr/bin/xcrun')):
   blocked.append([name,str(self)]);raise AssertionError('original input consulted')
  return original[name](self,*args,**kwargs)
 return guarded
old_process={name:getattr(subprocess,name) for name in ('run','Popen','call','check_output')}
def no_exec(*args,**kwargs):
 exec_calls.append(str(args));raise AssertionError('execution during proof replay')
for name in original:setattr(Path,name,wrap(name))
for name in old_process:setattr(subprocess,name,no_exec)
try:
 v,e=g.load_artifact(g.ROOT/side['path'],side['sha256'],prefer_archive=True,expected_raw_sha256=side['rawJsonSha256'],expected_raw_bytes=side['rawJsonBytes'])
finally:
 for name,fn in original.items():setattr(Path,name,fn)
 for name,fn in old_process.items():setattr(subprocess,name,fn)
receipt={'kind':'public-ancestor-forced-archive-replay','artifact':side,'wholeArtifactEqual':True,'originalInputCalls':blocked,'subprocessCalls':exec_calls,'resolutionStatus':e['resolution']['status'],'sourceStarts':len(e['resolution']['rows']),'rawRecords':len(e['resolution']['compilerInventory'])}
(g.HERE/'public-ancestor-archive-replay-v2.json').write_text(json.dumps(receipt,sort_keys=True,separators=(',',':'))+'\n')
print(json.dumps(receipt))
