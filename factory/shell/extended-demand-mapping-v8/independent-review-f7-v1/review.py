from pathlib import Path
import sys,json,hashlib,copy
ROOT=Path(__file__).resolve().parents[4];P=ROOT/'factory/shell/extended-demand-mapping-v8';OUT=Path(__file__).resolve().parent
sys.path.insert(0,str(P));import verify_v8 as verifier;import test_mapping_v8 as tests
sha=lambda b:hashlib.sha256(b).hexdigest()
stage_raw=(P/'stage-manifest-v8.json').read_bytes();stage=json.loads(stage_raw)
if sha(stage_raw)!='3a4f1a2dc9e64a59bea3b6c0ca739a67a26106c745916091fbe9c3786d281f44':raise ValueError('Latest stage hash drift')
pins=[]
for x in stage['files']:
 b=(P/x['path']).read_bytes()
 if sha(b)!=x['sha256'] or len(b)!=x['bytes']:raise ValueError('Producer file drift '+x['path'])
 pins.append({'path':str(P/x['path']),'sha256':sha(b),'size':len(b)})
for x in stage['dependencies']:
 b=(ROOT/x['path']).read_bytes()
 if sha(b)!=x['sha256']:raise ValueError('Dependency drift '+x['path'])
 pins.append({'path':x['path'],'sha256':sha(b),'size':len(b)})
baseline=verifier.verify()
mutations=[('denominator-drift',lambda v:v.update(denominator=106)),('row-omission',lambda v:v['rows'].pop()),('promotion-fault',lambda v:v.update(registryPromotion=1)),('base-overlay-drift',lambda v:v.update(baseOverlaySha256='0'*64)),('registry-hash-drift',lambda v:v.update(registrySnapshotSha256='0'*64)),('resolved-fault',lambda v:v['rows'][0].update(fullDemandResolved=True)),('identity-claim-fault',lambda v:v['rows'][1].update(apiIdentityProven=True)),('disposition-drift',lambda v:v['rows'][0].update(disposition='resolved')),('evidence-text-drift',lambda v:v['rows'][0].update(requiredEvidence=['anything','anything'])),('boolean-count-fault',lambda v:v.update(newFullDemandResolutions=False))]
results=[tests.rejected(name,fn) for name,fn in mutations]
# Own isolated faults extend typed count & exact row/status barriers.
extra=[('boolean-denominator',lambda v:v.update(denominator=True)),('boolean-registry-zero',lambda v:v.update(registryPromotion=False)),('duplicate-held-row',lambda v:v['rows'].__setitem__(1,copy.deepcopy(v['rows'][0]))),('string-false-row',lambda v:v['rows'][0].update(fullDemandResolved='false')),('prior-disposition-drift',lambda v:v['rows'][0].update(priorDisposition='resolved')),('status-promotion',lambda v:v.update(status='qualified'))]
extras=[tests.rejected(name,fn) for name,fn in extra]
prior=json.loads(verifier.V7.read_bytes());current=json.loads((P/'mapping-v8-action-overlay.json').read_bytes());base=json.loads(verifier.V6.read_bytes())
by={r['rowKey']:r for r in prior['rows']};actual=[]
for r in current['rows']:
 fields={k:r[k] for k in ('demand','disposition','priorDisposition','requiredEvidence')}
 if any(r[k]!=by[r['rowKey']][k] for k in fields):raise ValueError('Independent held row drift')
 actual.append({'rowKey':r['rowKey'],**fields,'fullDemandResolved':r['fullDemandResolved'],'registryPromotion':r['registryPromotion'],'apiIdentityProven':r['apiIdentityProven']})
if len(base['remainingUnresolved'])!=5 or len(base['ambiguousRows'])!=3:raise ValueError('Independent base denominator drift')
# Source-only replay never runs producer generate/freeze or producer test main (writes controls).
report={'kind':'independent-extended-demand-v8-review-f7-v1','decision':'CLEAR-REQUIREMENTS-ONLY','producerStageHash':sha(stage_raw),'overlayHash':sha((P/'mapping-v8-action-overlay.json').read_bytes()),'verifierHash':sha((P/'verify_v8.py').read_bytes()),'pins':pins,'actualBaseline':baseline,'actualProducerControlReplay':results,'additionalOwnFaults':extras,'exactHeldRows':actual,'denominator':107,'unresolvedHeld':5,'ambiguousHeld':3,'fullDemandResolutions':0,'registryPromotion':0,'producerModifications':0,'compilerRuns':0,'nativeRuns':0,'scope':'Exact existing requirements/dispositions preserved; no API identity, complete demand coverage, registry eligibility or status promotion.'}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'decision':report['decision'],'producerFaults':len(results),'ownFaults':len(extras),'reportHash':sha((OUT/'report.json').read_bytes())}))
