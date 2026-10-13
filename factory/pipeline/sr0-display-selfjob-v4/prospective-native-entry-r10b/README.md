# SR0 staged controls & native entry r10b

These wrappers run against admitted `v5-root-r10` stage. Controls entry reruns staged production preflight, verifies exact `one-run-plan-r8.json` SHA-256, invokes staged r10 controls, & writes fresh receipt plus gate. Native entry reruns same preflight, verifies exact plan & controls-receipt SHA-256, then invokes `schedule-once-v7.ps1` with every plan path/pin. Native entry is root-owned; it creates scheduled task & starts one diagnostic run. No qualification claim is emitted.

Use exact plan SHA from `source-pins-r8.json`; use exact controls SHA from controls receipt or controls gate. Keep both values literal in root command history.

```powershell
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r10'
$plan=Join-Path $stage 'one-run-plan-r8.json'
$p=Get-Content -LiteralPath $plan -Raw | ConvertFrom-Json
$planSha=(Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash.ToLowerInvariant()
$preflight='D:\Claude\swiftright\.factory-work\root-tools\source-root-r10\factory\pipeline\sr0-display-selfjob-v4\prospective-native-stage-v1\entry-native-r8.ps1'
$preflightSha=(Get-FileHash -LiteralPath $preflight -Algorithm SHA256).Hash.ToLowerInvariant()
& .\factory\pipeline\sr0-display-selfjob-v4\prospective-native-entry-r10b\invoke-staged-controls-r10b.ps1 `
  -StageRoot $stage -PlanPath $plan -ExpectedPlanSha256 $planSha `
  -PreflightPath $preflight -ExpectedPreflightSha256 $preflightSha `
  -OutputPath (Join-Path $p.factoryRoot 'drain-controls-r10.json') `
  -GateReceiptPath (Join-Path $p.factoryRoot 'staged-controls-gate-r10b.json')
$controlsSha=(Get-FileHash -LiteralPath (Join-Path $p.factoryRoot 'drain-controls-r10.json') -Algorithm SHA256).Hash.ToLowerInvariant()
& .\factory\pipeline\sr0-display-selfjob-v4\prospective-native-entry-r10b\invoke-staged-native-r10b.ps1 `
  -StageRoot $stage -PlanPath $plan -ExpectedPlanSha256 $planSha `
  -PreflightPath $preflight -ExpectedPreflightSha256 $preflightSha `
  -ControlsReceiptPath (Join-Path $p.factoryRoot 'drain-controls-r10.json') `
  -ExpectedControlsReceiptSha256 $controlsSha `
  -ScheduleReceiptPath (Join-Path $p.factoryRoot 'native-schedule-gate-r10b.json') -Rows 200 -KeyRate 10
```

`invoke-staged-controls-r10b.ps1` is source-control only. `invoke-staged-native-r10b.ps1` is separate native scheduling entry; run it only after reviewing fresh control receipt, while root holds existing desktop ownership protocol. Both wrappers bound JSON reads at 2 MiB, reject reparse paths, require plan memory 1 GiB, deadline 900 s, poll 1 s, `NoActivate`, `NoResources`, `nativeActions=0`, & `qualificationClaim=false` before scheduling.

For retained scheduled-parent evidence, use observer instead of direct scheduling entry. It admits root transport helper before schedule child, acquires original schedule handle immediately, drains child streams at 8 MiB each, waits launcher/collector lock-release proof, checks scheduler terminal state, & emits `nativeQualificationClaim=false`.

Observer also requires coordinator `passed` status with matching `taskName`, `parentCertificatePresent`, `parentKernelTerminal`, & `lockOwnerObserved`; scheduled-task absence counts terminal only after those receipts pass. Cleanup records transport descendants & remains held without self-only proof.

```powershell
$transport='D:\Claude\swiftright\factory\pipeline\sr0-display-selfjob-v4\root-transport-job-v1\Sr0RootTransportJobV1.cs'
$transportSha=(Get-FileHash -LiteralPath $transport -Algorithm SHA256).Hash.ToLowerInvariant()
& .\factory\pipeline\sr0-display-selfjob-v4\prospective-native-entry-r10b\observe-staged-native-r10b.ps1 `
  -StageRoot $stage -PlanPath $plan -ExpectedPlanSha256 $planSha `
  -PreflightPath $preflight -ExpectedPreflightSha256 $preflightSha `
  -ControlsReceiptPath (Join-Path $p.factoryRoot 'drain-controls-r10.json') `
  -ExpectedControlsReceiptSha256 $controlsSha -TransportHelperPath $transport `
  -TransportHelperSha256 $transportSha `
  -OutputPath (Join-Path $p.factoryRoot 'native-observer-r10b.json')
```
