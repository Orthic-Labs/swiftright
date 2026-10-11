#!/usr/bin/env python3
"""Incremental v3 offline controls: mocked producer, real normalize/archive/checker."""
from pathlib import Path
from unittest.mock import patch
import copy,importlib.util,json,shutil,sys,tempfile,hashlib
ROOT=Path(__file__).resolve().parents[5];sys.path.insert(0,str(ROOT))
from factory.native.macos import capture as producer
from factory.native.macos.normalize import normalize_run
from factory.native.macos.check_evidence import verify
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.gate.mac_origin_admission import mac_origin_admission_issues
from factory.core.artifacts import canonical_hash
spec=importlib.util.spec_from_file_location('v2_fixture',ROOT/'factory/native/macos/origin-capture-producer-v2/independent-review-v1/controls.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
Fixture=mod.Fixture;write=mod.write

def prepare(root,conflict=False):
 f=Fixture(root);aux=f.root/'external-ax-client';aux.mkdir()
 for name in ('AXClient.swift','f5-ax-client'):shutil.copy2(f.work/name,aux/name)
 auxreceipt=f.root/'ax-compiler-receipt.json';r=copy.deepcopy(f.axreceipt);comp=r['compiler']
 tool=f.root/'aux-distinct-compiler';tool.write_bytes(b'AUX DISTINCT COMPILER NEVER EXECUTED')
 logical=str(f.tool if conflict else tool)
 real={'logicalPath':logical,'realPath':str(tool),'sha256':producer.digest(tool),'bytes':tool.stat().st_size}
 comp.update(logicalCompilerPath=logical,realPathBefore=str(tool),realHashBefore=real['sha256'],realToolBefore=real,realToolAfter=copy.deepcopy(real),cwd=str(aux))
 ref=producer.file_ref(aux/'AXClient.swift');comp['sourceBefore']={'AXClient.swift':ref};comp['sourceAfter']=copy.deepcopy(comp['sourceBefore']);r['sourceBefore']=copy.deepcopy(comp['sourceBefore']);r['sourceAfter']=copy.deepcopy(comp['sourceAfter'])
 comp['outputBinary']=producer.file_ref(aux/'f5-ax-client');comp['argv']=['/usr/bin/xcrun','swiftc','-O','-o',str(aux/'f5-ax-client'),str(aux/'AXClient.swift')]
 for proc in (r['resolver'],comp):
  for label in ('stdout','stderr'):
   old=Path(proc[label+'Path']);new=f.root/old.name;shutil.copyfile(old,new);proc[label+'Path']=str(new)
   if proc is r['resolver'] and label=='stdout':new.write_text(logical+'\n')
   proc[label+'Hash']=producer.digest(new)
 write(auxreceipt,r)
 client={'externalAX':'AVAILABLE','sourcePath':str(aux/'AXClient.swift'),'executable':str(aux/'f5-ax-client'),'compilerReceiptPath':str(auxreceipt),'compilerReceiptHash':producer.digest(auxreceipt),'sourceHash':producer.digest(aux/'AXClient.swift'),'binaryHash':producer.digest(aux/'f5-ax-client'),'compilerStatus':'SUCCESS','compilerExitCode':0,'permissionRequests':False}
 case=next(x for x in json.loads((ROOT/'factory/pipeline/gate-pilot/seed-cases.json').read_text()) if x['block']=='swiftui.padding-frame');write(f.casepath,case)
 f.summary['case']={'id':case['id'],'hash':canonical_hash(case)};f.summary['freshAXClient']=client;f.summary['channels']={};f.summarypath=f.ev/'origin-summary.json';write(f.summarypath,f.summary)
 origin={'version':'1','captureId':case['id']+'.macos.run-001',**{k:producer.file_ref(p) for k,p in [('summary',f.summarypath),('case',f.casepath),('source',f.work/'Witness.swift'),('adapter',f.work/'CaptureHost.swift'),('binary',f.exe),('compilerReceipt',f.receiptpath)]},'auxiliaryAX':{k:producer.file_ref(p) for k,p in [('receipt',auxreceipt),('source',aux/'AXClient.swift'),('binary',aux/'f5-ax-client')]}}
 run=f.ev/'run-001';run.mkdir();write(run/'instrumented.raw.json',{'monoStartNs':10,'monoEndNs':20,'rootLayout':{'placements':[]}})
 cap=normalize_run(run,{'case':f.summary['case']},case,1,{},producer.digest(f.exe),origin)
 f.summary['runs']=[{'run':1,'captureHash':producer.digest(run/'capture.json')}];write(f.ev/'summary.json',f.summary)
 return f,client,cap,tool

def run():
 scratch=ROOT/'.factory-work';scratch.mkdir(exist_ok=True);out={}
 with tempfile.TemporaryDirectory(prefix='mac-v3-independent-',dir=scratch) as tmp:
  root=Path(tmp);f,client,cap,auxtool=prepare(root/'positive')
  with patch.object(producer,'REPO',mod.fake_tools(f)):
   reader,manifest=producer.archive_origin(f.ev,[cap],f.casepath,f.work,f.exe,client)
  assert manifest['status']=='PASS';assert verify(f.root)['cases'][0]['runs']==1
  out['actual-normalize-envelope+outer-checker+CLI-parent-aux']='PASS schema-valid synthetic candidate; no semantic/parity claim'
  config=json.loads((f.ev/'origin-reader-config.json').read_text())
  for key in (client['compilerReceiptPath'],str(auxtool),str(f.tool),client['sourcePath'],client['executable']):assert key in config['macPathMap'],key
  shutil.rmtree(f.work);shutil.rmtree(Path(client['sourcePath']).parent);f.casepath.unlink();f.tool.unlink();f.xcrun.unlink();auxtool.unlink()
  for p in f.root.glob('ax-*'):p.unlink()
  for p in list(f.ev.iterdir()):
   if p.is_file() and p.name not in ('origin-reader-config.json','origin-archive-manifest.json','summary.json'):p.unlink()
  assert mac_origin_admission_issues(cap,lambda ref:reader(capture=cap,reference=ref))==[]
  assert verify(f.root)['status']=='PASS';out['full-AVAILABLE-replay-live-inputs-deleted']='PASS bothcompilers+auxstreams &outerchecker'
  receipt=Path(config['macPathMap'][cap['meta']['conditions']['macOrigin']['compilerReceipt']['path']]);summary=Path(config['macPathMap'][cap['meta']['conditions']['macOrigin']['summary']['path']]);capfile=f.ev/'run-001/capture.json';finalsummary=f.ev/'summary.json'
  saved={p:p.read_bytes() for p in (receipt,summary,capfile,finalsummary)}
  rr=json.loads(receipt.read_text());rr['compiler']['pid']=True;write(receipt,rr);ss=json.loads(summary.read_text());ss['compilerReceipt']=rr;write(summary,ss);cc=copy.deepcopy(cap)
  for key,path in [('compilerReceipt',receipt),('summary',summary)]:cc['meta']['conditions']['macOrigin'][key].update(sha256=producer.digest(path),bytes=path.stat().st_size)
  write(capfile,cc);fs=json.loads(finalsummary.read_text());fs['runs'][0]['captureHash']=producer.digest(capfile);write(finalsummary,fs)
  try:verify(f.root)
  except AssertionError as error:
   assert 'mac-origin:process: main.compiler.pid' in str(error),str(error);out['typed-boolPID-outerchecker']='PASS exact production guard rejection'
  else:raise AssertionError('typed malformed producer receipt accepted')
  for p,raw in saved.items():p.write_bytes(raw)

  g,client,c,tool=prepare(root/'conflict',conflict=True)
  with patch.object(producer,'REPO',mod.fake_tools(g)):
   try:producer.archive_origin(g.ev,[c],g.casepath,g.work,g.exe,client)
   except producer.CaptureError as error:
    assert 'Mac origin admission failed' in str(error) and 'read-failed' in str(error),str(error)
    out['same-logical-tool-path-conflicting-hashes']={'rejection':'fullguard read-failed before PASS','error':str(error)}
   else:raise AssertionError('conflicting compiler aliases silently accepted')
  # Checker read closure fails after one mapped source mutation; originals stay absent.
  target=Path(config['macPathMap'][cap['meta']['conditions']['macOrigin']['source']['path']]);target.write_bytes(b'FORGED')
  try:verify(f.root)
  except (ValueError,AssertionError) as error:
   assert 'bytes differ from pinned hash' in str(error),str(error);out['durable-byte-mutation']='PASS exact reader hash rejection'
  else:raise AssertionError('forged archive accepted')
  h=Fixture(root/'nonexec',mode=0o644);assert h.receipt['status']=='OUTPUT_MODE' and h.result.returncode!=0;out['nonexec-output-regression']='PASS OUTPUT_MODE/nonzero'
 return {'scope':'offline mocked producer &real schema-normalize/archive/checker/guard; no native/compiler/remote execution','controls':out}
if __name__=='__main__':print(json.dumps(run(),indent=2,sort_keys=True))
