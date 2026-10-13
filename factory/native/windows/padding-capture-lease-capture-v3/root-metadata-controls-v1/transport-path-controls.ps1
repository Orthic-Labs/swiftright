<#
Pure path guards shared by Count1 transport exporter & offline fault controls.
No filesystem, process, native-window, GUI, remote, or lock action occurs here.
#>
function Assert-AdapterArchivePath {
 param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Path)
 $parts=$Path.Split('/')
 if([string]::IsNullOrWhiteSpace($Path) -or $Path -match '^[A-Za-z]:' -or $Path -match '^[\\/]' -or $Path.Contains('\') -or $Path.Contains(':') -or $Path.Contains('//') -or $parts -contains '' -or $parts -contains '.' -or $parts -contains '..'){
  throw ('Adapter ref must be normalized repo-relative archive path: '+$Path)
 }
 return $Path
}

function Get-ContainedTransportPath {
 param(
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][string]$Candidate,
  [Parameter(Mandatory=$true)][string]$Label
 )
 $rootFull=[System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
 $candidateFull=[System.IO.Path]::GetFullPath($Candidate)
 $prefix=$rootFull+[System.IO.Path]::DirectorySeparatorChar
 if(-not $candidateFull.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)){
  throw ($Label+' escaped fresh transport root: '+$Candidate)
 }
 return $candidateFull
}
