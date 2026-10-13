# Source-only root RSS guard. It observes coordinator process only; no child
# memory limit or renderer/runtime behavior is changed here.
function Get-StackRootRssSample([string]$Phase) {
    $root = Get-Process -Id $PID -ErrorAction Stop
    [ordered]@{
        supervisor = 'rootRSS'
        phase = $Phase
        pid = $root.Id
        path = $root.Path
        workingSetBytes = [int64]$root.WorkingSet64
        privateBytes = [int64]$root.PrivateMemorySize64
        sampledAt = [DateTimeOffset]::UtcNow.ToString('o')
    }
}
function Assert-StackRootRss([string]$Phase,[int64]$MaxBytes = 1073741824) {
    $sample = Get-StackRootRssSample $Phase
    if($sample.workingSetBytes -le 0 -or $sample.workingSetBytes -gt $MaxBytes){
        throw ('rootRSS supervisor bound exceeded: '+$Phase)
    }
    return $sample
}
