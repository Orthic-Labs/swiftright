"""Pin one source-only pilot packet to bounded native retained-handle compiler lifecycle."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,zipfile
p=argparse.ArgumentParser();p.add_argument('--host',choices=('image','image-v2','image-star-provider','image-star-observation','stack-overlay-colors','custom-layout-colors','rounded-stroke-boundary','bundled-font-compiled','bundled-font-live','bundled-font-observation','rounded-stroke','rounded-stroke-centered','rounded-stroke-circular','rounded-stroke-observation','stack-overlay-centered','stack-overlay-observation','custom-layout','custom-layout-v2','custom-layout-centered','custom-layout-observation'),required=True);p.add_argument('--compile-revision',type=int,choices=range(1,11),default=1);p.add_argument('--source-packet',type=Path,help='packet root under checkout; must contain package/plan.json & package/case.json');p.add_argument('--runtime-source-receipt',type=Path,help='factory-additive-runtime-source receipt bound to packet plan');a=p.parse_args()
repo=Path('/Volumes/D/claude/swiftright')
rel={'image':'text-shape-image/image-host-package-v1','image-v2':'text-shape-image/image-host-package-v2','image-star-provider':'text-shape-image/image-system-star-fill-v1/windows-source/provider-bound-delivery-v2','image-star-observation':'text-shape-image/image-system-star-fill-v6','stack-overlay-colors':'stack-layout/stack-overlay-centered-execution-v6','custom-layout-colors':'stack-layout/custom-layout-host-v2/light-centered-execution-v4','rounded-stroke-boundary':'text-shape-image/rounded-stroke-host-v1/continuous-observation-delivery-v5','bundled-font-compiled':'text-shape-image/bundled-font-readiness-v3-windows-host','bundled-font-live':'text-shape-image/bundled-font-readiness-v3-windows-host','bundled-font-observation':'text-shape-image/bundled-font-readiness-v2/windows-host','rounded-stroke':'text-shape-image/rounded-stroke-host-v1','rounded-stroke-centered':'text-shape-image/rounded-stroke-host-v1/centered-delivery-v1','rounded-stroke-circular':'text-shape-image/rounded-stroke-host-v1/circular-centered-delivery-v2','rounded-stroke-observation':'text-shape-image/rounded-stroke-host-v1/continuous-observation-delivery-v3','stack-overlay-centered':'stack-layout/stack-overlay-centered-execution-v2','stack-overlay-observation':'stack-layout/stack-overlay-centered-execution-v3','custom-layout':'stack-layout/custom-layout-host-v1','custom-layout-v2':'stack-layout/custom-layout-host-v2','custom-layout-centered':'stack-layout/custom-layout-host-v2/light-centered-delivery-v1','custom-layout-observation':'stack-layout/custom-layout-host-v2/light-centered-execution-v2'}[a.host]
new_host=a.host!='image'
repo_real=repo.resolve()
delivery_root=(repo/'factory/pipeline/pilot-delivery-five-v1').resolve()
def repo_path(value,label):
 path=Path(value); raw=path if path.is_absolute() else repo/path
 try: raw.relative_to(repo_real)
 except ValueError: raise AssertionError(label+' must stay under checkout')
 for parent in [repo_real,*raw.relative_to(repo_real).parents]:
  probe=repo_real/parent if not parent.is_absolute() else parent
  if probe.is_symlink(): raise AssertionError(label+' may not traverse symlink')
 target=raw.resolve()
 try: target.relative_to(repo_real)
 except ValueError: raise AssertionError(label+' must stay under checkout')
 rel_target=target.relative_to(repo_real)
 if any(part in ('..','') for part in rel_target.parts): raise AssertionError(label+' has unsafe path')
 if target.is_symlink(): raise AssertionError(label+' must not be symlink')
 return target
if bool(a.source_packet) != bool(a.runtime_source_receipt):
 raise AssertionError('--source-packet & --runtime-source-receipt must be supplied together')
packet_root=repo_path(a.source_packet,'source packet') if a.source_packet else None
if packet_root is not None:
 try: packet_root.relative_to(delivery_root)
 except ValueError: raise AssertionError('source packet must stay under factory/pipeline/pilot-delivery-five-v1')
 if not (packet_root/'package/plan.json').is_file() or not (packet_root/'package/case.json').is_file():
  raise AssertionError('source packet must contain package/plan.json & package/case.json')
 rel=packet_root.relative_to(delivery_root).as_posix()
packet=packet_root/'package' if packet_root is not None else repo/'factory/pipeline/pilot-delivery-five-v1'/rel/'package'
out=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution'/(a.host+f'-compile-r{a.compile_revision}')
out.mkdir(exist_ok=True)
assert {path.name for path in out.iterdir()} <= {'Sr0OwnedJobProcess.cs'}, 'compile request already prepared'
def rd(path,cap=4194304):
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<=cap
 return path.read_bytes()
def sha(b):return hashlib.sha256(b).hexdigest()
def jd(v):return (json.dumps(v,indent=2,sort_keys=True)+'\n').encode()
def strict_hash(value,label):
 if not isinstance(value,str) or not re.fullmatch(r'sha256:[0-9a-f]{64}',value):
  raise AssertionError(label+' must be sha256-prefixed lowercase hex')
 return value
def runtime_source_receipt(path):
 receipt_path=repo_path(path,'runtime source receipt')
 raw=rd(receipt_path,16*1024*1024)
 try: receipt=json.loads(raw.decode('utf-8-sig'))
 except Exception as exc: raise AssertionError('runtime source receipt is not JSON') from exc
 if receipt.get('kind')!='factory-additive-runtime-source' or receipt.get('synthetic') is not False:
  raise AssertionError('runtime source receipt kind/synthetic mismatch')
 if receipt.get('snapshotMethod')!='git archive exact commit; no working-tree bytes':
  raise AssertionError('runtime source receipt snapshot method mismatch')
 package_path=receipt.get('runtimePackagePath')
 if not isinstance(package_path,str) or not re.fullmatch(r'D:\\Claude\\swiftright\\.factory-work\\runtime-stage\\[A-Za-z0-9_.-]+(?:\\[A-Za-z0-9_.-]+)*',package_path):
  raise AssertionError('runtime source package path must stay under runtime-stage')
 commit=receipt.get('sourceCommit')
 if not isinstance(commit,str) or not re.fullmatch(r'[0-9a-f]{40}',commit):
  raise AssertionError('runtime source commit missing')
 tree_hash=strict_hash(receipt.get('sourceTreeHash'),'runtime source tree')
 bindings=receipt.get('sourceBindings')
 if not isinstance(bindings,list) or not bindings or len(bindings)>256:
  raise AssertionError('runtime source bindings missing/bounded')
 seen=set(); normalized=[]
 for row in bindings:
  if not isinstance(row,dict) or not isinstance(row.get('path'),str) or row['path'] in seen:
   raise AssertionError('runtime source binding invalid')
  relpath=row['path']
  if relpath!='Package.swift' and not relpath.startswith('Sources/'):
   raise AssertionError('runtime source binding leaves Package.swift/Sources')
  if any(part in ('','..') for part in Path(relpath).parts):
   raise AssertionError('runtime source binding path unsafe')
  expected=strict_hash(row.get('sha256'),'runtime source binding hash')
  seen.add(relpath); normalized.append((relpath,expected))
 git=subprocess.run(['git','-C',str(repo),'cat-file','-e',commit+'^{commit}'],capture_output=True,timeout=30)
 if git.returncode!=0: raise AssertionError('runtime source commit missing')
 total=0
 for relpath,expected in normalized:
  tracked=subprocess.run(['git','-C',str(repo),'ls-tree','--full-tree',commit,'--','probes/sr0-s/fresh-runtime/'+relpath],capture_output=True,text=True,timeout=30)
  if tracked.returncode!=0: raise AssertionError('runtime source tree lookup failed')
  lines=[line for line in tracked.stdout.splitlines() if line]
  if len(lines)!=1: raise AssertionError('runtime source binding not uniquely tracked')
  fields,path_name=lines[0].split('\t',1) if '\t' in lines[0] else ('','')
  parts=fields.split()
  if len(parts)!=3 or parts[1]!='blob' or path_name!='probes/sr0-s/fresh-runtime/'+relpath:
   raise AssertionError('runtime source binding blob missing')
  source=subprocess.run(['git','-C',str(repo),'show',commit+':probes/sr0-s/fresh-runtime/'+relpath],capture_output=True,timeout=30)
  if source.returncode!=0 or sha(source.stdout)!=expected[7:]:
   raise AssertionError('runtime source binding content drift')
  total+=len(source.stdout)
 if total>268435456: raise AssertionError('runtime source bindings exceed source cap')
 canonical=json.dumps([{'path':relpath,'sha256':expected} for relpath,expected in normalized],sort_keys=True,separators=(',',':')).encode()
 if sha(canonical)!=tree_hash[7:]:
  raise AssertionError('runtime source tree hash mismatch')
 return {'commit':commit,'treeHash':tree_hash,'sourceReceiptHash':'sha256:'+sha(raw),'receipt':receipt}
raw=rd(packet/'plan.json');plan=json.loads(raw)
case_raw=rd(packet/'case.json');case_doc=json.loads(case_raw);canonical_case=case_doc['id']
runtime_receipt=runtime_source_receipt(a.runtime_source_receipt) if a.runtime_source_receipt else None
runtime_commit=runtime_receipt['commit'] if runtime_receipt else '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
if runtime_receipt:
 plan['sourceCommit']=runtime_receipt['commit'];plan['runtimeSourceTreeHash']=runtime_receipt['treeHash'];plan['runtimeSourceReceiptHash']=runtime_receipt['sourceReceiptHash'];plan['runtimePackagePath']=runtime_receipt['receipt']['runtimePackagePath']
 plan['runtimeBinding']={'commit':runtime_receipt['commit'],'treeHash':runtime_receipt['treeHash'],'sourceReceiptHash':runtime_receipt['sourceReceiptHash']}
plan.setdefault('candidate', case_doc['block']+'.pilot')
plan.setdefault('witness', 'Sources/FactoryProbe/Witness.swift')
if runtime_receipt:
 assert isinstance(plan['runtimeSourceTreeHash'],str) and re.fullmatch(r'sha256:[0-9a-f]{64}',plan['runtimeSourceTreeHash'])
else:
 assert plan['runtimeSourceTreeHash']=='sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
plan['rendererSha256']=plan['rendererSha256'].removeprefix('sha256:')
plan['compilerHash']=plan['compilerHash'].removeprefix('sha256:')
if 'rendererPath' not in plan: plan['rendererPath']=plan['rendererLoadPath']
if 'bridgeBindings' not in plan:
 donor=json.loads(rd(repo/'factory/pipeline/pilot-delivery-five-v1/root-execution/rounded-stroke-circular-compile-r1/plan-prebuild-v4.json'))
 assert donor['bridgePackagePath']==plan['bridgePackagePath'] and donor['rendererSha256']==plan['rendererSha256']
 if not runtime_receipt: assert donor['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash']
 plan['bridgeBindings']=donor['bridgeBindings']
assert plan['rendererSha256']=='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
assert plan['compilerHash']=='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
assert plan.get('sourceCommit',plan.get('runtimeSourceCommit')) == runtime_commit
files={}
for path in packet.rglob('*'):
 if path.is_dir():continue
 assert not path.is_symlink()
 relpath=path.relative_to(packet).as_posix();files['package/'+relpath]=rd(path)
assert len(files)<=128 and sum(map(len,files.values()))<=16777216
for row in plan['sourceBindings']:
 data=files['package/'+row['path']]
 assert len(data)==row['bytes'] and sha(data)==row['sha256'].replace('sha256:','')
actual={k[8:] for k in files if k=='package/Package.swift' or k.startswith('package/Sources/')}
expected={r['path'] for r in plan['sourceBindings'] if r['path']=='Package.swift' or r['path'].startswith('Sources/')}
assert actual==expected
assert sha(files['package/runtime-source-tree.json'])==plan['runtimeSourceTreeHash'][7:]
receiptHash=sha(files['package/runtime-source-receipt.json'])
assert receiptHash==plan['runtimeSourceReceiptHash'][7:]
if runtime_receipt: assert receiptHash==runtime_receipt['sourceReceiptHash'][7:]
helper_source=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution/Sr0OwnedJobProcess.cs'
helper=out/'Sr0OwnedJobProcess.cs'
hb=rd(helper_source)
helper.write_bytes(hb)
assert sha(hb)=='112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e'
base=repo/'factory/native/windows/pilot-rectangle-fixed-root-v2/build-owned-v4.ps1'
adapter=rd(base);assert sha(adapter)=='f88932bcaaeb536f3dd7103b8401221cf1a27384fec75e928ebfd397dac53c7d'
text=adapter.decode()
text=text.replace("$stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle'","$stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\"+a.host+"'")
if runtime_receipt:
 text=text.replace('37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b',runtime_receipt['commit'])
 text=text.replace(r'D:\Claude\swiftright\.factory-work\runtime-stage\runtime',runtime_receipt['receipt']['runtimePackagePath'])
text=text.replace('factory-rectangle-compiler-plan-v2','factory-pilot-five-compiler-plan-v1').replace('swiftui.shapes.rectangle-fill.pilot-next',plan['candidate'])
text=text.replace('factory-rectangle-','factory-pilot-five-')
assert text.count('--jobs 1 -c release')==1
if new_host:
 text=text.replace('build --package-path','build --build-system native -v --package-path')
 text=text.replace('--jobs 1 -c release','--jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release')
 text=text.replace('out\\Products\\Release-windows-x86_64\\FactoryProbe.exe','x86_64-unknown-windows-msvc\\release\\FactoryProbe.exe')
 text=text.replace('swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.*',canonical_case)
 if a.host=='image-v2': text=text.replace("$scratch=Join-Path $package 'build-bound-r1\\scratch'", "$scratch=Join-Path $package 'build-bounded-r2\\scratch'")
else:
 text=text.replace('--jobs 1 -c release','--jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release')
check=" if((Hash (Join-Path $package 'runtime-source-receipt.json')) -cne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'runtime receipt drift'}\n"
text=text.replace(' Verify-Rows $package $plan.sourceBindings $true\n',' Verify-Rows $package $plan.sourceBindings $true\n'+check)
files['build-owned-pilot-v1.ps1']=text.encode();files['Sr0OwnedJobProcess.cs']=hb
stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\'+a.host
package=stage+'\\package';scratch=package+('\\build-bounded-r2\\scratch' if a.host=='image-v2' else '\\build-bound-r1\\scratch')
plan.update(kind='factory-pilot-five-compiler-plan-v1',phase='prebuild',runtimeSourceCommit=runtime_commit,helperSha256=sha(hb),case=None,expectedHostHash=None)
plan['packageSourcePath']='factory/pipeline/pilot-delivery-five-v1/'+rel+'/package'
plan['compileRequest'].update(packagePath=package,scratchPath=scratch,maxParallelJobs=1,maxFrontendThreads=1,memoryCapBytes=1073741824)
plan['compileRequest'].setdefault('kind','swiftpm-windows-gui-release/1')
if new_host:
 dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
 plan['packageStagePath']=package
 plan['scratchPath']=scratch
 plan['compileRequest']['buildSystem']='native'
 plan['compileRequest']['argv']=['build','--build-system','native','-v','--package-path',package,'--scratch-path',scratch,'--jobs','1','-Xswiftc','-j1','-Xswiftc','-num-threads','-Xswiftc','1','-c','release','-Xlinker','/MANIFEST:EMBED','-Xlinker',dep,'-Xlinker','/SUBSYSTEM:WINDOWS','-Xlinker','/ENTRY:mainCRTStartup']
plan['tuple']={'id':'sr1-'+a.host+'-delivery-r11-20261012-r1','rendererHash':'sha256:'+plan['rendererSha256'],'hostHashes':{'windows':None},'runtimeSourceCommit':runtime_commit,'abiVersion':'0.6'}
plan['packetPlanHash']='sha256:'+sha(raw);plan['executionEligible']=False;plan['nativeParity']='hold'
files['package/packet-plan.json']=raw
files['package/plan-prebuild-v4.json']=jd(plan)
(out/'plan-prebuild-v4.json').write_bytes(files['package/plan-prebuild-v4.json'])
(out/'build-owned-pilot-v1.ps1').write_bytes(files['build-owned-pilot-v1.ps1'])
manifest={'kind':'factory-pilot-five-root-compile-stage-v1','files':[{'path':k,'bytes':len(b),'sha256':sha(b)} for k,b in files.items()],'nativeActions':0}
files['stage-manifest.json']=jd(manifest)
cache=repo/'.factory-work/pilot-delivery-five-v1';cache.mkdir(parents=True,exist_ok=True);z=cache/(a.host+f'-delivery-compile-r{a.compile_revision}.zip')
with zipfile.ZipFile(z,'x',zipfile.ZIP_DEFLATED) as archive:
 for k,b in files.items():archive.writestr(k,b)
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='__STAGE__'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
if(Test-Path -LiteralPath $Stage){throw 'fresh pilot host stage required'}
$Zip='D:\Claude\swiftright\.factory-work\__ZIP__'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne '__ZIPHASH__'){throw 'pilot zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$M=Get-Content -LiteralPath (Join-Path $Stage 'stage-manifest.json') -Raw|ConvertFrom-Json
$Total=0;foreach($R in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Stage $R.path) -Force;$Total+=$F.Length;if($F.Length -ne $R.bytes -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -cne $R.sha256){throw 'pilot staged source drift'}}
if(@($M.files).Count -gt 128 -or $Total -gt 16777216){throw 'pilot stage cap'}
$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
& $Builder -PlanPath $Plan -PlanSha256 '__PLANHASH__' -Phase prebuild -Attempt 1 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '__PLANHASH__' -Phase prebuild -Attempt 1
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw
'''
for k,v in {'STAGE':stage,'ZIP':z.name,'ZIPHASH':sha(rd(z)),'PLANHASH':sha(files['package/plan-prebuild-v4.json'])}.items():script=script.replace('__'+k+'__',v)
(out/'stage-build-r1.ps1').write_text(script)
(out/'preparation.json').write_bytes(jd({'host':a.host,'packageFiles':len(manifest['files']),'packetPlanHash':sha(raw),'planSha256':sha(files['package/plan-prebuild-v4.json']),'builderHash':sha(files['build-owned-pilot-v1.ps1']),'helperHash':sha(hb),'memoryCapBytes':1073741824,'nativeActions':0,'qualification':'pending-actual-compile'}))
print(json.dumps({'host':a.host,'installer':str(out/'stage-build-r1.ps1'),'zip':str(z),'nativeActions':0,'rootCopyRequired':True}))
