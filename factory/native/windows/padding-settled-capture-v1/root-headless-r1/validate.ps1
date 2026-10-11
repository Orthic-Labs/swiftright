$ErrorActionPreference='Stop'
$here='D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v1'
$manifest=Join-Path $here 'root-stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne '05b109c61b989dd8e184ccd8fa8bc39a7b7d038660b6bd7a174179287a2d2277'){throw 'Root capture stage drift'}
$stage=Get-Content $manifest -Raw|ConvertFrom-Json
$parsed=@()
foreach($row in $stage.files){
 $file=Join-Path 'D:\Claude\swiftright' $row.path
 if((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $row.sha256 -or (Get-Item -LiteralPath $file).Length -ne $row.bytes){throw ('Root capture file drift '+$row.path)}
 if($file.EndsWith('.ps1')){
  $tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
  if(@($parseErrors).Count){throw ('AST parse failure '+$row.path+' '+[string]$parseErrors)}
  $parsed+=@{path=$row.path;sha256=$row.sha256;errors=0}
 }
}
$pkg='D:\Claude\swiftright\.factory-work\hosts\padding-settled\package'
& "$here\prepare-capture.ps1" -CompileReceiptPath "$pkg\build-settled-r1\observation.json" -ExecutablePath "$pkg\build-settled-r1\FactoryProbe.exe" -CompileReceiptHash '33eaea411164c7c650fe69521ba01ee81a0855fa31f8ff345d0b08a3202de9ba' -ExeHash '431e68252a68dbbc0218c6bd854eb130b7a0385713f98d07ec4b3c3cf5f2cbc3' -Count 1 -OutputPath "$here\actual-single-r1"
@{status='COUNT1_AST_AND_NO_LAUNCH_PREPARATION_PASSED';parsed=$parsed;nativeActions=0;lockAcquired=$false;prepared=(Get-Content "$here\prepared-dispatch-1.json" -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 12
