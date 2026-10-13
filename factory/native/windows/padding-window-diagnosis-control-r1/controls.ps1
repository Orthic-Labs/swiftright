$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright'
$source=Join-Path $repo 'factory\native\windows\padding-window-diagnosis-capture-v2'
$out=Join-Path $repo 'factory\native\windows\padding-window-diagnosis-control-r1'
if(Test-Path -LiteralPath $out){throw 'Fresh root admission namespace required'}
New-Item -ItemType Directory -Path $out|Out-Null
$manifest=Join-Path $source 'root-stage-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne '4088322c03c02ed876542797688d5a849aed01c206318ce29b00d08318e5350c'){throw 'Source stage drift'}
$stage=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
foreach($row in $stage.files){$path=Join-Path $repo $row.path.Replace('/','\');if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $row.hash.Replace('sha256:','')){throw ('Source drift: '+$row.path)}}
& (Join-Path $source 'run-controls.ps1') -OutputRoot (Join-Path $out 'actual-controls')
& (Join-Path $source 'prepare-capture.ps1') -CompileReceiptPath 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-diagnosis-r1\observation.json' -ExecutablePath 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-diagnosis-r1\FactoryProbe.exe' -CompileReceiptHash '74bf90f689d00124abbcfbe56a97b1160fe3117277c7e332490b48be713ca8d7' -ExeHash 'caa9b760f2fc4574b0ca9846610f5b177b50e5180986c930415a442b3d83a369' -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba' -Count 1 -OutputPath (Join-Path $out 'launch-admission.json')
[ordered]@{status='controls-and-launch-admission-passed';sourcePins=$stage.files.Count;nativeLaunches=0;desktopLockWrites=0}|ConvertTo-Json
