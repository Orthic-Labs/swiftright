$ErrorActionPreference='Stop'
$repo='D:\Claude\swiftright\.factory-work\controls-source'
$manifest=Join-Path $repo 'transfer-manifest.json'
if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne '0f0405fc0d7633cfff105942cbfffbbe7fe62cd404cc517c5264f5c21ad43f2a'){throw 'Root transport manifest drift'}
$rows=@(([IO.File]::ReadAllText($manifest)|ConvertFrom-Json).files)
foreach($row in $rows){
 $file=Join-Path $repo ($row.path -replace '/','\')
 if((Get-Item -LiteralPath $file).Length -ne $row.bytes -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256.Replace('sha256:','')){throw ('Root transport source drift: '+$row.path)}
 if($file.EndsWith('.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Output $_.Message};throw ('Parse failed: '+$row.path)}}
}
Write-Output ('ROOT_TRANSPORT_PARSE_PASS count='+$rows.Count)
$entry=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3\root-entry.ps1'
& $entry -OutputRoot 'D:\Claude\swiftright\.factory-work\controls-results\sr1-v3-r1'
Write-Output 'ROOT_HEADLESS_CONTROLS_RETURNED'
