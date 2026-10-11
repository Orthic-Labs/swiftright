from pathlib import Path
from unittest.mock import patch
import importlib.util,sys,json,copy
HERE=Path(__file__).resolve().parent;BASE=HERE.parent/'destructor-api-eligibility-proof/archive-wrapper-v2'
s=importlib.util.spec_from_file_location('wrapper_fault_v2',BASE/'archive_wrapper.py');w=importlib.util.module_from_spec(s);sys.modules[s.name]=w;s.loader.exec_module(w)
faults=[];old=Path.read_bytes
for member in ('SwiftUI.swiftinterface','SwiftUICore.swiftinterface','independent-access-review.json'):
 target=BASE.parent/'raw-arm64-v2'/member
 def changed(path,*a,**kw):
  raw=old(path,*a,**kw);return bytes([raw[0]^1])+raw[1:] if path==target else raw
 with patch.object(Path,'read_bytes',changed):
  try:w.Replay(force_archive=True)
  except ValueError as e:faults.append({'fault':'unused-member-corruption:'+member,'reason':str(e)})
  else:raise AssertionError(member)
r=w.Replay(force_archive=True);r.verify_all();receipt=json.loads(r.read(r.original.RAW/'SwiftUI-arm64.receipt.json'))
for label,mutate in [('timed_out',lambda x:x.update(timedOut=True)),('argv_compiler',lambda x:x['argv'].__setitem__(0,'/tmp/other-tool')),('stderr_hash',lambda x:x['stderr'].update(sha256='sha256:'+'0'*64))]:
 bad=copy.deepcopy(receipt);mutate(bad)
 try:r.verify_receipt('SwiftUI',bad)
 except ValueError as e:faults.append({'fault':label,'reason':str(e)})
 else:raise AssertionError(label)
seed=json.loads(r.read(r.original.SEED,r.original.SEED_HASH));f=copy.deepcopy(seed['rows'][0]['cursor']['fields']);src=r.source(f['modulename'])
for label,change in [('wrong_cursor_usr',lambda x:x.update(usr=x['usr']+'x')),('unknown_cursor_path_alias',lambda x:x.update(filepath=x['filepath'].replace('/MacOSX.sdk/','/MacOSX27.0.sdk/')))]:
 bad=copy.deepcopy(f);change(bad);assert not r.cursor_source_identity(bad,src);faults.append({'fault':label,'reason':'exact pinned source pair rejected'})
(HERE/'extra-faults-v2-result.json').write_text(json.dumps({'count':len(faults),'faults':faults},indent=2)+'\n');print(len(faults))
