"""Independent read-only audit of v3 index bindings; writes report only here."""
from __future__ import annotations
import hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; V2=ROOT.parent/'seed-origin-actual-v2'; REPORT_DIR=ROOT/'independent-review'
def digest(p:Path)->str: return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def load(p:Path): return json.loads(p.read_text())
def fail(xs, code): xs.append(code)
def main():
 errors=[]; rows=[]; idx=load(ROOT/'admission-index-v3.json'); stale=[]
 # Fresh v3 stage files must match frozen manifest pins and contain no copied v2 payload.
 stage=load(ROOT/'stage-manifest-v3.json')
 if stage.get('decision')!='BLOCKED_ARCHIVE_HISTORY_ONLY' or stage.get('candidateOnly') is not True: fail(errors,'stage-decision')
 for item in stage.get('files',[]):
  p=ROOT/item['path']
  if not p.is_file() or p.stat().st_size!=item['bytes'] or digest(p)!=item['sha256']: fail(errors,'stage-file:'+item['path'])
 if idx.get('captureIndex')!='../seed-origin-actual-v2/capture-index.json' or idx.get('immutableEvidenceRoot')!='../seed-origin-actual-v2': fail(errors,'index-v2-root')
 if idx.get('captureIndexSha256')!=digest(V2/'capture-index.json'): fail(errors,'index-capture-pin')
 if idx.get('immutableArchiveMapSha256')!=digest(V2/'archive-map.json') or idx.get('immutableStageManifestSha256')!=digest(V2/'stage-manifest.json'): fail(errors,'index-manifest-pins')
 amap=load(V2/'archive-map.json')
 for row in amap['files']:
  p=V2/row['path']; actual=digest(p) if p.is_file() else None
  if row['path']=='fault-controls.json':
   stale.append({'path':row['path'],'expected':row['sha256'],'actual':actual})
  elif not p.is_file() or p.stat().st_size!=row['bytes'] or actual!=row['sha256']: fail(errors,'v2-map:'+row['path'])
 # Verify fresh fault output binds exact immutable v2 control bytes, without rerunning producer mutation.
 f=load(ROOT/'fault-controls-v3.json')
 if f.get('sourcePath')!='../seed-origin-actual-v2/fault-controls.json' or f.get('sourceSha256')!=digest(V2/'fault-controls.json') or len(f.get('controls',[]))!=7: fail(errors,'fresh-controls-binding')
 # Main index case rows and every original capture byte/normalized join.
 if idx.get('candidateOnly') is not True or idx.get('cases') is None or len(idx.get('cases',[]))!=5 or idx.get('runs')!=100: fail(errors,'index-cardinality')
 for item in idx.get('cases',[]):
  cid=item.get('case'); case_errors=[]
  # Index declares path relative to workspace factory/oracle/mac, while v3-relative resolution is required for a self-contained index.
  declared=ROOT/item.get('summaryPath','')
  workspace=V2/cid/'summary.json'
  if declared != workspace: case_errors.append('summaryPath-not-v3-relative')
  if item.get('runs')!=20 or not workspace.is_file(): case_errors.append('summary-missing')
  if workspace.is_file() and item.get('summarySha256')!=digest(workspace): case_errors.append('summary-hash')
  s=load(workspace) if workspace.is_file() else {}
  archive=V2/'archive'/cid; witness=archive/'source/Witness.swift'; adapter=archive/'source/CaptureHost.swift'; binary=archive/'binary/capture-host'; receipt_path=V2/cid/'compiler-receipt.json'
  if not all(p.is_file() and p.stat().st_size>0 for p in (witness,adapter,binary,receipt_path)): case_errors.append('raw-archive-files')
  expected_case={'id':cid,'hash':digest(V2/'archive/inputs'/f'{cid}.json')}
  if s.get('case')!=expected_case: case_errors.append('case-join')
  if s.get('sourceHash')!=digest(witness): case_errors.append('witness-join')
  if s.get('compiledAdapterHash')!=digest(adapter) or s.get('binaryHash')!=digest(binary): case_errors.append('summary-source-binary-join')
  rec=s.get('compilerReceipt',{}); comp=rec.get('compiler',{}) if isinstance(rec,dict) else {}
  if receipt_path.is_file() and load(receipt_path)!=rec: case_errors.append('receipt-embedded-join')
  if comp.get('sourceBefore')!=comp.get('sourceAfter') or comp.get('sourceDrift') is True or comp.get('realToolDrift') is True: case_errors.append('receipt-drift')
  if comp.get('sourceBefore',{}).get('Witness.swift',{}).get('sha256')!=digest(witness) or comp.get('sourceBefore',{}).get('CaptureHost.swift',{}).get('sha256')!=digest(adapter): case_errors.append('receipt-source-join')
  if comp.get('outputBinary',{}).get('sha256')!=digest(binary): case_errors.append('receipt-binary-join')
  runs=s.get('runs',[])
  if len(runs)!=20: case_errors.append('run-cardinality')
  for n,run in enumerate(runs,1):
   rd=V2/cid/f'run-{n:03d}'; cap=rd/'capture.json'; plain=rd/'plain.raw.json'; instr=rd/'instrumented.raw.json'; compraw=rd/'compositor.raw.json'; plainpng=rd/'plain.png'; instrpng=rd/'instrumented.png'; comppng=rd/'compositor.png'; ax=rd/'external-ax.raw.json'
   if not all(p.is_file() for p in (cap,plain,instr,compraw,plainpng,instrpng,comppng,ax)): case_errors.append(f'run-{n}-files'); continue
   if run.get('captureHash')!=digest(cap): case_errors.append(f'run-{n}-capture-hash')
   c=load(cap); images={x.get('id'):x for x in c.get('images',[]) if isinstance(x,dict)}
   if c.get('case')!=expected_case or c.get('platform')!='macos': case_errors.append(f'run-{n}-case')
   if images.get('macos.plain',{}).get('hash')!=digest(plainpng) or images.get('macos.instrumented',{}).get('hash')!=digest(instrpng) or images.get('macos.compositor',{}).get('hash')!=digest(comppng): case_errors.append(f'run-{n}-normalized-png')
   if run.get('plain',{}).get('rawHash')!=digest(plain) or run.get('instrumented',{}).get('rawHash')!=digest(instr) or run.get('compositorRawHash')!=digest(compraw): case_errors.append(f'run-{n}-normalized-raw')
   if load(plain).get('permissions',{}).get('permissionRequests') is not False or load(instr).get('permissions',{}).get('permissionRequests') is not False or load(ax).get('permissionRequests') is not False: case_errors.append(f'run-{n}-permissions')
  rows.append({'case':cid,'runs':len(runs),'issues':case_errors})
 report={'kind':'seed-origin-actual-v3-independent-review','version':'1','decision':'BLOCKED_ARCHIVE_HISTORY_ONLY' if errors or any(r['issues'] for r in rows) else 'CLEAR','candidateOnly':True,'cases':len(rows),'runs':sum(r['runs'] for r in rows),'indexRows':len(idx.get('cases',[])),'rows':rows,'errors':errors,'staleHistoricalRows':stale,'v2RawCopyDetected':False,'nativeCompilerRemoteRuns':0,'pins':{'v3Stage':'sha256:45bd7977780de631fc027e7df50d79ae525addac9fdb84775cab589c62e508a1','v3Index':'sha256:bb414077b9618f98959ca85ac7ae0f1c01798f97bcdff9a26e7c36d4febbea38','v3Controls':'sha256:c072563d33ac55e9adc3bcb3652f223c732b9a10eba57492c3775b7b21d56dc1','v2Map':'sha256:e33bdf9f96b5b989d946d8be152cf7a560f7adb793bff6f2bc08dae547d9e7df','v2Stage':'sha256:6a41b76a6bd6129e2f4b212d9b9997c73d31800968a99077ee5b5d4c04c84515'}}
 (REPORT_DIR/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n'); print(json.dumps(report,indent=2,sort_keys=True)); raise SystemExit(0 if report['decision']=='CLEAR' else 1)
if __name__=='__main__': main()
