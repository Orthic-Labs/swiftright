$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$installer='D:\Claude\swiftright\.factory-work\root-tools\install-text-count1-r12-root-v7-r1.ps1'
$zip='D:\Claude\swiftright\.factory-work\root-tools\text-count1-r12-root-v7-r1.zip'
foreach($row in @(
 @{path=$installer;bytes=9708;sha256='fa67ca2263bbf0d6def4f5403f10850eff733c3fa3766dbf4e4844311f0da2ec'},
 @{path=$zip;bytes=112559;sha256='8f07da8dfe19db1a9802846c15b5ab0bacbf55b883e386d7dd2b374069d33fd2'}
)){
 $item=Get-Item -LiteralPath $row.path -Force -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $item.FullName).Hash.ToLowerInvariant() -cne $row.sha256){throw ('pinned admission source drift: '+$row.path)}
}
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$errors)|Out-Null
if($null -ne $errors -and $errors.Count -gt 0){throw ('installer parse failed: '+[string]$errors[0])}
& $installer -PackagePath $zip
Get-Content -LiteralPath 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r12\control-count1-r5\package-preflight.json' -Raw
