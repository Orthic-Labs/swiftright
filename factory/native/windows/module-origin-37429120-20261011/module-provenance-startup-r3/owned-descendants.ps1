# Pure traversal used by actual startup observation & fault controls.
function Get-OwnedDescendants {
  param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Rows,[Parameter(Mandatory=$true)][uint32]$RootPid,[Parameter(Mandatory=$true)][datetime]$RootStartedAt)
  if($RootPid -eq 0){throw 'Invalid root PID'}
  $ids=[Collections.Generic.HashSet[uint32]]::new()
  foreach($row in $Rows){
    if($null -eq $row.ProcessId -or $null -eq $row.ParentProcessId -or [string]$row.ProcessId -notmatch '^\d+$' -or [string]$row.ParentProcessId -notmatch '^\d+$'){throw 'Malformed process identity'}
    if(-not $ids.Add([uint32]$row.ProcessId)){throw 'Duplicate process PID'}
  }
  $visited=[Collections.Generic.HashSet[uint32]]::new();$null=$visited.Add($RootPid)
  $frontier=@($RootPid);$round=0
  while($frontier.Count -gt 0){
    $round++;if($round -gt 32){throw 'Descendant traversal depth exceeded'}
    $next=@($Rows|Where-Object{[uint32]$_.ParentProcessId -in $frontier})
    $newIds=@()
    foreach($child in $next){
      if(-not $visited.Add([uint32]$child.ProcessId)){throw 'Cyclic process ancestry'}
      if($child.CreationDate -isnot [datetime] -or $child.CreationDate.ToUniversalTime() -lt $RootStartedAt.ToUniversalTime() -or [string]::IsNullOrEmpty($child.ExecutablePath)){throw 'Malformed owned child identity'}
      $newIds+=[uint32]$child.ProcessId
      [ordered]@{pid=[uint32]$child.ProcessId;parentPid=[uint32]$child.ParentProcessId;path=$child.ExecutablePath;startedAt=$child.CreationDate.ToUniversalTime().ToString('o');commandLine=$child.CommandLine}
    }
    # Explicit pipeline creates zero-length array when no child exists.
    $frontier=@($newIds|ForEach-Object{$_})
  }
}
