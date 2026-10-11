"""Focused offline byte-input & report contract review; zero captures."""
from pathlib import Path
from copy import deepcopy
import hashlib,json,importlib.util,sys
from collections import Counter
ROOT=Path(__file__).resolve().parents[4]; HERE=Path(__file__).resolve().parent; PACKET=HERE.parent
sys.dont_write_bytecode=True
sys.path.insert(0,str(ROOT))

def pin(path):
    raw=path.read_bytes();return {'path':str(path.relative_to(ROOT)),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}

def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def run():
    stage_path=PACKET/'stage-manifest.json'
    assert pin(stage_path)['sha256']=='3e67da2930d27bed32e31c0288906b0a2515135ff610d61490f01a119a8cdb50'
    stage=json.loads(stage_path.read_bytes())
    for row in stage['files']+stage['sourceAndInputRefs']:
        assert pin(ROOT/row['path'])==row,row['path']
    adapter=module(ROOT/'factory/shell/report_demand.py','independent_report_demand')
    renderer=module(ROOT/'factory/reports/report.py','independent_report_renderer')
    paths=[ROOT/'factory/shell/demand.json',ROOT/'factory/registry/manifest.json',ROOT/'factory/registry/evidence/block-registry.json',PACKET/'crosswalk.json']
    raw=[p.read_bytes() for p in paths];objects=[json.loads(x) for x in raw]
    d,m,r,c=objects; actual=adapter.build_report_demand(*raw)
    assert actual['integration']['mappingCount']==10
    assert len(actual['journeys'])==26 and len(actual['unmappedDemands'])==107
    assert actual['unmappedDemands']==d['unmapped_demands']
    assert actual['blockCapabilities']=={} and actual['integration']['capabilityMapping']=='none'
    assert all(row['registry_block_id'] is None for row in actual['unmappedDemands'])
    assert Counter(x['status'] for x in actual['unmappedDemands'])=={'unmapped':61,'source_inventory_only':46}
    for row,source in zip(actual['journeys'],d['journey_demands']):
        assert row=={'id':source['journey_id'],'name':source['journey_id'],'blocks':[adapter.REVIEWED_MAPPING[x] for x in source['pilot_blocks']]}
    for key,data in zip(['f12DemandSha256','f2ManifestSha256','blockRegistrySha256','crosswalkSha256'],raw):assert actual['integration'][key]==hashlib.sha256(data).hexdigest()
    controls=[];fixtures=HERE/'fixtures';fixtures.mkdir(exist_ok=True)
    def fault(label,index,mutate):
        values=deepcopy(objects);mutate(values[index]);inputs=list(raw);inputs[index]=(json.dumps(values[index],indent=2)+'\n').encode();(fixtures/(label+'.json')).write_bytes(inputs[index])
        try: adapter.build_report_demand(*inputs); rejected=False;reason=None
        except (ValueError,TypeError) as e:rejected=True;reason=str(e)
        controls.append({'fault':label,'rejected':rejected,'reason':reason,'fixture':pin(fixtures/(label+'.json'))});assert rejected,label
    fault('omittedMapping',3,lambda x:x['mappings'].pop())
    fault('misboundMapping',3,lambda x:x['mappings'][0].update(registryBlockId='swiftui.image'))
    fault('duplicateMapping',3,lambda x:x['mappings'].append(deepcopy(x['mappings'][0])))
    fault('staleDemandRef',3,lambda x:x['sourceRefs']['demand'].update(sha256='0'*64))
    fault('misboundManifestPath',3,lambda x:x['sourceRefs']['registryManifest'].update(path='wrong.json'))
    fault('staleConsumedDemandObject',0,lambda x:x['journey_demands'][0].update(journey_id='poisoned'))
    fault('omittedJourney',0,lambda x:x['journey_demands'].pop())
    fault('duplicateJourney',0,lambda x:x['journey_demands'].append(deepcopy(x['journey_demands'][0])))
    fault('promotedExtendedDemand',0,lambda x:x['unmapped_demands'][0].update(registry_block_id='swiftui.image',status='pass'))
    fault('omittedCuratedTarget',1,lambda x:x['blocks'].pop())
    fault('duplicateRegistryTarget',2,lambda x:x['blocks'].append(deepcopy(x['blocks'][0])))
    fault('omittedRegistryTarget',2,lambda x:x['blocks'].pop())
    poisoned=deepcopy(objects);old=poisoned[0]['journey_demands'][0]['journey_id'];poisoned[0]['journey_demands'][0]['journey_id']=old+'.poisoned'
    for row in poisoned[0]['unmapped_demands']:
        if row.get('journey_id')==old:row['journey_id']=old+'.poisoned'
    (fixtures/'priorExactPoisonedDemand.json').write_text(json.dumps(poisoned[0],indent=2)+'\n')
    try:adapter.build_report_demand(*poisoned);rejected=False
    except (ValueError,TypeError):rejected=True
    assert rejected;controls.append({'fault':'callerParsedPoisonedObjects','rejected':True,'fixture':pin(fixtures/'priorExactPoisonedDemand.json')})
    try:adapter.build_report_demand(*raw,demand_sha256=hashlib.sha256(raw[0]).hexdigest());rejected=False
    except (ValueError,TypeError):rejected=True
    assert rejected;controls.append({'fault':'callerAssertedHash','rejected':True})
    normalized={'blockCapabilities':{r['blocks'][0]['id']:['existing-capability']},'journeys':[{'id':'legacy','name':'Legacy journey','blocks':[r['blocks'][0]['id']]}]}
    rendered=renderer.build_report(r,[],[],[],HERE/'normalized-compatibility',normalized)
    text=Path(rendered['markdown']).read_text();assert '| Legacy journey | 1 | 0 | 1 |' in text and 'existing-capability' in text
    offline=PACKET/'evidence/current-blocked-report-v4'
    summary=json.loads((offline/'pilot-summary.json').read_bytes()); verdicts=json.loads((offline/'verdicts.json').read_bytes()); captures=json.loads((offline/'captures.json').read_bytes());adapted=json.loads((offline/'report-demand.json').read_bytes())
    assert adapted==actual and summary['caseDenominator']==81 and summary['nativeCaptureCount']==200 and len(summary['primaries'])==10 and summary['parityGranted'] is False
    assert all(p['parity']=='held' and p['qualification']=='unqualified' and p['nativeCaptureCounts']=={'macos':20} for p in summary['primaries'])
    assert summary['verdictCounts']=={'blocked':81} and len(verdicts)==81 and len(captures)==200
    assert all(c['platform']=='macos' for c in captures)
    dashboard=(offline/'report/index.md').read_text();assert '**Passing:** 0' in dashboard and '**Blocked:** 10' in dashboard and 'Unmapped extended demands (107)' in dashboard and 'No capability mapping supplied' in dashboard
    refs=[ROOT/'factory/shell/report_demand.py',ROOT/'factory/pipeline/workflow.py',ROOT/'factory/reports/report.py',ROOT/'factory/tools/canonical_json.py',*paths]
    refs.extend(p for p in sorted(offline.rglob('*')) if p.is_file())
    refs.extend(ROOT/row['path'] for row in stage['files']+stage['sourceAndInputRefs'])
    refs.append(stage_path)
    refs=list(dict.fromkeys(refs))
    report={'kind':'independent-f12-f9-review-v1','decision':'CLEAR','sourceByteBinding':'Public adapter parses & hashes exact raw bytes; workflow passes same once-read bytes; parsed-object/callerhash fault rejected.','counts':{'crosswalkTargets':10,'journeys':26,'extendedNullUnchanged':107,'fixedCases':81,'MacCaptures':200,'blockedPrimaries':10,'parityGranted':False},'controls':controls,'producerStage':pin(stage_path),'producerStageFilesVerified':len(stage['files']),'producerStageSourceRefsVerified':len(stage['sourceAndInputRefs']),'normalizedF9Compatibility':True,'noInferredCapabilitiesDependenciesOrProgress':True,'repairedPriorFinding':'Prior public parsed-object/hash API admitted navigation.poisoned while claiming actual45c483 sourcehash; byte-only API closes that boundary.','references':[pin(p) for p in refs],'scope':{'captureReruns':0,'GUI':0,'Dell':0,'productionEdits':0,'Git':0}}
    (HERE/'findings.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'decision':report['decision'],'controls':len(controls),'report':pin(HERE/'findings.json')},indent=2))

if __name__=='__main__':run()
