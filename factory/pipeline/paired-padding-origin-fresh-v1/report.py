#!/usr/bin/env python3
"""Fresh Mac-origin report; original envelopes remain authoritative bytes."""
from __future__ import annotations
import argparse, hashlib, json, tempfile
from pathlib import Path
from factory.core.artifacts import canonical_hash
from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError
from factory.reports.report import build_report

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
FRESH=ROOT/'factory/oracle/mac/padding-origin-fresh-v1/actual'
EVIDENCE=FRESH/'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258'
PINS=HERE/'source-pins.json'
CASE_PATH=ROOT/'factory/pipeline/gate-pilot/seed-cases.json'
CFG=ROOT/'factory/pipeline/paired-padding-settled-v2/source-config.json'
ACCEPT=ROOT/'factory/pipeline/inputs/acceptance-candidate.json'
REG=ROOT/'factory/registry/evidence/block-registry.json'
PEER=ROOT/'factory/native/windows/padding-settled-capture-v4/actual-repeat-review-v1/report.json'
GATE_PLAN=ROOT/'factory/pipeline/gate-pilot/gate-results.json'
GATE_CASES=ROOT/'factory/pipeline/inputs/cases.json'
GATE_TUPLE=ROOT/'factory/pipeline/inputs/observed-tuple.json'
MANIFESTS=ROOT/'factory/pipeline/manifests'

def sha(p): return 'sha256:'+hashlib.sha256(Path(p).read_bytes()).hexdigest()
def fail(c,m):
    if not c: raise ValueError(m)
def load(p): return json.loads(Path(p).read_text())
def strict_reader(mac_map=None):
    return ArchiveByteReader(mac_roots=[ROOT,FRESH],mac_path_map=mac_map or {})
def read_json(r,p,pin=None):
    raw=r(capture={'platform':'macos'},reference={'path':str(Path(p).resolve()),'sha256':pin or sha(p)})
    return raw,json.loads(raw.decode('utf-8-sig'))
def source_pins(r):
    d=load(PINS); fail(d.get('schema')=='paired-padding-origin-fresh-source-pins-v1','source pin schema changed')
    for key,rel in {'captureIndex':'capture-index.json','verification':'verification.json'}.items():
        actual=FRESH/rel; raw,_=read_json(r,actual,d['files'][key]); fail(sha(actual)==d['files'][key],f'{key} changed')
    for key,rel in {'rootRunPlan':'root-run-plan.json','rootProcess':'root-process.json','rootOwnedProcess':'root-owned-process.json'}.items():
        actual=ROOT/'factory/oracle/mac/padding-origin-fresh-v1'/rel; raw=r(capture={'platform':'macos'},reference={'path':str(actual.resolve()),'sha256':d['files'][key]}); fail(sha(actual)==d['files'][key],f'{key} changed')
    for key,rel in {'originReaderConfig':'origin-reader-config.json','originArchiveManifest':'origin-archive-manifest.json','summary':'summary.json','originSummary':'origin-summary.json'}.items():
        actual=EVIDENCE/rel; raw=r(capture={'platform':'macos'},reference={'path':str(actual.resolve()),'sha256':d['files'][key]}); fail(sha(actual)==d['files'][key],f'{key} changed')
    return d

def case_inputs(r):
    _,rows=read_json(r,CASE_PATH); case=next(x for x in rows if x['id']=='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258')
    _,cfg=read_json(r,CFG); _,accept=read_json(r,ACCEPT)
    fail(canonical_hash(case)==cfg['case']['sha256'],'case hash drift')
    return case,cfg,accept

def captures(r,pins,case):
    from factory.pipeline import workflow
    result=workflow.collect([case],[EVIDENCE],reader=r)
    fail(not result['diagnostics'],f'fresh collection diagnostics: {result["diagnostics"][:1]}')
    rows=sorted(result['captures'],key=lambda x:x['meta']['run']); fail(len(rows)==20,'fresh capture denominator changed')
    refs=[]
    for row in rows:
        i=row['meta']['run']; fail(row['case']=={'id':case['id'],'hash':canonical_hash(case)},'capture case binding changed')
        fail(row['id'].endswith(f'.macos.run-{i:03d}'),'capture ID/run binding changed')
        refs.append({'run':i,'id':row['id'],'capture':sha(EVIDENCE/f'run-{i:03d}/capture.json'),'externalAX':sha(EVIDENCE/f'run-{i:03d}/external-ax.raw.json'),'clock':sha(EVIDENCE/f'run-{i:03d}/clock.json')})
        expected=pins['runs'][f'{i:03d}']; fail(refs[-1]['capture']==expected['capture.json'],'capture pin changed'); fail(refs[-1]['externalAX']==expected['external-ax.raw.json'],'AX pin changed'); fail(refs[-1]['clock']==expected['clock.json'],'clock pin changed')
    return rows,refs

def origin_proof(origin_reader,rows):
    results=[]; failures=[]
    for row in rows:
        local=[]; local_fail=[]
        def check(v):
            if isinstance(v,dict):
                if set(v).issuperset({'path','sha256','bytes'}):
                    try:
                        raw=origin_reader(capture={'platform':'macos'},reference={'path':v['path'],'sha256':v['sha256'],'bytes':v['bytes']})
                        fail(len(raw)==v['bytes'],f'origin byte count {v["path"]}')
                        local.append(v['path'])
                    except Exception as exc:
                        local_fail.append({'path':v.get('path'),'error':str(exc)})
                else:
                    for x in v.values(): check(x)
            elif isinstance(v,list):
                for x in v: check(x)
        check(row['meta']['conditions']['macOrigin'])
        failures.extend({'captureId':row['id'],**x} for x in local_fail)
        results.append({'captureId':row['id'],'descriptorCount':len(local),'verified':not local_fail})
    return results,failures

def windows_adjunct(r):
    raw,p=read_json(r,PEER); return {'status':'quarantine-adjunct','requestedRuns':p.get('requestedRuns'),'startedRuns':p.get('startedRuns'),'eligiblePeerRows':p.get('priorHostErrorFreeRawCaptures'),'invalidHostRuns':p.get('priorHostErrorRuns'),'deadlineRun':p.get('failedRun'),'notStarted':p.get('notStarted'),'typedCaptureCount':0,'rawHash':sha(PEER)}

def fault_controls(artifact_reader, origin_reader, rows, case):
    result={'baseline-fresh-origin20':'passed'}
    class BadOrigin:
        def __call__(self, *, capture, reference):
            raw=origin_reader(capture=capture, reference=reference)
            if isinstance(reference,dict) and reference.get('path','').endswith('CaptureHost.swift'):
                return raw+b'\n'
            return raw
    _,bad=origin_proof(BadOrigin(),rows)
    result['malformed-origin-bytes']='rejected' if bad else 'accepted-BUG'
    class BadArtifact:
        def __call__(self, *, capture, reference):
            raw=artifact_reader(capture=capture, reference=reference)
            if isinstance(reference,dict) and reference.get('path','').endswith('/run-001/capture.json'):
                return raw+b'\n'
            return raw
    from factory.pipeline import workflow
    try:
        out=workflow.collect([case],[EVIDENCE],reader=BadArtifact())
        result['malformed-artifact-bytes']='rejected' if len(out.get('captures',[])) != 20 else 'accepted-BUG'
    except Exception:
        result['malformed-artifact-bytes']='rejected'
    class MissingOrigin:
        def __call__(self, *, capture, reference):
            if isinstance(reference,dict) and reference.get('path','').endswith('CaptureHost.swift'):
                raise ArchiveReadError('synthetic missing origin')
            return origin_reader(capture=capture, reference=reference)
    _,missing=origin_proof(MissingOrigin(),rows)
    result['missing-origin-reader']='rejected' if missing else 'accepted-BUG'
    result['windows-absence-not-capture']='observed'
    return result

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--output',type=Path,default=HERE/'root-replay-r1'); a=ap.parse_args()
    artifact_reader=strict_reader(); pin=source_pins(artifact_reader); case,cfg,accept=case_inputs(artifact_reader)
    origin_cfg=load(EVIDENCE/'origin-reader-config.json'); origin_reader=strict_reader(origin_cfg['macPathMap'])
    rows,refs=captures(artifact_reader,pin,case); origins,origin_failures=origin_proof(origin_reader,rows)
    fail(not origin_failures,f'origin proof failures: {origin_failures[:1]}')
    from factory.comparison import compare_case
    comparison=compare_case(case,rows,acceptance_config=accept,holds=['Windows source/origin capture unavailable'])
    out=a.output; out.mkdir(parents=True,exist_ok=True)
    demand={'blockCapabilities':{case['block']:['layout','accessibility-provider']},'journeys':[],'unmappedDemands':[]}
    registry=load(REG); f9=build_report(registry,[case],rows,[comparison],out/'f9',demand)
    gate_dir=out/'workflow-gate-evidence'; gate_dir.mkdir(parents=True,exist_ok=True)
    from factory.pipeline import workflow
    gate=workflow.gate_evidence(gate_dir,GATE_PLAN,GATE_CASES,[EVIDENCE],GATE_TUPLE,ACCEPT,MANIFESTS,origin_reader=origin_reader,artifact_reader=artifact_reader)
    gate_reports=gate.get('gateResults',[]); gate_issues=[i for x in gate_reports for i in x.get('report',{}).get('issues',[]) if isinstance(x,dict)]
    peer=windows_adjunct(artifact_reader)
    report={'schema':'paired-padding-origin-fresh-observational-report-v1','status':'fresh-mac-origin-verified-partial','candidateOnly':True,'identity':{'block':case['block'],'actualCase':{'id':case['id'],'hash':canonical_hash(case)},'historicalCaseTuple':case['tuple'],'historicalTupleBinding':'sr1-observed-r09; preserved as template only','windowsSourceBinding':{'rendererSha256':'sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93','runtimeSourceCommit':'37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b','status':'separate source plan; not migrated into Mac tuple'},'source':cfg['source']},'macOS':{'count':len(rows),'captureIds':[x['id'] for x in rows],'captures':rows,'readerRefs':refs,'originProof':{'verifiedCount':sum(x['verified'] for x in origins),'descriptorCounts':origins,'readerConfigHash':pin['files']['originReaderConfig'],'archiveManifestHash':pin['files']['originArchiveManifest']}},'windows':peer,'qualification':{'originVerified20':sum(x['verified'] for x in origins)==20,'schemaCollected20':True,'parityQualified':False,'semantic':'held-windows-origin-proof','timing':'raw-only','nativeParity':'held','pixelParity':'held','promotion':'held'},'integration':{'artifactReader':'repo-root+fresh-actual-root ArchiveByteReader','originReader':'fresh origin-reader-config mapped ArchiveByteReader','workflowCollect':{'status':'collected','count':20},'workflowGateEvidence':{'status':gate.get('status'),'gateIssueCount':len(gate_issues)},'f9ReportBuilder':{'status':'observational','paths':f9},'gateMissingOriginExactCode':sum('mac-origin:missing-origin' in i for i in gate_issues),'encounteredCaptureIds':len(rows),'windowsAbsenceControl':{'typedWindowsCaptures':0,'peerEligibleAdjunct':peer['eligiblePeerRows'],'status':'held-no-windowsExitProof'}}}
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    (out/'fault-controls.json').write_text(json.dumps(fault_controls(artifact_reader,origin_reader,rows,case),indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':report['status'],'macRuns':20,'originVerified':report['macOS']['originProof']['verifiedCount'],'windowsTyped':0,'gate':gate.get('status')},sort_keys=True))
if __name__=='__main__': main()
