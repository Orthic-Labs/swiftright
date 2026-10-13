#!/usr/bin/env python3
"""Generate held Round2 source probes without compiler/native execution."""
from __future__ import annotations
import argparse, hashlib, json, os, re, sys, tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PACKET = ROOT / 'factory' / 'recipes' / 'round2-extra-v1'
DEFAULT_CONFIG = Path(__file__).with_name('config.json')
EXPECTED = {
 'candidate': ('factory/recipes/round2-extra-v1/dependencies/registry-candidate-manifest.json','e7366d2f526577c240343155e36d353a8c0be6bba0c2542a66dfba684585febf'),
 'join': ('factory/recipes/round2-extra-v1/registry-source-join.json','71141aa8fb954ea3bcfb307b3b431fbb953ddb7e117967dc7ee37e1c1603353a'),
 'validation': ('factory/recipes/round2-extra-v1/validation.json','440966690da58b2eade55247b8ad9cb2d1ebe6f8336c9a13749154ebf8ce0fba'),
 'native': ('factory/recipes/round2-extra-v1/native-requirements.json','2610d49e05a93ded6bea7e3bd903140ddb393f5ff778a4278b25ff6fd8218270'),
 'catalogue': ('factory/catalogue/evidence/catalogue.json','740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270'),
}
BLOCKS = ('swiftui.popover','swiftui.animation.spring-interruption','swiftui.text-field-ime','swiftui.environment-font-color-scheme','swiftui.context-menu')
DESCRIPTOR_COUNTS = {'swiftui.popover':3,'swiftui.animation.spring-interruption':4,'swiftui.text-field-ime':3,'swiftui.environment-font-color-scheme':6,'swiftui.context-menu':3}
IMPORTS = '#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n'
_ID = re.compile(r'^[a-z][a-z0-9._/-]{1,159}$')

class GenerationError(ValueError): pass

def digest_bytes(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def sha256(data: bytes) -> str: return 'sha256:' + digest_bytes(data)
def canon(value: Any) -> bytes: return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',',':'))+'\n').encode()
def read_json(path: Path):
    raw=path.read_bytes()
    try: value=json.loads(raw)
    except json.JSONDecodeError as e: raise GenerationError(f'invalid JSON {path}: {e}') from e
    return value,raw

def safe_id(value: str) -> str:
    if not isinstance(value,str) or not _ID.fullmatch(value) or any(x in {'.','..'} for x in value.split('/')): raise GenerationError(f'unsafe case id {value!r}')
    return value.replace('/','_')

def inside(path: Path, root: Path) -> Path:
    p=Path(os.path.abspath(path)); r=Path(os.path.abspath(root))
    if not p.is_relative_to(r): raise GenerationError(f'path escapes root: {path}')
    if p.is_symlink(): raise GenerationError(f'symlink input: {path}')
    return p

def load_packet(config_path: Path = DEFAULT_CONFIG) -> dict[str,Any]:
    config, config_raw=read_json(config_path)
    if config.get('kind')!='round2-extra-f4-source-config' or config.get('version')!='0.1': raise GenerationError('invalid F4 config kind/version')
    if config.get('expectedBlocks') != list(BLOCKS): raise GenerationError('config block order/membership drift')
    policy=config.get('sourcePolicy',{})
    if policy.get('executionEligible') is not False or policy.get('compileRuns') != 0 or policy.get('nativeRuns') != 0 or policy.get('registryPromotion') is not False: raise GenerationError('execution/promotion policy')
    for block in BLOCKS:
        channels=config.get('unsupportedObservability',{}).get(block)
        if not isinstance(channels,dict) or not channels: raise GenerationError(f'missing unsupported observability {block}')
    loaded={}
    for name,(rel,expected) in EXPECTED.items():
        p=ROOT/rel; value,raw=read_json(p)
        if digest_bytes(raw)!=expected: raise GenerationError(f'{name} frozen input hash drift')
        loaded[name]=(value,raw,p)
    candidate=loaded['candidate'][0]
    if candidate.get('activeRegistryMutation') is not False or candidate.get('status')!='held-source-bound-candidates': raise GenerationError('candidate is not held')
    blocks=candidate.get('blocks')
    if not isinstance(blocks,list) or [x.get('id') for x in blocks] != list(BLOCKS): raise GenerationError('candidate block membership')
    for b in blocks:
        if b.get('registryPromotion') is not False or b.get('coverageStatus')!='identity-only' or b.get('nativeCoverage')!='unsupported' or b.get('semanticDependencies') != []: raise GenerationError(f'candidate promotion/dependency gate {b.get("id")}')
    join=loaded['join'][0]
    if {x.get('block') for x in join.get('rows',[])} != set(BLOCKS): raise GenerationError('source join membership')
    validation=loaded['validation'][0]
    if validation.get('compilerRuns') != 0 or validation.get('nativeRuns') != 0 or validation.get('measurementTuple') is not None: raise GenerationError('validation execution claim')
    native=loaded['native'][0]
    if native.get('measurementTuple') is not None or native.get('nativeCapabilityClaims') is not False or native.get('goldenPromotion') is not False: raise GenerationError('native claim')
    packet={'config':config,'configRaw':config_raw,'candidate':candidate,'candidateRaw':loaded['candidate'][1],'join':join,'validation':validation,'native':native,'catalogue':loaded['catalogue'][0]}
    validate_candidate_catalogue(packet)
    validate_candidate_source_joins(packet)
    return packet

def validate_candidate_catalogue(packet: dict[str,Any]) -> None:
    """Bind every candidate selector/path/evidence hash to frozen catalogue bytes."""
    catalogue=packet['catalogue']; symbols=catalogue.get('symbols')
    if not isinstance(symbols,list): raise GenerationError('catalogue symbols missing')
    byusr={x.get('usr'):x for x in symbols if isinstance(x,dict)}
    for block in packet['candidate'].get('blocks',[]):
        for selected in block.get('symbols',[]):
            selector=selected.get('selector') if isinstance(selected,dict) else None
            if not isinstance(selector,str) or not selector.startswith('usr:'): raise GenerationError(f'{block.get("id")}: malformed USR selector')
            item=byusr.get(selector[4:])
            if item is None or selected.get('path') != item.get('path') or selected.get('catalogueStatus') != item.get('status') or selected.get('symbolEvidenceSha256') != digest_bytes(canon(item)): raise GenerationError(f'{block.get("id")}: USR/catalogue binding')

def validate_candidate_source_joins(packet: dict[str,Any]) -> None:
    """Require every selected source-use record to be an exact candidate symbol."""
    byblock={b.get('id'):b for b in packet['candidate'].get('blocks',[])}
    if set(byblock) != set(BLOCKS): raise GenerationError('candidate source block set')
    seen=set()
    for row in packet['join'].get('rows',[]):
        block=row.get('block'); candidate=byblock.get(block)
        if candidate is None: raise GenerationError(f'unknown source-join block {block}')
        if block in seen: raise GenerationError(f'duplicate source-join block {block}')
        seen.add(block)
        symbols=candidate.get('symbols',[])
        for selected in row.get('selectedSourceSymbols',[]):
            if not isinstance(selected,dict) or selected not in symbols: raise GenerationError(f'{block}: selected USR/source is not candidate-bound')
    if seen != set(BLOCKS): raise GenerationError('source-join block coverage')

def candidate_witness(recipe: dict[str,Any]) -> tuple[dict[str,Any],bytes]:
    if len(recipe.get('witnesses',[])) != 1: raise GenerationError(f'{recipe["block"]}: witness cardinality')
    w=recipe['witnesses'][0]; wid=w.get('id');
    if not isinstance(wid,str): raise GenerationError('missing witness id')
    p=inside(PACKET/'witnesses'/(wid+'.swift'), PACKET)
    raw=p.read_bytes()
    if w.get('sourceHash') != sha256(raw) or w.get('resources') != [{'id':wid+'.swift','hash':sha256(raw)}]: raise GenerationError(f'{recipe["block"]}: witness source binding')
    text=raw.decode('utf-8')
    if re.search(r'^\s*import\s+',text,re.M) or not re.search(r'\bstruct\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*View\b',text): raise GenerationError(f'{recipe["block"]}: witness shape')
    return w,raw

def negative_source(recipe:dict[str,Any]) -> bytes:
    if len(recipe.get('negativeCases',[])) != 1: raise GenerationError(f'{recipe["block"]}: negative cardinality')
    n=recipe['negativeCases'][0]; p=inside(PACKET/'witnesses'/(n['id']+'.swift'),PACKET); raw=p.read_bytes()
    if n.get('mode')!='must-not-compile' or n.get('sourceHash') != sha256(raw): raise GenerationError(f'{recipe["block"]}: negative source binding')
    return raw

def specialize(recipe:dict[str,Any], inputs:dict[str,Any], raw:bytes) -> bytes:
    text=raw.decode('utf-8'); placeholders=set(re.findall(r'\{\{([a-z][a-z0-9-]*)\}\}',text))
    if set(inputs) != placeholders: raise GenerationError(f'{recipe["block"]}: case inputs/placeholders mismatch')
    for k,v in inputs.items():
        if isinstance(v,bool): lit='true' if v else 'false'
        elif isinstance(v,int): lit=str(v)
        elif isinstance(v,str) and re.fullmatch(r'[A-Za-z0-9_.$(), :.+\-\"]+',v): lit=v
        else: raise GenerationError(f'{recipe["block"]}: unsafe input {k}')
        text=text.replace('{{'+k+'}}',lit)
    if '{{' in text or '}}' in text: raise GenerationError(f'{recipe["block"]}: unresolved placeholder')
    return text.encode()

def generate(packet:dict[str,Any], output_dir:Path) -> dict[str,Any]:
    output_dir.mkdir(parents=True,exist_ok=True)
    candidate=packet['candidate']
    if candidate.get('activeRegistryMutation') is not False or candidate.get('status')!='held-source-bound-candidates': raise GenerationError('candidate is not held')
    if [b.get('id') for b in candidate.get('blocks',[])] != list(BLOCKS): raise GenerationError('candidate block membership')
    for b in candidate['blocks']:
        if b.get('registryPromotion') is not False or b.get('coverageStatus')!='identity-only' or b.get('nativeCoverage')!='unsupported' or b.get('semanticDependencies') != []: raise GenerationError(f'candidate promotion/dependency gate {b.get("id")}')
    validate_candidate_catalogue(packet)
    validate_candidate_source_joins(packet)
    byblock={x['block']:x for x in packet['join']['rows']}
    vrows={x['block']:x for x in packet['validation']['recipes']}
    recipes={}
    for block in BLOCKS:
        rp=PACKET/'data'/(block+'.json'); recipe,recipe_raw=read_json(rp)
        if recipe.get('block')!=block or recipe.get('provenance',{}).get('review',{}).get('decision')!='candidate': raise GenerationError(f'{block}: recipe identity/review')
        if 'sha256:'+digest_bytes(recipe_raw) != byblock[block]['recipeHash']: raise GenerationError(f'{block}: recipe join hash')
        if recipe.get('provenance',{}).get('inputs') != [{'id':packet['candidate']['id'],'hash':sha256(packet['candidateRaw'])}]: raise GenerationError(f'{block}: recipe candidate input')
        w,raw=candidate_witness(recipe); negative=negative_source(recipe); recipes[block]=(recipe,w,raw,negative)
    outputs=[]; total=0
    for block in BLOCKS:
        recipe,w,raw,negative=recipes[block]; joined=byblock[block]; validation=vrows.get(block)
        if validation is None: raise GenerationError(f'{block}: missing validation row')
        if len(validation.get('descriptors',[])) != DESCRIPTOR_COUNTS[block]: raise GenerationError(f'{block}: case descriptor cardinality')
        if validation.get('recipeHash') != 'sha256:'+digest_bytes((PACKET/'data'/(block+'.json')).read_bytes()) or validation.get('witnessHash') != w['sourceHash']: raise GenerationError(f'{block}: validation recipe/source join')
        expected_channels={a['channel'] for a in recipe['assertions']}
        unsupported=packet['config']['unsupportedObservability'][block]
        if expected_channels != set(unsupported): raise GenerationError(f'{block}: unsupported channel map')
        seen_case_ids=set()
        for desc in validation['descriptors']:
            cid=desc.get('id'); safe_id(cid)
            if cid in seen_case_ids: raise GenerationError(f'{block}: duplicate case id {cid}')
            seen_case_ids.add(cid)
            if not (cid == block+'.instrumentation-transparency' or cid == block+'.negative.invalid-argument' or re.fullmatch(re.escape(recipe['id'])+r'/case/[0-9a-f]{16}',str(cid))): raise GenerationError(f'{block}: case id is not frozen recipe binding {cid}')
            if not isinstance(desc.get('inputs'),dict) or desc.get('executionEligible') is not False or desc.get('projectionOnly') is not True: raise GenerationError(f'{block}: case policy {cid}')
            if cid.endswith('.negative.invalid-argument'):
                body=negative; scenario='negative:must-not-compile'; expectation='failure'
            else:
                body=specialize(recipe,desc['inputs'],raw); scenario='instrumentation-transparency' if cid.endswith('.instrumentation-transparency') else 'candidate-projection'; expectation='success'
            if sha256(body) != desc.get('projectedWitnessHash'): raise GenerationError(f'{block}: projected source drift {cid}')
            source=IMPORTS.encode()+b'\n'+body.rstrip()+b'\n'; sid=safe_id(cid)
            manifest={'kind':'generated-round2-candidate-probe','version':'0.1','recipe':{'id':recipe['id'],'hash':'sha256:'+digest_bytes((PACKET/'data'/(block+'.json')).read_bytes())},'case':{'id':cid,'descriptorHash':sha256(canon(desc)),'descriptor':desc},'caseInputs':desc['inputs'],'block':block,'sourceBindings':joined['selectedSourceSymbols'],'scenario':scenario,'witness':{'id':w['id'],'sourceHash':w['sourceHash'],'resourcePath':'factory/recipes/round2-extra-v1/witnesses/'+w['id']+'.swift'},'witnessType':re.search(r'\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*View\b',raw.decode()).group(1),'executionEligible':False,'compileExpectation':expectation,'sourceFile':sid+'.swift','sourceHash':sha256(source),'assertionChannels':sorted(expected_channels),'unsupportedObservability':unsupported,'instrumentationInserted':False,'registryPromotion':False}
            (output_dir/(sid+'.swift')).write_bytes(source); (output_dir/(sid+'.manifest.json')).write_bytes((json.dumps(manifest,ensure_ascii=False,sort_keys=True,indent=2)+'\n').encode()); outputs.append(manifest); total+=1
    return {'kind':'round2-extra-f4-generated-candidate','version':'0.1','scope':'source-only held candidate','executionEligible':False,'compilerRuns':0,'nativeRuns':0,'measurementTuple':None,'registryPromotion':False,'outputs':len(outputs),'blocks':list(BLOCKS),'sourceHashes':[x['sourceHash'] for x in outputs]}

def main(argv=None):
    ap=argparse.ArgumentParser(); ap.add_argument('--output-dir',type=Path); ap.add_argument('--config',type=Path,default=DEFAULT_CONFIG); ap.add_argument('--check-only',action='store_true'); a=ap.parse_args(argv)
    try:
        packet=load_packet(a.config)
        if a.check_only: result={'kind':'round2-extra-f4-check','ok':True,'blocks':list(BLOCKS),'compilerRuns':0,'nativeRuns':0}
        elif a.output_dir is None: raise GenerationError('--output-dir is required unless --check-only is used')
        else: result=generate(packet,a.output_dir)
    except (GenerationError,OSError,UnicodeError) as exc: print(f'round2-extra-generator: {exc}',file=sys.stderr); return 2
    print(json.dumps(result,sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
