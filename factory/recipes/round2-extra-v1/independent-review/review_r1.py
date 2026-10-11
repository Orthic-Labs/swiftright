#!/usr/bin/env python3
"""Independent offline review of frozen Round2 candidate recipe packet."""
from __future__ import annotations
import hashlib, json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKET = ROOT / 'factory' / 'recipes' / 'round2-extra-v1'
CAT = ROOT / 'factory' / 'catalogue' / 'evidence' / 'catalogue.json'
EXPECTED_BLOCKS = [
 'swiftui.popover', 'swiftui.animation.spring-interruption',
 'swiftui.text-field-ime', 'swiftui.environment-font-color-scheme',
 'swiftui.context-menu',
]
JOIN_COUNTS = {
 'swiftui.popover': 1,
 'swiftui.animation.spring-interruption': 2,
 'swiftui.text-field-ime': 1,
 'swiftui.environment-font-color-scheme': 3,
 'swiftui.context-menu': 1,
}
SHA = {
 'factory/recipes/round2-extra-v1/root-stage-manifest.json': '42969de7d3810b8c5d174af990bc3cf5f35f17762c53f1f17fe265d17a22a304',
 'factory/recipes/round2-extra-v1/registry-source-join.json': '71141aa8fb954ea3bcfb307b3b431fbb953ddb7e117967dc7ee37e1c1603353a',
 'factory/recipes/round2-extra-v1/validation.json': '440966690da58b2eade55247b8ad9cb2d1ebe6f8336c9a13749154ebf8ce0fba',
 'factory/recipes/round2-extra-v1/native-requirements.json': '2610d49e05a93ded6bea7e3bd903140ddb393f5ff778a4278b25ff6fd8218270',
 'factory/registry/round2-extra-v1/candidate-manifest.json': 'e7366d2f526577c240343155e36d353a8c0be6bba0c2542a66dfba684585febf',
 'factory/registry/round2-extra-v1/stage-manifest.json': 'e200fa92e234ab9ce9ba649b2bd3300fedc8ee6ecf1d92b131d0acf6d69c8a77',
 'factory/catalogue/evidence/catalogue.json': '740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270',
}


def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def load(p: Path):
    return json.loads(p.read_bytes())

def fail(msg):
    raise AssertionError(msg)

def check_stage():
    stage = load(PACKET / 'root-stage-manifest.json')
    if stage.get('scope') != 'candidate-source-only; no active registry/data mutation': fail('stage scope')
    for row in stage['files']:
        p = ROOT / row['path']
        if not p.is_file(): fail('missing staged file '+row['path'])
        if digest(p) != row['sha256'] or p.stat().st_size != row['size']: fail('stage drift '+row['path'])
    return len(stage['files'])

def check_recipes():
    from factory.core.artifacts import validate_artifact
    data = sorted((PACKET/'data').glob('*.json'))
    if len(data) != 5: fail('recipe count')
    rows = {}
    positive = negative = 0
    for p in data:
        recipe = load(p)
        validate_artifact(recipe)
        block = recipe.get('block')
        if block not in EXPECTED_BLOCKS or block in rows: fail('recipe block '+str(block))
        if recipe['id'] != block+'.recipe': fail(block+' id')
        if recipe['provenance']['review']['decision'] != 'candidate': fail(block+' review decision')
        if recipe['provenance'].get('inputs') != [{'id':'swiftui-pilot-round2-extra-candidates-v1','hash':'sha256:e7366d2f526577c240343155e36d353a8c0be6bba0c2542a66dfba684585febf'}]: fail(block+' candidate input')
        if not recipe['assertions'] or any(a.get('observability') != 'blocked' for a in recipe['assertions']): fail(block+' observability')
        if len(recipe['witnesses']) != 1 or len(recipe['negativeCases']) != 1: fail(block+' witness cardinality')
        w = recipe['witnesses'][0]; wp = PACKET/'witnesses'/(w['id']+'.swift')
        if not wp.is_file() or 'sha256:'+digest(wp) != w['sourceHash'] or w.get('resources') != [{'id':w['id']+'.swift','hash':w['sourceHash']}]: fail(block+' witness binding')
        n = recipe['negativeCases'][0]; np = PACKET/'witnesses'/(n['id']+'.swift')
        if not np.is_file() or 'sha256:'+digest(np) != n.get('sourceHash'): fail(block+' negative binding')
        if n['mode'] != 'must-not-compile': fail(block+' negative mode')
        if recipe.get('statefulSequences') and any(not seq for seq in recipe['statefulSequences']): fail(block+' empty sequence')
        positive += 1; negative += 1; rows[block] = recipe
    if set(rows) != set(EXPECTED_BLOCKS): fail('recipe membership')
    return rows, positive, negative

def check_join(rows):
    candidate = load(PACKET/'dependencies/registry-candidate-manifest.json')
    if digest(PACKET/'dependencies/registry-candidate-manifest.json') != SHA['factory/registry/round2-extra-v1/candidate-manifest.json']: fail('candidate raw digest')
    if candidate.get('activeRegistryMutation') is not False: fail('candidate promotion gate')
    byblock = {b['id']: b for b in candidate['blocks']}
    cat = load(CAT); byusr = {x['usr']: x for x in cat['symbols']}
    join = load(PACKET/'registry-source-join.json')
    if {r['block'] for r in join['rows']} != set(EXPECTED_BLOCKS): fail('join membership')
    for row in join['rows']:
        block = row['block']; recipe = rows[block]
        if len(row['selectedSourceSymbols']) != JOIN_COUNTS[block]: fail(block+' selected count')
        if row['semanticDependencies'] != [] or row['registryPromotion'] is not False or row['nativeQualification'] is not False: fail(block+' promotion/deps')
        if row['recipeHash'] != 'sha256:'+digest(PACKET/'data'/(block+'.json')): fail(block+' recipe hash')
        if row['witnessHash'] != recipe['witnesses'][0]['sourceHash']: fail(block+' witness join')
        expected = [byblock[block]['symbols'][i] for i in range(JOIN_COUNTS[block])]
        if row['selectedSourceSymbols'] != expected: fail(block+' source selector join')
        for sym in row['selectedSourceSymbols']:
            if sym['selector'].removeprefix('usr:') not in byusr: fail(block+' unknown USR')
            item = byusr[sym['selector'].removeprefix('usr:')]
            if item['path'] != sym['path'] or item['status'] != sym['catalogueStatus']: fail(block+' catalogue source join')
    return len(join['rows']), sum(len(r['selectedSourceSymbols']) for r in join['rows'])

def check_validation(rows):
    v = load(PACKET/'validation.json')
    if len(v['recipes']) != 5 or sum(len(r['descriptors']) for r in v['recipes']) != 19 or len(v['faultControls']) != 28: fail('validation counts')
    if v['compilerRuns'] != 0 or v['nativeRuns'] != 0 or v['measurementTuple'] is not None: fail('execution claims')
    if not all(c.get('rejected') is True and c.get('syntheticMutation') is True for c in v['faultControls']): fail('fault receipts')
    if any(r['block'] not in rows or r['generatorHold'] != "unsupported block '"+r['block']+"'" or r['compilerRuns'] != 0 or r['nativeRuns'] != 0 or r['measurementTuple'] is not None for r in v['recipes']): fail('held projection')
    return len(v['recipes']), sum(len(r['descriptors']) for r in v['recipes']), len(v['faultControls'])

def check_native():
    n = load(PACKET/'native-requirements.json')
    if n.get('measurementTuple') is not None or n.get('nativeCapabilityClaims') is not False or n.get('goldenPromotion') is not False: fail('native top-level gate')
    req = {r['block']:r for r in n['requirements']}
    if set(req) != set(EXPECTED_BLOCKS): fail('native requirements membership')
    for block,r in req.items():
        if r.get('qualified') is not False or r.get('projectionOnly') is not True or r.get('providerSubstitution') != 'forbidden': fail(block+' native gate')
    return len(req)

def main():
    for path,h in SHA.items():
        p=ROOT/path
        if digest(p)!=h: fail('pinned hash drift '+path)
    files=check_stage(); rows,pos,neg=check_recipes(); joins,selected=check_join(rows); recs,projections,faults=check_validation(rows); native=check_native()
    result={'status':'independent-source-review-pass','scope':'offline source/schema/projection only','producerStageSha256':SHA['factory/recipes/round2-extra-v1/root-stage-manifest.json'],'producerJoinSha256':SHA['factory/recipes/round2-extra-v1/registry-source-join.json'],'producerValidationSha256':SHA['factory/recipes/round2-extra-v1/validation.json'],'candidateRegistrySha256':SHA['factory/registry/round2-extra-v1/candidate-manifest.json'],'counts':{'stagedFiles':files,'recipes':recs,'positiveSwiftSources':pos,'negativeSwiftSources':neg,'projections':projections,'faultControls':faults,'joinRows':joins,'selectedUSRs':selected,'nativeRequirementRows':native},'holds':['no compiler/typecheck execution','no native execution','no measurement tuple','F4 active whitelist rejects all five blocks','no registry promotion or semantic dependency inference'],'checks':['stage hashes/sizes','schema validation','witness/negative byte hashes','candidate manifest membership/status','exact USR/source joins','projection and fault receipt counts','native requirement hold flags']}
    out=PACKET/'independent-review'/'report-r1.json'; out.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n'); print(json.dumps(result,sort_keys=True))
if __name__=='__main__': main()
