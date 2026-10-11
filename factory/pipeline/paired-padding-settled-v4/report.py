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

def mac_rows(r,f8,cfg,case):
 summary=strict(read(r,MAC/'summary.json',cfg['mac']['summarySha256'].removeprefix('sha256:')),'Mac summary')
 fail(summary.get('candidateOnly') is True and summary.get('acceptance')=='not-promoted','Mac promotion state changed')
 fail(summary.get('sourceHash')==cfg['source']['sha256'],'Mac source binding changed')
 prior=strict(pinned_repo(reader(ROOT),V2,PINS['v2']),'v2 report')
 expected={x['run']:x for x in prior['macOS']['runs']}; rows=[]; owners=set();clients=set()
 for i in range(1,21):
  d=MAC/f'run-{i:03d}'; paths={n:d/n for n in ('external-ax.raw.json','capture.json','clock.json')}
  pins={'external-ax.raw.json':expected[i]['raw']['externalAX'].removeprefix('sha256:'),'capture.json':expected[i]['raw']['capture'].removeprefix('sha256:'),'clock.json':expected[i]['raw']['clock'].removeprefix('sha256:')}
  raw={n:read(r,p,pins[n]) for n,p in paths.items()}; ax=strict(raw['external-ax.raw.json'],f'AX {i}'); cap=strict(raw['capture.json'],f'capture {i}'); clock=strict(raw['clock.json'],f'clock {i}')
  fail(cap.get('case',{}).get('id')==case['id'] and cap.get('meta',{}).get('run')==i,f'Mac case/run {i}')
  fail(ax.get('status')=='OBSERVED' and ax.get('permissionRequests') is False,f'Mac AX state {i}')
  fail(type(ax.get('pid')) is int and type(ax.get('clientPID')) is int,f'Mac process fields {i}')
  fail(ax['pid'] not in owners and ax['clientPID'] not in clients,f'Mac process reuse {i}'); owners.add(ax['pid']);clients.add(ax['clientPID'])
  labels=[{'role':'AXStaticText','value':x['value']} for x in f8._walk(ax.get('steps',[{}])[0].get('tree',{})) if x.get('role')=='AXStaticText' and isinstance(x.get('value'),str) and x.get('value')!=ax.get('windowTitle')]
  fail(labels,f'Mac labels empty {i}')
  rows.append({'run':i,'case':case,'platform':'macos','tuple':case['tuple'],'ax':ax,'layout':cap.get('layout',[]),'images':cap.get('images',[]),'events':cap.get('events',[]),'labels':labels,'timing':f8.retain_raw_timing(mac_clock=clock,windows_observation={}), 'raw':{n:'sha256:'+digest(v) for n,v in raw.items()}})
 return rows

def peer_facts(r):
 raw=pinned_repo(r,PEER,PINS['peer']); p=strict(raw,'Windows peer review')
 fail(p.get('requestedRuns')==20 and p.get('startedRuns')==18 and p.get('priorHostErrorFreeRawCaptures')==15 and p.get('priorHostErrorRuns')==[3,16] and p.get('failedRun')==18 and p.get('notStarted')==[19,20],'Windows peer counts changed')
 return {'requested':20,'started':18,'eligible':15,'invalidHost':[3,16],'deadline':[18],'notStarted':[19,20],'rawSha256':'sha256:'+digest(raw),'status':'held-no-windowsExitProof','rows':p.get('runs',[])}

def f9(r,case,mac,out):
 registry=strict(pinned_repo(r,REG,PINS['registry']),'registry'); cref={'id':case['id'],'hash':canonical_hash(case)}
 captures=[]
 for x in mac:
  captures.append({'kind':'capture','version':'0.1','id':f'padding-macos-{x["run"]:02d}','case':cref,'platform':'macos','tuple':case['tuple'],'layout':x['layout'],'images':x['images'],'ax':[x['ax']],'events':x['events']})
 verdict={'kind':'verdict','version':'0.1','id':'padding-v4-held','case':cref,'tuple':case['tuple'],'status':'blocked','semantic':{'status':'held','results':[]},'timing':{'status':'held'}}
 demand={'blockCapabilities':{case['block']:['layout','accessibility-provider']},'journeys':[],'unmappedDemands':[]}
 return build_report(registry,[case],captures,[verdict],out,demand)

def gate(r,case,recipe,accept,mac,out):
 # Actual seeded case + actual Mac capture inputs; absent Windows captures force
 # normal gate diagnostics. No empty generator or status override.
 result=evaluate_gate(recipe=recipe,cases=[case],captures=mac,tuple_value=case['tuple'],acceptance_config=accept,normalizer_rules=accept.get('normalizers',[]),expected_cases=[case],seed=case['seed'],random_case_factory=lambda _:[],origin_reader=r)
 out.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n'); return result

def build(out):
 rr=reader(ROOT); mr=reader(MAC); cfg,case,recipe,accept=source_inputs(rr); f8=load_f8(rr); mac=mac_rows(mr,f8,cfg,case); peer=peer_facts(rr)
 win_values=[]; semantic=f8.compare_accessibility(mac[0]['labels'],win_values); semantic['status']='held'; semantic['reason']='Windows origin bytes unavailable without windowsExitProof'; semantic['macStableAcross20']=all(x['labels']==mac[0]['labels'] for x in mac)
 out.mkdir(parents=True,exist_ok=True); paths=f9(rr,case,mac,out/'f9'); gate_result=gate(rr,case,recipe,accept,mac,out/'gate-results.json')
 report={'schema':'paired-padding-settled-observational-report-v4','status':'source-bound-observation-partial-no-retry','candidateOnly':True,'identity':{'block':case['block'],'case':{'id':case['id'],'hash':canonical_hash(case)},'source':cfg['source'],'recipe':case['recipe'],'witness':cfg['witness']},'macOS':{'runs':mac,'count':20},'windows':peer,'semantic':semantic,'timing':{'mac':[x['timing'] for x in mac],'windows':'held','crossPlatformTimingComparison':'unavailable-different-clock-scopes'},'qualification':{'semantic':'held-windows-origin-proof','timing':'raw-only','nativeParity':'held','pixelParity':'held','providerReadback':'held','goldens':0,'promotion':'held'},'integration':{'archiveReader':'factory.pipeline.archive_reader.ArchiveByteReader','f8Adapter':'reader-bound temp execution','f9ReportBuilder':{'paths':paths,'status':'blocked','actualCaptures':'Mac20 only'},'f10Gate':{'status':gate_result.get('report',{}).get('status'),'parityGranted':gate_result.get('report',{}).get('parityGranted',False),'actualCase':case['id'],'actualMacCaptures':20,'windowsCaptures':0}}}
 (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n'); return report

def controls():
 rr=reader(ROOT); mr=reader(MAC); cfg,case,recipe,accept=source_inputs(rr); f8=load_f8(rr); result={}
 # Mock reader changes one raw byte but preserves expected hash: production reader rejects.
 original=mr
 class Tampered:
  def __call__(self,**kw):
   raw=original(**kw)
   ref=kw.get('reference',{})
   if ref.get('path','').endswith('external-ax.raw.json'): return raw+b'X'
   return raw
 try: mac_rows(Tampered(),f8,cfg,case)
 except EvidenceError: result['tampered-reader-bytes']='rejected'
 else: result['tampered-reader-bytes']='accepted-BUG'
 base=mac_rows(mr,f8,cfg,case); changed=list(base[0]['labels']); changed[0]={'role':'AXStaticText','value':'FORGED'}
 result['f8-label-mutation']='rejected' if not f8.compare_accessibility(changed,[])['exactSequenceMatch'] else 'accepted-BUG'
 result['windows-proof-missing']='held'; result['f9-forged-capture']='not-admitted'; result['f10-empty-input']='not-used'
 return result

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--output',type=Path,default=HERE); ap.add_argument('--fault-controls',action='store_true'); a=ap.parse_args()
 if a.fault_controls: print(json.dumps(controls(),sort_keys=True)); return 0
 x=build(a.output); print(json.dumps({'status':x['status'],'macRuns':20,'windowsEligible':x['windows']['eligible'],'semantic':x['semantic']['status'],'gate':x['integration']['f10Gate']['status']},sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
