"""Offline source-plan and single rolling-root transfer checks; no host actions."""
from __future__ import annotations
import copy, hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
LABELS = ('disabled', 'image', 'shapes.fill-stroke', 'text.bundled-font', 'toggle')
V5 = ROOT / 'factory/native/windows/remaining-five-hosts-v5'
ROLLING = r'D:\Claude\swiftright\.factory-work\hosts\remaining-pilot\package'
RESULTS = r'D:\Claude\swiftright\.factory-work\hosts\remaining-pilot\results\remaining-pilot-r2'
RUNTIME = '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
TREE = 'sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
RENDERER = 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
SERIALIZER = '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'

class PacketError(ValueError): pass
def digest(raw: bytes) -> str: return hashlib.sha256(raw).hexdigest()
def read_json(path: Path): return json.loads(path.read_bytes())

def _without_paths(value, label):
    value = copy.deepcopy(value)
    request = value['compileRequest']
    request.pop('packagePath', None); request.pop('scratchPath', None)
    return value

def verify(packet=None):
    packet = read_json(HERE/'rolling-plan.json') if packet is None else packet
    if packet.get('kind') != 'remaining-five-rolling-root-admission-source-packet-r2' or packet.get('version') != '0.1': raise PacketError('packet kind/version')
    if tuple(packet.get('sequence', ())) != LABELS or len(packet.get('plans', ())) != len(LABELS): raise PacketError('strict five-case sequence')
    if packet.get('rollingRoot') != ROLLING or packet.get('rollingResultsRoot') != RESULTS: raise PacketError('rolling roots')
    if packet.get('sourcePolicy') != {'compilerInvocations': 0, 'nativeCalls': 0, 'remoteCalls': 0, 'qualification': 'hold', 'mac20Witnesses': 'held exact source/case identities; no new capture claim', 'windowsPairs': 'held exact source/case identities; no new capture claim'}: raise PacketError('source-only boundary')
    tuple_pin = packet.get('canonicalTuple', {})
    if tuple_pin.get('id') != 'tuple11' or tuple_pin.get('rendererSha256') != RENDERER or tuple_pin.get('runtimeSourceCommit') != RUNTIME or tuple_pin.get('runtimeSourceTreeHash') != TREE or tuple_pin.get('serializerControlSha256') != SERIALIZER: raise PacketError('canonical tuple pin')
    stage = packet.get('sourceStageManifest', {})
    stage_path = ROOT / stage.get('path', '')
    if not stage_path.is_file() or stage.get('sha256') != 'sha256:'+digest(stage_path.read_bytes()): raise PacketError('source stage pin')
    seen_results = set(); rows=[]
    for row in packet['plans']:
        label=row.get('label')
        if label not in LABELS or row.get('planPath') != f'factory/native/windows/remaining-five-hosts-v6/root-admission-r2/plans/{label}.plan.json': raise PacketError('plan inventory')
        if row.get('sourcePlan') != f'factory/native/windows/remaining-five-hosts-v5/{label}/package/plan.json': raise PacketError('source plan path')
        src_path=ROOT/row['sourcePlan']; new_path=ROOT/row['planPath']
        if not src_path.is_file() or not new_path.is_file(): raise PacketError('plan file missing')
        if row.get('sourcePlanSha256') != digest(src_path.read_bytes()) or row.get('planSha256') != digest(new_path.read_bytes()): raise PacketError('plan hash')
        source=read_json(src_path); plan=read_json(new_path)
        expected=json.loads(json.dumps(source)); expected['compileRequest']['packagePath']=ROLLING; expected['compileRequest']['scratchPath']=ROLLING+'\\build-r2-20261011\\'+label+'\\scratch'
        if plan != expected: raise PacketError(f'{label}: non-path plan mutation')
        if plan['case'] != source['case'] or plan['sourceHash'] != source['sourceHash'] or plan['manifestHash'] != source['manifestHash'] or plan['sourceBindings'] != source['sourceBindings']: raise PacketError(f'{label}: witness/source binding drift')
        if plan['runtimeSourceCommit'] != RUNTIME or plan['runtimeSourceTreeHash'] != TREE or plan['rendererSha256'] != RENDERER or plan['executionEligible'] is not False or plan['frozenTupleBound'] is not False: raise PacketError(f'{label}: runtime/hold boundary')
        request=plan['compileRequest']
        if request['packagePath'] != ROLLING or request['scratchPath'] in seen_results or request['scratchPath'] == ROLLING: raise PacketError(f'{label}: package/scratch destination')
        seen_results.add(request['scratchPath'])
        if row.get('caseId') != plan['case']['id'] or row.get('caseHash') != plan['case']['hash'] or row.get('sourceHash') != plan['sourceHash'] or row.get('witnessManifestHash') != plan['manifestHash']: raise PacketError(f'{label}: packet join')
        result=row.get('resultPaths', {})
        if set(result) != {'preflight','compile','capture'} or any(not isinstance(v,str) or not v.startswith(RESULTS+'\\'+label+'\\') for v in result.values()): raise PacketError(f'{label}: result paths')
        rows.append({'label':label,'sourcePlanSha256':row['sourcePlanSha256'],'planSha256':row['planSha256'],'caseId':row['caseId'],'sourceHash':row['sourceHash'],'scratchPath':request['scratchPath'],'resultPaths':result})
    if len(seen_results) != 5: raise PacketError('scratch uniqueness')
    boundary=packet.get('transferBoundary', {})
    if boundary.get('destinationCount') != 1 or boundary.get('packageDestination') != ROLLING or boundary.get('overwrite') is not False or boundary.get('delete') is not False or boundary.get('order') != 'strict sequence only': raise PacketError('transfer boundary')
    return {'kind':'remaining-five-rolling-root-admission-source-check-r2','status':'PASS_SOURCE_ONLY','labels':list(LABELS),'rollingRoot':ROLLING,'planCount':5,'scratchCount':len(seen_results),'compilerInvocations':0,'nativeCalls':0,'remoteCalls':0,'qualification':'hold','rows':rows}

def main():
    packet=read_json(HERE/'rolling-plan.json'); baseline=verify(packet); controls=[]
    faults=[('five-package-roots', lambda p: p.update(rollingRoot=r'D:\Claude\swiftright\.factory-work\hosts\disabled\package')),
            ('source-hash', lambda p: p['plans'][0].update(sourceHash='0'*64)),
            ('reordered-sequence', lambda p: p.update(sequence=list(reversed(LABELS)))),
            ('renderer', lambda p: p['canonicalTuple'].update(rendererSha256='0'*64)),
            ('duplicate-scratch', lambda p: p['plans'][1]['resultPaths'].update(capture=p['plans'][0]['resultPaths']['capture']))]
    for name, mutate in faults:
        bad=copy.deepcopy(packet); mutate(bad)
        try: verify(bad)
        except PacketError: controls.append({'name':name,'rejected':True})
        else: raise PacketError('accepted fault: '+name)
    print(json.dumps({'baseline':baseline,'faultControls':controls},indent=2,sort_keys=True))
if __name__=='__main__': main()
