# Target-only WM_CLOSE after source-bound UIA/PW capture; no activation/focus API.
function Request-FactoryOwnedClose([IntPtr]$Hwnd,[int]$ExpectedPID,[int]$WindowPID,[scriptblock]$OwnedGuard,[scriptblock]$SourceGuard,[scriptblock]$LockGuard,[scriptblock]$BackgroundGuard,[scriptblock]$Post){
 if($Hwnd -eq [IntPtr]::Zero -or $ExpectedPID -le 0 -or $WindowPID -ne $ExpectedPID){throw 'Owned close HWND/PID mismatch'}
 & $OwnedGuard
 & $SourceGuard
 & $LockGuard
 & $BackgroundGuard
 if(-not [bool](& $Post $Hwnd ([uint32]0x0010) ([IntPtr]::Zero) ([IntPtr]::Zero))){throw 'Owned WM_CLOSE posting failed'}
 return [ordered]@{hwnd=$Hwnd.ToInt64();pid=$ExpectedPID;message=16;messageName='WM_CLOSE';posted=$true;at=[DateTimeOffset]::UtcNow.ToString('o');activationRequested=$false}
}
