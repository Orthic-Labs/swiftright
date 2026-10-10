# Runs one script while holding the Dell desktop lock (D:\Claude\desktop.lock).
# Protocol: wait until the lock file reads `free`, write `<Label> <timestamp>`, run the script, then write `free` again (in a finally block,
# so a failing script still releases it). Waiting is a sleep loop on this side, never a short poll of the desktop. Nothing is deleted.
param(
  [Parameter(Mandatory = $true)][string]$File,
  [string]$FileArgs = '',
  [string]$Label = 'T10/12/4',
  [string]$Lock = 'D:\Claude\desktop.lock',
  [int]$PollSeconds = 20,
  [int]$MaxWaitMinutes = 720
)
$ErrorActionPreference = 'Stop'
$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
$got = $false
while (-not $got) {
  $cur = ''
  try { $cur = ([string](Get-Content -Raw -LiteralPath $Lock)).Trim() } catch { }
  if ($cur -eq 'free') {
    Set-Content -LiteralPath $Lock -Value ('{0} {1}' -f $Label, (Get-Date).ToString('o'))
    Start-Sleep -Milliseconds 300
    if (([string](Get-Content -Raw -LiteralPath $Lock)).Trim() -like "$Label *") { $got = $true }
  } else {
    if ((Get-Date) -gt $deadline) { throw "lock still held after $MaxWaitMinutes min: $cur" }
    "waiting $(Get-Date -Format o) lock=[$cur]"
    Start-Sleep -Seconds $PollSeconds
  }
}
"lock taken $(Get-Date -Format o) label=$Label"
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $File @($FileArgs -split ' ' | Where-Object { $_ })
  "script exit=$LASTEXITCODE"
} finally {
  Set-Content -LiteralPath $Lock -Value 'free'
  "lock released $(Get-Date -Format o)"
}
