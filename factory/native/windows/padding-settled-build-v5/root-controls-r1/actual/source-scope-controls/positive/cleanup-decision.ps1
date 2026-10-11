# Pure decision shared with production. WAIT_OBJECT_0 means exited: never terminate.
function Get-CompilerCleanupAction([uint32]$WaitStatus,[bool]$AbortRequested) {
 if($WaitStatus -eq 0){return 'natural-exit-no-termination'}
 if($WaitStatus -ne 258){throw 'Owned handle wait failed/unknown'}
 if(-not $AbortRequested){throw 'Still-running compiler without abort reason'}
 return 'terminate-owned-handle'
}
