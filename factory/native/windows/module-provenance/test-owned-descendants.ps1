$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'owned-descendants.ps1')
$start=[datetime]::Parse('2026-10-11T00:00:00Z').ToUniversalTime()
function Row($id,$parent){return [pscustomobject]@{ProcessId=$id;ParentProcessId=$parent;CreationDate=$start;ExecutablePath='C:\fixture\swift.exe';CommandLine='synthetic fixture'}}
function Reject($label,$rows){try{$null=@(Get-OwnedDescendants -Rows $rows -RootPid 100 -RootStartedAt $start)}catch{return [ordered]@{control=$label;rejected=$true;reason=[string]$_}};throw "Fault accepted: $label"}
$zero=@(Get-OwnedDescendants -Rows @() -RootPid 100 -RootStartedAt $start)
if($zero.Count -ne 0){throw 'Zero-child traversal failed'}
$normal=@(Get-OwnedDescendants -Rows @((Row 100 1),(Row 101 100),(Row 102 101),(Row 900 1)) -RootPid 100 -RootStartedAt $start)
if($normal.Count -ne 2 -or $normal[0].pid -ne 101 -or $normal[1].pid -ne 102){throw 'Accepted real traversal fixture failed'}
$controls=@()
$controls+=Reject 'cyclic-child' @((Row 100 102),(Row 101 100),(Row 102 101))
$controls+=Reject 'duplicate-child-pid' @((Row 101 100),(Row 101 100))
$bad=Row 101 100;$bad.CreationDate=$null;$controls+=Reject 'missing-child-time' @($bad)
$bad=Row 101 100;$bad.ExecutablePath='';$controls+=Reject 'missing-child-path' @($bad)
$bad=Row 101 100;$bad.ProcessId=-1;$controls+=Reject 'malformed-child-pid' @($bad)
$deep=@();for($i=101;$i -le 134;$i++){$deep+=Row $i ($i-1)};$controls+=Reject 'depth-bound' $deep
[ordered]@{kind='pure-powershell-traversal-controls';synthetic=$true;nativeProcessLaunched=$false;zeroChildCount=$zero.Count;acceptedChildCount=$normal.Count;controls=$controls}|ConvertTo-Json -Depth 8
