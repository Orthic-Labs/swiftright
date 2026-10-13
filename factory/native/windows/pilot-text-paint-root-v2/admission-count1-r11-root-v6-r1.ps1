$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$installer='D:\Claude\swiftright\.factory-work\root-tools\install-text-count1-r11-root-v6-r1.ps1'
$zip='D:\Claude\swiftright\.factory-work\root-tools\text-count1-r11-root-v6-r1.zip'
foreach($row in @(
 @{path=$installer;bytes=8912;sha256='f523c539489589633f9b7d29cdb9dc8dfb2d8c407d18e9dfc232f45a3c42ffda'},
 @{path=$zip;bytes=110035;sha256='427a507f5695f9a1a74cd8e423bbe5b228c87cdcc86ce46af39cfb0a97829f6e'}
)){
 $item=Get-Item -LiteralPath $row.path -Force -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $item.FullName).Hash.ToLowerInvariant() -cne $row.sha256){throw ('pinned admission source drift: '+$row.path)}
}
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$errors)|Out-Null
if($null -ne $errors -and $errors.Count -gt 0){throw ('installer parse failed: '+[string]$errors[0])}
& $installer -PackagePath $zip
Get-Content -LiteralPath 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r11\control-count1-r5\package-preflight.json' -Raw
