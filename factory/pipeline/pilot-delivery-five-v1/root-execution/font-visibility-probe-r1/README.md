# DirectWrite font visibility probe r1

This packet is diagnostic only. It tests whether temporary `AddFontResourceExW(..., flags=0)` registration is visible through DirectWrite system collections, with `FR_PRIVATE` as control. It does not claim renderer font selection or SwiftUI parity.

Stage packet on Windows from canonical checkout:

```powershell
& .\stage-font-visibility-probe-v1.ps1
```

Stage destination is `D:\Claude\swiftright\.factory-work\root-tools\font-visibility-probe-r1`. Staging refuses existing input, reparse points, oversized files, hash drift, & deletion.

Run one bounded compile then one probe under `D:\Claude\desktop.lock`:

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\run-font-visibility-probe-v1.ps1 `
  -CompilerPath 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\cl.exe' `
  -VcVars64Path 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat' `
  -FontPath 'D:\Claude\swiftright\.factory-work\root-tools\font-visibility-probe-r1\Tinos-Regular.ttf' `
  -VctipPath 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\vctip.exe' `
  -VctipSha256 '0438198f79ccba1ad170f4344632e74bbf8b0d8ae55f92446565c54bedb26e37' `
  -Revision 1 -InnerDeadlineSeconds 120
```

Pinned inputs: C++ `ffe9c95e...aa4f`, ProviderOwnedJobProcess helper `0ed9cec5...fab86`, Tinos-Regular.ttf `60a0e8ef...cb61`, cl `dc8426b8...0d53`, vcvars64 `6b516d8f...2209`, vctip `0438198f...6e37`. Full values are in `request.json`.

Expected output includes compile/probe stdout/stderr, retained-handle receipts, `probe-manifest.json`, both `RemoveFontResourceExW` results, DirectWrite `FALSE`/`TRUE` collection observations, lock owner/release, & bounded memory/stream fields. `qualification` remains `registration-visibility-observation-only`.

Archive successful or failed run without deleting inputs:

```powershell
Compress-Archive -LiteralPath 'D:\Claude\swiftright\.factory-work\root-tools\font-visibility-probe-r1\run-r1' -DestinationPath 'D:\Claude\swiftright\.factory-work\root-tools\font-visibility-probe-r1\archive-r1.zip'
```

No compiler, native capture, or remote execution was run while preparing this packet.
