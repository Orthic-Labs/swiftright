"""Prepare centered Rectangle final-plan admission from measured prebuild archive.

Source-side only: archive must already be local. Remote copy, compiler, native
capture, SSH, & Git remain root-owned.
"""
from pathlib import Path
import argparse, base64, hashlib, json

REPO=Path('/Volumes/D/claude/swiftright')
BASE=REPO/'factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-centered-build-r1'
PRIOR=REPO/'factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-build-r2/plan-final-v4.json'
REMOTE_ROOT=r'D:\Claude\swiftright\.factory-work\hosts\rectangle'
REMOTE_PACKAGE=REMOTE_ROOT+r'\package'

ap=argparse.ArgumentParser()
ap.add_argument('--prebuild-archive',required=True,
                help='local bounded archive containing observation.json, compile.stdout.bin, compile.stderr.bin, FactoryProbe.exe')
ap.add_argument('--prebuild-plan',required=True,
                help='exact current prebuild plan; its measured hash is carried into final packet')
ap.add_argument('--prebuild-attempt',type=int,required=True,
                help='fresh remote prebuild attempt number, for example 6')
ap.add_argument('--final-attempt',type=int,
                help='fresh remote final attempt number; defaults to prebuild attempt')
args=ap.parse_args()
PREBUILD=Path(args.prebuild_plan)
if not PREBUILD.is_absolute(): PREBUILD=REPO/PREBUILD
BASE=PREBUILD.parent
PREBUILD_ATTEMPT=args.prebuild_attempt
FINAL_ATTEMPT=args.final_attempt if args.final_attempt is not None else PREBUILD_ATTEMPT
if PREBUILD_ATTEMPT<1 or FINAL_ATTEMPT<1: raise SystemExit('attempt numbers must be positive')
OUT=BASE/f'centered-final-prep-r{FINAL_ATTEMPT}'
REMOTE_PREBUILD=REMOTE_ROOT+f'\\prebuild-r{PREBUILD_ATTEMPT}'

def bytes_of(p,cap=67108864):
    p=Path(p)
    if not p.is_file() or p.is_symlink() or p.stat().st_size>cap:
        raise SystemExit(f'bounded regular file required: {p}')
    return p.read_bytes()
def digest(p):
    p=Path(p); h=hashlib.sha256()
    if not p.is_file() or p.is_symlink() or p.stat().st_size>67108864:
        raise SystemExit(f'bounded regular file required: {p}')
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''): h.update(block)
    return h.hexdigest()
def load(p):
    return json.loads(bytes_of(p,4194304).decode('utf-8-sig'))
def fail(msg): raise SystemExit(msg)
def copy_member(src,dst):
    data=bytes_of(src);dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(data)
    return {'path':dst.name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}

pre_raw=bytes_of(PREBUILD,4194304);pre_hash=hashlib.sha256(pre_raw).hexdigest();pre=load(PREBUILD)
old_raw=bytes_of(PRIOR,4194304);old_hash=hashlib.sha256(old_raw).hexdigest();old=load(PRIOR)
if old_hash!='802d064cfd971585e73d1f7d9fce969876029b93d04e7296f22a64f71b211c30': fail('prior Rectangle final guard drift')
if pre.get('phase')!='prebuild' or pre.get('case') is not None: fail('centered plan must remain unmeasured prebuild')
if old.get('case',{}).get('id')!='swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.73250c091e3660b1': fail('prior Rectangle case mismatch')
if old.get('case',{}).get('hash')!='sha256:bdb866ab75c201e782d8b2079d6fb4f15f5fd8d46e7f16135c4a007bdb408eab': fail('prior Rectangle case hash mismatch')

archive=Path(args.prebuild_archive)
receipt_path=archive/'observation.json';receipt_raw=bytes_of(receipt_path,4194304);receipt=load(receipt_path);receipt_hash=hashlib.sha256(receipt_raw).hexdigest()
if receipt.get('kind')!='factory-rectangle-owned-compile-v1' or receipt.get('phase')!='prebuild': fail('archive receipt must be centered prebuild receipt')
if receipt.get('planSha256')!=pre_hash: fail('prebuild receipt plan hash mismatch')
if receipt.get('sourceHash')!=pre.get('sourceHash'): fail('prebuild receipt source hash mismatch')
failed=(receipt.get('exitCode')!=0 or receipt.get('error') or receipt.get('cleanupError'))
if failed:
    # Preserve failed receipt & sealed streams as evidence, then stop before
    # final-plan mutation. No synthetic executable or success fields are made.
    failure_out=BASE/f'prebuild-actual-r{PREBUILD_ATTEMPT}'
    if failure_out.exists(): fail(f'fresh prebuild-actual-r{PREBUILD_ATTEMPT} required')
    failure_out.mkdir()
    members=[]
    members.append(copy_member(receipt_path,failure_out/'observation.json'))
    missing=[]
    for name in ('compile.stdout.bin','compile.stderr.bin'):
        src=archive/name
        if src.is_file(): members.append(copy_member(src,failure_out/name))
        else: missing.append(name)
    exe_src=archive/'FactoryProbe.exe'
    if exe_src.is_file(): members.append(copy_member(exe_src,failure_out/'FactoryProbe.exe'))
    failure={'kind':'factory-rectangle-centered-prebuild-failure-v1','status':'failed-prebuild','planSha256':'sha256:'+pre_hash,'receiptSha256':'sha256:'+receipt_hash,'exitCode':receipt.get('exitCode'),'error':receipt.get('error'),'cleanupError':receipt.get('cleanupError'),'streamsSealed':receipt.get('streamsSealed'),'missingMembers':missing,'nativeActions':receipt.get('nativeActions'),'compilerActions':1}
    (failure_out/'archive-manifest.json').write_text(json.dumps({'kind':'factory-rectangle-centered-prebuild-archive-v1','members':members,'receipt':failure},indent=2,sort_keys=True)+'\n')
    (failure_out/'failure.json').write_text(json.dumps(failure,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'status':'failed-prebuild-preserved','output':str(failure_out),'receiptSha256':'sha256:'+receipt_hash,'exitCode':receipt.get('exitCode'),'error':receipt.get('error'),'cleanupError':receipt.get('cleanupError'),'missingMembers':missing,'nativeActions':0}))
    raise SystemExit(0)
for key in ('exitCode','ownedExited','originalHandleRetained','streamDrainComplete','streamsSealed','jobActiveCount','cleanupJobActive','kernelWait','memoryCapBytes','nativeActions'):
    if key not in receipt: fail(f'prebuild receipt missing {key}')
if receipt['exitCode']!=0 or not receipt['ownedExited'] or not receipt['originalHandleRetained'] or not receipt['streamDrainComplete'] or not receipt['streamsSealed'] or receipt['jobActiveCount']!=0 or receipt['cleanupJobActive']!=0 or receipt['kernelWait']!=0 or receipt['memoryCapBytes']!=1073741824 or receipt['nativeActions']!=0: fail('prebuild lifecycle admission failed')
for stream in ('stdout','stderr'):
    p=archive/f'compile.{stream}.bin'
    if digest(p)!=receipt.get(f'{stream}Sha256') or p.stat().st_size!=receipt.get(f'{stream}Bytes'): fail(f'prebuild {stream} archive mismatch')
exe=archive/'FactoryProbe.exe'
exe_hash=digest(exe);exe_bytes=exe.stat().st_size
if exe_hash!=receipt.get('exeSha256') or exe_bytes!=receipt.get('exeBytes'): fail('prebuild executable archive mismatch')

plan=json.loads(pre_raw.decode('utf-8-sig'))
plan['phase']='final';plan['case']=old['case'];plan['expectedHostHash']='sha256:'+exe_hash
plan['tuple']['hostHashes']['windows']=plan['expectedHostHash']
plan['prebuildReceiptHash']='sha256:'+receipt_hash
plan['centeredFinalization']={'priorFinalPlanHash':'sha256:'+old_hash,'prebuildPlanHash':'sha256:'+pre_hash,'prebuildReceiptHash':'sha256:'+receipt_hash,'prebuildRemoteRoot':REMOTE_PREBUILD,'finalAttempt':FINAL_ATTEMPT,'qualification':'pending-final-compile-receipt'}
final_raw=(json.dumps(plan,indent=2,sort_keys=True)+'\n').encode();final_hash=hashlib.sha256(final_raw).hexdigest()

payload=base64.b64encode(final_raw).decode()
script=f'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='{REMOTE_ROOT}';$Package=Join-Path $Stage 'package';$PlanPath=Join-Path $Package 'plan-final-v4.json'
function Hash([string]$p){{$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or $i.Length -gt 67108864 -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){{throw 'bounded regular file required'}};(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}}
if((Hash $PlanPath) -cne '{old_hash}'){{throw 'remote prior final plan guard drift'}}
if((Hash (Join-Path $Package '{PREBUILD.name}')) -cne '{pre_hash}'){{throw 'remote centered prebuild plan drift'}}
if((Hash (Join-Path $Stage 'prebuild-r{PREBUILD_ATTEMPT}\\observation.json')) -cne '{receipt_hash}'){{throw 'remote centered prebuild receipt drift'}}
[IO.File]::WriteAllBytes($PlanPath,[Convert]::FromBase64String('{payload}'))
if((Hash $PlanPath) -cne '{final_hash}'){{throw 'centered final plan bytes drift'}}
& (Join-Path $Stage 'build-owned-centered-v1.ps1') -PlanPath $PlanPath -PlanSha256 '{final_hash}' -Phase final -Attempt {FINAL_ATTEMPT} -PreflightOnly
& (Join-Path $Stage 'build-owned-centered-v1.ps1') -PlanPath $PlanPath -PlanSha256 '{final_hash}' -Phase final -Attempt {FINAL_ATTEMPT}
Get-Content -LiteralPath (Join-Path $Stage 'final-r{FINAL_ATTEMPT}\\observation.json') -Raw
'''
if OUT.exists(): fail(f'fresh centered-final-prep-r{FINAL_ATTEMPT} required')
OUT.mkdir()
(OUT/'plan-final-v4.json').write_bytes(final_raw)
(OUT/'finalize-centered-r1.ps1').write_text(script)
prep={'kind':'factory-rectangle-centered-final-preparation-v1','priorFinalPlanHash':'sha256:'+old_hash,'prebuildPlanPath':str(PREBUILD),'prebuildPlanHash':'sha256:'+pre_hash,'prebuildReceiptHash':'sha256:'+receipt_hash,'prebuildReceiptBytes':len(receipt_raw),'exeSha256':'sha256:'+exe_hash,'exeBytes':exe_bytes,'finalPlanHash':'sha256:'+final_hash,'remotePrebuildRoot':REMOTE_PREBUILD,'prebuildAttempt':PREBUILD_ATTEMPT,'finalAttempt':FINAL_ATTEMPT,'nativeActions':0,'compilerActions':0,'qualification':'pending-final-compile'}
(OUT/'preparation.json').write_text(json.dumps(prep,indent=2,sort_keys=True)+'\n')
print(json.dumps({'output':str(OUT),'finalPlanHash':'sha256:'+final_hash,'prebuildReceiptHash':'sha256:'+receipt_hash,'exeSha256':'sha256:'+exe_hash,'finalAttempt':FINAL_ATTEMPT,'nativeActions':0}))
