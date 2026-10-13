$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$installer='D:\Claude\swiftright\.factory-work\root-tools\install-text-count1-r10-root-v5-r2.ps1'
$zip='D:\Claude\swiftright\.factory-work\root-tools\text-count1-r10-root-v5-r2.zip'
foreach($row in @(
  @{path=$installer;bytes=8905;sha256='57c9feb06f5045f523eb7363efdea1afb1e53b47d6cf0abb306a345b8956b140'},
  @{path=$zip;bytes=108776;sha256='d880057a7e36a17b7152e4a309a03e29ad91178078b36a6dc3b6c24a61dc105d'}
)){
  $item=Get-Item -LiteralPath $row.path -Force -ErrorAction Stop
  if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne $row.bytes -or (Get-FileHash -LiteralPath $item.FullName).Hash.ToLowerInvariant() -cne $row.sha256){throw ('pinned admission source drift: '+$row.path)}
}
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$errors)|Out-Null
if($null -ne $errors -and $errors.Count -gt 0){throw ('installer parse failed: '+[string]$errors[0])}
& $installer -PackagePath $zip
$control='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r10\control-count1-r5'
$preflight=Join-Path $control 'package-preflight.json'
if((Get-Item -LiteralPath $preflight).Length -gt 2097152){throw 'source preflight bounds'}
Get-Content -LiteralPath $preflight -Raw
