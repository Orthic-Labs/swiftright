# SR0-B batch 4 runbook

Run on the Windows host (`D:\Claude\sr0b-frame-clock`). Two parts run at the same time: an elevated
PresentMon capture (all processes, no name filter) and the interactive desktop harness
`run-desktop-v3.ps1` with the b4 binary. Do not run RightKit window tests or any other
foreground-stealing test on this host during the batch.

## Inputs already staged

| Item | Path |
|---|---|
| Harness v3 | `D:\Claude\sr0b-frame-clock\scripts-v3\run-desktop-v3.ps1` |
| Analyzer | `D:\Claude\sr0b-frame-clock\scripts-v3\pm_an3.py` |
| b4 SwiftHost (+ DLL beside exe) | `D:\Claude\sr0b-frame-clock\b4\scratch-b4\out\Products\Release-windows-x86_64\` |
| PresentMon 2.6.0 | `D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe` |

## Output names

| File | Written by |
|---|---|
| `D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.csv` | PresentMon (`--output_file`) |
| `D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.console.txt` | PresentMon stdout and stderr |
| `D:\Claude\sr0b-frame-clock\result-desktop-v3-batch4.txt` | harness (`-OutFile`) |
| `D:\Claude\sr0b-frame-clock\runs-b4\<stamp>\<variant>-<n>\` | per run: events.csv, dwm.csv, jobs.csv, ticks.csv, meta.txt, harness-samples.csv |
| `D:\Claude\sr0b-frame-clock\analysis-batch4.txt` | analyzer output |

`<stamp>` is the `runRoot=` value in the first lines of `result-desktop-v3-batch4.txt`.

## Step 1: PresentMon (elevated PowerShell, start first)

Run in an elevated PowerShell (ETW needs admin). The `--timed 480` value replaces the plan's 360
because 30 launches at about 13 s each plus setup needs roughly 400 s. `--track_etw_status` is
omitted: PresentMon 2.6.0 does not have it (checked with `--help`).

```powershell
& "D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe" --v1_metrics --qpc_time --no_track_gpu --no_track_input --no_console_stats --write_display_metadata --session_name SR0B4 --stop_existing_session --output_file D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.csv --timed 480 --terminate_after_timed *> D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.console.txt
```

Do not use `--process_name`, `--exclude_dropped` or `--no_track_display`.

## Step 2: desktop harness (start 5 s after step 1)

Run from the normal (non-elevated) session that owns the desktop, or from an admin shell that
registers this interactive task:

```powershell
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\Claude\sr0b-frame-clock\scripts-v3\run-desktop-v3.ps1 -Runs 10 -OutFile D:\Claude\sr0b-frame-clock\result-desktop-v3-batch4.txt'
$pri = New-ScheduledTaskPrincipal -UserId adrds -LogonType Interactive
Register-ScheduledTask -TaskName SR0B4Desktop -Action $act -Principal $pri -Force | Out-Null
Start-ScheduledTask -TaskName SR0B4Desktop
```

Variants per round are `base`, `tbp` (`--timer-res-1`) and `nosamp` (`--no-dwm-sampler`).
`-Runs 10` gives 30 launches (10 per variant). A launch is skipped with `skip_run ... reason=rk2-present`
if an `rk2*` process is still alive after 60 s.

When the result file contains `finished=`, remove the task:

```powershell
Unregister-ScheduledTask -TaskName SR0B4Desktop -Confirm:$false
```

## Step 3: analysis (after `finished=` and PresentMon has exited)

```powershell
py -3.11 -I D:\Claude\sr0b-frame-clock\scripts-v3\pm_an3.py D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.csv D:\Claude\sr0b-frame-clock\result-desktop-v3-batch4.txt D:\Claude\sr0b-frame-clock\presentmon\pm-batch4.console.txt > D:\Claude\sr0b-frame-clock\analysis-batch4.txt
```

Send `analysis-batch4.txt` back to the Mac. Do not change any file in `scripts-v3` during the batch.

## Pass criteria (from INVESTIGATION.md)

- Capture integrity PASS (every PID has at least 355 rows; QPC join within range; no loss lines).
- At least 9 of 10 valid runs per variant. Disturbed runs stay in the table with their reason.
- Zero missed vblanks and no `Dropped=1` in the workload window of valid runs; displayed p95 at most 16.764 ms.
- Variant differences are claimed only from the rank-sum output with at least 20 valid runs per variant.
