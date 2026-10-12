[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$item=Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt 2097152){throw 'bounded regular coordinator source required'}
$src=[IO.File]::ReadAllText($item.FullName)
foreach($needle in @('Read-BoundedJson','Write-AtomicJson','startReceipt','finalReceipt','parentCertificatePresent','parentOriginalHandle','parentPath','parentStartTimeUtc','presentMonSessionAbsent','activeSelfOnly','noActivate','lockMutated=$false','[IO.File]::Move','EntryPoint="WaitForSingleObject"','EntryPoint="GetExitCodeProcess"','Sr0DisplayCoordinatorKernelV4','parentExitRaw','parentExitSigned')){if($src.IndexOf($needle,[StringComparison]::Ordinal)-lt 0){throw "coordinator token missing: $needle"}}
foreach($forbidden in @('Start-Process','Stop-Process','taskkill.exe','[IO.File]::Delete','Remove-Item')){if($src.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase)-ge 0){throw "coordinator forbidden action: $forbidden"}}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out=[ordered]@{kind='sr0-display-coordinator-v4-controls';status='passed';sourcePath=$item.FullName;sourceBytes=$item.Length;nativeActions=0;lockActions=0;guiActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8
