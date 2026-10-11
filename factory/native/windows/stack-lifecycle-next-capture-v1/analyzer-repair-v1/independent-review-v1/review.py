#!/usr/bin/env python3
"""Offline review of analyzer-repair-v1; no compiler/native/remote action."""
from __future__ import annotations
import hashlib, importlib.util, json, shutil, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[6]
A=ROOT/'factory/native/windows/stack-lifecycle-next-capture-v1/analyzer-repair-v1'
FROZEN=ROOT/'factory/native/windows/stack-lifecycle-next-capture-v1'
BUILD=ROOT/'factory/native/windows/stack-lifecycle-next-build-v1'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text(encoding='utf-8'))
def load_analyzer():
 spec=importlib.util.spec_from_file_location('repaired_analyzer',A/'analyze_lifecycle.py'); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def main():
 failures=[]; checks=[]
 m=load(A/'root-stage-manifest.json'); bad=[]
 for e in m['files']:
  p=ROOT/e['path']
  if not p.is_file(): bad.append(f'missing:{e["path"]}'); continue
  if p.stat().st_size!=e['bytes'] or sha(p)!=e['hash'].removeprefix('sha256:'): bad.append(f'drift:{e["path"]}')
 if bad: failures.extend(bad)
 checks.append({'name':'repair-stage-refs','ok':not bad,'entries':len(m['files']),'stageSha256':sha(A/'root-stage-manifest.json')})
 # Frozen capture source remains exact, including original 24-ref stage hash.
 frozen=load(FROZEN/'root-stage-manifest.json')
 if len(frozen['files'])!=24 or sha(FROZEN/'root-stage-manifest.json')!='4cb0602f6ed2a50ee7717895ce1dc03d48e80e82909996f395fa1b1da93f7eb4': failures.append('frozen 24-ref capture stage drift')
 checks.append({'name':'frozen-capture-unchanged','ok':not any('frozen' in x for x in failures),'entries':len(frozen['files']),'stageSha256':sha(FROZEN/'root-stage-manifest.json')})
 mod=load_analyzer(); root=A/'synthetic-controls'; observed=[]
 for d in sorted(root.iterdir()):
  n=d/'native-01'
  if not (n/'capture-outcome.json').exists(): continue
  try: mod.analyze(n); observed.append({'case':d.name,'accepted':True})
  except Exception as e: observed.append({'case':d.name,'accepted':False,'error':str(e)})
 accepted=[x for x in observed if x['accepted']]
 if len(observed)!=9 or len(accepted)!=1: failures.append(f'fixture outcomes expected 1/8, got {len(accepted)}/{len(observed)-len(accepted)}')
 if accepted and accepted[0]['case']!='78e36bcc9f944e2a8af38763c06a92d1': failures.append('unexpected fixture accepted')
 checks.append({'name':'nine-offline-controls','ok':not any('fixture' in x for x in failures),'results':observed})
 analyzer=(A/'analyze_lifecycle.py').read_text()
 required=['EXPECTED_PLAN_SHA256','EXPECTED_COMPILE_SHA256','owned-process.json','sourceHash','compiled[\'exePath\']','rawHashesQualification','len(streams)!=2','copyCompleted','destinationClosed','sealed','taskIsCompleted','taskIsFaulted','taskIsCanceled','sourceIsAsync','taskException','taskStatus','closureTaskStatus','hashQualification','flushCompleted','completedWithinDeadline','deadlineExpired','host.'+"'+name+'"+'.txt','hashlib.sha256(raw_by_name[name])']
 missing=[x for x in required if x not in analyzer]
 if missing: failures.extend('analyzer missing '+x for x in missing)
 checks.append({'name':'strict-raw-lineage-source-checks','ok':not missing,'missing':missing})
 # Verify expected pinned source/compile bytes are represented in repaired source.
 if '9e385e4e50b46c109103cf28b9d8e93be01298fed6c35f2426a1d6a3cdaacef1' not in analyzer or '99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8' not in analyzer: failures.append('actual source/compile pins absent')
 checks.append({'name':'actual-source-compile-pins','ok':not any('actual source' in x for x in failures),'planSha256':'9e385e4e…acef1','compileReceiptSha256':'99a0332b…dcae8'})
 # Confirm no new execution capabilities were added in analyzer repair.
 if any(x in analyzer for x in ['subprocess','Process.Start','Start-ScheduledTask','swiftc','xcrun','ssh']): failures.append('analyzer repair contains execution API')
 checks.append({'name':'offline-only','ok':not any('execution API' in x for x in failures)})
 decision='CLEAR_ANALYZER_REPAIR' if not failures else 'HOLD_ANALYZER_REPAIR'
 return {'kind':'stack-lifecycle-analyzer-repair-independent-review','version':'1','decision':decision,'qualification':'diagnostic-only','reviewScope':'offline analyzer/source/fixture audit; no compiler/native/remote action','repairStageSha256':sha(A/'root-stage-manifest.json'),'repairEntries':len(m['files']),'frozenCaptureStageSha256':sha(FROZEN/'root-stage-manifest.json'),'buildPlanSha256':sha(BUILD/'package/plan.json'),'actualCompileReceiptSha256':'99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8','nativeRuns':0,'compilerRuns':0,'remoteActions':0,'checks':checks,'failures':failures,'rawCaptureAdmission':'CLEAR_INDEPENDENT_OF_ANALYZER: frozen Count1 runner source guards, actual Windows AST/source controls & actual Launch preflight are separate from analyzer; root owns final runtime receipt/lock/raw proof.'}
if __name__=='__main__': print(json.dumps(main(),indent=2,sort_keys=True))
