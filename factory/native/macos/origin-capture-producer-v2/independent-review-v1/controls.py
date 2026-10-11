#!/usr/bin/env python3
"""Offline synthetic v2 closure checks; mocked processes never execute bytes."""
from pathlib import Path
from unittest.mock import patch
import copy,gzip,importlib.util,json,os,shutil,sys,tempfile,hashlib
ROOT=Path(__file__).resolve().parents[5];sys.path.insert(0,str(ROOT))
from factory.native.macos import capture as producer
from factory.gate.mac_origin_admission import mac_origin_admission_issues
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.native.macos.check_evidence import _verify_origin
spec=importlib.util.spec_from_file_location('v1_fixture',ROOT/'factory/native/macos/origin-capture-producer-v1/independent-review-v1/controls.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
Fixture=mod.Fixture

def sha(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def write(path,x):path.write_text(json.dumps(x,sort_keys=True)+'\n')
def fake_tools(f):
 repo=f.root/'fake-repo';tool=repo/'factory/oracle/mac/compiler-tool-archive-v1';tool.mkdir(parents=True)
 entries=[]
 for source,compressed in [(f.xcrun,False),(f.tool,True)]:
  raw=source.read_bytes();blob=gzip.compress(raw,mtime=0) if compressed else raw;relative=source.name+('.gz' if compressed else '')
  p=tool/relative;p.write_bytes(blob);p.chmod(0o644)
  entries.append({'sha256':sha(raw),'archivePath':relative,'compression':'gzip' if compressed else 'none','bytes':len(raw),'archiveBytes':len(blob),'archiveSha256':sha(blob)})
 write(tool/'archive-manifest.json',{'entries':entries});return repo

def remove_aux(f):
 f.capture['meta']['conditions']['macOrigin'].pop('auxiliaryAX');f.summary['freshAXClient']={'externalAX':'HELD'};write(f.summarypath,f.summary);f.capture['meta']['conditions']['macOrigin']['summary']=producer.file_ref(f.summarypath)

def real_archive(f):
 with patch.object(producer,'REPO',fake_tools(f)):
  return producer.archive_origin(f.ev,[f.capture],f.casepath,f.work,f.exe,{'externalAX':'HELD'})

def run():
 scratch=ROOT/'.factory-work';scratch.mkdir(exist_ok=True);out={}
 with tempfile.TemporaryDirectory(prefix='mac-origin-v2-review-',dir=scratch) as tmp:
  root=Path(tmp);f=Fixture(root/'main');remove_aux(f)
  f.summarypath=f.ev/'origin-summary.json';write(f.summarypath,f.summary);f.capture['meta']['conditions']['macOrigin']['summary']=producer.file_ref(f.summarypath)
  reader,manifest=real_archive(f);assert manifest['status']=='PASS'
  # Production archive method, not hand-created mappings; delete every original receipt input outside archives.
  config=json.loads((f.ev/'origin-reader-config.json').read_text());assert str(f.exe) in config['macPathMap'] and '/usr/bin/xcrun' in config['macPathMap']
  shutil.rmtree(f.work);f.casepath.unlink();f.summarypath.unlink();f.xcrun.unlink();f.tool.unlink()
  for p in list(f.ev.iterdir()):
   if p.is_file() and p.name not in ('origin-reader-config.json','origin-archive-manifest.json'):p.unlink()
  issues=mac_origin_admission_issues(f.capture,lambda ref:reader(capture=f.capture,reference=ref));assert not issues,issues
  _verify_origin(f.capture,f.summary,1,reader);out['production-main-archive-after-live-deletion']='PASS realarchive+reader+guard+checker fixtureonly'
  mapped=Path(config['macPathMap'][str(f.tool)]);assert mapped.read_bytes()==b'SYNTHETIC TOOL NEVER EXECUTED' and (mapped.stat().st_mode&0o777)==0o644
  out['production-gzip-tool-mapping']='PASS exact extracted0644rawbytes'
  # Full guard rejection on malformed receipt, with all hashes & embedded joins repaired in owned fixtures.
  receipt_target=Path(config['macPathMap'][str(f.receiptpath)]);summary_target=Path(config['macPathMap'][str(f.summarypath)])
  r=json.loads(receipt_target.read_text());r['compiler']['pid']=True;write(receipt_target,r);s=copy.deepcopy(f.summary);s['compilerReceipt']=r;write(summary_target,s)
  c=copy.deepcopy(f.capture);o=c['meta']['conditions']['macOrigin']
  for key,target in [('summary',summary_target),('compilerReceipt',receipt_target)]:o[key]['sha256']=sha(target.read_bytes());o[key]['bytes']=target.stat().st_size
  _verify_origin(c,s,1,reader)
  issues=mac_origin_admission_issues(c,lambda ref:reader(capture=c,reference=ref));assert any(x.startswith('mac-origin:process') for x in issues),issues
  out['fullguard-malformed-boolPID']='PASS realguard rejects; outer verify invokes guard at70'
  for name,mut,code in [
   ('ownerfalse',lambda r:r['compiler'].update(ownedProcessGroup=False),'mac-origin:process-owner'),
   ('cleanup-int0',lambda r:r['compiler']['cleanup'].update(killSent=0),'mac-origin:cleanup'),
   ('rawhash',lambda r:r['compiler'].update(stdoutHash=sha(b'wrong')),'mac-origin:read-failed'),
   ('reversedUTC',lambda r:r['compiler'].update(endedAtUtc='2000-01-01T00:00:00+00:00'),'mac-origin:process-time')]:
   r=copy.deepcopy(f.receipt);mut(r);write(receipt_target,r);s=copy.deepcopy(f.summary);s['compilerReceipt']=r;write(summary_target,s)
   c=copy.deepcopy(f.capture);o=c['meta']['conditions']['macOrigin']
   for key,target in [('summary',summary_target),('compilerReceipt',receipt_target)]:o[key]['sha256']=sha(target.read_bytes());o[key]['bytes']=target.stat().st_size
   issues=mac_origin_admission_issues(c,lambda ref:reader(capture=c,reference=ref));assert any(x.startswith(code) for x in issues),(name,issues);out[name]={'rejection':code,'issues':issues}

  g=Fixture(root/'nonexec',mode=0o644);assert g.receipt['status']=='OUTPUT_MODE' and g.result.returncode!=0;out['compiler-nonexec-output']='PASS OUTPUT_MODE &nonzero, no launch'
  # AVAILABLE paths reproduce real CLI wiring: preflight auxfiles at outputroot, per-case evidence lacks them.
  a=Fixture(root/'aux');auxwork=a.work.parent/'external-ax-client';auxwork.mkdir()
  for name in ('AXClient.swift','f5-ax-client'):shutil.copy2(a.work/name,auxwork/name)
  parent=a.ev.parent
  for p in list(a.ev.glob('ax-*')):shutil.move(str(p),str(parent/p.name))
  client={'externalAX':'AVAILABLE','compilerReceiptPath':str(parent/'ax-compiler-receipt.json')}
  with patch.object(producer,'REPO',fake_tools(a)):
   try:producer.archive_origin(a.ev,[a.capture],a.casepath,a.work,a.exe,client)
   except producer.CaptureError as error:
    assert str(a.ev/'ax-compiler-receipt.json') in str(error),str(error);out['actualCLI-AVAILABLE-parent-aux-receipt']={'result':'BLOCKER reproduced','error':str(error)}
   else:raise AssertionError('expected missing percase aux receipt rejection')
  # Frozensource no prompt/new permission request API.
  swift='\n'.join((ROOT/'factory/native/macos'/n).read_text() for n in ('CaptureHost.swift','AXClient.swift'))
  for forbidden in ('CGRequestScreenCaptureAccess','AXIsProcessTrustedWithOptions','NSWorkspace.shared.open'):assert forbidden not in swift,forbidden
  assert 'CGPreflightScreenCaptureAccess()' in swift and 'AXIsProcessTrusted()' in swift
  out['TCC-source-controls']='PASS preflightonly/no permission request APIs'
 return {'scope':'offline synthetic mocked resolver/compiler; no native/compiler/remote execution','controls':out}
if __name__=='__main__':print(json.dumps(run(),indent=2,sort_keys=True))
