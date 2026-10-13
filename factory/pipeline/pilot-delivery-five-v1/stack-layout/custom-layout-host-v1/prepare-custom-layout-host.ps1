# Source-only prebuild planner. Emits compile inputs/argv; starts no compiler, host, lock or native action.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$PlanOutput
)
$ErrorActionPreference='Stop'
$packet='D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\custom-layout-host-v1'
$package='D:\Claude\swiftright\.factory-work\hosts\custom-layout-lifecycle\package'
if($RunRoot -match '["\r\n]' -or $PlanOutput -match '["\r\n]'){throw 'Quoted/newline argument rejected'}
$run=[IO.Path]::GetFullPath($RunRoot);$planOut=[IO.Path]::GetFullPath($PlanOutput)
if(-not $run.StartsWith($packet+'\native\',[StringComparison]::OrdinalIgnoreCase)){throw 'RunRoot must be fresh custom-layout native descendant'}
if(-not $planOut.StartsWith($packet+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'PlanOutput must remain under custom-layout-host-v1'}
if(Test-Path -LiteralPath $planOut){throw 'Fresh planner output required'}
. (Join-Path $packet 'source\custom-layout-source-join.ps1')
$join=Assert-CustomLayoutSource $package
$files=[ordered]@{}
foreach($rel in @('prepare-custom-layout-host.ps1','source\custom-layout-source-join.ps1','helpers\cleanup-v3.ps1','helpers\stream-seal.ps1','helpers\owned-close.ps1','helpers\pixels-background.ps1','helpers\host-inputs.ps1')){
 $p=Join-Path $packet $rel
 if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('Packet source missing: '+$rel)}
 $files[$rel]=[ordered]@{sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $p).Length}
}
$expectedHelpers=@{
 'helpers\cleanup-v3.ps1'='cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'
 'helpers\stream-seal.ps1'='4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'
 'helpers\owned-close.ps1'='d0898e1a2ebdefce64fbf5b16cbc3b9f72578e2f0efb649ee001c182f7aaec7c'
 'helpers\pixels-background.ps1'='7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'
 'helpers\host-inputs.ps1'='93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'
}
foreach($rel in $expectedHelpers.Keys){if($files[$rel].sha256 -cne $expectedHelpers[$rel]){throw ('Helper drift: '+$rel)}}
$request=$join
$compile=$join
$compiler='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$scratch='D:\Claude\swiftright\.factory-work\hosts\custom-layout-lifecycle\package\build-custom-layout-r1\scratch'
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$args='build --package-path "'+$package+'" --scratch-path "'+$scratch+'" --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED -Xlinker "'+$dep+'" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
$entry='"'+$compiler+'" '+$args
$planHash=(Get-FileHash -LiteralPath (Join-Path $package 'plan.json')).Hash.ToLowerInvariant()
$doc=[ordered]@{
 kind='factory-custom-layout-host-prebuild-plan-v1';status='SOURCE_READY';caseID=$join.caseID;diagnosticScope=$join.diagnosticScope;package=$package
 plan=[ordered]@{path=(Join-Path $package 'plan.json');sha256=$planHash}
 runtime=[ordered]@{commit=$join.runtimeCommit;treeHash=$join.runtimeTreeHash;api='current-37429120'}
 renderer=[ordered]@{path='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll';sha256=$join.rendererHash}
 compileRequest=[ordered]@{compilerPath=$compiler;argv=$args;packagePath=$package;scratchPath=$scratch;target='windows-x86_64';configuration='release';maxParallelJobs=1;maxFrontendThreads=1;nativeActions=0}
 entry=$entry;runRoot=$run;count=0;nativeActions=0;compilerActions=0;lockActions=0;nativeParity='hold';frozenTupleBound=$false
 closePolicy=[ordered]@{childSeconds=15;streamSeconds=5;destinationClosureSeconds=5;retainedKernelHandle=$true;waitABI='FactoryProcessWaitV6'}
 sourceOnly=[ordered]@{exeHash=$null;compileReceiptHash=$null;nativeObservation=$null;requiredNext='root-owned compile receipt + produced GUI EXE before Count1'}
 files=$files
}
$dir=Split-Path -Parent $planOut;New-Item -ItemType Directory -Path $dir -Force|Out-Null
$doc|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $planOut -Encoding UTF8
$doc|ConvertTo-Json -Depth 12
