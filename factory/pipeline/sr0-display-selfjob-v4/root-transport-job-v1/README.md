# SR0 root transport job v1

This packet gives root-side PowerShell transport one owned current-process Job Object before it reads or launches pinned workload code. `Sr0RootTransportJobV1` admits exactly 256 MiB with `JOB_OBJECT_LIMIT_JOB_MEMORY` (`0x200`) and deliberately omits `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` (`0x2000`). It proves initial/final active count, memory limit/peak, kernel terminal state, signed raw exit, .NET exit, bounded child cleanup, membership revalidation, and self-only quiescence. Raw over-cap snapshots remain available for held failure receipts; `RequireMemoryOnly` still rejects over-cap qualification.

`run-root-transport-job-v1.ps1` bounds helper/script files at 2 MiB, rejects reparse points, verifies helper SHA-256 before `Add-Type`, verifies script SHA-256 before child start, admits current process, then starts only explicit pinned PowerShell script. It retains child handle immediately, redirects stdout/stderr into independent 4 KiB bounded drains capped at 8 MiB each, terminates on cap/deadline, waits for terminal & stream completion, closes stream handles before hashing, and publishes stream hashes/bytes plus one scalar failure message in one fresh receipt. Wrong helper/script hashes publish held receipts without loading helper type.

Root invocation from repository root (PowerShell 5.1):

```powershell
$repo='D:\Claude\swiftright'
$dir=Join-Path $repo 'factory\pipeline\sr0-display-selfjob-v4\root-transport-job-v1'
$work=Join-Path $repo '.work\sr0-root-transport-v1'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$helper=Join-Path $dir 'Sr0RootTransportJobV1.cs'
$runner=Join-Path $dir 'run-root-transport-job-v1.ps1'
$helperSha=(Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
$runnerSha=(Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash
$target=Join-Path $repo 'factory\pipeline\sr0-display-selfjob-v4\run-once-v4.ps1'
$targetSha=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'test-root-transport-controls-v1.ps1') -RootPath $dir -OutputPath (Join-Path $work 'controls.json')
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'test-root-transport-stream-controls-v1.ps1') -WrapperPath $runner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -HelperPath $helper -HelperSha256 $helperSha -ScriptPath $target -ScriptSha256 $targetSha -OutputPath (Join-Path $work 'transport.json') -DeadlineSeconds 45
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'run-root-transport-runtime-controls-v1.ps1') -RootPath $dir -HelperSha256 $helperSha -WrapperSha256 $runnerSha -OutputPath (Join-Path $work 'runtime-controls.json')
```

Runtime controls launch real pinned PowerShell children: exit-zero/self-only with sealed stream hashes, timeout with descendant termination, foreign sentinel survival, deterministic >8 MiB output cap with post-terminal drain/hash, wrong helper hash, and wrong script hash with no child. Runner must be given exact immutable script hash, output paths must be fresh, and caller must retain resulting receipts with source pins. Controls are source-only until root runs them; this packet has not executed them.

Over-cap source controls:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'test-memory-failure-controls-v1.ps1') -HelperSourcePath $helper -WrapperSourcePath $runner -OutputPath (Join-Path $work 'memory-failure-controls.json')
```
