# Actual production decoder, pure JSON/file fixtures; no child/compiler/window calls.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh decoder-control output required'}
. (Join-Path $PSScriptRoot 'stream-control-admission.ps1')
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$results=@()
foreach($count in @(1,2,6)){
 $path=Join-Path $OutputRoot ('array-'+$count+'.json')
 $objects=@();for($i=0;$i -lt $count;$i++){$objects+=@{mode=('row-'+$i)}}
 ConvertTo-Json -InputObject @($objects)|Set-Content -Encoding UTF8 -LiteralPath $path
 $rows=Read-CompilerControlRows $path
 if($rows.Count -ne $count){throw 'JSON array boxing regression'}
 for($i=0;$i -lt $count;$i++){if($rows[$i].mode -cne ('row-'+$i)){throw 'JSON row identity lost'}}
 $results+=@{count=$count;passed=$true;synthetic=$true}
}
foreach($json in @('{}','true','null','[]','[1]','["row"]','[[{}]]')){
 $path=Join-Path $OutputRoot ('fault-'+$results.Count+'.json');[IO.File]::WriteAllText($path,$json)
 $rejected=$false;try{$null=Read-CompilerControlRows $path}catch{$rejected=$true}
 if(-not $rejected){throw 'Malformed row/root admitted'}
 $results+=@{input=$json;rejected=$true;synthetic=$true}
}
ConvertTo-Json -InputObject @($results) -Depth 12|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
