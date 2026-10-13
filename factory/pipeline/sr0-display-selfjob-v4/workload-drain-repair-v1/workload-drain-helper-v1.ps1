function Complete-WorkloadDrainV1 {
  param(
    [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
    [Parameter(Mandatory)][System.Threading.Tasks.Task[string]]$StdoutTask,
    [Parameter(Mandatory)][System.Threading.Tasks.Task[string]]$StderrTask,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 15
  )
  $frequency=[System.Diagnostics.Stopwatch]::Frequency
  $startedTicks=[System.Diagnostics.Stopwatch]::GetTimestamp()
  $deadlineTicks=$startedTicks + ([int64]$TimeoutSeconds * $frequency)
  function Get-RemainingMilliseconds([int64]$Deadline,[int64]$Freq){
    $left=$Deadline-[System.Diagnostics.Stopwatch]::GetTimestamp()
    if($left -le 0){return 0}
    $ms=[int64][math]::Ceiling(($left * 1000.0) / $Freq)
    if($ms -gt [int64]([int]::MaxValue)){$ms=[int64]([int]::MaxValue)}
    return [int]$ms
  }
  $processWaitCompleted = $false
  $processTerminal = $false
  $processWaitError = $null
  try {
    # One monotonic deadline covers process terminal wait & both pipe drains.
    # WaitForExit(Int32) synchronizes exit without closing or discarding streams.
    $processWaitCompleted = $Process.WaitForExit((Get-RemainingMilliseconds $deadlineTicks $frequency))
    $processTerminal = [bool]$processWaitCompleted
  } catch {
    $processWaitError = $_.Exception.Message
    try { $processTerminal = [bool]$Process.HasExited } catch { $processTerminal = $false }
  }
  $stdoutCompleted = $false
  $stderrCompleted = $false
  try { $stdoutCompleted = $StdoutTask.Wait((Get-RemainingMilliseconds $deadlineTicks $frequency)) } catch { }
  try { $stderrCompleted = $StderrTask.Wait((Get-RemainingMilliseconds $deadlineTicks $frequency)) } catch { }
  $elapsedMs=[int64][math]::Floor(([System.Diagnostics.Stopwatch]::GetTimestamp()-$startedTicks)*1000.0/$frequency)
  [ordered]@{
    processWaitCompleted = [bool]$processWaitCompleted
    processTerminal = [bool]$processTerminal
    processWaitError = $processWaitError
    stdoutCompleted = [bool]$stdoutCompleted
    stderrCompleted = [bool]$stderrCompleted
    stdoutFaulted = [bool]$StdoutTask.IsFaulted
    stderrFaulted = [bool]$StderrTask.IsFaulted
    stdoutCanceled = [bool]$StdoutTask.IsCanceled
    stderrCanceled = [bool]$StderrTask.IsCanceled
    streamsDrained = [bool]($stdoutCompleted -and $stderrCompleted -and $StdoutTask.IsCompleted -and $StderrTask.IsCompleted)
    timeoutSeconds = $TimeoutSeconds
    elapsedMilliseconds = $elapsedMs
    totalBudgetBounded = [bool]($elapsedMs -le ([int64]$TimeoutSeconds*1000+1000))
  }
}
