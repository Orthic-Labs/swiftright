from pathlib import Path
import hashlib,json,struct,datetime,re
ROOT=Path(__file__).resolve().parents[6]
SEED=ROOT/'factory/native/windows/seed-stack-lifecycle-host-v1'
OWN=Path(__file__).resolve().parent
PLANS={'lifecycle':'82f29632a9a2937fa313ba52eee5b2a4dbc1b23b1a24ebbced923107cbe3cbcd'}
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def pin(p):return {'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':h(p)}
def checkhash(p,v):assert h(p)==v.removeprefix('sha256:'),(p,v)
def ticks(s):
 m=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',s);assert m,s
 d=datetime.datetime.fromisoformat(m[1]+m[3].replace('Z','+00:00'));delta=d-datetime.datetime(1,1,1,tzinfo=datetime.timezone.utc)
 return (delta.days*86400+delta.seconds)*10000000+int((m[2] or '').ljust(7,'0'))
def verify(label):
 base=SEED;pkg=base/'package';out=base/'build-actual-lifecycle-v1-r1';plan=load(pkg/'plan.json');receipt=load(out/'observation.json');refs=[]
 assert h(pkg/'plan.json')==PLANS[label]
 remote='D:\\Claude\\swiftright\\factory\\native\\windows\\seed-stack-lifecycle-host-v1\\package'
 assert receipt['cwd']==remote
 for k in ['sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','compilerHash','rendererSha256']:assert receipt[k]==plan[k]
 assert receipt['planSha256']==PLANS[label]
 for b in plan['sourceBindings']:checkhash(pkg/b['path'],b['sha256']);refs.append(pin(pkg/b['path']))
 actual={str(p.relative_to(pkg)) for p in (pkg/'Sources').rglob('*') if p.is_file()}|{'Package.swift'}
 assert actual=={b['path'] for b in plan['sourceBindings'] if b['path']=='Package.swift' or b['path'].startswith('Sources/')}
 for name,key in [('runtime-source-receipt.json','runtimeSourceReceiptHash'),('runtime-source-tree.json','runtimeSourceTreeFileHash')]:checkhash(pkg/name,plan[key]);refs.append(pin(pkg/name))
 runtime=ROOT/'factory/native/windows/module-origin-37429120-20261011/runtime'
 tree=load(pkg/'runtime-source-tree.json');assert len(tree)==21 and len({b['path'] for b in tree})==21
 for b in tree:checkhash(runtime/b['path'],b['sha256']);refs.append(pin(runtime/b['path']))
 assert {b['path'] for b in tree}=={'Package.swift'}|{str(p.relative_to(runtime)) for p in (runtime/'Sources').rglob('*') if p.is_file()}
 bridge=ROOT/'factory/native/windows/first-capture-corrections-v1/staged-bridge-inputs-r09'
 assert len(plan['bridgeBindings'])==10
 for b in plan['bridgeBindings']:checkhash(bridge/b['path'],b['sha256']);assert (bridge/b['path']).stat().st_size==b['bytes'];refs.append(pin(bridge/b['path']))
 checkhash(bridge/'receipt.json',plan['bridgeInputSnapshotReceiptHash']);refs.append(pin(bridge/'receipt.json'))
 compiler=ROOT/'factory/native/windows/module-origin-37429120-20261011/module-provenance-run-r4/compiler-input/swift.exe';checkhash(compiler,plan['compilerHash']);refs.append(pin(compiler))
 renderer=ROOT/'factory/native/windows/staged-renderer-byte-archive-v1/swiftright_render.dll.bin';checkhash(renderer,plan['rendererSha256']);assert renderer.stat().st_size==11885056;refs.append(pin(renderer))
 for k,v in {'exitCode':0,'timedOut':False,'ownedExited':True,'error':None,'cleanupError':None,'cleanupAction':'natural-exit-no-termination','streamDrainComplete':True,'nativeWindowOpened':False,'nativeParity':'hold','frozenTupleBound':False,'closureBinding':None,'descendantOwnership':'not-observed'}.items():assert type(receipt[k]) is type(v) and receipt[k]==v,(label,k)
 assert type(receipt['pid']) is int and receipt['pid']>0
 start,proc,end=map(ticks,[receipt['startedAt'],receipt['processStartedAt'],receipt['finishedAt']]);assert start<=proc<end and end-start<315*10000000
 dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
 expected='build --package-path "'+remote+'" --scratch-path "'+remote+'\\build-lifecycle-v1-r1\\scratch" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
 assert receipt['argv']==expected
 assert {r['path'] for r in receipt['files']}=={'compile.stdout.bin','compile.stderr.bin','FactoryProbe.exe'} and len(receipt['files'])==3
 for b in receipt['files']:checkhash(out/b['path'],b['sha256']);assert type(b['bytes']) is int and (out/b['path']).stat().st_size==b['bytes'];refs.append(pin(out/b['path']))
 checkhash(out/'FactoryProbe.exe',receipt['exeSha256']);raw=(out/'FactoryProbe.exe').read_bytes();assert raw[:2]==b'MZ';pe=struct.unpack_from('<I',raw,60)[0];assert raw[pe:pe+4]==b'PE\0\0' and struct.unpack_from('<H',raw,pe+92)[0]==receipt['exeSubsystem']==2
 assert receipt['exePath']==remote+'\\build-lifecycle-v1-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe'
 stdout=(out/'compile.stdout.bin').read_bytes();assert b'Build complete!' in stdout
 transfer=load(base/'root-build-output-scp-r1.json');assert len(transfer['transfers'])==4 and all(x['exitCode']==0 and x['stderr']=='' for x in transfer['transfers'])
 for p,v in transfer['files'].items():checkhash(ROOT/p,v)
 refs += [pin(pkg/'plan.json'),pin(out/'observation.json'),pin(base/'root-build-output-scp-r1.json')]
 return {'label':label,'exit':0,'pid':receipt['pid'],'start':receipt['startedAt'],'end':receipt['finishedAt'],'exeSha256':receipt['exeSha256'],'scope':'Successful guarded compiler output; receipt attests natural retained-handle exit & drains. Descendants not independently observed. No native launch/parity. Exact archived renderer bytes independently rehashed.','references':refs}

if __name__=='__main__':
 result=verify('lifecycle')
 receipt=load(SEED/'build-actual-lifecycle-v1-r1/observation.json');plan=load(SEED/'package/plan.json')
 assert receipt['kind']=='factory-lifecycle-diagnostic-compile-only-owned-handle-v1'
 assert receipt['diagnosticScope']==plan['diagnosticScope']=='factory-stack-host-lifecycle-v1'
 assert receipt['diagnosticLineage']==plan['diagnosticLineage']
 checkhash(SEED/'adapt-host.py',plan['diagnosticLineage']['adapterSha256'])
 stage=SEED/'root-stage-manifest.json';checkhash(stage,'fada5ea5455bce12333823d51760563eaf5855c26613bc90710fb4e1edb27d10')
 for b in load(stage)['files']:
  p=ROOT/b['path'];checkhash(p,b['sha256']);assert p.stat().st_size==b['bytes']
 controls=SEED/'root-before-compile-controls-r1/receipt.json';c=load(controls)
 assert c['passed'] is True and c['error'] is None and c['stageSha256']==h(stage)
 assert ticks(c['finishedAt'])<ticks(receipt['startedAt'])
 for b in c['files']:
  p=controls.parent/b['path'].replace('\\','/');checkhash(p,b['sha256']);assert p.stat().st_size==b['bytes']
 for k in ['astPassed','cleanupPassed','hostInputsPassed','integerPassed','productionAdmissionPassed','productionInvocationProofPassed']:assert c[k] is True
 checkhash(SEED/'root-before-compile-controls.ps1',c['entrySha256'])
 controlReview=SEED/'independent-review/actual-controls-r1/root-stage-manifest.json'
 for b in load(controlReview)['files']:
  p=ROOT/b['path'];checkhash(p,b['sha256']);assert p.stat().st_size==b['bytes']
 result['references'] += [pin(stage),pin(controls),pin(controlReview),pin(SEED/'adapt-host.py'),pin(SEED/'build-lifecycle.ps1'),pin(SEED/'run-compile.ps1')]
 result['diagnosticLineage']=receipt['diagnosticLineage']
 result['precompileControlsBeforeCompiler']=True
 result['decision']='clear-exact-diagnostic-compiler-output'
 print(json.dumps(result,indent=2))
