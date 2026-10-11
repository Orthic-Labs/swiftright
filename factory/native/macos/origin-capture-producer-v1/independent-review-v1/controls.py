#!/usr/bin/env python3
"""Offline synthetic controls. Popen is mocked; fixture bytes never execute."""
from pathlib import Path
from unittest.mock import patch
import copy, gzip, hashlib, json, os, shutil, subprocess, sys, tempfile
ROOT=Path(__file__).resolve().parents[5]
sys.path.insert(0,str(ROOT))
from factory.native.macos import capture as producer
from factory.native.macos.check_evidence import _verify_origin
from factory.gate.mac_origin_admission import mac_origin_admission_issues
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.core.artifacts import canonical_hash

def sha(b): return 'sha256:'+hashlib.sha256(b).hexdigest()
def write(p,obj): p.write_text(json.dumps(obj,sort_keys=True)+'\n')
class Fixture:
 def __init__(self,root,mode=0o755,fault=None):
  self.root=root;root.mkdir();self.work=root/'work';self.work.mkdir();self.ev=root/'evidence';self.ev.mkdir();self.calls=[]
  self.tool=root/'tool-swiftc';self.tool.write_bytes(b'SYNTHETIC TOOL NEVER EXECUTED');self.xcrun=root/'tool-xcrun';self.xcrun.write_bytes(b'SYNTHETIC XCRUN NEVER EXECUTED')
  for name in ('Witness.swift','CaptureHost.swift','AXClient.swift'): (self.work/name).write_bytes(('SYNTHETIC '+name).encode())
  self.exe=self.work/'capture-host';self.axexe=self.work/'f5-ax-client';self.real_digest=producer.digest
  def digest(p): return self.real_digest(self.xcrun if str(p)=='/usr/bin/xcrun' else p)
  fixture=self
  class Process:
   def __init__(self,argv,**kw):
    fixture.calls.append({'argv':argv,'kwargs':kw});self.pid=31000+len(fixture.calls);self.returncode=0;self.argv=argv;self.isresolver=argv==['/usr/bin/xcrun','--find','swiftc']
    assert kw['start_new_session'] is True and kw['stdout']==subprocess.PIPE and kw['stderr']==subprocess.PIPE and kw['text'] is False
    if not self.isresolver:
     output=Path(argv[argv.index('-o')+1]);output.write_bytes(b'SYNTHETIC BINARY NEVER EXECUTED '+output.name.encode());output.chmod(mode)
     if fault=='source-drift':(fixture.work/'Witness.swift').write_bytes(b'changed')
   def communicate(self,timeout):
    if fault=='timeout' and not self.isresolver:self.returncode=None;raise subprocess.TimeoutExpired(self.argv,timeout)
    if fault=='resolver-failure' and self.isresolver:self.returncode=1;return b'',b'resolve failure'
    return (str(fixture.tool).encode()+b'\n',b'') if self.isresolver else (b'build output',b'')
  self.kills=[]
  with patch.object(producer.subprocess,'Popen',Process),patch.object(producer,'digest',digest),patch.object(producer.os,'killpg',lambda pid,sig:self.kills.append((pid,sig))):
   self.result,self.receipt=producer.compiler_build(self.work,self.ev,self.exe)
   if fault is None:self.axresult,self.axreceipt=producer.auxiliary_compiler_build(self.work/'AXClient.swift',self.ev,self.axexe)
  if fault is not None:return
  self.case={'id':'fixture.case','kind':'case','version':'0.1'};self.casepath=root/'case.json';write(self.casepath,self.case)
  self.summarypath=root/'summary.json';self.receiptpath=self.ev/'compiler-receipt.json';self.axreceiptpath=self.ev/'ax-compiler-receipt.json'
  self.summary={'case':{'id':self.case['id'],'hash':canonical_hash(self.case)},'candidateOnly':True,'acceptance':'not-promoted','sourceHash':producer.digest(self.work/'Witness.swift'),'compiledAdapterHash':producer.digest(self.work/'CaptureHost.swift'),'binaryHash':producer.digest(self.exe),'compilerReceipt':self.receipt,'freshAXClient':{'externalAX':'AVAILABLE','sourceHash':producer.digest(self.work/'AXClient.swift'),'binaryHash':producer.digest(self.axexe),'compilerReceiptHash':producer.digest(self.axreceiptpath),'compilerStatus':'SUCCESS','compilerExitCode':0}}
  write(self.summarypath,self.summary)
  self.capture={'id':'fixture.case.macos.run-001','platform':'macos','case':self.summary['case'],'meta':{'conditions':{'macOrigin':{'version':'1','captureId':'fixture.case.macos.run-001',**{k:producer.file_ref(p) for k,p in [('summary',self.summarypath),('case',self.casepath),('source',self.work/'Witness.swift'),('adapter',self.work/'CaptureHost.swift'),('binary',self.exe),('compilerReceipt',self.receiptpath)]},'auxiliaryAX':{k:producer.file_ref(p) for k,p in [('receipt',self.axreceiptpath),('source',self.work/'AXClient.swift'),('binary',self.axexe)]}}}}}
  self.archive=root/'archive';self.archive.mkdir();self.mapping={}
  for i,p in enumerate([x for x in root.rglob('*') if x.is_file()]):
   dest=self.archive/f'{i:02d}.bin';shutil.copyfile(p,dest);self.mapping[str(p)]=dest
  self.mapping['/usr/bin/xcrun']=self.mapping[str(self.xcrun)]
  self.reader=ArchiveByteReader(mac_roots=[self.archive],mac_path_map=self.mapping)
 def issues(self,cap=None):
  cap=cap or self.capture
  return mac_origin_admission_issues(cap,lambda ref:self.reader(capture=cap,reference=ref))
 def change_receipt(self,mutate):
  r=copy.deepcopy(self.receipt);mutate(r);write(self.mapping[str(self.receiptpath)],r)
  s=copy.deepcopy(self.summary);s['compilerReceipt']=r;write(self.mapping[str(self.summarypath)],s)
  c=copy.deepcopy(self.capture);o=c['meta']['conditions']['macOrigin']
  for key,path in [('compilerReceipt',self.receiptpath),('summary',self.summarypath)]:
   raw=self.mapping[str(path)].read_bytes();o[key]['sha256']=sha(raw);o[key]['bytes']=len(raw)
  return c,s

def run():
 scratch=ROOT/'.factory-work';scratch.mkdir(exist_ok=True);results={}
 with tempfile.TemporaryDirectory(prefix='mac-origin-independent-',dir=scratch) as tmp:
  base=Path(tmp);f=Fixture(base/'baseline');assert f.result.returncode==0 and f.axresult.returncode==0
  assert f.issues()==[],f.issues();results['actual-mocked-producer-main-and-AX-to-real-guard']='PASS fixture only'
  assert len(f.calls)==4;results['resolver/compiler-argv-pipes-owned-session']='PASS exact producer calls'
  # Live originals disappear; explicit archived aliases alone remain sufficient.
  shutil.rmtree(f.work);f.tool.unlink();f.xcrun.unlink();assert f.issues()==[]
  results['archived-aliases-after-live-source/tool/binary-removal']='PASS no live/compiler execution'
  zipped=base/'compiler.gz';zipped.write_bytes(gzip.compress(f.mapping[str(f.tool)].read_bytes(),mtime=0));decoded=gzip.decompress(zipped.read_bytes());assert sha(decoded)==f.receipt['compiler']['realToolBefore']['sha256']
  results['gzip-control']='PASS extracted raw hash matches; gzip bytes themselves are not reader-compatible'
  for name,mut,code in [
   ('bool-pid',lambda r:r['compiler'].update(pid=True),'mac-origin:process'),
   ('owner-false',lambda r:r['compiler'].update(ownedProcessGroup=False),'mac-origin:process-owner'),
   ('cleanup-int0',lambda r:r['compiler']['cleanup'].update(timedOut=0),'mac-origin:cleanup'),
   ('raw-hash',lambda r:r['compiler'].update(stdoutHash=sha(b'wrong')),'mac-origin:read-failed'),
   ('compiler-before-resolver',lambda r:r['compiler'].update(startedAtUtc='2001-01-01T00:00:00+00:00'),'mac-origin:process-time'),
   ('naive-clock',lambda r:r['compiler'].update(endedAtUtc='2026-01-01T00:00:00'),'mac-origin:bad-timezone'),
   ('output-hash',lambda r:r['compiler']['outputBinary'].update(sha256=sha(b'wrong')),'mac-origin:binary-join'),
   ('argv-extra',lambda r:r['compiler']['argv'].append('-DFAKE'),'mac-origin:compiler-argv'),
   ('tool-alias-drift',lambda r:r['compiler']['realToolAfter'].update(bytes=1),'mac-origin:tool-drift')]:
   c,s=f.change_receipt(mut);issues=f.issues(c);assert any(x.startswith(code) for x in issues),(name,issues);results[name]={'rejection':code,'issues':issues}
  f.capture,_=f.change_receipt(lambda r:None)
  c=copy.deepcopy(f.capture);c['meta']['conditions']['macOrigin'].pop('adapter');assert any(x.startswith('mac-origin:missing-ref') for x in f.issues(c));results['missing-descriptor-ref']='mac-origin:missing-ref'
  c=copy.deepcopy(f.capture);c['meta']['conditions']['macOrigin']['case']['sha256']=sha(b'wrong');assert any(x.startswith('mac-origin:read-failed') for x in f.issues(c));results['wrong-case-ref']='mac-origin:read-failed'
  c=copy.deepcopy(f.capture);c['meta']['conditions']['macOrigin'].pop('auxiliaryAX');assert any(x.startswith('mac-origin:ax-join') for x in f.issues(c));results['AVAILABLE-without-auxiliary']='mac-origin:ax-join'
  # Separate fresh fixture for shallow checker; mutation does not touch frozen evidence.
  shallow=Fixture(base/'shallow');r=copy.deepcopy(shallow.receipt);r['compiler']['pid']=True;write(shallow.receiptpath,r);shallow.summary['compilerReceipt']=r;write(shallow.summarypath,shallow.summary)
  o=shallow.capture['meta']['conditions']['macOrigin'];o['summary']=producer.file_ref(shallow.summarypath);o['compilerReceipt']=producer.file_ref(shallow.receiptpath)
  _verify_origin(shallow.capture,shallow.summary,1)
  for source in (shallow.receiptpath,shallow.summarypath):shutil.copyfile(source,shallow.mapping[str(source)])
  assert any(x.startswith('mac-origin:process') for x in shallow.issues()),shallow.issues()
  results['shallow-checker-invalid-bool-pid']='ACCEPTED defect; real guard rejects same receipt'
  nonexec=Fixture(base/'nonexec',mode=0o644);assert nonexec.result.returncode==0 and nonexec.receipt['status']=='SUCCESS' and not os.access(nonexec.exe,os.X_OK) and nonexec.issues()==[]
  results['nonexecutable-output']='ACCEPTED producer+byte guard; launch not executed; must validate executable output before statusSUCCESS'
  for fault,status in [('resolver-failure','RESOLVE_FAILED'),('source-drift','SOURCE_DRIFT'),('timeout','TIMEOUT')]:
   g=Fixture(base/fault,fault=fault);assert g.receipt['status']==status and g.result.returncode!=0,(fault,g.receipt);results[fault]={'status':status,'returncode':g.result.returncode,'ownedSignals':g.kills}
 return {'scope':'offline synthetic mocked producer; no compiler/resolver/native/remote execution','controls':results}
if __name__=='__main__':print(json.dumps(run(),indent=2,sort_keys=True))
