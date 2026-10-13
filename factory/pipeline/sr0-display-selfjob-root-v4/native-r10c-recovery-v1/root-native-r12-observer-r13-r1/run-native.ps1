$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$installer='D:\Claude\swiftright\.factory-work\root-tools\sr0-r12-root-v4-installer'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r12b'
$factory='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r12b'
foreach($row in @(
 @((Join-Path $installer 'observer-source-r13.ps1'),23979,'b4e8f8c87a90a0bcd8aa444760ccc6d163ba109aacdcb9a6866639de17ef2c7e'),
 @((Join-Path $installer 'preflight-r12.ps1'),6244,'c903ae24ed047cb605275c37d5c7d49ec54a80e00f08b6d61092677efd0dc411'),
 @((Join-Path $stage 'one-run-plan-r12.json'),24291,'c20382642f5b05ffe73e6288a4204a1acb76a116ecf895f2bdc59ce8723951d6'),
 @((Join-Path $factory 'drain-controls-r11.json'),9483,'b5a38209e029e2df4dd57708e746174b2fda4b1c398dfa161c19f3b6992ee92c')
)){
 $f=Get-Item -LiteralPath $row[0] -Force
 if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -ne $row[1] -or (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row[2]){throw 'native entry measured binding drift'}
}
if(([IO.File]::ReadAllText('D:\Claude\desktop.lock')).Trim() -cne 'free'){throw 'desktop is busy'}
& (Join-Path $installer 'observer-source-r13.ps1') -StageRoot $stage -PlanPath (Join-Path $stage 'one-run-plan-r12.json') -ExpectedPlanSha256 'c20382642f5b05ffe73e6288a4204a1acb76a116ecf895f2bdc59ce8723951d6' -PreflightPath (Join-Path $installer 'preflight-r12.ps1') -ExpectedPreflightSha256 'c903ae24ed047cb605275c37d5c7d49ec54a80e00f08b6d61092677efd0dc411' -ControlsReceiptPath (Join-Path $factory 'drain-controls-r11.json') -ExpectedControlsReceiptSha256 'b5a38209e029e2df4dd57708e746174b2fda4b1c398dfa161c19f3b6992ee92c' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootControlSuiteJobV1.cs' -TransportHelperSha256 '3ea2ea6d0134278fb704ef4ef8caf3fecc3b8e9463e1872b715baed70c6d0c76' -OutputPath (Join-Path $factory 'native-observer-r13.json') -DeadlineSeconds 1100
