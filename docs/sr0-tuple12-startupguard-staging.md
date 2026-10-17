# Tuple12 StartupGuard source staging

Current overlay is r2, recorded in [`qualification/tuple12-startupguard-overlay-r2.json`](../qualification/tuple12-startupguard-overlay-r2.json), SHA256 `0d537b83d0bc761f1f78fee738b15199846fbb94125a4708aaf8ae9f0fcbb27a`. The r1 overlay (`qualification/tuple12-startupguard-overlay.json`, `c7d4ecaa…`) is superseded; see the r4 build addendum.

Base remains pinned source commit `0e201571e4320a3b6ccce14313fd2ad67e523904`; historical recorder, tuple11 receipts, & pinned source are immutable. Overlay r2 (`0d537b83…`) consists of `Fixture.swift`, `main.swift`, new `StartupGuard.swift`, & `drive-fixture.ps1`, each bound by current bytes plus base hashes where applicable.

Source-only wrapper: `probes/sr0-s/fresh-on-bridge/scripts/stage-tuple12-startupguard.ps1`, SHA256 `e84491fab439cd5d7b94ec77667676a6cda9281737342efd6cf296f2ed0f3b74`. It requires a clean base clone at pinned commit, verifies overlay manifest bytes/hash, verifies each base/current file hash, rejects path traversal & existing candidate roots, clones locally into a fresh candidate namespace, applies only four listed files, verifies copied bytes, & emits candidate manifest. It performs no remote build, GUI, runner, signing, deletion, or historical-stage reuse. Renderer path/hash & recovery receipt are mandatory inputs; recovered DLL is now admitted at SHA-256 `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2` (11,887,616 bytes), with source-bound fixture build r4 passing (`exitCode: 0`, FreshOnBridge `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`); fresh canonical stage & qualification remain pending.

Root run shape after exact DLL admission (all paths on Dell):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stage-tuple12-startupguard.ps1 `
  -BaseSource D:\Claude\swiftright\.work\sr0-r12\src `
  -OverlaySource D:\Claude\swiftright `
  -OverlayManifest D:\Claude\swiftright\qualification\tuple12-startupguard-overlay-r2.json `
  -ExpectedOverlaySha256 0d537b83d0bc761f1f78fee738b15199846fbb94125a4708aaf8ae9f0fcbb27a `
  -CandidateSource D:\Claude\swiftright\.work\sr0-r12-startupguard\src `
  -RendererDll D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll `
  -ExpectedRendererSha256 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 `
  -RendererReceipt D:\Claude\swiftright\probes\sr0-s\fresh-on-bridge\out\tuple12-renderer-recovery-v1\seal-managed-renderer-r3.stdout.bin
```

After `SOURCE_CANDIDATE_OK`, root records candidate source/tree hash and does not commit the overlay; it invokes existing frozen `stage-tuple.ps1` at canonical stage commit `a9556b77f50315afcae27fc8fc44c0cd274959e2` (base `0e201571` + overlay r2 `0d537b83…`, source manifest `f45b9e0d…`) with its reviewed no-delete override. Existing frozen stage paths remain unchanged; candidate matrix is a fresh namespace. Windows parser/typecheck, renderer closure admission, then 20-per-side compare remain held for root.

No historical artifact or producer path is changed by this staging record.
