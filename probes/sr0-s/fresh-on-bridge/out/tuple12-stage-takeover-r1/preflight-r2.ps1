$ErrorActionPreference='Stop'
$tools='D:\Claude\swiftright\.work\sr0-stage-tools'
$manifest=Join-Path $tools 'transfer-manifest.json'
if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'a71694057c0ee8921092e0236cec59af24387bae122694f6b67ed1a25eeac62c'){throw 'Manifest transport drift'}
$doc=[IO.File]::ReadAllText($manifest)|ConvertFrom-Json
foreach($row in @($doc.files)){
 if($row.path -notmatch '^(probes/sr0-|examples/)' -or $row.path -match '\.\.|[\r\n]'){throw 'Unsafe overlay path'}
 $file=Join-Path $tools ($row.path -replace '/','\')
 if((Get-Item -LiteralPath $file).Length -ne $row.bytes -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $row.sha256){throw ('Transport drift: '+$row.path)}
 $tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null
 if($errors.Count){$errors|ForEach-Object{Write-Output $_.Message};throw ('Bootstrap parse failure: '+$row.path)}
}
& (Join-Path $tools 'probes\sr0-s\fresh-on-bridge\scripts\preflight-ps1.ps1') -Root $tools
Write-Output 'ROOT_BOOTSTRAP_PARSE_PASS'
