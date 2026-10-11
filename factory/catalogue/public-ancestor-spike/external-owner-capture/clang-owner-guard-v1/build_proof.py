"""Replay captured compiler bytes only; no subprocess or live SDK/tool reads."""
import importlib.util,json,sys
from pathlib import Path
from unittest.mock import patch
from exact_clang import *

def load(name,path):
 s=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(s);s.loader.exec_module(module);return module

def build():
 resolver_path=ROOT/'factory/catalogue/public-ancestor-spike/archive-resolver-v1/archive_resolver.py'
 resolver=load('bounded_clang_archive',resolver_path)
 first=resolver.ArchiveResolver();second=resolver.ArchiveResolver(manifest_path=resolver.V2_MANIFEST_PATH,expected_manifest_sha256=resolver.V2_MANIFEST_SHA256)
 original_read=Path.read_bytes;reads=[];cache={}
 def blocked(path):
  need(str(path).startswith(str(ROOT)+'/'),'live external source/tool/cache read blocked '+str(path))
  return original_read(path)
 def read(path,force_archive=False):
  need(force_archive is True,'forced archive required');reads.append(path)
  if path in cache:return cache[path]
  if str(path).startswith(str(ROOT)+'/'):raw=original_read(Path(path))
  else:
   selected=first if path in first._records else second
   raw=selected.read_bytes(path,force_archive=True)
  cache[path]=raw;return raw
 with patch.object(Path,'read_bytes',blocked):
  g=ExactClangOwners(read_bytes=read,force_archive=True);rows=g.validate();need(len(rows)==12 and len(g.supportRows)==1,'archive full owner baseline')
  # New malformed receipt exception normalization is exercised on actual raw data.
  altered=dict(g.inputs);p=strict_json(altered['processes']);del p['runs'][0]['argv'];altered['processes']=json.dumps(p).encode()
  try:g.validate(altered)
  except ValueError as error:need('malformed actual compiler input' in str(error),'malformed semantic rejection');malformed=str(error)
  else:raise AssertionError('malformed raw receipt accepted')
  sys.path.insert(0,str(HERE.parent/'swift-stdlib-process-v2'))
  from archived_swift16 import ArchivedExactSwift16
  swift=ArchivedExactSwift16(read_bytes=read,force_archive=True);swiftrows=swift.validate();need(len(swiftrows)==16,'archive Swift16 baseline')
  again=g.validate();need(again==rows,'identical complete owner replay')
 controls=strict_json((HERE/'controls.json').read_bytes());need(controls['eligibleRequestedOwners']==12 and len(controls['rawControls'])==212,'full semantic control artifact')
 sources=['exact_clang.py','ast_reader.py','nominal_bridge.py','raw_faults.py','test_exact_clang.py','build_inputs.py','build_proof.py','capture-inputs.json','controls.json','README.md']
 return {'schema':'strict-clang-owner-proof-v1','status':'exact-bounded-compiled-owner-correspondences','requestedOwners':rows,'supportRows':g.supportRows,'actualInputs':g.manifest,'sourcePins':{name:digest((HERE/name).read_bytes()) for name in sources},'rawControls':controls,'archiveReplay':{'requestedOwners':12,'supportOwners':1,'swift16Owners':16,'actualReadCount':len(reads),'uniqueOriginalPaths':len(set(reads)),'liveExternalReads':0,'deterministicOwnerReplay':True,'malformedReceiptRejection':malformed,'resolver':{'path':str(resolver_path.relative_to(ROOT)),'sha256':digest(resolver_path.read_bytes())},'manifests':[{'path':str(r.manifest_path.relative_to(ROOT)),'sha256':digest(r.manifest_path.read_bytes())} for r in [first,second]]},'scope':'Exact captured source/header/export/import/nominal identities only; denominator & effective ancestor proof belongs to separate production guard.'}
if __name__=='__main__':
 output=json.dumps(build(),indent=2,sort_keys=True)+'\n';path=HERE/'strict-clang-owner-proof.json'
 if '--check' in sys.argv:need(path.read_text()==output,'whole proof byte equality')
 else:path.write_text(output)
 print('archive replay: 12 requested + 1 support; Swift16 16; controls 212; zero live external reads')
