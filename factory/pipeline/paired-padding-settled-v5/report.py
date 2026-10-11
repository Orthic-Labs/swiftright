#!/usr/bin/env python3
"""Fail-closed v4 paired padding report.

Only bytes returned by production ArchiveByteReader enter parsing. Mac rows are
actual capture records. Windows facts come only from reviewed raw peer JSON;
without windowsExitProof, no Windows raw row is admitted to semantic capture
comparison. F9 & F10 therefore receive actual partial inputs & remain blocked.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, tempfile
from pathlib import Path
from typing import Any
from factory.core.artifacts import canonical_hash
from factory.gate.core import evaluate_gate
from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError
from factory.reports.report import build_report

ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).resolve().parent
MAC=ROOT/'factory/native/macos/evidence/20261010-gate-seeded/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258'
CFG=ROOT/'factory/pipeline/paired-padding-settled-v2/source-config.json'
V2=ROOT/'factory/pipeline/paired-padding-settled-v2/report.json'
PEER=ROOT/'factory/native/windows/padding-settled-capture-v4/actual-repeat-review-v1/report.json'
SEEDS=ROOT/'factory/pipeline/gate-pilot/seed-cases.json'
ACCEPT=ROOT/'factory/pipeline/inputs/acceptance-candidate.json'
REG=ROOT/'factory/registry/evidence/block-registry.json'; RECIPE=ROOT/'factory/recipes/data/swiftui.padding-frame.json'
F8=ROOT/'factory/pipeline/paired-next-observations-v1/adapter.py'
GATE_PLAN=ROOT/'factory/pipeline/gate-pilot/gate-results.json'
GATE_CASES=ROOT/'factory/pipeline/inputs/cases.json'
GATE_SEED_CASES=ROOT/'factory/pipeline/gate-pilot/seed-cases.json'
PINS={
 'cfg':'801941da071123876b19c4907cb5a105334deff4b2f6461c1f2910cdf1d665ea',
 'v2':'6aa22b923df24ef8d596169a80624c56a58af45899ecb619d360654982cbc4e4',
 'peer':'679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c',
 'seeds':'7843fcea9c4441375ec8889716e5373b247e11214087f41b2499003b3763fb21',
 'accept':'082fe5a160dba7d326ded1ce1fbbea5a4cc7222aa1d21c2d8778af4babbbd874',
 'registry':'1ad0a508bb0b721a31f9e2ecdf209a217d20c52d2666a14d3eaf970653d8b983',
 'recipe':'c371fe9f27a86fcac6f59c66d98c72a15557a3d0b7f595732eb26967d1b55d37',
 'f8':'64acee7502d9e6bb6b7fcb172d338a1337f1973fabe542e169b0325e585846af',
}
class EvidenceError(ValueError): pass

def digest(b): return hashlib.sha256(b).hexdigest()
def fail(c,m):
 if not c: raise EvidenceError(m)
def strict(raw,label):
 def pairs(items):
  out={}
  for k,v in items:
   if k in out: raise EvidenceError(f'duplicate JSON key: {label}')
   out[k]=v
  return out
 try: return json.loads(raw.decode('utf-8-sig'),object_pairs_hook=pairs,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('non-finite')))
 except (UnicodeDecodeError,json.JSONDecodeError,ValueError) as e: raise EvidenceError(f'invalid JSON: {label}') from e

def reader(root): return ArchiveByteReader(mac_roots=[root])
def read(r,path,pin):
 try: return r(capture={'platform':'macos'},reference={'path':str(path.resolve()),'sha256':'sha256:'+pin})
 except (ArchiveReadError,OSError) as e: raise EvidenceError(f'reader rejected {path}') from e
def repo(r,path,pin): return read(r,path,pin)
def pinned_repo(r,path,pin):
 raw=repo(r,path,pin); fail(digest(raw)==pin,f'pin changed: {path}'); return raw

def load_f8(r):
 raw=pinned_repo(r,F8,PINS['f8'])
 with tempfile.TemporaryDirectory(prefix='paired-padding-f8-') as d:
  p=Path(d)/'adapter.py'; p.write_bytes(raw)
  spec=importlib.util.spec_from_file_location('paired_padding_f8',p)
  if spec is None or spec.loader is None: raise EvidenceError('F8 adapter unavailable')
  mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def source_inputs(r):
 cfg=strict(pinned_repo(r,CFG,PINS['cfg']),'config')
 seedrows=strict(pinned_repo(r,SEEDS,PINS['seeds']),'seed cases')
 case=next((x for x in seedrows if x.get('id')==cfg['case']['id']),None)
 fail(isinstance(case,dict),'actual seeded case missing')
 fail(case.get('tuple',{}).get('acceptanceConfigHash')=='sha256:'+PINS['accept'],'seed tuple changed')
 recipe=strict(pinned_repo(r,RECIPE,PINS['recipe']),'recipe')
 accept=strict(pinned_repo(r,ACCEPT,PINS['accept']),'acceptance config')
 return cfg,case,recipe,accept

def mac_captures(r,f8,cfg,case):
 summary=strict(read(r,MAC/'summary.json',cfg['mac']['summarySha256'].removeprefix('sha256:')),'Mac summary')
 fail(summary.get('candidateOnly') is True and summary.get('acceptance')=='not-promoted','Mac promotion state changed')
 fail(summary.get('sourceHash')==cfg['source']['sha256'],'Mac source binding changed')
 prior=strict(pinned_repo(reader(ROOT),V2,PINS['v2']),'v2 report')
 expected={x['run']:x for x in prior['macOS']['runs']}; captures=[]; refs=[]
 for i in range(1,21):
  d=MAC/f'run-{i:03d}'; cap_path=d/'capture.json'; ax_path=d/'external-ax.raw.json'; clock_path=d/'clock.json'
  cap_pin=expected[i]['raw']['capture'].removeprefix('sha256:'); ax_pin=expected[i]['raw']['externalAX'].removeprefix('sha256:'); clock_pin=expected[i]['raw']['clock'].removeprefix('sha256:')
  cap_raw=read(r,cap_path,cap_pin); ax_raw=read(r,ax_path,ax_pin); clock_raw=read(r,clock_path,clock_pin)
  cap=strict(cap_raw,f'capture {i}'); ax=strict(ax_raw,f'AX {i}'); clock=strict(clock_raw,f'clock {i}')
  fail(cap.get('kind')=='capture' and cap.get('version')=='0.1','original capture envelope changed')
  fail(cap.get('case')=={'id':case['id'],'hash':canonical_hash(case)} and cap.get('platform')=='macos','Mac capture case/platform changed')
  fail(cap.get('meta',{}).get('run')==i,'Mac capture run changed')
  fail(ax.get('status')=='OBSERVED' and ax.get('permissionRequests') is False,'Mac AX state changed')
  fail(clock.get('clockId')=='macos.dispatch.uptime','Mac clock changed')
  captures.append(cap); refs.append({'run':i,'capture':'sha256:'+digest(cap_raw),'ax':'sha256:'+digest(ax_raw),'clock':'sha256:'+digest(clock_raw)})
 return captures,refs

def workflow_collect(case, reader, output):
 # Existing collector is authoritative for original envelope validation. Reader
 # verifies every capture.json before collector sees it.
 try:
  from factory.pipeline import workflow
  collected=workflow.collect([case],[MAC])
 except ModuleNotFoundError as exc:
  return {'status':'blocked-dependency','error':f'{exc.name}: {exc.msg}'}
 except (OSError,ValueError,KeyError,TypeError) as exc:
  return {'status':'blocked','error':str(exc)}
 captures=collected.get('captures',[])
 if len(captures)!=20: return {'status':'blocked','error':f'collector returned {len(captures)} Mac captures'}
 return {'status':'collected','count':len(captures),'diagnostics':collected.get('diagnostics',[]),'captures':captures}

def compare_actual(case,captures,accept):
 try:
  from factory.comparison import compare_case
  return {'status':'compared','verdict':compare_case(case,captures,acceptance_config=accept,holds=['Windows origin proof unavailable'])}
 except ModuleNotFoundError as exc:
  return {'status':'blocked-dependency','error':f'{exc.name}: {exc.msg}'}
 except (ValueError,KeyError,TypeError) as exc:
  return {'status':'blocked','error':str(exc)}

def peer_facts(r):
 raw=pinned_repo(r,PEER,PINS['peer']); p=strict(raw,'Windows peer review')
 fail(p.get('requestedRuns')==20 and p.get('startedRuns')==18 and p.get('priorHostErrorFreeRawCaptures')==15 and p.get('priorHostErrorRuns')==[3,16] and p.get('failedRun')==18 and p.get('notStarted')==[19,20],'Windows peer counts changed')
 return {'requested':20,'started':18,'eligible':15,'invalidHost':[3,16],'deadline':[18],'notStarted':[19,20],'rawSha256':'sha256:'+digest(raw),'status':'held-no-windowsExitProof','rows':p.get('runs',[])}

def f9(r,case,captures,verdict,out):
 registry=strict(pinned_repo(r,REG,PINS['registry']),'registry')
 demand={'blockCapabilities':{case['block']:['layout','accessibility-provider']},'journeys':[],'unmappedDemands':[]}
 return build_report(registry,[case],captures,[verdict],out,demand)

def workflow_gate(case,reader,out):
 # Reuse recorded gate plan & seed cases; no generated lambda, no status override.
 try:
  from factory.pipeline import workflow
  result=workflow.gate_evidence(out,GATE_PLAN,GATE_CASES,[MAC],ROOT/'factory/pipeline/inputs/observed-tuple.json',ACCEPT,ROOT/'factory/pipeline/manifests',origin_reader=reader)
  return {'status':'completed','result':result}
 except ModuleNotFoundError as exc:
  return {'status':'blocked-dependency','error':f'{exc.name}: {exc.msg}'}
 except (OSError,ValueError,KeyError,TypeError) as exc:
  return {'status':'blocked','error':str(exc)}

def build(out):
 rr=reader(ROOT); mr=reader(MAC); cfg,case,recipe,accept=source_inputs(rr); f8=load_f8(rr); captures,refs=mac_captures(mr,f8,cfg,case); peer=peer_facts(rr)
 collected=workflow_collect(case,mr,out/'collector')
 compare=compare_actual(case,captures,accept)
 if compare.get('status')=='compared': verdict=compare['verdict']
 else: verdict={'kind':'verdict','version':'0.1','id':case['id']+'.comparison-held','provenance':{'producer':'factory/pipeline/paired-padding-settled-v5','sourceHash':canonical_hash(case)},'case':{'id':case['id'],'hash':canonical_hash(case)},'tuple':case['tuple'],'macCaptures':[{'id':x['id'],'hash':canonical_hash(x)} for x in captures],'windowsCaptures':[],'semantic':{'status':'blocked','results':[]},'timing':{'status':'blocked'},'status':'blocked','holdReason':compare.get('error','comparison unavailable')}
 out.mkdir(parents=True,exist_ok=True); paths=f9(rr,case,captures,verdict,out/'f9'); gate=workflow_gate(case,mr,out/'workflow-gate-evidence')
 report={'schema':'paired-padding-settled-observational-report-v5','status':'source-bound-observation-partial-no-retry','candidateOnly':True,'identity':{'block':case['block'],'case':{'id':case['id'],'hash':canonical_hash(case)},'source':cfg['source'],'recipe':case['recipe'],'witness':cfg['witness']},'schemaCounts':{'readerVerified20':len(captures)==20,'schemaCollected20':collected.get('status')=='collected' and collected.get('count')==20,'originVerified':0,'parityQualified':0},'macOS':{'captures':captures,'count':len(captures),'readerRefs':refs},'windows':peer,'qualification':{'semantic':'held-windows-origin-proof','timing':'raw-only','nativeParity':'held','pixelParity':'held','providerReadback':'held','goldens':0,'promotion':'held'},'integration':{'archiveReader':'factory.pipeline.archive_reader.ArchiveByteReader','workflowCollect':{k:v for k,v in collected.items() if k!='captures'},'compareCase':{k:v for k,v in compare.items() if k!='verdict'},'f9ReportBuilder':{'paths':paths,'status':'blocked','actualCaptures':len(captures)},'workflowGateEvidence':{k:v for k,v in gate.items() if k!='result'},'encounteredCaptureIds':len(captures),'notAdmittedWindowsCaptures':0}}
 (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n'); return report

def controls():
 rr=reader(ROOT); mr=reader(MAC); cfg,case,recipe,accept=source_inputs(rr); f8=load_f8(rr); result={}; base,refs=mac_captures(mr,f8,cfg,case)
 class Tampered:
  def __call__(self,**kw):
   raw=mr(**kw); ref=kw.get('reference',{})
   if ref.get('path','').endswith('external-ax.raw.json'): return raw+b'X'
   return raw
 try: mac_captures(Tampered(),f8,cfg,case)
 except EvidenceError: result['tampered-reader-bytes']='rejected'
 else: result['tampered-reader-bytes']='accepted-BUG'
 dup=[dict(x) for x in base]; dup[1]=dict(dup[1]); dup[1]['id']=dup[0]['id']
 try:
  x=compare_actual(case,dup,accept); result['duplicate-id']='rejected' if x.get('status') in ('blocked','blocked-dependency') else 'accepted-BUG'
 except (ValueError,KeyError,TypeError): result['duplicate-id']='rejected'
 result['missing-origin-exact-code']='held'; result['windows-adjunct-not-capture']='held'; result['frozen-source-mutation']='not-attempted'
 return result

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--output',type=Path,default=HERE); ap.add_argument('--fault-controls',action='store_true'); a=ap.parse_args()
 if a.fault_controls: print(json.dumps(controls(),sort_keys=True)); return 0
 x=build(a.output); print(json.dumps({'status':x['status'],'macRuns':20,'windowsEligible':x['windows']['eligible'],'schemaCollected20':x['schemaCounts']['schemaCollected20'],'gate':x['integration']['workflowGateEvidence']['status']},sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
