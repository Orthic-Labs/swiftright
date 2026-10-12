"""Prepare runnable host-bound Count1 capture stage from measured Rectangle lifecycle graph."""
from pathlib import Path
import argparse, base64, hashlib, json, zipfile, re

REPO=Path('/Volumes/D/claude/swiftright')
DONOR=REPO/'factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-r5/sources'
CACHE=REPO/'.factory-work/pilot-delivery-five-v1/generic-native-capture'

p=argparse.ArgumentParser()
p.add_argument('--host',choices=('image','rounded-stroke','custom-layout','stack-overlay'),required=True)
p.add_argument('--plan',required=True)
p.add_argument('--revision',type=int,choices=range(1,21),default=1)
p.add_argument('--compile-receipt-hash',required=True)
p.add_argument('--compile-receipt-path',required=True)
p.add_argument('--compile-receipt-artifact-path',required=True)
p.add_argument('--exe-hash',required=True)
p.add_argument('--exe-path',required=True)
p.add_argument('--exe-artifact-path',required=True)
p.add_argument('--serializer-control-hash',required=True)
p.add_argument('--serializer-control-path',required=True)
p.add_argument('--serializer-control-artifact-path',required=True)
p.add_argument('--renderer-artifact-path',required=True,
               help='local measured renderer artifact; its bytes are hashed before admission')
p.add_argument('--case-artifact-path',required=True,
               help='local materialized-case.json emitted by finalizer; raw case path stays plan.casePath')
p.add_argument('--mac-sidecar-receipt-path',
               help='optional measured Mac full-viewport receipt; required for Rounded observational sidecar')
p.add_argument('--mac-sidecar-image-path',
               help='optional measured Mac full-viewport PNG; required for Rounded observational sidecar')
p.add_argument('--mac-sidecar-manifest-path',
               help='measured Mac archive manifest; required when sidecar is supplied')
p.add_argument('--mac-sidecar-observation-path',
               help='raw Mac observation; required when sidecar is supplied')
a=p.parse_args()

def rd(path,cap=4194304):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=cap, path
    return path.read_bytes()
def sha(data):return hashlib.sha256(data).hexdigest()
def canonical_hash(value):
    """Match factory.core.artifacts.canonical_hash for JSON-safe final plans."""
    return 'sha256:'+sha(json.dumps(value,ensure_ascii=False,allow_nan=False,
                                    sort_keys=True,separators=(',',':')).encode('utf-8'))
def jd(value):return (json.dumps(value,indent=2,sort_keys=True)+'\n').encode()
def req(obj,*keys):
    for k in keys:
        if isinstance(obj,dict) and obj.get(k) not in (None,''):
            return obj[k]
    raise SystemExit('final compiled plan missing '+('/'.join(keys)))
def unprefix(v):return str(v).removeprefix('sha256:')
def nested(obj,*paths):
    for path in paths:
        cur=obj
        for key in path:cur=cur.get(key) if isinstance(cur,dict) else None
        if cur not in (None,''):return int(cur)
    raise SystemExit('final compiled plan missing byte count')
def local_path(value,label):
    """Resolve source-side path while retaining Windows path in emitted joins."""
    raw=Path(str(value))
    candidates=[raw]
    text=str(value).replace('\\','/')
    marker='/swiftright/'
    if marker in text:
        candidates.append(REPO/text.split(marker,1)[1])
    if not raw.is_absolute():candidates.append(REPO/raw)
    for candidate in candidates:
        if candidate.exists():return candidate
    raise SystemExit(f'{label} measured artifact unavailable: {value}')
def measured(path,label,expected_hash=None):
    pth=local_path(path,label)
    if pth.is_symlink() or pth.stat().st_size>67108864: raise SystemExit(f'{label} must be bounded regular file')
    h=hashlib.sha256();size=0
    with pth.open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):
            size+=len(block);h.update(block)
    actual=h.hexdigest();data=None
    if expected_hash and actual != unprefix(expected_hash):
        raise SystemExit(f'{label} measured hash mismatch')
    return pth,data,actual,size
def measured_json(path,label,expected_hash=None):
    pth,data,actual,size=measured(path,label,expected_hash)
    data=rd(pth,4194304)
    return pth,data,actual,size
def walk(v,changes):
    if isinstance(v,str):
        for x,y in changes:v=v.replace(x,y)
        return v
    if isinstance(v,list):return [walk(x,changes) for x in v]
    if isinstance(v,dict):return {k:walk(x,changes) for k,x in v.items()}
    return v

def winpath(path):
    return str(path).replace('/','\\')

def rebind_source_pin_graph(files, donor_rows):
    """Reseal staged child hashes into typed parents & embedded guards."""
    names=set(files); old_by_hash={}
    for row in donor_rows: old_by_hash.setdefault(row['sha256'],set()).add(row['path'])
    def resolve(raw,owner):
        if not isinstance(raw,str) or not raw.strip(): return None
        text=raw.replace('\\','/').rstrip('/')
        exact=[rel for rel in names if text==rel or text.endswith('/'+rel)]
        if len(exact)==1:return exact[0]
        leaf=text.rsplit('/',1)[-1]
        leaf_hits=[rel for rel in names if rel.rsplit('/',1)[-1]==leaf]
        if len(leaf_hits)==1:return leaf_hits[0]
        prefixes=[]
        if owner.startswith('producer/dependencies/uia-worker/'):prefixes+=['producer/dependencies/uia-worker/']
        elif owner.startswith('producer/'):prefixes+=['producer/']
        elif owner.startswith('overlay/'):prefixes+=['overlay/']
        elif owner.startswith('admission/'):prefixes+=['admission/']
        prefixes+=['producer/','overlay/','admission/']
        for prefix in prefixes:
            candidate=prefix+text
            if candidate in names:return candidate
        return None
    def near_target(text,pos,owner):
        window=text[max(0,pos-140):min(len(text),pos+140)]
        hits=[rel for rel in names if rel in window or rel.split('/',1)[-1].replace('/','\\') in window]
        return hits[0] if len(hits)==1 else None
    def bind_json(value,owner,parent,edges):
        if isinstance(value,dict):
            target=resolve(value.get('path'),owner)
            if target:
                edges.append((parent,target));h=sha(files[target])
                for key in list(value):
                    if (key=='sha256' or key.lower().endswith('hash')) and isinstance(value[key],str) and re.fullmatch(r'(?:sha256:)?[0-9a-f]{64}',value[key],re.I):
                        value[key]=('sha256:'+h) if value[key].lower().startswith('sha256:') else h
                    elif key.lower().endswith('bytes') and isinstance(value[key],(int,float)): value[key]=len(files[target])
            for item in value.values():bind_json(item,owner,parent,edges)
        elif isinstance(value,list):
            for item in value:bind_json(item,owner,parent,edges)
    def check_cycles(edges):
        graph={}
        for parent,target in edges:
            if parent==target:raise SystemExit(f'source pin self-reference: {parent}')
            graph.setdefault(parent,set()).add(target)
        state={}
        def visit(node):
            if state.get(node)==1:raise SystemExit(f'source pin cycle detected at {node}')
            if state.get(node)==2:return
            state[node]=1
            for child in graph.get(node,()):visit(child)
            state[node]=2
        for node in graph:visit(node)
    for _ in range(16):
        before=dict(files);edges=[]
        # These manifests are executable source contracts, so reseal them first.
        for rel in ('producer/integration-bindings.json','producer/dependencies/uia-worker/worker-contract.json'):
            if rel not in files:continue
            doc=json.loads(files[rel].decode('utf-8-sig'));rows=doc.get('files',[]) if rel.endswith('integration-bindings.json') else doc.get('sourceBindings',[])
            for row in rows:
                target=resolve(row.get('path'),rel)
                if target:row.update(bytes=len(files[target]),sha256=sha(files[target]));edges.append((rel,target))
            files[rel]=jd(doc)
        for rel,data in list(files.items()):
            if rel.endswith('.json'):
                try:doc=json.loads(data.decode('utf-8-sig'))
                except Exception:continue
                bind_json(doc,rel,rel,edges)
                if rel=='admission/source-inputs.json':
                    for key,target in {'contextHash':'admission/context.json','tupleHash':'admission/candidate-tuple.json','bindingHash':'admission/candidate-binding.json','recipeHash':'admission/recipe.json','integrationBindingsHash':'producer/integration-bindings.json'}.items():
                        if target in files:doc[key]=sha(files[target])
                files[rel]=jd(doc)
            elif rel.endswith(('.ps1','.cs','.py','.md')):
                text=data.decode('utf-8-sig')
                for old,targets in old_by_hash.items():
                    live=[target for target in targets if target in files];desireds={sha(files[target]) for target in live}
                    if not live or len(desireds)!=1:continue
                    desired=next(iter(desireds));pat=re.compile(r'(?<![0-9a-f])'+re.escape(old)+r'(?![0-9a-f])',re.I)
                    text=pat.sub(lambda m:desired if near_target(text,m.start(),rel) in live else m.group(0),text)
                files[rel]=text.encode()
        check_cycles(edges)
        if files==before:break
    else:raise SystemExit('source pin graph did not converge; cycle or hidden self-pin')
    for rel,data in files.items():
        if not rel.endswith(('.ps1','.cs','.py','.md')):continue
        text=data.decode('utf-8-sig')
        for old,targets in old_by_hash.items():
            live=[target for target in targets if target in files];desireds={sha(files[target]) for target in live}
            if not live or len(desireds)!=1:continue
            desired=next(iter(desireds))
            if old==desired:continue
            for match in re.finditer(r'(?<![0-9a-f])'+re.escape(old)+r'(?![0-9a-f])',text,re.I):
                if near_target(text,match.start(),rel) in live:raise SystemExit(f'unresolved embedded source pin: {rel} -> {live[0]}')

plan_path=Path(a.plan)
if not plan_path.is_absolute():plan_path=REPO/plan_path
plan_raw=rd(plan_path);plan=json.loads(plan_raw.decode('utf-8-sig'));plan_hash=sha(plan_raw)
raw_case_path=plan.get('casePath') or plan.get('rawCasePath') or ('case.json' if any(row.get('path')=='case.json' for row in plan.get('sourceBindings',[])) else 'plan.json')
raw_case=plan_path.parent/raw_case_path
raw_case_pin=req(plan,'caseRawJsonHash') if raw_case_path!='plan.json' else None
raw_case_hash=unprefix(raw_case_pin) if raw_case_pin else None
if raw_case.exists():
    measured_raw_hash=sha(rd(raw_case))
    if raw_case_hash and measured_raw_hash!=raw_case_hash:
        raise SystemExit('final raw case hash differs from caseRawJsonHash')
    raw_case_hash=measured_raw_hash
if not raw_case_hash and raw_case_path!='plan.json':
    raise SystemExit('final compiled plan missing caseRawJsonHash')
case_artifact_local,case_artifact_raw,case_artifact_hash,case_artifact_bytes=measured_json(a.case_artifact_path,'materialized case')
try: case_artifact=json.loads(case_artifact_raw.decode('utf-8-sig'))
except Exception as exc: raise SystemExit(f'materialized case JSON invalid: {exc}')
case_doc=case_artifact
case=plan.get('case') if isinstance(plan.get('case'),dict) else case_artifact
case_id=req(case,'id')
case_hash=case.get('hash') or plan.get('caseHash')
if not case_hash:
    for row in plan.get('sourceBindings',[]):
        if row.get('path')==raw_case_path and row.get('sha256'):case_hash=row['sha256'];break
if not case_hash:case_hash='sha256:'+raw_case_hash
if case_artifact.get('id')!=case_id or case_artifact.get('kind')!='case':
    raise SystemExit('materialized case identity mismatch')
if case_artifact.get('provenance',{}).get('inputs', [{}])[0].get('hash') is None:
    raise SystemExit('materialized case missing typed recipe provenance')
if case_artifact.get('recipe',{}).get('id') != case_artifact.get('provenance',{}).get('inputs',[{}])[0].get('id'):
    raise SystemExit('materialized case recipe provenance mismatch')
if plan.get('canonicalCaseHash') and unprefix(plan['canonicalCaseHash'])!=unprefix(case_hash):
    raise SystemExit('final canonical case hash mismatch')
if canonical_hash(case_artifact)!=case_hash:
    raise SystemExit('materialized case canonical hash mismatch')
materialization=plan.get('caseMaterialization') if isinstance(plan.get('caseMaterialization'),dict) else {}
recipe=materialization.get('recipe') if isinstance(materialization.get('recipe'),dict) else None
typed_recipe=case_artifact.get('recipe') if isinstance(case_artifact.get('recipe'),dict) else None
if not isinstance(recipe,dict):
    raise SystemExit('final compiled plan missing canonical recipe object')
recipe_id=req(recipe,'id')
recipe_hash=req(recipe,'recipeHash') if recipe.get('recipeHash') else req(materialization,'recipeHash')
if typed_recipe.get('id')!=recipe_id or typed_recipe.get('hash')!=recipe_hash:
    raise SystemExit('typed case recipe does not join canonical recipe')
if canonical_hash(recipe)!=recipe_hash:
    raise SystemExit('final recipe canonical hash mismatch')
# packetRecipeCanonicalHash is the registry recipe hash; recipeHash above is
# finalizer's narrowed/host-bound recipe. Keep both joins explicit.
packet_recipe_path=materialization.get('packetRecipePath')
packet_recipe_hash=materialization.get('packetRecipeCanonicalHash')
if not packet_recipe_path or not packet_recipe_hash:
    raise SystemExit('final case materialization missing registry recipe binding')
packet_recipe_local,packet_recipe_raw,packet_recipe_actual,_=measured_json(packet_recipe_path,'registry recipe')
packet_recipe=json.loads(packet_recipe_raw.decode('utf-8-sig'))
if canonical_hash(packet_recipe)!=packet_recipe_hash or packet_recipe.get('block')!=recipe.get('block'):
    raise SystemExit('registry recipe canonical binding mismatch')
if recipe.get('block')!=case_artifact.get('block') or recipe.get('kind')!='recipe':
    raise SystemExit('final recipe block/kind mismatch')
tuple_obj=plan.get('tuple') if isinstance(plan.get('tuple'),dict) else case_doc.get('tuple')
if not isinstance(tuple_obj,dict):raise SystemExit('final compiled plan missing tuple object')
tuple_id=req(tuple_obj,'id')
witness=req(plan,'witness','witnessPath')
source_hash=req(plan,'sourceHash');runtime_commit=req(plan,'runtimeSourceCommit','sourceCommit')
runtime_tree=req(plan,'runtimeSourceTreeHash')
renderer_path=req(plan,'rendererPath','rendererLoadPath');renderer_hash=unprefix(req(plan,'rendererSha256'))
mac_sidecar=None
# Windows observation may precede Mac pairing; missing sidecar stays explicitly
# unqualified in existing context. A supplied sidecar still gets every check.
if a.mac_sidecar_receipt_path or a.mac_sidecar_image_path:
    if not (a.mac_sidecar_receipt_path and a.mac_sidecar_image_path and a.mac_sidecar_manifest_path and a.mac_sidecar_observation_path): raise SystemExit('Mac sidecar receipt/image/manifest/raw observation must be supplied together')
    mac_receipt_local,mac_receipt_raw,mac_receipt_hash,mac_receipt_bytes=measured_json(a.mac_sidecar_receipt_path,'Mac sidecar receipt')
    mac_receipt=json.loads(mac_receipt_raw.decode('utf-8-sig'))
    mac_manifest_local,mac_manifest_raw,mac_manifest_hash,mac_manifest_bytes=measured_json(a.mac_sidecar_manifest_path,'Mac sidecar archive manifest')
    mac_manifest=json.loads(mac_manifest_raw.decode('utf-8-sig'))
    mac_observation_local,mac_observation_raw,mac_observation_hash,mac_observation_bytes=measured_json(a.mac_sidecar_observation_path,'Mac sidecar raw observation')
    mac_observation=json.loads(mac_observation_raw.decode('utf-8-sig'))
    if mac_receipt.get('kind')!='factory-full-viewport-mac-build-receipt-v1' or mac_receipt.get('host')!=a.host or mac_receipt.get('exitCode')!=0 or mac_receipt.get('nativeActions')!=0 or mac_receipt.get('originalHandleRetained') is not True or mac_receipt.get('qualified') is not False: raise SystemExit('Mac sidecar receipt lifecycle/qualification mismatch')
    expected_sidecar_case={'id':case_id,'hash':case_hash}
    if mac_manifest.get('kind')!='factory-full-viewport-mac-count1-archive-v1' or mac_manifest.get('qualified') is not False or mac_manifest.get('sourceHash')!=source_hash or mac_manifest.get('case')!=expected_sidecar_case or unprefix(mac_manifest.get('buildReceiptHash',''))!=mac_receipt_hash or mac_manifest.get('originalTerminalProof') is not True or mac_manifest.get('permissionRequests') is not False: raise SystemExit('Mac sidecar archive source/case/build join mismatch')
    reference_context=mac_manifest.get('referenceContext') if isinstance(mac_manifest.get('referenceContext'),dict) else {}
    if reference_context.get('tupleRendererHash')!='sha256:'+renderer_hash or reference_context.get('runtimeCommit')!=runtime_commit: raise SystemExit('Mac sidecar reference context join failed')
    manifest_rows=mac_manifest.get('rows') if isinstance(mac_manifest.get('rows'),list) else []
    expected_rows={'client.png','observation.raw.json','stderr.bin','supervision.json','original-start.json'}
    row_map={str(row.get('path')):row for row in manifest_rows if isinstance(row,dict)}
    if set(row_map)!=expected_rows or len(row_map)!=len(manifest_rows): raise SystemExit('Mac sidecar archive row set mismatch')
    row_bytes={}
    for row_name,row in row_map.items():
        if not row_name or row_name.startswith(('/','\\')) or '..' in Path(row_name).parts: raise SystemExit('Mac sidecar archive row path invalid')
        sibling=mac_manifest_local.parent/row_name
        _,_,row_hash,row_size=measured(sibling,'Mac sidecar archive row '+row_name)
        if row_hash!=unprefix(row.get('sha256','')) or row_size!=int(row.get('bytes',-1)): raise SystemExit('Mac sidecar archive row bytes/hash mismatch')
        row_bytes[row_name]=(row_hash,row_size,sibling.resolve())
    mac_image_local,mac_image_raw,mac_image_hash,mac_image_bytes=measured(a.mac_sidecar_image_path,'Mac sidecar image')
    if mac_image_local.resolve()!=row_bytes['client.png'][2] or mac_observation_local.resolve()!=row_bytes['observation.raw.json'][2]: raise SystemExit('Mac sidecar supplied artifact path mismatch')
    if mac_observation.get('kind')!='factory-full-viewport-mac-observation-v1' or mac_observation.get('status')!='OBSERVED' or mac_observation.get('pid')!=mac_manifest.get('originalPid') or mac_observation.get('permissionRequests') is not False: raise SystemExit('Mac sidecar raw observation/PID join failed')
    supervision_path=mac_manifest_local.parent/'supervision.json';supervision=json.loads(rd(supervision_path).decode('utf-8-sig'))
    original_start_path=mac_manifest_local.parent/'original-start.json';original_start=json.loads(rd(original_start_path).decode('utf-8-sig'))
    if supervision.get('kind')!='factory-supervised-local-job-v2' or supervision.get('pid')!=mac_manifest.get('originalPid') or supervision.get('exitCode')!=0 or supervision.get('budgetFailure') is not None or supervision.get('finalInventory',{}).get('known') is not True or supervision.get('finalInventory',{}).get('count')!=0 or supervision.get('quiescenceKnown') is not True or supervision.get('ownedGroupQuiescent') is not True or supervision.get('termination')!=[] or supervision.get('supervisorError')!='': raise SystemExit('Mac sidecar supervision join failed')
    if unprefix(supervision.get('stdout',{}).get('sha256',''))!=unprefix(row_map['observation.raw.json'].get('sha256','')) or supervision.get('stdout',{}).get('bytes')!=row_map['observation.raw.json'].get('bytes') or unprefix(supervision.get('stderr',{}).get('sha256',''))!=unprefix(row_map['stderr.bin'].get('sha256','')) or supervision.get('stderr',{}).get('bytes')!=row_map['stderr.bin'].get('bytes'): raise SystemExit('Mac sidecar stream row join failed')
    if original_start.get('pid')!=mac_manifest.get('originalPid') or original_start.get('pgid')!=mac_manifest.get('originalPid') or not isinstance(original_start.get('argv'),list) or not original_start.get('argv'): raise SystemExit('Mac sidecar original-start join failed')
    mac_exe=mac_receipt.get('executable') if isinstance(mac_receipt.get('executable'),dict) else {}
    mac_host_hash=unprefix(req(mac_exe,'sha256'));mac_host_bytes=int(req(mac_exe,'bytes'))
    image_rows=[row for row in manifest_rows if row.get('path')=='client.png']
    if len(image_rows)!=1 or unprefix(image_rows[0].get('sha256',''))!=mac_image_hash or int(image_rows[0].get('bytes',-1))!=mac_image_bytes: raise SystemExit('Mac sidecar PNG/archive manifest join failed')
    receipt_sources=mac_receipt.get('sources') if isinstance(mac_receipt.get('sources'),list) else []
    host_source_hash=unprefix(mac_manifest.get('hostSourceHash',''))
    if not host_source_hash or not any(unprefix(row.get('sha256',''))==host_source_hash for row in receipt_sources if isinstance(row,dict)): raise SystemExit('Mac sidecar host source join failed')
    if not any(unprefix(row.get('sha256',''))==unprefix(source_hash) for row in receipt_sources if isinstance(row,dict)): raise SystemExit('Mac sidecar Witness/source join failed')
    if unprefix(mac_manifest.get('hostHash',''))!=mac_host_hash or mac_manifest.get('buildReceiptPath','').replace('\\','/').split('/')[-1] != 'receipt.json': raise SystemExit('Mac sidecar executable/build join failed')
    raw_png=Path(str(mac_observation.get('pngPath','')).replace('\\','/')).name
    if not raw_png.lower().endswith('.png') or not mac_observation.get('imagePixels'): raise SystemExit('Mac sidecar raw observation PNG join failed')
    mac_sidecar={'case':{'id':case_id,'hash':case_hash},'sourceHash':source_hash,'receipt':{'path':str(mac_receipt_local),'bytes':mac_receipt_bytes,'sha256':'sha256:'+mac_receipt_hash},'manifest':{'path':str(mac_manifest_local),'bytes':mac_manifest_bytes,'sha256':'sha256:'+mac_manifest_hash},'observation':{'path':str(mac_observation_local),'bytes':mac_observation_bytes,'sha256':'sha256:'+mac_observation_hash,'pid':mac_observation.get('pid')},'host':{'path':mac_exe.get('path'),'bytes':mac_host_bytes,'sha256':'sha256:'+mac_host_hash},'image':{'path':str(mac_image_local),'bytes':mac_image_bytes,'sha256':'sha256:'+mac_image_hash},'qualification':'observational-sidecar-unqualified'}
package_path=winpath(req(plan.get('compileRequest',{}),'packagePath'))
compile_hash=unprefix(a.compile_receipt_hash);exe_hash=unprefix(a.exe_hash);serializer_hash=unprefix(a.serializer_control_hash)
compile_path=winpath(a.compile_receipt_path);exe_path=winpath(a.exe_path);serializer_path=winpath(a.serializer_control_path)
# Final Image/Rounded plans carry prebuild output pins, while final receipt,
# serializer, renderer, & executable byte counts are measured inputs. Never
# synthesize counts from plan metadata or caller-supplied integers.
receipt_local,receipt_raw,receipt_actual_hash,compile_bytes=measured_json(a.compile_receipt_artifact_path,'compile receipt')
if receipt_actual_hash != unprefix(a.compile_receipt_hash):
    raise SystemExit('compile receipt hash differs from caller pin')
try: receipt=json.loads(receipt_raw.decode('utf-8-sig'))
except Exception as exc: raise SystemExit(f'compile receipt JSON invalid: {exc}')
phase=receipt.get('phase')
if receipt.get('kind')!='factory-pilot-five-owned-compile-v1' or phase!='final':
    raise SystemExit('compile receipt must be measured final receipt')
if receipt.get('planSha256') != plan_hash:
    raise SystemExit('final receipt plan hash differs from finalized plan')
for key in ('exitCode','ownedExited','originalHandleRetained','streamDrainComplete','streamsSealed','jobActiveCount','cleanupJobActive','kernelWait','memoryCapBytes','nativeActions','sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','rendererSha256','exeSha256','exeBytes','exePath'):
    if key not in receipt:raise SystemExit(f'compile receipt missing {key}')
if receipt['exitCode']!=0 or receipt['ownedExited'] is not True or receipt['originalHandleRetained'] is not True or receipt['streamDrainComplete'] is not True or receipt['streamsSealed'] is not True or receipt['jobActiveCount']!=0 or receipt['cleanupJobActive']!=0 or receipt['kernelWait']!=0 or receipt['memoryCapBytes']!=1073741824 or receipt['nativeActions']!=0:
    raise SystemExit('compile receipt lifecycle admission failed')
receipt_case=receipt.get('case') if isinstance(receipt.get('case'),dict) else {}
if receipt_case.get('id')!=case_id or receipt_case.get('hash')!=case_hash or receipt['sourceHash']!=source_hash or receipt['runtimeSourceCommit']!=runtime_commit or receipt['runtimeSourceTreeHash']!=runtime_tree or unprefix(receipt['rendererSha256'])!=renderer_hash or unprefix(receipt['exeSha256'])!=exe_hash or winpath(receipt['exePath'])!=exe_path:
    raise SystemExit('compile receipt source/runtime/output join mismatch')
exe_artifact_local,exe_artifact_raw,exe_artifact_hash,exe_artifact_bytes=measured(a.exe_artifact_path,'executable artifact',exe_hash)
exe_bytes=int(receipt['exeBytes'])
if exe_artifact_bytes!=exe_bytes:
    raise SystemExit('executable artifact byte count differs from final receipt')
outputs=plan.get('outputs') if isinstance(plan.get('outputs'),dict) else {}
for key,value in (('prebuildExeBytes',exe_bytes),('prebuildExeSha256','sha256:'+exe_hash),('prebuildExePath',exe_path)):
    if key in outputs and str(outputs[key]).replace('/','\\') != str(value).replace('/','\\'):
        raise SystemExit(f'final plan {key} differs from measured receipt')
serializer_local,serializer_raw,serializer_actual_hash,serializer_bytes=measured(a.serializer_control_artifact_path,'serializer control',serializer_hash)
renderer_local,renderer_raw,renderer_actual_hash,renderer_bytes=measured(a.renderer_artifact_path,'renderer artifact',renderer_hash)

# Final plan must carry exact tuple host identity; null Windows pins are rejected.
host_hashes=tuple_obj.get('hostHashes')
if not isinstance(host_hashes,dict) or host_hashes.get('windows')!='sha256:'+exe_hash:
    raise SystemExit('final tuple windows host hash differs from exe hash')

out=REPO/f'factory/pipeline/pilot-delivery-five-v1/root-execution/{a.host}-native-capture-r{a.revision}'
out.mkdir(); sources=out/'sources'; sources.mkdir()
old_root=r'D:\Claude\swiftright\.factory-work\hosts\rectangle'
old_ns=old_root+r'\captures\color-r5'
target_root=package_path.rsplit('\\',1)[0]
target_ns=target_root+r'\captures\count1-r'+str(a.revision)
target_roots={k:target_ns+'\\'+k+'-count1-r'+str(a.revision) for k in ('producer','admission','overlay')}
target_native=target_ns+r'\native\count1-r1'
changes=[(old_ns,target_ns),(old_root,target_root),('D:\\Claude\\swiftright\\factory\\native\\windows\\',target_ns+'\\native\\'),
         ('count1-r5','count1-r'+str(a.revision)),
         ('color-r5','count1-r'+str(a.revision)),
         ('D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle\\package',package_path)]
# Exact old pins are replaced after metadata is built; path changes never touch protected controls semantics.
old_pins={'caseID':'swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.73250c091e3660b1',
          'caseHash':'bdb866ab75c201e782d8b2079d6fb4f15f5fd8d46e7f16135c4a007bdb408eab',
          'tupleID':'sr1-rectangle-color-fix-r11-20261012-r1',
          'exeHash':'faa2816f2f0b9a6d999e6334d92ecfeb76fe4a5bda6c158d42e2b7aa59b6a2c3',
          'compileHash':'75e829ce130a2a4d3da3568ecc3c4c26488269e5ac500d54d0997314ecc092f1',
          'rendererHash':'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93',
          'runtimeCommit':'37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b','sourceHash':'sha256:5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d'}
# Transform donor graph bytes, retaining all lifecycle/control code & remapping only measured paths/pins.
manifest=json.loads(rd(DONOR/'stage-manifest.json'));assert len(manifest['files'])==47
files={}
json_pin_changes=[(old_pins['caseID'],case_id),(old_pins['caseHash'],unprefix(case_hash)),(old_pins['sourceHash'],unprefix(source_hash)),(old_pins['tupleID'],tuple_id),(old_pins['exeHash'],exe_hash),(old_pins['compileHash'],compile_hash),(old_pins['rendererHash'],renderer_hash),(old_pins['runtimeCommit'],runtime_commit)]
for row in manifest['files']:
    rel=row['path']; data=rd(DONOR/rel);assert len(data)==row['bytes'] and sha(data)==row['sha256']
    if rel.endswith('.json'):
        data=jd(walk(json.loads(data.decode('utf-8-sig')),changes+json_pin_changes))
    elif rel.endswith(('.ps1','.cs','.py','.md')):
        text=data.decode();
        for x,y in changes:text=text.replace(x,y)
        data=text.encode()
    files[rel]=data

# Build host metadata from final plan, preserving existing worker, lifecycle & fault-control sources.
ctx=json.loads(files['admission/context.json']);ctx.pop('macHostHash',None);ctx.pop('macRawArchive',None);ctx.update(kind='factory-rectangle-measured-context-v1',case={'id':case_id,'hash':case_hash},sourceHash=source_hash,tupleID=tuple_id,windowsHostHash='sha256:'+exe_hash,rawCasePath=winpath(raw_case_path),rawCaseHash='sha256:'+raw_case_hash,canonicalCasePath=package_path+'\\materialized-case.json',canonicalCaseHash='sha256:'+case_artifact_hash,qualified=False,qualificationHold='observational-hold-macos-sidecar-unqualified' if mac_sidecar else 'observational-hold-missing-macos-host')
if mac_sidecar:
    ctx['macHostHash']=mac_sidecar['host']['sha256'];ctx['macRawArchive']=mac_sidecar['receipt']['path'];ctx['macSidecar']=mac_sidecar
files['admission/context.json']=jd(ctx)
recipe_doc=recipe.copy();recipe_doc.setdefault('kind','recipe');recipe_doc.setdefault('version','0.1');files['admission/recipe.json']=jd(recipe_doc)
tuple_doc=json.loads(files['admission/candidate-tuple.json']);tuple_doc['case']={'id':case_id,'hash':case_hash};tuple_doc['tuple']=tuple_obj;tuple_doc['sourceInputs']['sourceHash']=source_hash;tuple_doc['sourceInputs']['compiledPlan']={'bytes':len(plan_raw),'path':package_path+'\\plan.json','sha256':'sha256:'+plan_hash};tuple_doc['sourceInputs']['context']={'bytes':len(files['admission/context.json']),'path':target_roots['admission']+'\\context.json','sha256':'sha256:'+sha(files['admission/context.json'])};files['admission/candidate-tuple.json']=jd(tuple_doc)
binding_doc=json.loads(files['admission/candidate-binding.json']);binding_doc['case']={'id':case_id,'hash':case_hash};binding_doc['sourceHash']=source_hash;binding_doc['runtime']={'sourceCommit':runtime_commit,'sourceTreeHash':runtime_tree};binding_doc['renderer']={'sha256':'sha256:'+renderer_hash};binding_doc['canonicalTupleRef']={'bytes':len(files['admission/candidate-tuple.json']),'path':target_roots['admission']+'\\candidate-tuple.json','sha256':'sha256:'+sha(files['admission/candidate-tuple.json'])};files['admission/candidate-binding.json']=jd(binding_doc)
cp=json.loads(files['producer/capture-plan.json']);cp['kind']='factory-rectangle-native-capture-plan-v1';cp['case']={'id':case_id,'hash':case_hash};cp['compiledHostPackagePath']=package_path;cp['sourceHash']=source_hash;cp['tuple']=tuple_obj;cp['dispatch']['first']['runRoot']=target_native;cp['dispatch']['repeat']['runRoot']=target_ns+r'\native\count20-r1';files['producer/capture-plan.json']=jd(cp)
# Narrow worker source prefix must point into target namespace.
for rel in ('overlay/uia-worker-invoke-v2.ps1','producer/dependencies/uia-worker/invoke-worker-mta.ps1','producer/dependencies/uia-worker/invoke-worker.ps1','producer/dependencies/uia-worker/worker.ps1'):
    text=files[rel].decode();text=text.replace(old_ns+'\\native\\',target_ns+'\\native\\');files[rel]=text.encode()
# Replace donor case/pin literals in non-protected source text.
replace_pairs=[(old_pins['caseID'],case_id),(old_pins['caseHash'],unprefix(case_hash)),(old_pins['tupleID'],tuple_id),(old_pins['exeHash'],exe_hash),(old_pins['compileHash'],compile_hash),(old_pins['rendererHash'],renderer_hash),(old_pins['runtimeCommit'],runtime_commit),(old_pins['sourceHash'],unprefix(source_hash))]
for rel,data in list(files.items()):
    if rel.endswith(('.ps1','.cs','.py','.md')):
        text=data.decode()
        for x,y in replace_pairs:text=text.replace(x,y)
        files[rel]=text.encode()
# Generic source inputs paths & exact source joins.
si=json.loads(files['admission/source-inputs.json']);si.update(kind='factory-rectangle-source-inputs-v1',count=1,caseID=case_id,caseHash=case_hash,sourceHash=source_hash,tupleID=tuple_id,planHash=plan_hash,compileReceiptHash=compile_hash,compileReceiptPath=compile_path,compiledHostPackagePath=package_path,exeHash=exe_hash,exePath=exe_path,rendererPath=renderer_path,rendererSha256=renderer_hash,runtimeSourceCommit=runtime_commit,serializerControlSha256=serializer_hash,serializerPath=serializer_path,rawCasePath=winpath(raw_case_path),rawCaseHash='sha256:'+raw_case_hash,canonicalCasePath=package_path+'\\materialized-case.json',canonicalCaseHash='sha256:'+case_artifact_hash)
# Hash-bearing refs are finalized after all source files exist.
for key,rel in [('contextRef','admission/context.json'),('tupleRef','admission/candidate-tuple.json'),('bindingRef','admission/candidate-binding.json'),('recipeRef','admission/recipe.json'),('capturePlanPath','producer/capture-plan.json')]:
    if key.endswith('Ref'):si[key]={'path':target_roots['admission']+'\\'+rel.split('/',1)[1],'bytes':0,'sha256':''}
si['planRef']={'path':package_path+'\\plan.json','bytes':len(plan_raw),'sha256':'sha256:'+plan_hash}
si['compileRef']={'path':compile_path,'bytes':compile_bytes,'sha256':'sha256:'+compile_hash};si['exeRef']={'path':exe_path,'bytes':exe_bytes,'sha256':'sha256:'+exe_hash};si['rendererRef']={'path':renderer_path,'bytes':renderer_bytes,'sha256':'sha256:'+renderer_hash};si['serializerRef']={'path':serializer_path,'bytes':serializer_bytes,'sha256':'sha256:'+serializer_hash}
si['buildPreflightPath']=target_roots['overlay']+'\\preflight-color-r1.ps1';si['capturePlanPath']=target_roots['producer']+'\\capture-plan.json';si['contextRef']['path']=target_roots['admission']+'\\context.json';si['tupleRef']['path']=target_roots['admission']+'\\candidate-tuple.json';si['bindingRef']['path']=target_roots['admission']+'\\candidate-binding.json';si['recipeRef']['path']=target_roots['admission']+'\\recipe.json';si['integrationBindingsRef']={'path':target_roots['producer']+'\\integration-bindings.json','bytes':0,'sha256':''};si['capturePlanHash']=sha(files['producer/capture-plan.json'])
files['admission/source-inputs.json']=jd(si)
# Integration bindings are recalculated from transformed producer sources.
ib=json.loads(files['producer/integration-bindings.json']);ib['kind']='root-pilot-helper-bindings-v1';
for row in ib['files']:
    b=files['producer/'+row['path']];row.update(bytes=len(b),sha256=sha(b))
files['producer/integration-bindings.json']=jd(ib)
# Generic preflight removes Rectangle-only literal plan/receipt kinds while retaining lifecycle gates.
preflight=r'''param([ValidateSet('Launch')][string]$Phase='Launch',[Parameter(Mandatory=$true)][string]$CompileReceiptSha256,[Parameter(Mandatory=$true)][long]$CompileReceiptBytes,[Parameter(Mandatory=$true)][string]$ExeSha256,[Parameter(Mandatory=$true)][long]$ExeBytes,[Parameter(Mandatory=$true)][string]$SerializerControlSha256,[Parameter(Mandatory=$true)][long]$SerializerControlBytes,[Parameter(Mandatory=$true)][long]$RendererBytes)
$ErrorActionPreference='Stop';$Root='__HOST_ROOT__';$Package='__PACKAGE__';$PlanPath=Join-Path $Package 'plan.json';$ReceiptPath='__COMPILE_PATH__'
function H([string]$p){$i=Get-Item -LiteralPath $p;if($i.PSIsContainer -or $i.Length -gt 67108864 -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded input required'};(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}
if((H $PlanPath) -cne '__PLAN_HASH__' -or (H $ReceiptPath) -cne $CompileReceiptSha256 -or (Get-Item -LiteralPath $ReceiptPath).Length -ne $CompileReceiptBytes -or $CompileReceiptSha256 -cne '__COMPILE_HASH__' -or $ExeSha256 -cne '__EXE_HASH__' -or $SerializerControlSha256 -cne '__SERIALIZER_HASH__'){throw 'exact compiled pins required'}
$p=Get-Content -Raw -LiteralPath $PlanPath|ConvertFrom-Json;$c=Get-Content -Raw -LiteralPath $ReceiptPath|ConvertFrom-Json
if($p.executionEligible -ne $false -or $p.sourceHash -cne '__SOURCE_HASH__' -or $p.case.id -cne '__CASE_ID__' -or $p.case.hash -cne '__CASE_HASH__' -or $p.tuple.id -cne '__TUPLE_ID__' -or $p.compileRequest.maxParallelJobs -ne 1){throw 'host plan identity/lane mismatch'}
if($c.phase -cne '__RECEIPT_PHASE__' -or $c.exitCode -ne 0 -or $c.timedOut -or $c.outputCapExceeded -or -not $c.ownedExited -or -not $c.originalHandleRetained -or $c.kernelWait -ne 0 -or -not $c.streamDrainComplete -or -not $c.streamsSealed -or $c.jobActiveCount -ne 0 -or $c.cleanupJobActive -ne 0 -or $c.memoryCapBytes -ne 1073741824 -or $c.nativeActions -ne 0 -or $c.sourceHash -ne $p.sourceHash -or $c.exeSha256 -ne $ExeSha256 -or $c.exeBytes -ne $ExeBytes -or (Get-Item -LiteralPath $c.exePath).Length -ne $ExeBytes -or (Get-Item -LiteralPath $p.rendererPath).Length -ne $RendererBytes -or (Get-Item -LiteralPath '__SERIALIZER_PATH__').Length -ne $SerializerControlBytes){throw 'compile lifecycle/byte admission failed'}
[ordered]@{kind='root-pilot-native-capture-compile-admission-v1';status='passed';case=$p.case;compileReceiptSha256=$CompileReceiptSha256;exeSha256=$ExeSha256;sourceHash=$p.sourceHash;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
'''
preflight=preflight.replace('__HOST_ROOT__',target_root).replace('__PACKAGE__',package_path).replace('__COMPILE_PATH__',compile_path).replace('__PLAN_HASH__',plan_hash).replace('__COMPILE_HASH__',compile_hash).replace('__COMPILE_BYTES__',str(compile_bytes)).replace('__EXE_HASH__',exe_hash).replace('__EXE_BYTES__',str(exe_bytes)).replace('__RECEIPT_PHASE__',phase).replace('__SERIALIZER_HASH__',serializer_hash).replace('__SERIALIZER_BYTES__',str(serializer_bytes)).replace('__SERIALIZER_PATH__',serializer_path).replace('__SOURCE_HASH__',source_hash).replace('__CASE_ID__',case_id).replace('__CASE_HASH__',case_hash).replace('__TUPLE_ID__',tuple_id).replace('__RENDERER_BYTES__',str(renderer_bytes))
# PowerShell's built-in `h` alias resolves before a function named H.
preflight=preflight.replace('function H(', 'function GetRootCaptureArtifactSha256(').replace('(H ', '(GetRootCaptureArtifactSha256 ')
files['overlay/preflight-color-r1.ps1']=preflight.encode();si['buildPreflightHash']=sha(files['overlay/preflight-color-r1.ps1'])
# Patch only known Rectangle kind literals, retaining every identity/lifecycle
# clause. Each replacement must match exactly once when present.
def patch_guard(rel,old,new):
    text=files[rel].decode();count=text.count(old)
    if count>1: raise SystemExit(f'ambiguous guard needle: {rel}: {old}')
    if count==1: text=text.replace(old,new,1)
    files[rel]=text.encode()
for rel in ('overlay/capture-rectangle-single-v3.ps1','overlay/dispatch-rectangle-single-v3.ps1','overlay/issue-rectangle-metadata-v1.ps1','overlay/integration-fresh-rectangle-v1.ps1'):
    patch_guard(rel,"$plan.kind -ne 'factory-rectangle-compiler-plan-v2'", "$plan.kind -notin @('factory-rectangle-compiler-plan-v2','factory-pilot-five-compiler-plan-v1')")
    patch_guard(rel,"$receipt.kind -ne 'factory-rectangle-owned-compile-v1'", "$receipt.kind -notin @('factory-rectangle-owned-compile-v1','factory-pilot-five-owned-compile-v1')")
    patch_guard(rel,"$sourceDocument.kind -ne 'factory-rectangle-source-inputs-v1'", "$sourceDocument.kind -notin @('factory-rectangle-source-inputs-v1','factory-pilot-source-inputs-v1')")
    patch_guard(rel,"$sourceDocument.kind -cne 'factory-rectangle-source-inputs-v1'", "$sourceDocument.kind -notin @('factory-rectangle-source-inputs-v1','factory-pilot-source-inputs-v1')")
    patch_guard(rel,"$plan.hostMode -ne 'renderer'", '$plan.executionEligible -ne $false')
# Capture worker names receipt as `$compiled`; keep its positive lifecycle
# admission while accepting measured pilot receipt kind.
patch_guard('overlay/capture-rectangle-single-v3.ps1', "$compiled.kind -ne 'factory-rectangle-owned-compile-v1'", "$compiled.kind -notin @('factory-rectangle-owned-compile-v1','factory-pilot-five-owned-compile-v1')")
# Pilot compile schema pins runtime tree/receipt, not legacy capture helper.
# Pin actual staged verifier bytes directly, also covered by source closure.
capture_rel='overlay/capture-rectangle-single-v3.ps1'
capture_text=files[capture_rel].decode()
if capture_text.count('$plan.runtimeVerifierHash')!=2:raise SystemExit('runtime verifier guard anchors drift')
capture_text=capture_text.replace('$plan.runtimeVerifierHash', "'"+sha(files['producer/support/verify-runtime-source.ps1'])+"'")
# A legitimate early host exit can leave MainWindowHandle null. Preserve its
# original exit code rather than failing window inventory on a null method.
if capture_text.count('$p.MainWindowHandle.ToInt64()')!=2:raise SystemExit('main-window observation anchors drift')
capture_text=capture_text.replace('$p.MainWindowHandle.ToInt64()',
    '$(if($null -eq $p.MainWindowHandle){[Int64]0}else{$p.MainWindowHandle.ToInt64()})')
early_exit="if($p.HasExited){throw 'Renderer exited before capture'}"
if capture_text.count(early_exit)!=1:raise SystemExit('early renderer exit anchor drift')
capture_text=capture_text.replace(early_exit, 'if($p.HasExited){throw ("Renderer exited before capture; original exitCode="+$p.ExitCode)}')
files[capture_rel]=capture_text.encode()
# Donor callers predate measured size parameters. Forward exact archived
# byte counts at every preflight call; retain mandatory byte/hash assertions.
byte_arguments=f' -CompileReceiptBytes {compile_bytes} -ExeBytes {exe_bytes} -SerializerControlBytes {serializer_bytes} -RendererBytes {renderer_bytes}'
for rel,variable,count in [('overlay/dispatch-rectangle-single-v3.ps1','buildPreflightPath',1),('overlay/capture-rectangle-single-v3.ps1','buildPreflight',2)]:
    old=f'& ${variable} -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256'
    text=files[rel].decode()
    if text.count(old)!=count:raise SystemExit('preflight byte forwarding anchor drift: '+rel)
    files[rel]=text.replace(old,old+byte_arguments).encode()
# Mac sidecar/missing-host holds relax only Mac tuple equality; all later
# source/case/receipt/metadata/binding checks still execute.
rel='overlay/integration-fresh-rectangle-v1.ps1';text=files[rel].decode()
old=" if([string]::IsNullOrWhiteSpace([string]$tupleID) -or [string]::IsNullOrWhiteSpace([string]$sourceHash) -or [string]::IsNullOrWhiteSpace([string]$caseID) -or [string]::IsNullOrWhiteSpace([string]$caseHash) -or [string]::IsNullOrWhiteSpace([string]$macHash) -or [string]::IsNullOrWhiteSpace([string]$winHash)){throw 'Rectangle context identity incomplete'}"
new=" $macHold=$Context.qualificationHold -in @('observational-hold-missing-macos-host','observational-hold-macos-sidecar-unqualified')\n if([string]::IsNullOrWhiteSpace([string]$tupleID) -or [string]::IsNullOrWhiteSpace([string]$sourceHash) -or [string]::IsNullOrWhiteSpace([string]$caseID) -or [string]::IsNullOrWhiteSpace([string]$caseHash) -or [string]::IsNullOrWhiteSpace([string]$winHash) -or (-not $macHold -and [string]::IsNullOrWhiteSpace([string]$macHash))){throw 'Rectangle context identity incomplete'}\n if($macHold -and $Context.qualified -ne $false){throw 'Mac observational hold must remain unqualified'}"
if text.count(old)!=1: raise SystemExit('integration context identity guard anchor drift')
text=text.replace(old,new,1)
old=" if($tupleID -cne $SourceInputs.tupleID -or $sourceHash -cne $SourceInputs.sourceHash -or $caseID -cne $SourceInputs.caseID -or $caseHash -cne $SourceInputs.caseHash -or $macHash -cne $Tuple.tuple.hostHashes.macos -or $winHash -ne $Tuple.tuple.hostHashes.windows){throw 'Rectangle context closure mismatch'}"
new=" if($tupleID -cne $SourceInputs.tupleID -or $sourceHash -cne $SourceInputs.sourceHash -or $caseID -cne $SourceInputs.caseID -or $caseHash -cne $SourceInputs.caseHash -or $winHash -ne $Tuple.tuple.hostHashes.windows -or (-not $macHold -and $macHash -cne $Tuple.tuple.hostHashes.macos)){throw 'Rectangle context closure mismatch'}"
if text.count(old)!=1: raise SystemExit('integration context closure guard anchor drift')
text=text.replace(old,new,1);files[rel]=text.encode()
# Rebind source-input ref hashes/bytes after metadata & integration files are finalized.
for rel,key in [('admission/context.json','contextRef'),('admission/candidate-tuple.json','tupleRef'),('admission/candidate-binding.json','bindingRef'),('admission/recipe.json','recipeRef'),('producer/integration-bindings.json','integrationBindingsRef')]:
    b=files[rel];si[key].update(bytes=len(b),sha256='sha256:'+sha(b))
si['tupleHash']=unprefix(si['tupleRef']['sha256']);si['bindingHash']=unprefix(si['bindingRef']['sha256']);si['recipeHash']=unprefix(si['recipeRef']['sha256']);si['integrationBindingsHash']=unprefix(si['integrationBindingsRef']['sha256'])
files['admission/source-inputs.json']=jd(si)
# Host binding is explicit & independently joined to final plan/source/tuple pins.
host_binding={'kind':'factory-pilot-host-plan-binding-v1','host':a.host,'count':1,'revision':a.revision,'case':{'id':case_id,'hash':case_hash},'rawCase':{'path':winpath(raw_case_path),'sha256':'sha256:'+raw_case_hash},'canonicalCase':{'path':package_path+'\\materialized-case.json','bytes':case_artifact_bytes,'sha256':'sha256:'+case_artifact_hash},'recipe':{'id':recipe_id,'hash':recipe_hash,'registryHash':packet_recipe_hash},'tuple':{'id':tuple_id,'hash':'sha256:'+si['tupleHash']},'source':{'hash':source_hash,'runtimeCommit':runtime_commit,'runtimeTreeHash':runtime_tree},'compiledPlan':{'path':package_path+'\\plan.json','bytes':len(plan_raw),'sha256':'sha256:'+plan_hash},'compileReceipt':{'path':compile_path,'bytes':compile_bytes,'sha256':'sha256:'+compile_hash},'executable':{'path':exe_path,'bytes':exe_bytes,'sha256':'sha256:'+exe_hash},'serializerControl':{'path':serializer_path,'bytes':serializer_bytes,'sha256':'sha256:'+serializer_hash},'renderer':{'path':renderer_path,'bytes':renderer_bytes,'sha256':'sha256:'+renderer_hash},'package':package_path,'sourceStage':str(out/'sources'),'qualification':'observational-hold-macos-sidecar-unqualified' if mac_sidecar else 'observational-hold-missing-macos-host','macSidecar':mac_sidecar,'nativeActions':0,'compilerActions':0,'lockActions':0}
files['admission/host-plan-binding.json']=jd(host_binding)
# Final bottom-up reseal catches helper pins embedded in parent PowerShell
# guards (including Count1 worker invoker) after every source edit.
rebind_source_pin_graph(files, manifest['files'])
si=json.loads(files['admission/source-inputs.json'].decode('utf-8-sig'))
for key,rel in (('contextRef','admission/context.json'),('tupleRef','admission/candidate-tuple.json'),('bindingRef','admission/candidate-binding.json'),('recipeRef','admission/recipe.json'),('integrationBindingsRef','producer/integration-bindings.json')):
    ref=si.get(key);data=files[rel]
    if not isinstance(ref,dict) or ref.get('bytes')!=len(data) or unprefix(ref.get('sha256',''))!=sha(data): raise SystemExit(f'final source pin join failed: {key}')
# Recompute final source metadata paths and write manifest.
for rel,data in files.items():
    dest=sources/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
rows=[{'path':rel,'bytes':len(data),'sha256':sha(data)} for rel,data in files.items()]
stage={'kind':'factory-pilot-native-capture-source-stage-v1','host':a.host,'count':1,'files':rows,'roots':target_roots,'nativeActions':0,'compilerActions':0,'lockActions':0}
stage_raw=jd(stage)
# Manifest describes payload files. Its own identity is bound by ZIP hash;
# adding a self row changes serialized bytes after hashing & cannot close.
assert all(row['path']!='stage-manifest.json' for row in rows)
(sources/'stage-manifest.json').write_bytes(stage_raw)
# Root installer stages graph, performs actual compile receipt admission, then writes config and runs source preflight.
zip_path=CACHE/f'{a.host}-native-capture-r{a.revision}.zip';zip_path.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
    for rel,data in files.items():z.writestr(rel,data)
    z.writestr('stage-manifest.json',stage_raw)
installer=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='__HOST_ROOT__';$NS='__NS__';$Package='__PACKAGE__';$Zip='D:\Claude\swiftright\.factory-work\__ZIP__';$ZipHash='__ZIP_HASH__';$Overlay=Join-Path $NS 'overlay-count1-r__REV__';$Producer=Join-Path $NS 'producer-count1-r__REV__';$Admission=Join-Path $NS 'admission-count1-r__REV__';$Control=Join-Path $NS 'control-count1-r__REV__';$Output=Join-Path $NS 'native';$Run=Join-Path $Output 'count1-r1';$Stage=Join-Path $NS 'source-stage'
if(Test-Path $NS){throw 'fresh host capture namespace required'}
New-Item -ItemType Directory -Path $NS -Force|Out-Null
 $PlanPath=Join-Path $Package 'plan.json';$FinalPlanPath=Join-Path $Package 'plan-final-v4.json';$Retired=Join-Path $NS 'retired'
if(Test-Path -LiteralPath $PlanPath){New-Item -ItemType Directory -Path $Retired -Force|Out-Null;Move-Item -LiteralPath $PlanPath -Destination (Join-Path $Retired 'plan-old.json')}
if(Test-Path -LiteralPath $FinalPlanPath){if((Get-FileHash -LiteralPath $FinalPlanPath).Hash.ToLowerInvariant() -cne '__PLAN_HASH__'){throw 'existing final plan drift'}}else{[IO.File]::WriteAllBytes($FinalPlanPath,[Convert]::FromBase64String('__PLAN_BASE64__'))}
if((Get-FileHash -LiteralPath $FinalPlanPath).Hash.ToLowerInvariant() -cne '__PLAN_HASH__' -or (Get-Item -LiteralPath $FinalPlanPath).Length -ne __PLAN_BYTES__){throw 'final plan bytes drift'}
Copy-Item -LiteralPath $FinalPlanPath -Destination $PlanPath -Force
if((Get-FileHash -LiteralPath $PlanPath).Hash.ToLowerInvariant() -cne '__PLAN_HASH__' -or (Get-Item -LiteralPath $PlanPath).Length -ne __PLAN_BYTES__){throw 'installed plan bytes drift'}
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne $ZipHash){throw 'capture source zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$m=Get-Content -Raw -LiteralPath (Join-Path $Stage 'stage-manifest.json')|ConvertFrom-Json;$total=0;foreach($r in @($m.files)){$f=Get-Item -LiteralPath (Join-Path $Stage $r.path) -Force;$total+=$f.Length;if($f.Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant() -cne $r.sha256){throw 'source stage byte drift'}};if($total -gt 16777216){throw 'source stage cap'}
foreach($pair in @(@($Producer,'producer'),@($Admission,'admission'),@($Overlay,'overlay'))){$srcRoot=Join-Path $Stage $pair[1];if(-not(Test-Path -LiteralPath $srcRoot -PathType Container)){throw ('source stage root missing: '+$pair[1])};New-Item -ItemType Directory -Path $pair[0] -Force|Out-Null;$children=@(Get-ChildItem -LiteralPath $srcRoot -Force);if($children.Count -gt 128){throw 'source stage child cap exceeded'};foreach($child in $children){if($child.FullName.StartsWith($srcRoot+'\',[StringComparison]::OrdinalIgnoreCase) -and $child.Name -notin @('.','..')){Copy-Item -LiteralPath $child.FullName -Destination (Join-Path $pair[0] $child.Name) -Recurse -Force}else{throw 'source stage child escaped root'}}}
New-Item -ItemType Directory -Path $Control -Force|Out-Null;New-Item -ItemType Directory -Path $Output -Force|Out-Null
& (Join-Path $Overlay 'preflight-color-r1.ps1') -Phase Launch -CompileReceiptSha256 '__COMPILE_HASH__' -CompileReceiptBytes __COMPILE_BYTES__ -ExeSha256 '__EXE_HASH__' -ExeBytes __EXE_BYTES__ -SerializerControlSha256 '__SERIALIZER_HASH__' -SerializerControlBytes __SERIALIZER_BYTES__ -RendererBytes __RENDERER_BYTES__|Set-Content -LiteralPath (Join-Path $Control 'root-preflight.json') -Encoding UTF8
$si=Get-Content -Raw -LiteralPath (Join-Path $Admission 'source-inputs.json')|ConvertFrom-Json
$cfg=[ordered]@{kind='factory-pilot-native-capture-config-v1';count=1;owner='pending-root-lock';qualification='__QUALIFICATION__';package=$Package;producerRoot=$Producer;admissionRoot=$Admission;overlayRoot=$Overlay;controlRoot=$Control;outputRoot=$Output;runRoot=$Run;sourceInputsPath=(Join-Path $Admission 'source-inputs.json');sourceInputsHash=(Get-FileHash (Join-Path $Admission 'source-inputs.json')).Hash.ToLowerInvariant();compileReceiptHash='__COMPILE_HASH__';compileReceiptBytes=__COMPILE_BYTES__;exeHash='__EXE_HASH__';exeBytes=__EXE_BYTES__;serializerControlSha256='__SERIALIZER_HASH__';serializerControlBytes=__SERIALIZER_BYTES__;rendererBytes=__RENDERER_BYTES__;integrationGuardPath=(Join-Path $Overlay 'integration-fresh-rectangle-v1.ps1');integrationGuardHash=(Get-FileHash (Join-Path $Overlay 'integration-fresh-rectangle-v1.ps1')).Hash.ToLowerInvariant();issuedMetadataPath=(Join-Path $Admission 'issued-metadata.json')}
$cfg|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $Control 'config-template.json') -Encoding UTF8
& (Join-Path $Overlay 'issue-rectangle-metadata-v1.ps1') -Count 1 -SourceInputsPath $cfg.SourceInputsPath -SourceInputsHash $cfg.sourceInputsHash -OutputPath $cfg.issuedMetadataPath -RunRoot $Run -PlanPath $si.planRef.path -PlanHash $si.planHash -CompileReceiptPath $si.compileReceiptPath -CompileReceiptHash $cfg.compileReceiptHash -ExePath $si.exePath -ExeHash $cfg.exeHash -RendererPath $si.rendererPath -RendererHash $si.rendererSha256 -SerializerPath $si.serializerPath -SerializerHash $cfg.serializerControlSha256 -TuplePath $si.tupleRef.path -TupleHash $si.tupleHash -BindingPath $si.bindingRef.path -BindingHash $si.bindingHash -RecipePath $si.recipeRef.path -RecipeHash $si.recipeHash
$cfg.issuedMetadataHash=(Get-FileHash -LiteralPath $cfg.issuedMetadataPath).Hash.ToLowerInvariant();$cfg|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $Control 'config-template.json') -Encoding UTF8;$cfgHash=(Get-FileHash -LiteralPath (Join-Path $Control 'config-template.json')).Hash.ToLowerInvariant()
[ordered]@{kind='factory-pilot-native-entry-pins-v1';preflightHash=(Get-FileHash -LiteralPath (Join-Path $Control 'root-preflight.json')).Hash.ToLowerInvariant();templateHash=$cfgHash;compileReceiptHash=$cfg.compileReceiptHash;exeHash=$cfg.exeHash;issuedMetadataHash=$cfg.issuedMetadataHash}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Control 'native-entry-pins.json') -Encoding UTF8
& (Join-Path $Overlay 'coordinator-count1-v3.ps1') -Template (Join-Path $Control 'config-template.json') -TemplateHash $cfgHash -PreflightOnly|Set-Content -LiteralPath (Join-Path $Control 'coordinator-preflight.json') -Encoding UTF8
[ordered]@{status='admission-ready';nativeActions=0;compilerActions=0;lockActions=0;configHash=$cfgHash;issuedMetadataHash=$cfg.issuedMetadataHash}|ConvertTo-Json
'''
zip_rel=zip_path.name
plan_b64=base64.b64encode(plan_raw).decode('ascii')
for k,v in {'HOST_ROOT':target_root,'NS':target_ns,'PACKAGE':package_path,'ZIP':zip_rel,'ZIP_HASH':sha(rd(zip_path)),'REV':str(a.revision),'PLAN_HASH':plan_hash,'PLAN_BYTES':str(len(plan_raw)),'PLAN_BASE64':plan_b64,'COMPILE_HASH':compile_hash,'COMPILE_BYTES':str(compile_bytes),'EXE_HASH':exe_hash,'EXE_BYTES':str(exe_bytes),'SERIALIZER_HASH':serializer_hash,'SERIALIZER_BYTES':str(serializer_bytes),'RENDERER_BYTES':str(renderer_bytes),'QUALIFICATION':'observational-hold-macos-sidecar-unqualified' if mac_sidecar else 'observational-hold-missing-macos-host'}.items():installer=installer.replace('__'+k+'__',v)
(out/f'install-native-capture-r{a.revision}.ps1').write_text(installer)
# Native entry invokes coordinator only after exact preflight/config/issued/source joins.
entry=r'''$ErrorActionPreference='Stop';$Control='__CONTROL__';$Template=Join-Path $Control 'config-template.json';$Preflight=Join-Path $Control 'root-preflight.json';$Pins=Get-Content -Raw -LiteralPath (Join-Path $Control 'native-entry-pins.json')|ConvertFrom-Json;$C=Get-Content -Raw -LiteralPath $Template|ConvertFrom-Json;$hashPre=(Get-FileHash -LiteralPath $Preflight).Hash.ToLowerInvariant();$hashTpl=(Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant();if($hashPre -ne $Pins.preflightHash -or $hashTpl -ne $Pins.templateHash){throw 'preflight/config drift'};if($C.count -ne 1 -or $C.compileReceiptHash -ne '__COMPILE_HASH__' -or $C.exeHash -ne '__EXE_HASH__' -or $C.compileReceiptBytes -ne __COMPILE_BYTES__ -or $C.exeBytes -ne __EXE_BYTES__ -or $C.serializerControlBytes -ne __SERIALIZER_BYTES__ -or $C.rendererBytes -ne __RENDERER_BYTES__ -or $C.issuedMetadataHash -ne $Pins.issuedMetadataHash -or $C.issuedMetadataHash -ne (Get-FileHash -LiteralPath $C.issuedMetadataPath).Hash.ToLowerInvariant()){throw 'actual metadata/source pin mismatch'};$I=Get-Content -Raw -LiteralPath $C.issuedMetadataPath|ConvertFrom-Json;if($I.expectedCount -ne 1 -or $I.compile.sha256 -ne ('sha256:'+'__COMPILE_HASH__') -or $I.compile.bytes -ne __COMPILE_BYTES__ -or $I.exe.sha256 -ne ('sha256:'+'__EXE_HASH__') -or $I.exe.bytes -ne __EXE_BYTES__ -or $I.renderer.bytes -ne __RENDERER_BYTES__){throw 'issued metadata join mismatch'};& '__COORDINATOR__' -Template $Template -TemplateHash $Pins.templateHash;Get-Content -Raw -LiteralPath (Join-Path $Control 'coordinator.json')
'''
entry=entry.replace('__CONTROL__',target_roots['overlay'].replace('overlay-count1-r'+str(a.revision),'control-count1-r'+str(a.revision))).replace('__COMPILE_HASH__',compile_hash).replace('__COMPILE_BYTES__',str(compile_bytes)).replace('__EXE_HASH__',exe_hash).replace('__EXE_BYTES__',str(exe_bytes)).replace('__SERIALIZER_BYTES__',str(serializer_bytes)).replace('__RENDERER_BYTES__',str(renderer_bytes)).replace('__COORDINATOR__',target_roots['overlay']+'\\coordinator-count1-v3.ps1')
(out/f'native-entry-count1-r{a.revision}.ps1').write_text(entry)
prep={'kind':'factory-pilot-native-capture-preparation-v1','host':a.host,'count':1,'revision':a.revision,'donorRows':len(files),'planPath':str(plan_path),'planSha256':plan_hash,'compileReceiptHash':compile_hash,'compileReceiptPath':compile_path,'compileReceiptBytes':compile_bytes,'exeHash':exe_hash,'exePath':exe_path,'exeBytes':exe_bytes,'serializerControlSha256':serializer_hash,'serializerControlBytes':serializer_bytes,'rendererSha256':renderer_hash,'rendererBytes':renderer_bytes,'nativeActions':0,'compilerActions':0,'lockActions':0,'qualification':'observational-hold-macos-sidecar-unqualified' if mac_sidecar else 'observational-hold-missing-macos-host','macSidecar':mac_sidecar}
(out/'preparation.json').write_bytes(jd(prep))
print(json.dumps({'host':a.host,'output':str(out),'installer':str(out/f'install-native-capture-r{a.revision}.ps1'),'entry':str(out/f'native-entry-count1-r{a.revision}.ps1'),'zip':str(zip_path),'rows':len(files),'nativeActions':0}))
