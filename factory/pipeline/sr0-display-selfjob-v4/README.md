# SR0 displayed-workload self-job v4

v4 adds one pure parser shared by interactive execution & controls:
`receipt-parser-v4.ps1`. Parser reads bounded pinned receipt text, normalizes
CRLF, & returns separate `ownershipTerminal` / `qualificationPass` results.
Nonzero natural worker exit fails qualification yet still permits lock release
when every owned process is terminal, every stream drained, task is quiescent,
& job query proves current process is sole member. Missing terminal, missing
stream drain, or count mismatch holds lock.

Interactive source is `interactive-selfjob-v4.ps1`. It requires `-NoActivate`,
launches frozen direct task v8 inside reviewed v15 self-job, admits parser,
& records `PeakJobMemoryUsedBytes` from `QueryPeakJobMemory` before/after work.
It writes fresh `StartReceiptPath` before lock/native work with current PID,
path, start time, session, retained parent handle, & initial job-memory proof.
After terminal/drain/self-only proof & lock release, it disables its finished
scheduled task & records separate displayed-metrics status.
Pinned inputs:

- `qualification/tuple12-takeover/workload-controls-v8/task-workload.ps1`
- `factory/pipeline/pilot-next-source-v1/windows-capture-v1/Sr0OwnedJobProcess-v15.cs`
- `factory/pipeline/sr0-display-selfjob-v4/receipt-parser-v4.ps1`

Parser controls use actual archived v7/v8 receipt supplied by root, then run
same parser against baseline plus consistent natural-nonzero, inconsistent
identity, stream-drain, terminal, & count mutations. Controls write only under
`.factory-work`.

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v4"
$archive="$repo\probes\sr0-b\workload\out\tuple12-source-build-v1\observed-workload-r10-v7-r1\runs\result-workload.txt"
$out="$repo\.factory-work\sr0-display-selfjob-v4\parser-controls.json"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-receipt-parser-controls-v4.ps1" `
  -ParserPath "$src\receipt-parser-v4.ps1" -ArchivedReceipt $archive -OutputPath $out -Runs 3
```

Root refreshes source pins, then schedules v4 only after parser controls pass:

Use one run with `Warmup=10`, `Measure=60`, `Rows=200`, `KeyRate=10`, & mandatory `NoActivate`; hashes are refreshed from exact helper, frozen task, & parser paths below.

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v4"
$base="$repo\.work\sr0-r12-workload-v1";$out="$repo\.work\sr0-display-selfjob-v4"
$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-capture-v1\Sr0OwnedJobProcess-v15.cs"
$frozen="$repo\qualification\tuple12-takeover\workload-controls-v8\task-workload.ps1"
$parser="$src\receipt-parser-v4.ps1"
$helperSha=(Get-FileHash $helper -Algorithm SHA256).Hash.ToLowerInvariant();$frozenSha=(Get-FileHash $frozen -Algorithm SHA256).Hash.ToLowerInvariant();$parserSha=(Get-FileHash $parser -Algorithm SHA256).Hash.ToLowerInvariant()
$arg="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$src\interactive-selfjob-v4.ps1`" -Base `"$base`" -ControlRoot `"$repo\qualification\tuple12-takeover\workload-controls-v8`" -FrozenTaskPath `"$frozen`" -HelperPath `"$helper`" -ParserPath `"$parser`" -FrozenTaskSha256 $frozenSha -HelperSha256 $helperSha -ParserSha256 $parserSha -RunRoot `"$base\runs\sr0-display-selfjob-v4`" -ResultFile `"$out\result-workload.txt`" -MemoryReceiptPath `"$out\memory-receipt.json`" -StartReceiptPath `"$out\start-receipt.json`" -TaskName SR0-display-selfjob-v4 -Lock `"D:\Claude\desktop.lock`" -Tag sr0-display-selfjob-v4 -Runs 1 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate"
$action=New-ScheduledTaskAction -Execute powershell.exe -Argument $arg -WorkingDirectory $repo
$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 12) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName SR0-display-selfjob-v4 -Action $action -Principal $principal -Settings $settings -Force
Start-ScheduledTask -TaskName SR0-display-selfjob-v4
```

Envelope preflight is also bounded:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-envelope-controls-v4.ps1" `
  -SourcePath "$src\interactive-selfjob-v4.ps1" -FrozenTaskPath $frozen `
  -HelperPath $helper -ParserPath "$src\receipt-parser-v4.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\envelope-controls.json"
```

Displayed evidence is observed separately from workload qualification. Analyzer
reads only explicit PresentMon CSV & run meta JSON, streams CSV rows under 64 MiB
& 2,000,000-row caps, bounds meta at 2 MiB, joins `WorkloadWin.exe` + recorded PID + recorded QPC window, then
reports `rawPresentRows`, `displayedRows`, & `droppedRows`. It emits
`nativeConclusion=display-context-only; strict PresentMon displayed-row gate unchanged`
& never converts row counts or ratios into readiness.

Schema binding follows primary analyzer
`probes/sr0-b/workload/analysis/analyze_workload.py`:
PresentMon `Application`, `ProcessID`, `QPCTime` or `CPUStartQPC`, & `Dropped`;
meta `pid`, `run_id`, `measure_start_ticks`, `measure_end_ticks`, & `hz`.
Unknown display schemas reject before counting.

Collector source is `collector-selfjob-v4.ps1`, adapted from
`factory/pipeline/pilot-next-source-v1/windows-task-memory-v1/run-workload-memory-v1.ps1`:
PresentMon starts before direct workload inside same self-job, keeps original
child handles, drains stdout/stderr, proves terminal identity, & enforces its
unique session output caps before lock release.

Use archived run bindings below. Controls exercise same analyzer against actual
capture, all-dropped, header-only, missing-input, & wrong-PID cases; every output stays under
`.factory-work`.

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v4"
$runs="$repo\probes\sr0-b\workload\out\tuple12-source-build-v1\observed-workload-r10-v7-r1\runs"
$csv="$runs\presentmon.csv";$meta="$runs\r1\meta.json"
$out="$repo\.factory-work\sr0-display-selfjob-v4\display-controls-r1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-display-evidence-controls-v4.ps1" `
  -AnalyzerPath "$src\display-evidence-v4.ps1" -PresentMonCsv $csv -MetaPath $meta `
  -OutputPath "$out\controls.json"
```

For one direct observation, use same `$csv` & `$meta` with
`display-evidence-v4.ps1`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\display-evidence-v4.ps1" `
  -PresentMonCsv $csv -MetaPath $meta -OutputPath "$out\display.json"
```

Collector integration command starts PresentMon before frozen workload inside
same self-job. It retains both child handles, drains each stdout/stderr stream
under 8 MiB, polls CSV at 1 s under 64 MiB, enforces 900 s deadline, then
requires original terminal identities, workload ownership proof, & active-self
only before releasing shared lock. Collector waits for first nonempty CSV before
launching workload, records `presentMonStarted`, parent path/start UTC/session,
peak job memory, limit flags, & exact PresentMon SHA-256. PresentMon argv matches
`qualification/tuple12-takeover/workload-controls-v8/run-workload.ps1`.

Launcher controls are source-only & bounded. They verify exact 1 GiB outer
budget against launcher helper v4 & nested collector helper v15, TaskName/Tag binding, retained child handles,
kernel exit proof, bounded descendant wait, truthful active-self receipt, &
reject mutations that remove each lifecycle proof:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-launcher-controls-v4.ps1" `
  -WorkerPath "$src\run-once-v4.ps1" -SchedulePath "$src\schedule-once-v4.ps1" `
  -HelperPath "$helper" -LauncherHelperPath "$src\Sr0LauncherOwnedJobProcess-v4.cs" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\launcher-controls.json"
```

Root may run real helper controls after source controls pass. They create one
foreign pre-job child & one inherited owned child, prove foreign handle is
rejected, terminate owned child through membership revalidation, & require
active-self-only before disposal:

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v4"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-launcher-job-controls-v4.ps1" `
  -LauncherHelperPath "$src\Sr0LauncherOwnedJobProcess-v4.cs" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\launcher-job-controls.json"
```

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v4"
$base="$repo\.work\sr0-r12-workload-v1";$root="$repo\.work\sr0-display-selfjob-v4";$control="$repo\qualification\tuple12-takeover\workload-controls-v8"
$frozen="$control\task-workload.ps1";$helper="$repo\factory\pipeline\pilot-next-source-v1\windows-capture-v1\Sr0OwnedJobProcess-v15.cs";$parser="$src\receipt-parser-v4.ps1";$pm='D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe'
$fh=(Get-FileHash $frozen -Algorithm SHA256).Hash.ToLowerInvariant();$hh=(Get-FileHash $helper -Algorithm SHA256).Hash.ToLowerInvariant();$ph=(Get-FileHash $parser -Algorithm SHA256).Hash.ToLowerInvariant();$pmh=(Get-FileHash $pm -Algorithm SHA256).Hash.ToLowerInvariant()
$task='SR0-display-selfjob-v4';$run="$root\collector-run";$result="$run\result-workload.txt";$memory="$run\collector-receipt.json";$start="$run\start-receipt.json"
$arg="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$src\collector-selfjob-v4.ps1`" -Base `"$base`" -ControlRoot `"$control`" -FrozenTaskPath `"$frozen`" -HelperPath `"$helper`" -ParserPath `"$parser`" -FrozenTaskSha256 $fh -HelperSha256 $hh -ParserSha256 $ph -RunRoot `"$run`" -ResultFile `"$result`" -MemoryReceiptPath `"$memory`" -StartReceiptPath `"$start`" -TaskName $task -PresentMonExe `"$pm`" -PresentMonSha256 $pmh -Lock `"D:\Claude\desktop.lock`" -Tag $task -Runs 1 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -NoActivate"
$action=New-ScheduledTaskAction -Execute powershell.exe -Argument $arg -WorkingDirectory $repo;$principal=New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited;$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force;Start-ScheduledTask -TaskName $task
```

Expected fresh outputs under `$run`: `start-receipt.json`,
`collector-receipt.json`, `presentmon.csv`, workload `result-workload.txt`,
`presentmon.stdout.txt`, `presentmon.stderr.txt`, `presentmon-stop.*`,
`presentmon-query.*`, & workload stdout/stderr files. Root should require
`presentMonStarted=true`, `presentMonSessionAbsent=true`, signed/raw exit
identity, stream drain completion, `activeAfter=1`, `activeSelfOnly=true`,
`lockReleased=true`, & scheduler disabled before accepting display evidence.
Start & final receipts publish through fresh temporary files followed by atomic
`File.Move`, so coordinator never reads an in-progress JSON document.

Run collector source controls before scheduling:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-collector-envelope-controls-v4.ps1" `
  -SourcePath "$src\collector-selfjob-v4.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\collector-controls.json"
```

Coordinator source controls:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-coordinator-controls-v4.ps1" `
  -SourcePath "$src\coordinator-selfjob-v4.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\coordinator-controls.json"
```

## Collector v5 forced-owned stop successor

`collector-selfjob-v5.ps1` preserves v4 cleanup gates & adds bounded raw PM
evidence. It records `presentMonStopMode` as `natural` or explicit
`forced-owned`; forced `-1` is accepted only after retained-handle native
raw/signed/.NET equality, explicit kill attempt after workload exit, stop exit
`0`, session absence, exact benign stderr
`warning: ignoring --write_display_metadata due to --v1_metrics.`, bounded CSV
hash/header/row evidence, drained streams, no timeout/output fault, workload
exit `0`, & active self-only proof. Any other stderr, exit, stop, session, CSV,
stream, or ownership condition stays held/failed.

Valid capture emits `status=qualification-held`, `captureComplete=true`, &
`qualificationHoldReason=strict-display-parser-pending`; strict displayed-row
analysis remains separate. Run source controls before staging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-collector-forced-stop-controls-v1.ps1" `
  -SourcePath "$src\collector-selfjob-v5.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\collector-v5-forced-stop-controls.json"
```

Pair collector v5 with `coordinator-selfjob-v5.ps1`; it requires final
collector kind v5, validated PM stop/CSV/stderr evidence, retained parent
certificate, & explicit display qualification hold. Its source control is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-coordinator-forced-stop-controls-v1.ps1" `
  -SourcePath "$src\coordinator-selfjob-v5.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\coordinator-v5-forced-stop-controls.json"
```

Root staging must refresh SHA-256 pins for `collector-selfjob-v5.ps1`,
`coordinator-selfjob-v5.ps1`, `run-once-v5.ps1`, `schedule-once-v5.ps1`,
`launch-once-v5.vbs`, helper, parser, frozen task, PM, WorkloadWin, & renderer.
Launch v5 worker/wrapper with v5 scheduler, retaining `Runs 1`, `Warmup 10`,
`Measure 60`, `Rows 200`, `KeyRate 10`, `NoActivate`, `NoResources`, 900s/1s,
1GiB `0x200`, & fresh run-root receipts. Require coordinator `status=passed`
only as capture admission; `qualification-held` remains pending strict display
parser output.

Receipt-fault controls execute only held fake-receipt cases:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-coordinator-receipt-controls-v4.ps1" `
  -CoordinatorPath "$src\coordinator-selfjob-v4.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\coordinator-receipt-controls.json"
```

Positive coordinator controls launch owned headless child fixtures with natural exit 0 & 17;
coordinator retains each original kernel handle, waits terminal, & verifies raw/signed/.NET exit identity:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-coordinator-positive-controls-v4.ps1" `
  -CoordinatorPath "$src\coordinator-selfjob-v4.ps1" `
  -ChildPath "$src\coordinator-child-fixture-v4.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\coordinator-positive-controls.json"
```

One-shot diagnostic scheduling uses `wscript.exe` in hidden batch mode, an
interactive Highest principal, & one fresh task. Worker starts coordinator
before collector inside exact 1 GiB outer job matching helper v15, retains both child handles, &
publishes `launcher-receipt.json`; task execution limit is 20 minutes for 900 s
collector work plus bounded cleanup. Coordinator starts before collector;
collector acquires CAS, owns 1GiB job, runs direct WorkloadWin with
`NoActivate` + `NoResources`, & disables only completed task:

```powershell
$exe='D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe'
$renderer='<exact renderer path from build.json>'
$pm='D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe'
$worker="$src\run-once-v4.ps1";$launcherHelper="$src\Sr0LauncherOwnedJobProcess-v4.cs";$collector="$src\collector-selfjob-v4.ps1";$coordinator="$src\coordinator-selfjob-v4.ps1";$wrapper="$src\launch-once-v4.vbs"
$fh=(Get-FileHash $frozen -Algorithm SHA256).Hash.ToLowerInvariant();$hh=(Get-FileHash $helper -Algorithm SHA256).Hash.ToLowerInvariant();$ph=(Get-FileHash $parser -Algorithm SHA256).Hash.ToLowerInvariant();$lh=(Get-FileHash $launcherHelper -Algorithm SHA256).Hash.ToLowerInvariant();$wh=(Get-FileHash $worker -Algorithm SHA256).Hash.ToLowerInvariant();$ch=(Get-FileHash $collector -Algorithm SHA256).Hash.ToLowerInvariant();$coh=(Get-FileHash $coordinator -Algorithm SHA256).Hash.ToLowerInvariant();$wsh=(Get-FileHash $wrapper -Algorithm SHA256).Hash.ToLowerInvariant();$eh=(Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant();$rh=(Get-FileHash $renderer -Algorithm SHA256).Hash.ToLowerInvariant();$pmh=(Get-FileHash $pm -Algorithm SHA256).Hash.ToLowerInvariant()
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\schedule-once-v4.ps1" `
  -WorkerPath $worker -LauncherHelperPath $launcherHelper -CollectorPath $collector -CoordinatorPath $coordinator -WrapperPath $wrapper `
  -ManifestPath "$root\one-shot-manifest.json" -Base $base -ControlRoot $control `
  -FrozenTaskPath $frozen -HelperPath $helper -ParserPath $parser -WorkloadExe $exe `
  -RendererDll $renderer -PresentMonExe $pm -FrozenTaskSha256 $fh -HelperSha256 $hh `
  -ParserSha256 $ph -LauncherHelperSha256 $lh -WorkerSha256 $wh -CollectorSha256 $ch -CoordinatorSha256 $coh -WrapperSha256 $wsh `
  -WorkloadExeSha256 $eh -RendererDllSha256 $rh -PresentMonSha256 $pmh `
  -TaskName 'SR0-display-selfjob-v4-diagnostic' -RunRoot "$root\one-shot-run" `
  -LockPath 'D:\Claude\desktop.lock'
```

Archived analyzer fixture is explicitly bound to
`probes\sr0-b\workload\out\tuple12-source-build-v1\observed-workload-r10-v7-r1\runs\presentmon.csv`
& its `r1\meta.json`; root should confirm CSV <=64 MiB, meta <=2 MiB before use.

Fresh root-owned one-run plan & observer:

```powershell
$repo='D:\Claude\swiftright';$src="$repo\factory\pipeline\sr0-display-selfjob-v4";$renderer='<exact renderer path from build.json>'
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\prepare-fresh-one-run-v4.ps1" -Repo $repo -RendererDll $renderer -OutputPath "$repo\factory\.factory-work\sr0-display-selfjob-v4\fresh-one-run-config.json"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\observe-fresh-one-run-v4.ps1" -PlanPath "$repo\factory\.factory-work\sr0-display-selfjob-v4\fresh-one-run-config.json" -OutputPath "$repo\factory\.factory-work\sr0-display-selfjob-v4\fresh-one-run-observer.json" -DeadlineSeconds 1100
```

Observer invokes `schedule-once-v4.ps1` with every plan pin, matches worker command line by exact manifest & worker paths, acquires `Process.Handle` while worker is alive, joins kernel raw/signed/.NET exit values, requires launcher aggregate active-self proof, & accepts only non-running scheduler state. It never writes desktop CAS or stops processes.

Observer source controls reject positional schedule arguments, missing worker
handle/start/session/exit joins, omitted queued-state grace, & unsafe cleanup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-observer-controls-v4.ps1" `
  -SourcePath "$src\observe-fresh-one-run-v4.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\observer-controls.json"
```

Observer r2 source packet is `observer-source-r2.ps1` with `test-observer-source-controls-r2.ps1`. Root transport memory-failure controls are `root-transport-job-v1/test-memory-failure-controls-v1.ps1`; outer 1GiB launcher memory-failure controls are `test-launcher-memory-failure-controls-v1.ps1`. Both preserve raw active/peak cleanup evidence & hold over-cap receipts.

## v5 capture-complete hold & frozen display parser

`run-once-v5.ps1`, `schedule-once-v5.ps1`, `launch-once-v5.vbs`,
`collector-selfjob-v5.ps1`, & `coordinator-selfjob-v5.ps1` are prospective
copies. They accept `sr0-display-collector-v5` with
`status=qualification-held`, `captureComplete=true`, & explicit
`strict-display-parser-pending`; they never convert that hold into parity or
display qualification. Refresh every source hash before staging.

Before staging v5 worker/scheduler, run wrapper source controls:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-v5-wrapper-controls-v1.ps1" `
  -WorkerPath "$src\run-once-v5.ps1" -SchedulePath "$src\schedule-once-v5.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\v5-wrapper-controls.json"
```

For one captured run, first bind CSV rows to original WorkloadWin PID with
`display-parser-adapter-v1.ps1`. It streams CSV with 64 MiB/1,000,000-row
bounds, requires exact PresentMon 2.6 columns, rejects invalid PID/QPC/time or
`Dropped`, records CSV hash/bytes & candidate displayed rows, then writes only
`status=qualification-held` plus exact frozen parser command. It does not run
Python or claim qualification:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\display-parser-adapter-v1.ps1" `
  -CsvPath "$run\presentmon.csv" -ResultPath "$run\result-workload.txt" `
  -AnalyzerPath "$repo\qualification\tuple12-takeover\workload-analysis-v3\analyze_workload.py" `
  -RunRoot $run -AnalyzerOutRoot "$run\strict-report" -OutputPath "$run\display-adapter.json" `
  -WorkloadPid <original-WorkloadWin-PID> -RunId r1 -ExpectedRuns 1 -ExpectedScale 2.5
```

Run frozen strict analysis only after adapter receipt is held:

```powershell
py -3 "$repo\qualification\tuple12-takeover\workload-analysis-v3\analyze_workload.py" `
  --os windows --root "$run" --out "$run\strict-report" --expect-runs 1 --expect-scale 2.5
```

Frozen parser joins `Application=WorkloadWin.exe`, original PID from
`result-workload.txt`, & `CPUStartQPC` or `QPCTime`; displayed rows remain
`Dropped=0` under frozen analyzer rules. `display-parser-adapter-v1.ps1` source
controls cover PID binding, exact header, bounds, hold status, parser command,
& no-parity claim:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-display-parser-adapter-controls-v1.ps1" `
  -SourcePath "$src\display-parser-adapter-v1.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\display-parser-adapter-controls.json"
```

Actual collector v5 keeps PM stdout/stderr separate & retains `pid_exit
handle=<n>` in raw `result-workload.txt`; frozen v3 parser expects joined
`presentmon.console.txt` & its legacy pid-exit shape. Use
`materialize-analysis-inputs-v1.ps1` to write only fresh derived files, with
raw byte/hash receipts. Then use local analyzer copy
`analyze_workload-v3-adapter-v1.py`; copy changes only optional `pid_exit`
handle parsing & explicit `--result-path`/`--console-path`, preserving every
threshold & frozen display rule:

```powershell
$derived="$run\analysis-derived"
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\materialize-analysis-inputs-v1.ps1" `
  -RawResultPath "$run\result-workload.txt" `
  -PresentMonStdoutPath "$run\presentmon.stdout.txt" -PresentMonStderrPath "$run\presentmon.stderr.txt" `
  -OutputRoot $derived -OutputPath "$derived\materialize-receipt.json"
py -3 "$src\analyze_workload-v3-adapter-v1.py" --os windows --root "$run" `
  --result-path "$derived\result-workload.adapter.txt" `
  --console-path "$derived\presentmon.console.adapter.txt" `
  --out "$run\strict-report" --expect-runs 1 --expect-scale 2.5
```

Materializer controls require bounded sealed inputs, raw hashes, handle
normalization, derived console paths, `rawPreserved=true`, & no parity claim:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-materialize-analysis-inputs-controls-v1.ps1" `
  -SourcePath "$src\materialize-analysis-inputs-v1.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\materialize-controls.json"
```

Prospective v5 observer matches worker mode switches independent of switch order,
retains original worker handle, & admits only `sr0-display-launcher-v5` receipts.
Run source controls before staging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-observer-source-v5-controls-r1.ps1" `
  -SourcePath "$src\observer-source-v5-r1.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\observer-v5-controls.json"
```

Forced-owned PresentMon pure controls reject wrong raw exit, stdio, missing CSV,
target PID, stop exit, & present session:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$src\test-forced-stop-admission-v5.ps1" `
  -CollectorPath "$src\collector-selfjob-v5.ps1" `
  -OutputPath "$repo\.factory-work\sr0-display-selfjob-v4\forced-stop-admission-controls.json"
```
