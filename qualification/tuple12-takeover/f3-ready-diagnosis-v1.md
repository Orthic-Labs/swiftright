# F3 vstack-1s ready/revalidation diagnosis

Frozen failure: `probes/sr0-s/fresh-on-bridge/out/tuple12-startupguard-smoke-v1/observed-full16-smoke-v4-r1/F3-vstack-1s-80227e8c3ca84917a7b4e0520d8255f8/F3-vstack-1s-r-ea57d67f82034389a6a00585484f2ad4/driver-trace.txt` SHA-256 `db4b085e563da441c547cb1d1c75b9713790f3df833ffbe2378bffd5e2ca1e33`.

Evidence:

- r5 driver SHA-256 is `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`; receipt SHA-256 is `e08b1b2cb4ddbc08a710c0e178b6c879e09fe0221f00267b4fc9e4a8bddeddc9`.
- Process/MainWindowHandle was found early: `window_hwnd=27921578 polls=4 exited_early=False`.
- Renderer-ready JSON was valid (`pid=60116`, source `Bridge.onReady`, positive 1600×1200 metrics), but r5 logged `waited_ms=68845`; its polling loop is bounded to 45,000 ms. The synchronous `IO.File.ReadAllText(rendererReadyFile)` and JSON parse occur after path detection and have no timing marker, so current receipt cannot distinguish polling delay from read/lock delay.
- After ready parsing, r5 failed closed: `renderer_window_revalidate=FAIL initial_hwnd=27921578 owner_pid=60116`, then `no window: UIA root unavailable`; child exit 1, driver exit 0. Native assertions were never relaxed.
- Renderer source writes ready telemetry synchronously from `Bridge.onReady` via `window.metrics()` then Foundation `Data.write(..., .withoutOverwriting)`. Current source pins are `StartupGuard.swift` git object `187539490e089ccd880bf1d5c13fab333e268f40` & `main.swift` git object `477935655489855654dd2caf856895569dc41161`.
- Failed stdout order is `SR0_RENDERER_READY file=created`, then `root-appear`; this confirms marker was emitted before UIA/self-test stages. It does not prove why r5's MainWindowHandle revalidation failed later.
- Child QPC deltas independently show `selftest start -> root-appear = 894.4934 ms`, `selftest start -> window ready = 908.9622 ms`, & `selftest start -> close = 40009.6742 ms`. Thus renderer reached onReady before root/UIA work; r5's `waited_ms=68845` is not explained by vstack readiness alone. Exact marker-file observation/read timing remains absent from frozen r5.

Disconfirmable hypothesis: ready-path handoff is not instrumented tightly enough. Polling condition evaluates `Test-Path` before 45,000 ms check, so one blocking filesystem call can exceed nominal bound; after path detection, synchronous `ReadAllText` & JSON parse are also outside that bound. Current trace collapses all phases into `waited_ms`; source/receipt do not establish which phase consumed 68,845 ms. R6 separates phases without relaxing assertions.

Prospective diagnostic driver is isolated at `qualification/tuple12-takeover/f3-ready-diagnosis-v1/drive-fixture-noactivate-focus-r6-diagnostic.ps1`, SHA-256 `0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c`. It preserves r5 assertions & fail-closed behavior, adding only `renderer_ready_file_seen_ms`, synchronous `read_ms`, & byte count around ready-file read. One root-owned F3 vstack-1s run can classify delay as path polling vs read/parse vs subsequent HWND revalidation. No old receipt is modified.

Pure controls: `qualification/test_f3_ready_diagnosis_controls.py`, SHA-256 `af9a8871f57947d60da9cf282f66f8728419e2b655a312045602197e1274392e`; `python3 qualification/test_f3_ready_diagnosis_controls.py` passed. Controls verify four-line-only r5→r6 overlay, timing-marker order, fail-closed HWND revalidation, & reject missing timing, fail-open revalidation, & removed ready identity checks.
