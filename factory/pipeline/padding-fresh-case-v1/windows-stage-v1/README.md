# Fresh Padding Windows stage

Source-only packet for one fresh Windows compile bound to materialized Padding
case, manifest & tuple. `stage_windows_package_v1.py` validates exact source,
case, runtime, renderer, compiler & original-handle helper bytes, then emits a
fresh package, compile plan & receipt. It performs no compiler, native, lock or
remote action. Manifest/tuple case hashes use canonical artifact identity;
copied `fresh-inputs/case.json` retains separately measured raw JSON SHA256/bytes.
Donor `plan.json` is measured input only & excluded from copy; fresh plan is
published exclusively after new joins. Compile argv retains measured Windows
GUI flags, including Common Controls manifest dependency, `/SUBSYSTEM:WINDOWS`,
`/ENTRY:mainCRTStartup`, single job & single frontend thread.

Root transport/stage command. Local Mac paths are measured evidence; Windows
paths are operational values serialized into fresh `plan.json`.

Measured source rows are compiler `1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a` (45,056 B), renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93` (11,885,056 B) & job helper `112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e` (13,575 B).

```text
factory/.venv/bin/python factory/pipeline/padding-fresh-case-v1/windows-stage-v1/stage_windows_package_v1.py \
  --source-package factory/native/windows/padding-capture-lease-build-v1/package \
  --case factory/pipeline/padding-fresh-case-v1/root-controls-r3/materialized/case.json \
  --manifest factory/pipeline/padding-fresh-case-v1/root-controls-r3/materialized/manifest.json \
  --tuple factory/pipeline/padding-fresh-case-v1/root-controls-r3/materialized/tuple.json \
  --output-package .factory-work/hosts/padding-fresh-r11/package \
  --compiler-path factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/compiler-byte-archive-r1/swift.exe \
  --renderer-path factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/count1-closure-r2/swiftright_render.dll \
  --job-helper-path factory/native/windows/pilot-rectangle-root-v1/Sr0OwnedJobProcess.cs \
  --windows-package-path 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11\package' \
  --windows-scratch-path 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11\scratch-r1' \
  --windows-compiler-path 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' \
  --windows-renderer-path 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' \
  --windows-job-helper-path 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11\inputs\Sr0OwnedJobProcess.cs' \
  --output-receipt .factory-work/hosts/padding-fresh-r11/stage-receipt.json
```

Root runs `build-padding-fresh-v1.ps1` only after reviewing staged receipt.
Build polls output caps during live wait, retains original process handle, drains sealed streams, verifies active job count zero, then closes owned handles.
Preflight records compiler actions `0`; final compile remains source-bound until
root measures fresh output bytes. Limits are 256 files, 64 MiB/file, 256 MiB
source package, 8 MiB JSON & one compiler frontend thread.

Bounded Dell installer uses fresh `D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3`
only after ZIP, stage-manifest, build script & helper hashes are supplied:

```powershell
.\install-padding-fresh-v1.ps1 -PackageZip .\padding-fresh-r3.zip -ZipSha256 <64hex> -ManifestPath .\stage-manifest.json -ManifestSha256 <64hex> -BuildScript .\build-padding-fresh-v1.ps1 -BuildSha256 acc3982cebf6047320a9f6f68c124c0eafc01ca4d30755a5e2b507e444567d5c -HelperPath .\Sr0OwnedJobProcess.cs -HelperSha256 112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e -StageRoot 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3'
```
