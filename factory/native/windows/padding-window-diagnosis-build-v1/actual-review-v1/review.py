#!/usr/bin/env python3
"""Read-only audit of six fetched actual compiler outputs; no compiler/native/remote action."""
from __future__ import annotations
import hashlib, json, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
BUILD=ROOT/'factory/native/windows/padding-window-diagnosis-build-v1'
ACT=BUILD/'root-build-r1/actual'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 failures=[];checks=[]
 stage=load(BUILD/'root-stage-manifest.json'); bad=[]
 for e in stage['files']:
  p=ROOT/e['path']
  if not p.is_file(): bad.append('missing '+e['path']);continue
  if p.stat().st_size!=e['bytes'] or sha(p)!=e['hash'].removeprefix('sha256:'):bad.append('drift '+e['path'])
 checks.append({'name':'78-source-stage-refs','ok':not bad,'entries':len(stage['files']),'stageSha256':sha(BUILD/'root-stage-manifest.json')})
 if bad: failures.extend(bad)
 fetch=load(BUILD/'root-build-r1/fetch.json'); fetched=fetch['files']; local={
  'FactoryProbe.exe':ACT/'FactoryProbe.exe','compile.stdout.bin':ACT/'compile.stdout.bin','compile.stderr.bin':ACT/'compile.stderr.bin','observation.json':ACT/'observation.json','runtime-module-archive/x86_64-unknown-windows-msvc.swiftdoc':ACT/'runtime-module-archive/x86_64-unknown-windows-msvc.swiftdoc','runtime-module-archive/x86_64-unknown-windows-msvc.swiftmodule':ACT/'runtime-module-archive/x86_64-unknown-windows-msvc.swiftmodule'}
 actual_bad=[]
 for name,p in local.items():
  if not p.is_file(): actual_bad.append('missing '+name);continue
  row=fetched.get(name)
  if not row or row['bytes']!=p.stat().st_size or row['sha256']!=sha(p):actual_bad.append('fetch mismatch '+name)
 if set(fetched)!=set(local): actual_bad.append('fetch six-file membership mismatch')
 if actual_bad: failures.extend(actual_bad)
 checks.append({'name':'actual-six-fetch-joins','ok':not actual_bad,'files':{n:{'bytes':p.stat().st_size,'sha256':sha(p)} for n,p in local.items()}})
 plan=load(BUILD/'package/plan.json'); obs=load(ACT/'observation.json'); rawchecks=[]
 for name in ('compile.stdout.bin','compile.stderr.bin'):
  p=ACT/name;raw=next((x for x in obs['rawFileHashes'] if x['path']==name),None)
  if raw is None or raw['hash']['sha256']!=sha(p) or raw['hash']['qualification']!='sealed-raw':rawchecks.append(name+' raw hash/qualification')
  state=next((x for x in obs['rawStreams'] if x['name']==('stdout' if 'stdout' in name else 'stderr')),None)
  if not state or any(state.get(k) is not True for k in ('copyCompleted','destinationClosed','sealed','taskIsCompleted')) or state.get('taskIsFaulted') is not False or state.get('taskIsCanceled') is not False or state.get('taskStatus')!='RanToCompletion' or state.get('closureTaskStatus')!='RanToCompletion' or state.get('hashQualification')!='sealed-raw':rawchecks.append(name+' terminal state')
  c=state.get('closure') if state else None
  if not isinstance(c,dict) or any(c.get(k) is not True for k in ('flushCompleted','destinationClosed','completedWithinDeadline')) or c.get('deadlineExpired') is not False or c.get('error')!='':rawchecks.append(name+' closure')
 if obs.get('rawStreams') and len(obs['rawStreams'])!=2:rawchecks.append('raw stream count')
 if rawchecks: failures.extend(rawchecks)
 checks.append({'name':'receipt-raw-joins','ok':not rawchecks,'rawStreams':len(obs.get('rawStreams',[])),'rawFileHashes':len(obs.get('rawFileHashes',[]))})
 # Exact compile lineage and argv.
 dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
 cr=plan['compileRequest'];expected='build --package-path "'+cr['packagePath']+'" --scratch-path "'+cr['scratchPath']+'" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
 lineage={'planSha256':sha(BUILD/'package/plan.json'),'sourceHash':plan['sourceHash'],'runtimeSourceCommit':plan['runtimeSourceCommit'],'runtimeSourceTreeHash':plan['runtimeSourceTreeHash'],'rendererSha256':plan['rendererSha256'],'compilerPath':plan['compilerPath'],'compilerHash':plan['compilerHash'],'cwd':str(cr['packagePath']),'target':cr['target'],'configuration':cr['configuration']}
 for k,v in lineage.items():
  ov=obs.get(k)
  if k=='planSha256': continue
  if ov!=v and not(k=='cwd' and ov==v): failures.append('lineage '+k)
 if obs.get('planSha256')!=sha(BUILD/'package/plan.json') or obs.get('argv')!=expected or obs.get('kind')!='factory-padding-window-diagnosis-compile-only-owned-handle-v1': failures.append('compiler request lineage/argv')
 if not (obs.get('exitCode')==0 and obs.get('kernelWait')==0 and obs.get('timedOut') is False and obs.get('ownedExited') is True and obs.get('streamDrainComplete') is True and obs.get('error') is None and obs.get('cleanupError') is None and obs.get('nativeWindowOpened') is False): failures.append('compiler termination qualification')
 checks.append({'name':'compile-request-receipt','ok':(not any(x.startswith('lineage ') for x in failures) and 'compiler request lineage/argv' not in failures and 'compiler termination qualification' not in failures),'argvExact':obs.get('argv')==expected,'termination':{'exitCode':obs.get('exitCode'),'kernelWait':obs.get('kernelWait'),'timedOut':obs.get('timedOut'),'ownedExited':obs.get('ownedExited'),'streamDrainComplete':obs.get('streamDrainComplete')}})
 # PE header independent parse.
 exe=(ACT/'FactoryProbe.exe').read_bytes(); peoff=int.from_bytes(exe[0x3c:0x40],'little') if exe[:2]==b'MZ' else -1; machine=int.from_bytes(exe[peoff+4:peoff+6],'little') if peoff>=0 and exe[peoff:peoff+4]==b'PE\0\0' else -1; subsystem=int.from_bytes(exe[peoff+24+68:peoff+24+70],'little') if peoff>=0 and exe[peoff:peoff+4]==b'PE\0\0' else -1
 if sha(ACT/'FactoryProbe.exe')!=obs.get('exeSha256') or machine!=34404 or subsystem!=2: failures.append('PE/exe hash')
 checks.append({'name':'actual-gui-pe','ok':not any(x=='PE/exe hash' for x in failures),'sha256':sha(ACT/'FactoryProbe.exe'),'machine':machine,'subsystem':subsystem})
 # Produced runtime module archive joins.
 mods=[]
 for m in obs.get('runtimeModules',[]):
  p=ACT/'runtime-module-archive'/Path(m['archivePath'].replace('\\','/')).name
  ok=p.is_file() and p.stat().st_size==m['bytes'] and sha(p)==m['sha256'] and m['runtimeSourceCommit']==plan['runtimeSourceCommit'] and m['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash']
  mods.append({'path':p.name,'ok':ok,'bytes':p.stat().st_size if p.exists() else None,'sha256':sha(p) if p.exists() else None})
 if len(mods)!=2 or not all(x['ok'] for x in mods): failures.append('runtime module archive joins')
 checks.append({'name':'runtime-module-archives','ok':not any(x=='runtime module archive joins' for x in failures),'modules':mods})
 # Re-run source-only verifier & tests is represented by archived controls; no execution from this script.
 controls=load(BUILD/'controls/source-tests.json'); verify_source_hash=sha(BUILD/'verify_source.py');
 # Independently bind all ten archived serializer files & shared source/control bytes.
 reuse=load(BUILD/'dependencies/serializer-reuse-bindings.json'); ser_bad=[]
 for row in reuse['files']:
  q=BUILD/'dependencies/serializer-actual-r2'/row['path'].replace('\\','/')
  if not q.is_file() or q.stat().st_size!=row['bytes'] or sha(q)!=row['sha256']: ser_bad.append(row['path'])
 if len(reuse['files'])!=10 or sha(BUILD/'dependencies/serializer-control-source.swift')!=reuse['controlSha256'] or sha(BUILD/'package/Sources/FactoryProbe/MetricsPayload.swift')!=reuse['sourceSha256'] or sha(BUILD/'dependencies/serializer-source-plan.json')!=reuse['recordedPlanSha256']: ser_bad.append('shared serializer/source bindings')
 if ser_bad: failures.append('serializer archive/source joins')
 checks.append({'name':'serializer-actual-archive','ok':not ser_bad,'files':len(reuse['files']),'controlSha256':sha(BUILD/'dependencies/serializer-actual-r2/control.json'),'exeSha256':sha(BUILD/'dependencies/serializer-actual-r2/serializer-control.exe')})
 if controls.get('exitCode')!=0 or controls.get('tests')!=13 or controls.get('result')!='OK': failures.append('source test receipt')
 checks.append({'name':'source-fault-controls','ok':not any(x=='source test receipt' for x in failures),'tests':controls.get('tests'),'exitCode':controls.get('exitCode'),'verifySourceSha256':verify_source_hash})
 return {'kind':'padding-window-diagnosis-actual-compile-independent-review','version':'1','decision':'CLEAR_ACTUAL_COMPILE_ONLY' if not failures else 'HOLD_ACTUAL_COMPILE','qualification':'compile-only; nativeParity=hold; frozenTupleBound=false','reviewScope':'offline six-file receipt/PE/source/runtime/archive audit; no compiler/native/remote action','buildStageSha256':sha(BUILD/'root-stage-manifest.json'),'actualReceiptSha256':sha(ACT/'observation.json'),'actualExeSha256':sha(ACT/'FactoryProbe.exe'),'actualReceiptPlanSha256':obs.get('planSha256'),'planSha256':sha(BUILD/'package/plan.json'),'sourceHash':obs.get('sourceHash'),'runtimeSourceCommit':obs.get('runtimeSourceCommit'),'runtimeSourceTreeHash':obs.get('runtimeSourceTreeHash'),'serializerControlSha256':'952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba','sixActualFiles':6,'compilerRuns':0,'nativeRuns':0,'remoteActions':0,'checks':checks,'failures':failures}
if __name__=='__main__': print(json.dumps(main(),indent=2,sort_keys=True))
