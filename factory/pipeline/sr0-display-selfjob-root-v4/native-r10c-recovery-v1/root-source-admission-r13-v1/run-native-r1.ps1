$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$installer='D:\Claude\swiftright\.factory-work\root-tools\sr0-r13-root-v1-installer'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r13'
$factory='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r13'
foreach($row in @(
 @((Join-Path $installer 'observer-source-r13.ps1'),24445, 'e0e806c1ee6efc6427c76f2effea4c9fee399d6c02511cc12ce437c65532441f'),
 @((Join-Path $installer 'preflight-r12.ps1'),6244,'c903ae24ed047cb605275c37d5c7d49ec54a80e00f08b6d61092677efd0dc411'),
 @((Join-Path $stage 'one-run-plan-r12.json'),24273,'6599c985a5cdea4d61a5444659f49ca7ecdc7e5c27eea610e6248cdf6a45a6c4'),
 @((Join-Path $factory 'drain-controls-r11.json'),9479,'91b75323f16aadea191327b9c644b21594cf21cb8f70626ce66b1b24dedd3176')
)){
 $f=Get-Item -LiteralPath $row[0] -Force
 if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -ne $row[1] -or (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row[2]){throw 'native entry measured binding drift'}
}
if(([IO.File]::ReadAllText('D:\Claude\desktop.lock')).Trim() -cne 'free'){throw 'desktop is busy'}
& (Join-Path $installer 'observer-source-r13.ps1') -StageRoot $stage -PlanPath (Join-Path $stage 'one-run-plan-r12.json') -ExpectedPlanSha256 '6599c985a5cdea4d61a5444659f49ca7ecdc7e5c27eea610e6248cdf6a45a6c4' -PreflightPath (Join-Path $installer 'preflight-r12.ps1') -ExpectedPreflightSha256 'c903ae24ed047cb605275c37d5c7d49ec54a80e00f08b6d61092677efd0dc411' -ControlsReceiptPath (Join-Path $factory 'drain-controls-r11.json') -ExpectedControlsReceiptSha256 '91b75323f16aadea191327b9c644b21594cf21cb8f70626ce66b1b24dedd3176' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootControlSuiteJobV1.cs' -TransportHelperSha256 '3ea2ea6d0134278fb704ef4ef8caf3fecc3b8e9463e1872b715baed70c6d0c76' -OutputPath (Join-Path $factory 'native-observer-r13.json') -DeadlineSeconds 1000
