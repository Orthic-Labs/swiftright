$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$overlay='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\root-metadata-controls-v1\execute-r3';$here=[IO.Path]::GetFullPath((Join-Path $overlay '..\..'));$baseRoot=$here
$expected='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3';if($here -cne $expected){throw 'Execution overlay root resolution failed'}
$rootManifest=Get-Content -Raw (Join-Path $here 'root-stage-manifest.json')|ConvertFrom-Json
$original=@($rootManifest.files|Where-Object{$_.path -ceq 'factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json'})
$results=@()
foreach($n in @('coordinator-r3.ps1','dispatch-r3.ps1','capture-repeat-r3.ps1')){
 $f=Join-Path $overlay $n;$tokens=$null;$errors=$null;$ast=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors);if($errors.Count){throw ('Parser failure '+$n)}
 $ifs=@($ast.FindAll({param($node)$node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.Contains("throw 'Integration binding manifest drift'")},$true));if($ifs.Count -ne 1){throw ('Exact integration guard cardinality '+$n)}
 $text=$ifs[0].Extent.Text
 foreach($fault in @('baseline','wrong-sha256','wrong-bytes')){
  $bindingEntry=@($original|ConvertTo-Json -Depth 20|ConvertFrom-Json)
  if($fault -ceq 'wrong-sha256'){$bindingEntry[0].sha256='sha256:'+('0'*64)}
  if($fault -ceq 'wrong-bytes'){$bindingEntry[0].bytes+=1}
  $accepted=$false;$message='';try{Invoke-Expression $text;$accepted=$true}catch{$message=[string]$_}
  if($accepted -ne ($fault -ceq 'baseline')){throw ('Execution-source guard outcome mismatch '+$n+' '+$fault)}
  if($fault -cne 'baseline' -and $message -cne 'Integration binding manifest drift'){throw 'Wrong guard rejection reason'}
  $results+=[ordered]@{script=$n;sourceSha256=(Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant();control=$fault;accepted=$accepted;error=$message}
 }
}
[ordered]@{kind='root-actual-windows-execution-overlay-manifest-controls-v1';status='PASS';controls=$results;exactGuardAstExecuted=$true;root=$here;nativeLaunches=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
