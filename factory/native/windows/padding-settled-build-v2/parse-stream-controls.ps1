param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh parse output required'}
$rows=@()
foreach($name in @('stream-seal.ps1','cleanup.ps1','test-stream-seal.ps1','test-process-streams-bounded.ps1','stream-control-admission.ps1','run-stream-controls.ps1','test-stream-admission.ps1','test-json-array-shape.ps1')){
 $file=Join-Path $PSScriptRoot $name;$tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
 $rows+=@{path=$file;sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant();errors=@($errors|ForEach-Object{[string]$_})}
}
ConvertTo-Json -InputObject @($rows) -Depth 8|Set-Content -Encoding UTF8 -LiteralPath $Output
if(@($rows|Where-Object{$_.errors.Count}).Count){throw 'Stream AST errors'}
