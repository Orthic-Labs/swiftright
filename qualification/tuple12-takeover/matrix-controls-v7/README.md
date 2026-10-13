# Tuple12 matrix controls v7

Source-only runner successor to sealed matrix v6. Worker-v5 & coordinator-v5 stay byte-identical. v7 bounds each hidden coordinator to 300 seconds, polls retained coordinator handle at one-second intervals, caps each redirected stream at 8 MiB, samples coordinator RSS with 2 GiB cap, preserves raw outputs, kills only exact coordinator on timeout/output/RSS fault, & aborts remaining cases. It never kills worker/child processes, writes desktop lock, or frees lock from scheduler state.

Inputs stay pinned to base `0e201571e4320a3b6ccce14313fd2ad67e523904`, driver `0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c`, EXE `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`, & renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`. Full mode remains 16 configurations × 20 runs; failure aborts remaining batch & preserves lock/output evidence.

Root parser/typecheck command:

```powershell
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File D:\Claude\swiftright\qualification\tuple12-takeover\matrix-controls-v7\headless-controls.ps1 -OutRoot D:\Claude\swiftright\.work\sr0-matrix-v7-headless-r1
```

Headless controls run two owned PowerShell children: positive terminal/drain & timeout termination. They retain original handles, poll kernel terminal, cap streams, record RSS, & write CreateNew receipts. They do not touch desktop lock, GUI, input, scheduled tasks, or sealed v6/raw archives. Controls source SHA `1f2ba5e152c453e57aa96277abfe584d581ef7a089191c3fd112c470b9ce0b42`; no controls have run in current source lane.

Runner SHA `93fd5533c6f2309b8a4c7541ab50bbb1fb16e18f2feb1b0aa397a731a3a7e292`; headless script SHA `46fed3a38cd97b0309a1c3523afbb9c849a8a33f0611de0e084e73ec73e2f97f`.
