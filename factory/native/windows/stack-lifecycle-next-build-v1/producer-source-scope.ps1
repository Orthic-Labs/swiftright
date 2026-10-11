# Fixed operational source authority. Generated fixture scripts never become executable producer input.
function Get-FactoryProducerScripts([string]$Root){
 $rootPath=[IO.Path]::GetFullPath($Root)
 $expected=@('build-hosts-v2.ps1','cleanup-decision.ps1','cleanup.ps1','control-admission.ps1','parse-stream-controls.ps1','preflight.ps1','producer-source-scope.ps1','pure-controls\parse-controls.ps1','pure-controls\reserved-assignment-lint.ps1','pure-controls\test-cleanup.ps1','pure-controls\test-host-inputs.ps1','pure-controls\test-integer-admission.ps1','run-controls.ps1','run-stream-controls.ps1','shared\host-inputs.ps1','shared\verify-runtime-source.ps1','stream-control-admission.ps1','stream-seal.ps1','test-json-array-shape.ps1','test-process-streams-bounded.ps1','test-producer-source-scope.ps1','test-stream-admission.ps1','test-stream-seal.ps1')|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $rootPath $_))}
 $actual=@(Get-ChildItem -LiteralPath $rootPath -File -Filter '*.ps1')
 foreach($dir in @('pure-controls','shared')){$actual+=@(Get-ChildItem -LiteralPath (Join-Path $rootPath $dir) -Recurse -File -Filter '*.ps1')}
 if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -cnotcontains $_.FullName}).Count -ne 0 -or @($actual.FullName|Select-Object -Unique).Count -ne $expected.Count){throw 'Exact operational producer script membership invalid'}
 return $actual|Sort-Object FullName
}
