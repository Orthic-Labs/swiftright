#!/usr/bin/env python3
"""Pair trusted Windows20 reader rows with existing Mac20 diagnostics."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, sys
from pathlib import Path
from factory.comparison.comparator import ComparisonError, compare_case

ROOT=Path('.').resolve()
READER=ROOT/'factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/trusted-reader-report.py'
REFS=ROOT/'factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/paired-inputs-r3/mac-rebased-refs-r3.json'
CASE=ROOT/'factory/oracle/mac/seed-origin-v5/inputs/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.json'
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p): return 'sha256:'+hashlib.sha256(Path(p).read_bytes()).hexdigest()
def module(p):
 s=importlib.util.spec_from_file_location('trusted_r7',p); m=importlib.util.module_from_spec(s); assert s.loader; s.loader.exec_module(m); return m
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--input',type=Path,required=True); ap.add_argument('--output',type=Path,required=True); a=ap.parse_args(); trusted=module(READER)
 manifest,mac_report_path,windows_path,reader=trusted.load_inputs(a.input)
 mac_report=trusted.parse_json(mac_report_path,'Mac report'); mac=trusted.mac_proof(mac_report,mac_report_path)
 refs=load(REFS); mac_runs=[]
 for row in refs['macCaptures']:
  p=(REFS.parent/row['path']).resolve(strict=True); raw=p.read_bytes()
  if sha(p)!=row['sha256'] or len(raw)!=row['bytes']: raise ValueError('Mac ref drift:'+str(row['run']))
  mac_runs.append(load(p))
 if len(mac_runs)!=20 or [x.get('meta',{}).get('run') for x in mac_runs]!=list(range(1,21)): raise ValueError('Mac20 run join')
 windows_payload=trusted.parse_json(windows_path,'Windows captures'); windows=windows_payload['captures']; rows=trusted.windows_rows(windows_payload,manifest,reader)
 try:
  comparison=compare_case(load(CASE),mac_runs+windows,acceptance_config={},holds=['F10 parity/golden/freeze held'])
 except ComparisonError as exc:
  comparison={'status':'blocked','reason':'canonical tuple/case admission rejected','error':str(exc),'parity':'held','goldens':0,'promotion':'held'}
 out={'schema':'paired-padding-f10-comparison-diagnostic-r7','status':'paired-comparison-diagnostic-complete','candidateOnly':True,'inputs':{'manifest':{'path':str(a.input.resolve()),'sha256':sha(a.input)},'macReport':{'path':str(mac_report_path),'sha256':sha(mac_report_path)},'windowsCaptures':{'path':str(windows_path),'sha256':sha(windows_path)},'case':{'path':str(CASE),'sha256':sha(CASE)}},'reader':{'macRuns':20,'windowsReaderVerified':len(rows),'windowsRows':rows},'comparison':comparison,'parity':{'status':'held','goldens':0,'promotion':'held'},'effects':{'nativeWindowActions':0,'compilerActions':0,'remoteActions':0,'lockActions':0,'sourceMutations':0}}
 if a.output.exists(): raise ValueError('output must be fresh')
 a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); print(json.dumps({'status':out['status'],'macRuns':20,'windowsReaderVerified':len(rows),'nativeParity':out['parity']['status']}))
if __name__=='__main__': main()
