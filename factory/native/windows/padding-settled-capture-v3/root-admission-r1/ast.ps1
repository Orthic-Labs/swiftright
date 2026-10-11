$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v3'
$manifest=Join-Path $root 'stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne 'd53703da3c712098bac4b51e919e47454dd284c39d92054ef396a6b908679822'){throw 'Reviewed capture stage drift'}
$stage=Get-Content $manifest -Raw|ConvertFrom-Json
$parsed=@()
foreach($row in $stage.files){
 $file=if($row.path.StartsWith('factory/native/windows/padding-settled-capture-v3/')){Join-Path $root $row.path.Replace('factory/native/windows/padding-settled-capture-v3/','')}elseif($row.path.StartsWith('factory/native/windows/padding-settled-build-v5/')){Join-Path 'D:\Claude\swiftright\.factory-work\hosts\padding-settled' $row.path.Replace('factory/native/windows/padding-settled-build-v5/','')}else{Join-Path 'D:\Claude\swiftright' $row.path}
 if((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $row.sha256.Replace('sha256:','') -or (Get-Item $file).Length -ne $row.bytes){throw ('Capture source drift '+$row.path)}
 if($file.EndsWith('.ps1') -and $row.path.StartsWith('factory/native/windows/padding-settled-capture-v3/')){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors);if($errors.Count){throw ('PowerShell parse errors '+$file)};$parsed+=$file}
}
@{status='CAPTURE_SOURCE_PINS_AND_AST_PASSED';parsed=$parsed;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 5
