#!/usr/bin/env python3
"""Read-only source admission audit; no PowerShell, compiler, native or remote action."""
from __future__ import annotations
import hashlib, json, re, sys, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[5]
TARGET=ROOT/'factory/native/windows/stack-lifecycle-next-capture-v1'
BUILD=ROOT/'factory/native/windows/stack-lifecycle-next-build-v1'
V4=ROOT/'factory/native/windows/padding-settled-capture-v4'

def sha(p:Path)->str: return hashlib.sha256(p.read_bytes()).hexdigest()
def readj(p:Path): return json.loads(p.read_text(encoding='utf-8'))

def analyzer_stderr_gap():
    # Demonstrates analyzer accepts nonclosed/mismatched stderr while stdout is valid.
    sys.path.insert(0,str(TARGET)); import analyze_lifecycle
    with tempfile.TemporaryDirectory(prefix='stack-lifecycle-review-') as td:
        root=Path(td); stdout=b''; stderr=b'actual stderr bytes'; (root/'host.stdout.txt').write_bytes(stdout); (root/'host.stderr.txt').write_bytes(stderr)
        ident={'pid':7,'path':'x','startedAt':'t'}; h='0'*64; outsha=hashlib.sha256(stdout).hexdigest()
        outcome={'ownedIdentity':ident,'compileReceiptHash':h,'exeHash':h,'stdoutSha256':outsha,'stderrSha256':h,'rawStreams':[{'name':'stdout','destinationClosed':True},{'name':'stderr','destinationClosed':False}], 'rawHashesQualification':'unqualified','cleanup':{},'primaryError':''}
        timing={'ownedIdentity':ident,'compileReceiptHash':h,'exeHash':h,'stdoutSha256':outsha,'stderrSha256':h,'observations':[{'retainedHandle':1,'handlePid':7,'queryStartTicks':1,'hasExitedStartTicks':2,'hasExitedEndTicks':3,'queryEndTicks':4,'frequency':1,'phase':'test','kernelBefore':0,'kernelAfter':0,'getExitCodeSucceeded':True,'exitCode':0,'errors':[]}]}
        (root/'capture-outcome.json').write_text(json.dumps(outcome)); (root/'lifecycle-timing.json').write_text(json.dumps(timing))
        try: analyze_lifecycle.analyze(root)
        except Exception as e: return {'accepted':False,'error':str(e)}
        return {'accepted':True,'stderrFileSha256':sha(root/'host.stderr.txt'),'claimedStderrSha256':h,'stderrDestinationClosed':False}

def main():
    failures=[]; checks=[]
    manifest=readj(TARGET/'root-stage-manifest.json'); entries=manifest['files']
    if len(entries)!=24: failures.append(f'root manifest entries={len(entries)}, expected 24')
    for e in entries:
        p=ROOT/e['path']
        if not p.is_file(): failures.append(f'missing {e["path"]}'); continue
        if p.stat().st_size!=e['bytes'] or sha(p)!=e['hash'].removeprefix('sha256:'): failures.append(f'root ref drift {e["path"]}')
    checks.append({'name':'root-24-pins','ok':not failures,'count':len(entries),'stageSha256':sha(TARGET/'root-stage-manifest.json')})
    plan=readj(BUILD/'package/plan.json'); cp=readj(TARGET/'capture-plan.json')
    if sha(BUILD/'package/plan.json')!=cp['sourcePlanSha256'].removeprefix('sha256:'): failures.append('capture plan sourcePlan hash mismatch')
    if sha(BUILD/'package/plan.json')!=cp['compiledPlanSha256'].removeprefix('sha256:'): failures.append('capture plan compiledPlan hash mismatch')
    if cp['dispatch']['first']['count']!=1 or cp['dispatch']['retries'] is not False: failures.append('Count1/retry pin drift')
    checks.append({'name':'case-plan-lineage','ok':not any('capture plan' in x or 'Count1' in x for x in failures),'planSha256':sha(BUILD/'package/plan.json'),'case':plan['case']['id']})
    markers=readj(TARGET/'lifecycle-marker-source.json'); source=(BUILD/'package/Sources/FactoryProbe/main.swift').read_text()
    if markers['count']!=12 or len(markers['sourceCallsites'])!=12: failures.append('marker source count != 12')
    if sha(BUILD/'package/Sources/FactoryProbe/main.swift')!=markers['sourceSha256']: failures.append('marker source hash drift')
    for event in markers['sourceCallsites']:
        literal=event.replace('\\(','\\(')
        if event.endswith('\\(result)'):
            if event not in source: failures.append(f'missing dynamic marker source {event}')
        elif f'"{event}"' not in source: failures.append(f'missing marker source {event}')
    checks.append({'name':'marker-source-12','ok':not any('marker source' in x or 'marker' in x for x in failures),'count':markers['count'],'sourceSha256':markers['sourceSha256']})
    support=['cleanup.ps1','host-inputs.ps1','owned-close.ps1','pixels-background.ps1','stream-seal.ps1','verify-runtime-source.ps1']
    for name in support:
        if (TARGET/'support'/name).read_bytes()!=(V4/'support'/name).read_bytes(): failures.append(f'V4 helper drift {name}')
    checks.append({'name':'v4-helper-byte-parity','ok':not any('V4 helper' in x for x in failures),'helpers':support})
    runner=(TARGET/'capture-repeat.ps1').read_text(); coord=(TARGET/'coordinator.ps1').read_text(); pre=(BUILD/'preflight.ps1').read_text(); analyzer=(TARGET/'analyze_lifecycle.py').read_text()
    required={
      'runner-count1':'[ValidateSet(1)][int]$Count=1', 'runner-window-deadline':'AddSeconds(15)', 'runner-raw-drain':'$stdoutTask.Wait(5000)',
      'runner-stderr-drain':'$stderrTask.Wait(5000)', 'runner-original-cleanup':'Invoke-FactoryOwnedCleanup', 'runner-host-failclosed':"if(-not $validHost){throw 'Owned host output failed original validity predicate'}",
      'preflight-receipt':'Measured actual compile receipt/exe pins mandatory', 'preflight-argv':'Exact production compiler kind/release/GUI argv required',
      'preflight-exe':'Actual produced GUI exe binding mismatch', 'coordinator-fresh':'Fresh coordinator output required; retries disabled', 'same-handle':'$retainedTimingHandle=$p.Handle',
    }
    for name,needle in required.items():
        if needle not in (runner+coord+pre): failures.append(f'missing control {name}')
    if re.search(r'ValidateSet\([^)]*20',runner+coord): failures.append('Count20 control present')
    checks.append({'name':'runner-preflight-controls','ok':not any(x.startswith('missing control') or x=='Count20 control present' for x in failures),'required':list(required)})
    # Analyzer must only report observed raw markers; verify no source-list synthesis.
    if 'markers=[]' not in analyzer or 'markers.append' not in analyzer or 'sourceCallsites' in analyzer: failures.append('marker analyzer synthesis/source binding drift')
    checks.append({'name':'marker-observation-only','ok':not any('marker analyzer' in x for x in failures)})
    gap=analyzer_stderr_gap()
    if gap.get('accepted'): failures.append('analyzer accepts unclosed/mismatched stderr raw stream')
    checks.append({'name':'analyzer-stderr-closure-hash','ok':not gap.get('accepted'),'probe':gap})
    decision='HOLD_ANALYZER_RAW_CLOSURE_JOIN' if any('stderr' in f for f in failures) else ('CLEAR_SOURCE_ONLY_HOLD' if not failures else 'HOLD_SOURCE')
    return {'kind':'stack-lifecycle-next-capture-independent-review','version':'1','decision':decision,'qualification':'hold','reviewScope':'offline source/control/analyzer audit; no compiler/native/remote action','rootStageSha256':sha(TARGET/'root-stage-manifest.json'),'rootStageEntries':len(entries),'buildStageSha256':sha(BUILD/'root-stage-manifest.json'),'planSha256':sha(BUILD/'package/plan.json'),'mainSha256':sha(BUILD/'package/Sources/FactoryProbe/main.swift'),'markerCallsites':markers['count'],'nativeRuns':0,'compilerRuns':0,'remoteActions':0,'checks':checks,'failures':failures,'analyzerGap':'analyze_lifecycle.py:13-16 checks only stdout destinationClosed & hash; stderr closure/sealed state/bytes are never read or recomputed; timing/outcome stderr hash equality alone is forgeable.'}

if __name__=='__main__': print(json.dumps(main(),indent=2,sort_keys=True))
