# SR0 fresh native stage r8

`stage-prospective-native-r8.ps1` copies explicit, bounded, non-reparse inputs into fresh `v5-root-r8`; it writes `one-run-plan-r8.json` & `source-pins-r8.json`. `entry-native-r8.ps1` only verifies pins, byte counts & hashes. `run-source-controls-r8.ps1` is separate root-invoked control entry; it calls staged `test-workload-drain-controls-r10.ps1` with exact pinned production drain helper. Stager & preflight create no tasks/processes, touch no desktop lock, & make no eligibility claim; controls start only bounded fixture children when explicitly invoked.

Root Windows invocation:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-v4\prospective-native-stage-v1\stage-prospective-native-r8.ps1
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\factory\pipeline\sr0-display-selfjob-v4\prospective-native-stage-v1\entry-native-r8.ps1 -StageRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r8
```

After preflight, root must run source controls & obtain fresh `drain-controls-r10.json` before invoking `schedule-once-v7.ps1` with every path & pin from plan. Worker admission rejects missing or failed control receipt. Scheduling/native execution remains root-owned. `run-once-v7.ps1` passes `DrainTaskPath`, `DrainTaskSha256`, `DrainHelperPath`, `DrainHelperSha256`, `IdentityHelperPath`, & `IdentityHelperSha256` into v5-r6-integration collector. Strict display analysis remains separate.


Root source-control invocation after reviewing preflight (must precede scheduling):

```powershell
$p=Get-Content -LiteralPath 'D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r8\one-run-plan-r8.json' -Raw | ConvertFrom-Json
& (Join-Path $p.stageRoot 'run-source-controls-r8.ps1') -StageRoot $p.stageRoot -PlanPath (Join-Path $p.stageRoot 'one-run-plan-r8.json') -OutputPath (Join-Path $p.factoryRoot 'drain-controls-r10.json')
```

Root-only schedule command after source receipt (this creates scheduled task & starts native work):

```powershell
$p=Get-Content -LiteralPath 'D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r8\one-run-plan-r8.json' -Raw | ConvertFrom-Json
& $p.schedulePath -WorkerPath $p.workerPath -LauncherHelperPath $p.launcherHelperPath -CollectorPath $p.collectorPath -CoordinatorPath $p.coordinatorPath -WrapperPath $p.wrapperPath -ManifestPath $p.manifestPath -Base $p.base -ControlRoot $p.controlRoot -ControlReceiptRoot $p.controlReceiptRoot -RequiredControlReceipts $p.requiredControlReceipts -FrozenTaskPath $p.frozenTaskPath -DrainTaskPath $p.drainTaskPath -HelperPath $p.helperPath -DrainHelperPath $p.drainHelperPath -ParserPath $p.parserPath -IdentityHelperPath $p.identityHelperPath -WorkloadExe $p.workloadExe -RendererDll $p.rendererDll -PresentMonExe $p.presentMonExe -FrozenTaskSha256 $p.sourcePins.frozenTask -DrainTaskSha256 $p.sourcePins.drainTask -HelperSha256 $p.sourcePins.helper -DrainHelperSha256 $p.sourcePins.drainHelper -ParserSha256 $p.sourcePins.parser -IdentityHelperSha256 $p.sourcePins.identityHelper -WorkerSha256 $p.sourcePins.worker -LauncherHelperSha256 $p.sourcePins.launcherHelper -CollectorSha256 $p.sourcePins.collector -CoordinatorSha256 $p.sourcePins.coordinator -WrapperSha256 $p.sourcePins.wrapper -WorkloadExeSha256 $p.sourcePins.workloadExe -RendererDllSha256 $p.sourcePins.rendererDll -PresentMonSha256 $p.sourcePins.presentMonExe -TaskName $p.taskName -Tag $p.tag -RunRoot $p.runRoot -LockPath $p.lockPath -Warmup $p.warmup -Measure $p.measure -Rows 200 -KeyRate 10
```


