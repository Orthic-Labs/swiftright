from pathlib import Path
import hashlib,json,struct,datetime,re
ROOT=Path(__file__).resolve().parents[5]
SEED=ROOT/'factory/native/windows/round1-seeded-hosts-v1'
OWN=Path(__file__).resolve().parent
PLANS={'custom-layout':'ab6cda2ffa89f13ae5ccb8d281a4deff91a28601597e809b7379e29b129279ee','padding-frame':'be73260accb728a1a613913be4503fae8414623218d129b7ed38eb2f609c7aaf','preference-key':'f61fee02568923f75f95ad46ffbfcdd6aeda17a07fc3c30fcafcd1540134d7d5','scroll-view':'cc751e98ed32e17b50797751b06e82e54b294592ff60ca0184db8cec32ed00b9','stack-overlay':'4cc752eee6d227bf2fcbff60e2822f8199f233a904e1a8087f5a3ddd65f19f9b'}
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def pin(p):return {'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':h(p)}
def checkhash(p,v):assert h(p)==v.removeprefix('sha256:'),(p,v)
def ticks(s):
 m=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',s);assert m,s
 d=datetime.datetime.fromisoformat(m[1]+m[3].replace('Z','+00:00'));delta=d-datetime.datetime(1,1,1,tzinfo=datetime.timezone.utc)
 return (delta.days*86400+delta.seconds)*10000000+int((m[2] or '').ljust(7,'0'))
def verify(label):
 base=SEED/label;pkg=base/'package';out=base/'build-actual-v2-r1';plan=load(pkg/'plan.json');receipt=load(out/'observation.json');refs=[]
 assert h(pkg/'plan.json')==PLANS[label]
 remote='D:\\Claude\\swiftright\\factory\\native\\windows\\round1-seeded-hosts-v1\\'+label+'\\package'
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
 expected='build --package-path "'+remote+'" --scratch-path "'+remote+'\\build-v2-r1\\scratch" -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
 assert receipt['argv']==expected
 assert {r['path'] for r in receipt['files']}=={'compile.stdout.bin','compile.stderr.bin','FactoryProbe.exe'} and len(receipt['files'])==3
 for b in receipt['files']:checkhash(out/b['path'],b['sha256']);assert type(b['bytes']) is int and (out/b['path']).stat().st_size==b['bytes'];refs.append(pin(out/b['path']))
 checkhash(out/'FactoryProbe.exe',receipt['exeSha256']);raw=(out/'FactoryProbe.exe').read_bytes();assert raw[:2]==b'MZ';pe=struct.unpack_from('<I',raw,60)[0];assert raw[pe:pe+4]==b'PE\0\0' and struct.unpack_from('<H',raw,pe+92)[0]==receipt['exeSubsystem']==2
 assert receipt['exePath']==remote+'\\build-v2-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe'
 stdout=(out/'compile.stdout.bin').read_bytes();assert b'Build complete!' in stdout
 transfer=load(base/'root-build-v2-output-scp.json');assert len(transfer['transfers'])==4 and all(x['exitCode']==0 and x['stderr']=='' for x in transfer['transfers'])
 for p,v in transfer['files'].items():checkhash(ROOT/p,v)
 refs += [pin(pkg/'plan.json'),pin(out/'observation.json'),pin(base/'root-build-v2-output-scp.json')]
 return {'label':label,'exit':0,'pid':receipt['pid'],'start':receipt['startedAt'],'end':receipt['finishedAt'],'exeSha256':receipt['exeSha256'],'scope':'Successful guarded compiler output; receipt attests natural retained-handle exit & drains. Descendants not independently observed. No native launch/parity. Exact archived renderer bytes independently rehashed.','references':refs}
if __name__=='__main__':
 rows=[];pending=[]
 for label in PLANS:
  if (SEED/label/'build-actual-v2-r1/observation.json').exists() and (SEED/label/'root-build-v2-output-scp.json').exists():rows.append(verify(label))
  else:pending.append(label)
 report={'kind':'seeded-actual-compiler-review-v1','completed':rows,'pending':pending,'compilerOrNativeRunsByReviewer':0}
 print(json.dumps(report,indent=2))
