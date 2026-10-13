"""Prepare exact factory root placement correction; no native/compiler action."""
from pathlib import Path
import base64, copy, hashlib, json

REPO=Path('/Volumes/D/claude/swiftright')
BASE=REPO/'factory/pipeline/pilot-delivery-five-v1/root-execution'
OUT=BASE/'rectangle-centered-build-r1'
OLD=BASE/'rectangle-color-build-r2/plan-final-v4.json'
SOURCE=BASE/'rectangle-color-capture-r5/actual-native-r3/files/native/count1-r1'
ADAPTER=REPO/'factory/pipeline/pilot-delivery-five-v1/text-shape-image/rectangle-host-fix-v3/FactoryCenteredLayout.swift'

def raw(p,cap=262144):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<=cap
    return p.read_bytes()
def sha(b):return hashlib.sha256(b).hexdigest()
old=raw(OLD)
assert sha(old)=='802d064cfd971585e73d1f7d9fce969876029b93d04e7296f22a64f71b211c30'
plan=copy.deepcopy(json.loads(old))
rows={r['path']:r for r in plan['sourceBindings']}
main=raw(SOURCE/'Sources/FactoryProbe/main.swift').decode()
assert 'sha256:'+sha(main.encode())==rows['Sources/FactoryProbe/main.swift']['sha256']
before='        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32) throws {'
after='''        let rootPixel = root.pixelFrame
        let intrinsicRoot = Rect(x: Float(rootPixel.x), y: Float(rootPixel.y),
                                 w: Float(rootPixel.width), h: Float(rootPixel.height))
        let rootTranslation = factoryCenteredRootSubtree(intrinsicRoot, viewport: viewport)
        func walk(_ n: ResolvedNode, parent: UInt64, order: UInt32,
                  translation: FactoryRootSubtreeTranslation) throws {'''
changes=[(before,after),
 ('            let bounds = Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height))',
  '            let bounds = translation.applying(to: Rect(x: Float(p.x), y: Float(p.y), w: Float(p.width), h: Float(p.height)))'),
 ('            for (index, child) in n.children.enumerated() { try walk(child, parent: id, order: UInt32(index)) }',
  '            for (index, child) in n.children.enumerated() { try walk(child, parent: id, order: UInt32(index), translation: translation) }'),
 ('            try walk(root, parent: backgroundID, order: 0)',
  '''            guard let rootTranslation else { throw NSError(domain: "FactoryRootSubtreeCenterUnavailable", code: 1) }
            print("FACTORY_ROOT_PLACEMENT rootPX=\\(intrinsicRoot) viewportPX=\\(viewport) dx=\\(rootTranslation.dx) dy=\\(rootTranslation.dy)")
            try walk(root, parent: backgroundID, order: 0, translation: rootTranslation)''')]
for before,after in changes:
    assert main.count(before)==1,before
    main=main.replace(before,after)
adapter=raw(ADAPTER)
assert sha(adapter)=='ee1ab5bd75daffe429653476afd8ff52a2bc8553ac28e2035879badab426aaf3'
rows['Sources/FactoryProbe/main.swift']['sha256']='sha256:'+sha(main.encode())
plan['sourceBindings'].append({'path':'Sources/FactoryProbe/FactoryCenteredLayout.swift','sha256':'sha256:'+sha(adapter)})
plan.update(phase='prebuild',case=None,expectedHostHash=None,executionEligible=False,nativeParity='hold')
plan['tuple']['id']='sr1-rectangle-centered-r11-20261012-r1'
plan['tuple']['hostHashes']['windows']=None
mac=json.loads(raw(BASE/'rectangle-full-viewport-v1/build-r1/receipt.json'))
plan['tuple']['hostHashes']['macos']=mac['executable']['sha256']
plan['hostCorrection']['rootPlacement']={'scope':'factory root subtree center; white background unchanged',
 'previousMainHash':json.loads(old)['sourceBindings'][9]['sha256'],
 'mainHash':'sha256:'+sha(main.encode()),'adapterHash':'sha256:'+sha(adapter),
 'evidence':'rectangle-full-client-diagnosis-r1.json','qualification':'pending fresh paired native observations'}
plan['compileRequest']['argv']=['build','--build-system','native','-v','--package-path',plan['compileRequest']['packagePath'],
 '--scratch-path',plan['compileRequest']['scratchPath'],'--jobs','1','-Xswiftc','-j1','-Xswiftc','-num-threads','-Xswiftc','1','-c','release',
 '-Xlinker','/MANIFEST:EMBED','-Xlinker',"/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'",'-Xlinker','/SUBSYSTEM:WINDOWS','-Xlinker','/ENTRY:mainCRTStartup']
plan['compileRequest']['maxFrontendThreads']=1
builder=raw(REPO/'factory/native/windows/pilot-rectangle-fixed-root-v2/build-owned-v4.ps1').decode()
oldargv="build --package-path"
assert builder.count(oldargv)==1
builder=builder.replace(oldargv,'build --build-system native -v --package-path')
assert builder.count('--jobs 1 -c release')==1
builder=builder.replace('--jobs 1 -c release','--jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release')
assert builder.count('out\\Products\\Release-windows-x86_64\\FactoryProbe.exe')==1
builder=builder.replace('out\\Products\\Release-windows-x86_64\\FactoryProbe.exe','x86_64-unknown-windows-msvc\\release\\FactoryProbe.exe')
data=(json.dumps(plan,indent=2,sort_keys=True)+'\n').encode()
payload={k:{'base64':base64.b64encode(v).decode(),'sha256':sha(v),'bytes':len(v)} for k,v in {
 'Sources/FactoryProbe/main.swift':main.encode(),'Sources/FactoryProbe/FactoryCenteredLayout.swift':adapter,
 'plan-prebuild-v4.json':data,'build-owned-centered-v1.ps1':builder.encode()}.items()}
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rectangle';$Package=Join-Path $Stage 'package'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
function Hash([string]$P){$I=Get-Item -LiteralPath $P -Force;if($I.PSIsContainer -or $I.Length -gt 67108864 -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular input required'};(Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant()}
$Previous=Join-Path $Package 'plan-final-v4.json'
if((Hash $Previous) -cne '__OLD__'){throw 'current plan drift'}
if((Hash (Join-Path $Stage 'build-owned-v4.ps1')) -cne 'f88932bcaaeb536f3dd7103b8401221cf1a27384fec75e928ebfd397dac53c7d'){throw 'old builder drift'}
$Old=Get-Content -LiteralPath $Previous -Raw|ConvertFrom-Json
foreach($R in @($Old.sourceBindings)){if((Hash (Join-Path $Package $R.path)) -cne $R.sha256.Replace('sha256:','')){throw ('source drift '+$R.path)}}
$Backup='D:\Claude\swiftright\.factory-work\retired\rectangle-before-centering-r1'
if(Test-Path -LiteralPath $Backup){throw 'fresh backup required'}
if(Test-Path -LiteralPath (Join-Path $Stage 'prebuild-r5')){throw 'fresh prebuild receipt required'}
if(Test-Path -LiteralPath (Join-Path $Package 'Sources\FactoryProbe\FactoryCenteredLayout.swift')){throw 'new adapter path required'}
[IO.Directory]::CreateDirectory($Backup)|Out-Null
Copy-Item -LiteralPath (Join-Path $Package 'Sources\FactoryProbe\main.swift') -Destination (Join-Path $Backup 'main.swift')
foreach($Name in @('plan-prebuild-v4.json','plan-final-v4.json')){Copy-Item -LiteralPath (Join-Path $Package $Name) -Destination (Join-Path $Backup $Name)}
$Rows='__PAYLOAD__'|ConvertFrom-Json
foreach($Prop in $Rows.PSObject.Properties){$Name=$Prop.Name;$Row=$Prop.Value;$P=if($Name -eq 'build-owned-centered-v1.ps1'){Join-Path $Stage $Name}else{Join-Path $Package $Name};[IO.File]::WriteAllBytes($P,[Convert]::FromBase64String($Row.base64));if((Hash $P) -cne $Row.sha256 -or (Get-Item -LiteralPath $P).Length -ne $Row.bytes){throw 'written source drift'}}
$Builder=Join-Path $Stage 'build-owned-centered-v1.ps1';$Plan=Join-Path $Package 'plan-prebuild-v4.json'
& $Builder -PlanPath $Plan -PlanSha256 '__PLAN__' -Phase prebuild -Attempt 5 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '__PLAN__' -Phase prebuild -Attempt 5
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r5\observation.json') -Raw
'''.replace('__OLD__',sha(old)).replace('__PLAN__',sha(data)).replace('__PAYLOAD__',json.dumps(payload,separators=(',',':')))
OUT.mkdir()
for name,b in {'main.swift':main.encode(),'FactoryCenteredLayout.swift':adapter,'plan-prebuild-v4.json':data,
 'build-owned-centered-v1.ps1':builder.encode(),'stage-prebuild-r1.ps1':script.encode()}.items():(OUT/name).write_bytes(b)
(OUT/'preparation.json').write_text(json.dumps({'kind':'factory-root-centered-preparation-v1','planSha256':sha(data),
 'mainSha256':sha(main.encode()),'adapterSha256':sha(adapter),'builderSha256':sha(builder.encode()),
 'nativeActions':0,'compilerActions':0,'oldPlanSha256':sha(old)},indent=2)+'\n')
print(json.dumps({'planSha256':sha(data),'qualification':'pending-build','nativeActions':0}))
