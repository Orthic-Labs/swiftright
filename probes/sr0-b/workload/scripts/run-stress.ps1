# SR0 stress series (Windows, R10). Runs scripts\run-workload.ps1 once per Rows x KeyRate combination, sequentially, each as a NORMAL gated run
# (artifact identity gate, quiet-host gate, PresentMon all-process capture, interactive task, analyzer with every section 11 threshold, resource sampling),
# then writes one summary table over all of them. Run it as a FILE from an ELEVATED session, like run-workload.ps1:
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-workload\probes\sr0-b\workload\scripts\run-stress.ps1"
#   ... -Rows 200+1000 -KeyRates 10            (a subset)       ... -Runs 1 -Measure 30        (a quick pass: still gated, but not the 3 x 60 s record)
# -Rows / -KeyRates take a list separated by + (or , ; :). Use + when starting this through `win "..."`: a bare comma is turned into an array by the
# calling shell and arrives glued together ("200,5000" -> "2005000").
#   ... -SummaryOnly -Series 20261010-101500   (rebuild the table of an earlier series)       ... -DryRun   (print the plan, run nothing)
# Default grid: rows 200, 1000, 5000 x key rate 10, 30 per second = 6 runs of 3 x (10 s warm-up + 60 s measured), about 30 minutes of wall clock.
# Each combination is its own run root <Base>\runs\<Series>-r<rows>-k<rate> with its own report\report.json. A combination whose gates abort (host busy,
# artifact mismatch, PresentMon not recording) is recorded as GATE in the table and the series continues with the next one (-StopOnAbort stops instead).
# -Rows needs the app to read `--rows N` (WorkloadArgs); the analyzer voids runs whose meta.json total_rows differs from the request.
# Outputs: <Base>\runs\<Series>-stress\series.json (manifest), stress-summary.md, stress-summary.json.
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$Rows = '200+1000+5000',
  [string]$KeyRates = '10+30',
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [string]$Series = '',
  [string]$ExpectDll = '',
  [double]$ExpectScale = 2.5,
  [switch]$Force,
  [switch]$NoResources,
  [switch]$StopOnAbort,
  [switch]$SummaryOnly,
  [switch]$DryRun
)
$ErrorActionPreference = 'Continue'
if (-not $Series) { $Series = Get-Date -Format 'yyyyMMdd-HHmmss' }
$scripts  = "$Base\probes\sr0-b\workload\scripts"
$analysis = "$Base\probes\sr0-b\workload\analysis"
$runsDir  = "$Base\runs"
$outDir   = "$runsDir\$Series-stress"
$manifest = "$outDir\series.json"
New-Item -ItemType Directory -Force $outDir | Out-Null
$entries = @()
$rowList  = @($Rows -split '[,;:+/ ]+' | Where-Object { $_ } | ForEach-Object { [int]$_ })
$rateList = @($KeyRates -split '[,;:+/ ]+' | Where-Object { $_ } | ForEach-Object { [double]$_ })
if (-not $rowList.Count -or -not $rateList.Count) { Write-Host "ABORT: -Rows '$Rows' / -KeyRates '$KeyRates' hold no numbers"; exit 3 }

function Rate-Text([double]$k) { ([string]$k).Replace(',', '.') }

if (-not $SummaryOnly) {
  $plan = foreach ($r in $rowList) { foreach ($k in $rateList) { [pscustomobject]@{ Rows = $r; KeyRate = $k; Tag = "$Series-r$r-k$(Rate-Text $k)" } } }
  Write-Host ("stress series {0}: {1} combinations x {2} runs (warm-up {3} s, measured {4} s){5}" -f $Series, @($plan).Count, $Runs, $Warmup, $Measure, $(if ($DryRun) { ' [dry run]' } else { '' }))
  foreach ($c in $plan) {
    $common = @{ Base = $Base; Runs = $Runs; Warmup = $Warmup; Measure = $Measure; Rows = $c.Rows; KeyRate = $c.KeyRate; Tag = $c.Tag; ExpectScale = $ExpectScale }
    if ($ExpectDll) { $common['ExpectDll'] = $ExpectDll }
    if ($Force) { $common['Force'] = $true }
    if ($NoResources) { $common['NoResources'] = $true }
    Write-Host ("--- rows={0} key_rate={1}/s tag={2}" -f $c.Rows, $c.KeyRate, $c.Tag)
    if ($DryRun) { Write-Host ("    run-workload.ps1 " + (($common.GetEnumerator() | Sort-Object Name | ForEach-Object { "-$($_.Name) $($_.Value)" }) -join ' ')); continue }
    $t0 = Get-Date
    $global:LASTEXITCODE = 0
    & "$scripts\run-workload.ps1" @common
    $rc = $LASTEXITCODE
    $report = "$runsDir\$($c.Tag)\report\report.json"
    $entries += [pscustomobject]@{
      rows = $c.Rows; key_rate = $c.KeyRate; tag = $c.Tag; run_root = "$runsDir\$($c.Tag)"; started = $t0.ToString('o'); ended = (Get-Date).ToString('o')
      exit_code = $rc; report = $(if (Test-Path $report) { $report } else { $null })
    }
    # run-workload exits 2-5 before any run when a gate fails (artifact, quiet host, PresentMon, busy host); the analyzer's own codes (0/1/2) arrive via report.json
    if (-not (Test-Path $report)) {
      Write-Host ("    GATE: no report for {0} (run-workload exit {1})" -f $c.Tag, $rc)
      if ($StopOnAbort) { Write-Host 'stopping the series (-StopOnAbort)'; break }
    }
    ($entries | ConvertTo-Json -Depth 4) | Set-Content -Path $manifest -Encoding ascii
  }
  if ($DryRun) { exit 0 }
  ($entries | ConvertTo-Json -Depth 4) | Set-Content -Path $manifest -Encoding ascii
}

# summary table (python 3.11, isolated mode): reads each combination's report\report.json
& py -3.11 -I "$analysis\stress_summary.py" --root $runsDir --series $Series --manifest $manifest --out "$outDir\stress-summary" 2>&1 | Tee-Object -FilePath "$outDir\stress-summary-console.txt"
Write-Host "stress summary: $outDir\stress-summary.md"
