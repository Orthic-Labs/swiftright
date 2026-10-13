<#
Offline path-fault controls for dynamic Count1 transport. Dot-sources only
pure guards; no filesystem, process, native-window, GUI, remote, or lock action.
#>
$ErrorActionPreference='Stop'
$helper=Join-Path $PSScriptRoot 'transport-path-controls.ps1'
if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw 'Transport path helper missing'}
if((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'f36d0eca2bd8dba2d4c27a62f05eede8b2ea3658287086e3168ac0307dc92595'){throw 'Transport path helper drift'}
. $helper
$cases=[ordered]@{
 'relative-positive'=@{kind='path';value='factory/native/windows/example.json';accept=$true}
 'drive-relative'=@{kind='path';value='C:relative.json';accept=$false}
 'drive-rooted'=@{kind='path';value='C:\rooted.json';accept=$false}
 'unc'=@{kind='path';value='\\server\share\file.json';accept=$false}
 'rooted-slash'=@{kind='path';value='/rooted.json';accept=$false}
 'backslash'=@{kind='path';value='factory\native\example.json';accept=$false}
 'colon'=@{kind='path';value='factory/native:C.json';accept=$false}
 'duplicate-separator'=@{kind='path';value='factory//native/example.json';accept=$false}
 'dot-segment'=@{kind='path';value='factory/./example.json';accept=$false}
 'traversal'=@{kind='path';value='factory/native/../example.json';accept=$false}
 'manifest-contained-positive'=@{kind='containment';root='D:\transport-r1';value='D:\transport-r1\dynamic-input-transport-manifest.json';accept=$true}
 'manifest-escape-sibling'=@{kind='containment';root='D:\transport-r1';value='D:\transport-r1-other\manifest.json';accept=$false}
 'destination-escape-parent'=@{kind='containment';root='D:\transport-r1\archive';value='D:\transport-r1\archive\..\outside.json';accept=$false}
 'destination-escape-drive'=@{kind='containment';root='D:\transport-r1\archive';value='C:\outside.json';accept=$false}
}
$results=[System.Collections.Generic.List[object]]::new()
foreach($name in $cases.Keys){
 $c=$cases[$name];$accepted=$false;$error=''
 try{
  if($c.kind -ceq 'path'){Assert-AdapterArchivePath $c.value|Out-Null}
  else{Get-ContainedTransportPath $c.root $c.value $name|Out-Null}
  $accepted=$true
 }catch{$error=[string]$_}
 if($accepted -ne $c.accept){throw ('Path control outcome mismatch: '+$name)}
 $results.Add([ordered]@{name=$name;accepted=$accepted;expected=$c.accept;error=$error;nativeWindowActions=0;lockActions=0})
}
[ordered]@{kind='factory-dynamic-transport-path-controls-v1';status='passed-source-only';cases=@($results);nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0;qualification='hold'}|ConvertTo-Json -Depth 8
