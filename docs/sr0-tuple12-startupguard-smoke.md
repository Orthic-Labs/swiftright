# Tuple 12 StartupGuard smoke

Windows r4 source-bound compile passed, and actual background smoke r3 passed with native 17/17, driver/child exit 0, exact EXE/DLL hashes, & lock free. Evidence: `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-matrix-smoke-r3` plus `matrix-smoke-actual-r3-root-review.json`. Fresh F1×20 is running; this smoke does not qualify matrix, native, package or 20-per-side compare. Overlay r1 and worker-v1 are superseded by overlay r3 and matrix worker-v2 documented in `docs/sr0-tuple12-startupguard-matrix.md`.

Required pins before launch:

- StartupGuard source SHA-256 `05f2f684da848e9c362fb27578c38cbce252f46e5141c0044fa64825f4415e17`; overlay manifest `qualification/tuple12-startupguard-overlay-r2.json` SHA-256 `0d537b83d0bc761f1f78fee738b15199846fbb94125a4708aaf8ae9f0fcbb27a`.
- Renderer DLL SHA-256 `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`; bytes `11887616`.
- FreshOnBridge SHA-256 `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`; 4,758,016 bytes; r4 source manifest `f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca` verifies 91 files.

Root must first verify r4 receipt `exitCode: 0`, retained compiler-handle evidence, executable bytes, renderer bytes, internal-disk canonical paths, no owned build process, & `D:\Claude\desktop.lock` ownership. Candidate stage must contain both DLL & EXE in same release bin; no copy may overwrite existing files. Create unique `SMOKE_OUT`; never remove or reuse prior output. Run from interactive Dell session:

```powershell
$base = 'D:\Claude\swiftright\.work\sr0-r12-typecheck\src' # root substitutes fresh admitted candidate stage after copying DLL
$bin = Join-Path $base 'scratch\out\Products\Release-windows-x86_64'
$exe = Join-Path $bin 'FreshOnBridge.exe'
$dll = Join-Path $bin 'swiftright_render.dll'
$smokeRoot = 'D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1'
$smoke = Join-Path $smokeRoot ('F1-r1-' + [guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $smoke) { throw 'smoke namespace already exists' }
[IO.Directory]::CreateDirectory($smokeRoot) | Out-Null
if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant() -cne '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2') { throw 'renderer hash mismatch' }
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'FreshOnBridge missing' }
$exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($exeHash -cne '87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374') { throw 'FreshOnBridge hash mismatch' }
if (Test-Path -LiteralPath ($smoke + '.driver.txt')) { throw 'driver receipt path already exists' }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'probes\sr0-s\fresh-on-bridge\scripts\tuple12-startupguard-smoke-v1\drive-fixture-noactivate-focus-r3.ps1') `
  -Base $base -Fixture F1 -Variant '' -Out $smoke -KeyMode char -NoActivate `
  *> ($smoke + '.driver.txt')
if ($LASTEXITCODE -ne 0) { throw "driver exit $LASTEXITCODE" }
```

Admission is fail-closed. Root records exact `$exeHash`, DLL hash/bytes, candidate source manifest hash, driver stdout/stderr hash, process exit code, & fresh paths. Driver output must contain `exit=0`, `renderer_ready_event=True`, `record=renderer-ready`, `phase=first-ready`, `source=Bridge.onReady`, positive `width_px`, `height_px`, `scale`, matching owner PID, & nonzero `bridge_window`; `SR0_RENDERER_READY file=created` must be present in captured native stdout. It must also contain startup `WindowMetrics`, `client_ok=True`, positive client dimensions, matching PID, & `same_process=True`. Driver-close-ready metrics are a separate later event and cannot substitute for first-ready telemetry. The final target guard must report `same_hwnd=True`, `same_process=True`, `same_handle=True` before close; any mismatch, missing marker, stale output, unexpected native stderr without checked exit code, or renderer hash drift rejects run.

This smoke is background-capable only through candidate `-NoActivate`; input remains targeted UIA/window messages. Root must keep desktop lock for launch through close, use no global key delivery, preserve all output, then release lock in `finally`. A passing smoke is a prerequisite for matrix preflight, not matrix evidence.

## F1 lifecycle checks

`SR0_NOACTIVATE guard=installed` must precede `SR0_RENDERER_READY`; source installs the thread CBT hook before `bridge.run` & defers removal until `run` returns. F1 calls `Focus-Edit Row 5`, posts targeted `a`, `b`, `c`, waits for `Row 5abc`, posts `d`, waits for `Row 5abcd`, waits for self-test ready-file, then records driver-close-ready metrics, posts `WM_CLOSE`, waits up to 90 seconds, & records process exit. Retained process handle is captured immediately after `Start-Process -PassThru`, before wait.

Bridge startup telemetry should satisfy `width_px = round(640 * scale)` & `height_px = round(480 * scale)` for `Bridge.run(width: 640, height: 480)`; exact physical pixels follow Dell DPI. Driver startup `GetClientRect` must be positive & agree with renderer metrics after DPI rounding. `active` may remain false under no-activate; it is recorded, not promoted to PASS. For noactivate overlay r3, UIA provider `HasKeyboardFocus=False` & desktop-global focus absence are expected; require `setfocus_attempt[Row 5]=0 noactivate=True`, `focus[Row 5]=NOT_CONFIRMED provider=HasKeyboardFocus`, native `SELFTEST F1: PASS (17/17`, `ASSERT F1 focus-stays-row5: PASS`, `ASSERT F1 row5-text: PASS`, `ASSERT F1 ax-focus-delivered: PASS`, all F1 assertions PASS, `driver_abort=none`, `driver_close_ready_file=True`, `close_window=WM_CLOSE posted=True`, `exit=0`, & final same-HWND/process/handle fields. HCBT_SETFOCUS veto can expose UIA focus incompatibility; a failed focus check rejects smoke without weakening no-activate guard. The first F1 candidate failed before UIA `SetFocus`: `Ensure-Foreground` was vetoed by noactivate, with `focus[Row 5]=not_foreground`; receipt `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-actual-r1/receipts/worker-98c8c43c1f4247d6aab779b5a3fd5330.json` records driver `0`, child `1`.

## Candidate noactivate focus overlay

Historical r1 overlay remains preserved. Current candidate is `probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r3.ps1`, SHA-256 `ec5e9ce17a9a3f1088ad15f08a15c1c32b7d9af0d45f091a66404d6ab5ef0780`; manifest `qualification/tuple12-startupguard-focus-overlay-r3.json`. Under `-NoActivate`, it skips only driver `Ensure-Foreground`, retains target identity checks & renderer CBT activation/focus veto, logs each UIA `$el.SetFocus()` attempt, then reads `AutomationElementIdentifiers.HasKeyboardFocusProperty` from target provider. Provider false is expected while native AX logical focus assertions pass; default branch remains unchanged. Use matrix worker-v2 admission from `docs/sr0-tuple12-startupguard-matrix.md`.

## Root-run worker/coordinator (matrix v2)

Source-only wrappers are pinned at `probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-matrix-v1/worker.ps1` SHA-256 `a71a960b9db01f05a9d97c2956b86fc6eba7474bb13304577f10887cd7aa9fe9` & `coordinator.ps1` SHA-256 `8e45f2d39a1be1d38056dcf54700d07105484852e9c0708c2261b3d414770152`. Worker launches reviewed r3 driver with `SR0S_DELIVERY=targeted`, `-NoActivate`, `-KeyMode char`, requires `fg_changes=0`, records raw streams & all fresh outputs, retains driver/renderer handles, proves terminal state with `WaitForSingleObject` & `GetExitCodeProcess`, then requires numeric zero exits & exact trace fields. Coordinator acquires `D:\Claude\desktop.lock` as exact `<owner> <timestamp>` CAS, launches one hidden interactive `wscript.exe` task, emits terminal JSON with task/receipt/runRoot/lock state, releases lock after kernel-terminal/quiescent proof even when semantic F1 checks fail, & retains lock when terminal proof is absent; it disables task without unregister/delete. Receipt & launcher writes use `CreateNew`.

Root-run command after exact EXE/DLL/source admission:

```powershell
$base = 'D:\Claude\swiftright\.work\sr0-r12-typecheck\src'
$script = Join-Path $base 'probes\sr0-s\fresh-on-bridge\scripts\tuple12-startupguard-matrix-v1'
$out = 'D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-startupguard-smoke-v1\observed-matrix-smoke-r3-next'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script 'coordinator.ps1') `
  -Base $base -Worker (Join-Path $script 'worker.ps1') `
  -Driver (Join-Path $base 'probes\sr0-s\fresh-on-bridge\scripts\tuple12-startupguard-smoke-v1\drive-fixture-noactivate-focus-r3.ps1') `
  -ExpectExe '87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374' `
  -ExpectDll '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2' -OutRoot $out
```

## r4 source overlay hold

F1×20-r2 run4 recorded only initialization transition `fg_change ... from=0 to=395622` (`Claude`); targeted `fg_before`/`fg_after` stayed equal, provider focus remained false under CBT veto, `driver_abort=none`, & native F1 was 17/17. Frozen r3 is preserved. Candidate r4 seeds `lastFg` from current foreground after renderer-ready metrics validation, before first targeted sample, while retaining later transition logging, targeted no-acquire behavior, global Ensure-Foreground abort, & all native gates.

Driver r4 SHA-256 `34d28b1f4cc6a4fccb279639ae767c069a40ae081290ef2b11aebafd52b441b4`; overlay SHA-256 `e94ffe94a9d35e5ca64e8ee75ffb796e94ff808a6a8c90a818e7222a4a05670b`; pure controls SHA-256 `19b1faba69487f6d661be655ff7532ca0dbd16fe4b266412e3a2cf428e95d4d5` (positive 12, three mutation rejections). Root reruns fresh F1×20 only after parser/source controls; r2 archive remains immutable.

## r3 actual startup failure

Fresh r3 failed before semantic execution: ready marker passed, but startup WindowMetrics had `pid=0`, `client_ok=False`, `window_ok=False`, `same_process=False`; UIA root was unavailable, Row5 AX focus wait timed out, child exit `1`, driver exit `0`. Candidate r5 revalidates current HWND ownership/client rect after ready marker & fails closed before UIA/input. Driver `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`; overlay `72932060449ea82d9ff04b2c04dc21a5dcef1c48016cf32454ba9de401774fb6`; controls `d2223b6d43e62d98fc4020f7100b1afcfbbf4d6c1e4381d4009bda8e73d8422e`.
