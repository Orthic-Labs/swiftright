# Actual production close helper: pure guard/callback controls; no OS messages/windows.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh output required'}
. (Join-Path $PSScriptRoot 'owned-close.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$results=@()
foreach($mode in @('normal','bad-hwnd','bad-pid','owned-drift','source-drift','lock-lost','foreground','failed-post')){
 $script:mode=$mode;$script:events=[Collections.Generic.List[string]]::new();$script:postCalls=0
 $hwnd=if($mode -eq 'bad-hwnd'){[IntPtr]::Zero}else{[IntPtr]::new(123)}
 $pidValue=if($mode -eq 'bad-pid'){8}else{7}
 $failed=$false;$result=$null
 try{$result=Request-FactoryOwnedClose $hwnd 7 $pidValue {
  $script:events.Add('owned');if($script:mode -eq 'owned-drift'){throw 'owned drift'}
 } {$script:events.Add('source');if($script:mode -eq 'source-drift'){throw 'source drift'}} {
  $script:events.Add('lock');if($script:mode -eq 'lock-lost'){throw 'lock lost'}
 } {$script:events.Add('background');if($script:mode -eq 'foreground'){throw 'owned foreground'}} {
  param($target,$message,$w,$l)
  $script:events.Add('post');$script:postCalls++
  if($target.ToInt64() -ne 123 -or $message -ne 16 -or $w -ne [IntPtr]::Zero -or $l -ne [IntPtr]::Zero){throw 'Non-WM_CLOSE/native parameter drift'}
  return ($script:mode -ne 'failed-post')
 }}catch{$failed=$true}
 if($failed -ne ($mode -ne 'normal')){throw ('Close control failed '+$mode)}
 if($script:postCalls -ne [int]($mode -in @('normal','failed-post'))){throw ('Unsafe post occurred '+$mode)}
 if($mode -eq 'normal' -and (($script:events -join ',') -ne 'source,lock,background,owned,post' -or $result.activationRequested)){throw 'Close skipped guards/requested activation'}
 if($mode -eq 'owned-drift' -and ($script:events -join ',') -ne 'source,lock,background,owned'){throw 'Final live ownership check omitted'}
 $results+=[ordered]@{mode=$mode;rejected=$failed;postCalls=$script:postCalls;events=@($script:events)}
}
$results|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
