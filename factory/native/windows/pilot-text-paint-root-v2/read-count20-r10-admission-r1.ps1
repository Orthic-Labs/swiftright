$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10'
$control=Join-Path $root 'control-count20-r10';$admission=Join-Path $root 'admission-count20-r10'
$paths=@{
 'config-template.json'=(Join-Path $control 'config-template.json')
 'package-preflight.json'=(Join-Path $control 'package-preflight.json')
 'mta-config-controls.json'=(Join-Path $control 'mta-config-controls.json')
 'uia-mta-controls.json'=(Join-Path $control 'uia-mta-controls.json')
 'integration-controls.json'=(Join-Path $control 'integration-controls.json')
 'issued-metadata.json'=(Join-Path $admission 'issued-metadata.json')
 'source-inputs.json'=(Join-Path $admission 'source-inputs.json')
}
$files=@();$total=0
foreach($name in $paths.Keys){$f=Get-Item -LiteralPath $paths[$name] -Force;if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $f.Length -gt 1048576){throw 'bounded leaf required'};$total+=$f.Length;if($total -gt 4194304){throw 'aggregate bound'};$b=[IO.File]::ReadAllBytes($f.FullName);$h=[Security.Cryptography.SHA256]::Create();try{$sha=([BitConverter]::ToString($h.ComputeHash($b))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()};$files+=@{path=$name;bytes=$b.Length;sha256=$sha;base64=[Convert]::ToBase64String($b)}}
@{status='exported';files=$files;bytes=$total;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 8
