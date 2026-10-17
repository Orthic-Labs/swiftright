# SR0 tuple 12: Dell staging record (resume plan)

## State at takeover

Tuple 12 staging was stopped at 2026-10-11 11:04–11:05 local, after stop was relayed from Adrian. Parser preflight failed before clone/root creation; current audit recorded `ROOT_MISSING D:\Claude\swiftright\.work\sr0-r12`. No qualification receipt is valid until fresh staging completes & audit output binds every member. Any later partial root must be preserved.

| Field | Pin |
|---|---|
| Stage source commit | `a9556b77f50315afcae27fc8fc44c0cd274959e2` |
| Product fixes commit | `4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2` |
| Renderer source | `D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll` |
| Renderer sha256 | `7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2` |
| Staging root | `D:\Claude\swiftright\.work\sr0-r12` |
| Stage capture | `/Volumes/D/sr0-artifacts/stage-r12.log` |

The source commit is canonical stage commit `a9556b77f` (base `0e201571` + startup-guard overlay r2, Sage 17 October); it contains product fixes from `4b1ca6d0`. ABI remains 0.6. Renderer was built from `4b1ca6d0` by RightKit build broker. No tuple member hash is accepted from transcript shorthand.

## Receipts required

`audit-tuple.ps1` must emit exact SHA-256 & path for renderer, FreshOnBridge, BridgeSmoke, BridgePixels, WorkloadWin, TextGeom06, Modal06 & ColdOpen06. It must also emit source `HEAD`, tracked-dirty state, `SOURCE-HEAD.txt`, `build.json`, `incremental.json`, every `stage-tools\` log hash plus tail, desktop lock, matching processes & matching scheduled tasks. Root Mac session must separately record broker status before any new broker submission.

Expected receipt paths after successful staging:

* `D:\Claude\swiftright\.work\sr0-r12\stage-tools\*.log`
* `D:\Claude\swiftright\.work\sr0-r12\workload\build.json`
* `D:\Claude\swiftright\.work\sr0-r12\workload\incremental.json`
* `D:\Claude\swiftright\.work\sr0-r12\workload\SOURCE-HEAD.txt`

## Safe commands

Copy exact pinned source scripts from commit `a9556b77f50315afcae27fc8fc44c0cd274959e2` into `D:\Claude\swiftright\.work\sr0-overrides` using repo-relative paths, then check each copied file's SHA-256 against `probes/sr0-s/fresh-on-bridge/out/tuple12-stage-takeover-r1/transfer-manifest-r2.json`. Include `stage-tuple.ps1`, `audit-tuple.ps1`, `resume-tuple.ps1`, `preflight-ps1.ps1` & every file listed by preflight. `-ScriptOverride` selects these reviewed files while clone stays clean. Parse every stage script before audit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\.work\preflight-ps1.ps1 -Root D:\Claude\swiftright\.work\sr0-overrides *> D:\Claude\swiftright\.work\sr0-r12-ps-parse.txt
```

Parse must emit `PS_PARSE_ALL_OK`; then run audit only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\.work\audit-tuple.ps1 -Commit a9556b77f50315afcae27fc8fc44c0cd274959e2 -RendererDll "D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll" -ExpectRenderer 7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2 *> D:\Claude\swiftright\.work\sr0-r12-audit.txt
```

Before build, run bridge-header preflight against cloned source. It reads resolved bytes only & rejects one-line Git symlink text; expected tuple12 source header is 41,937 bytes, SHA-256 `12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\.work\sr0-overrides\probes\sr0-s\fresh-on-bridge\scripts\verify-bridge-header.ps1 -Header D:\Claude\swiftright\.work\sr0-r12\src\packages\SwiftRightBridge\Sources\CSwiftRight\swiftright.h -ExpectedSha256 12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b -ExpectedBytes 41937
```

After root confirms no matching process/task, desktop lock is `free` & Mac broker is quiescent, resume partial tree:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\.work\resume-tuple.ps1 -ScriptOverride D:\Claude\swiftright\.work\sr0-overrides -Commit a9556b77f50315afcae27fc8fc44c0cd274959e2 -RendererDll "D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll" -ExpectRenderer 7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2 *> D:\Claude\swiftright\.work\sr0-r12-resume.txt
```

Root-side broker read: `rightkit list`; do not submit while RustRight fix install is unverified.

If source clone is incomplete, leave `sr0-r12` in place & use fresh sibling root; this is additive & does not delete old evidence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\.work\resume-tuple.ps1 -ScriptOverride D:\Claude\swiftright\.work\sr0-overrides -Restart -Commit a9556b77f50315afcae27fc8fc44c0cd274959e2 -RendererDll "D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll" -ExpectRenderer 7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2 *> D:\Claude\swiftright\.work\sr0-r12-restart.txt
```

`resume-tuple.ps1` invokes build-only staging. It does not launch an app, create scheduled tasks, remove files or contact broker. `Copy-Tree` is additive `robocopy /E` without purge/mirror flags; all staged copies & content writes fail closed. Build scripts must use retained unique scratch/log paths; any `Remove-Item`, `rmdir`, `/MIR`, `/PURGE` or destructive cleanup is a preflight violation.
With audit result `ROOT_MISSING`, same command creates canonical `sr0-r12`; `-Restart` is only for an existing partial root whose source clone is unusable.

## Script audit corrections

Stage dependencies contain no GUI/native app launch. Native `swift`, `git`, `robocopy`, `mt.exe` & `dumpbin.exe` calls now have explicit exit checks; incremental builds fail closed on nonzero build, Rust invocation or hash drift; GeoModal manifest checks fail closed. `build-incremental.ps1` uses unique UTC run directories/logs; `BridgeGeoModal` manifest extraction uses unique retained temp files; fixed temp manifest paths were removed. Stage logs append, preserving stopped-run output. `Copy-Item`, `Set-Content` & directory creation in stage fail on mutation errors. Existing partial root remains untouched until explicit resume/restart command.

Pinned-source metadata: original `0e201571e4320a3b6ccce14313fd2ad67e523904` blobs hash to `build-incremental.ps1=46b6a7b55454cd61a1cc1e11f039a0b27f700c838e2d8d1938d80943f32b3591` & `BridgeGeoModal/scripts/build.ps1=ffd72e442672a971edde8fd0f28face0a23a9b40dadb4caf12f293bbcc8c25a6`; original violations were `Remove-Item $log` line 18 & `Remove-Item $tmp` line 36. `-ScriptOverride` makes reviewed replacements explicit; source clone stays pinned/clean.

## Requalification order after `STAGE_OK`

Bind every receipt to tuple 12 pins before advancing: artifact/manifest verification, matrix 320/320, BridgeSmoke/pixels, TextGeom06/Modal06/ColdOpen06, native IME & Narrator automatable checks, workload R10, signed Windows package checks, then compare. Use 20 Mac & 20 Windows recordings per contract config (320 per side for 16 configs); keep Dell lock for one interactive job at a time, pass tuple 12 FreshOnBridge & renderer hashes into `win-cross.sh`, reassemble, then run comparator fault controls. Narrator speech remains human-listen step.

`win-cross.sh` now accepts optional `EXPECT_RENDERER=<lowercase tuple 12 hash>` & aborts if `run-cross.ps1` records another DLL; existing tuple 11 callers remain unchanged when variable is unset.

W08 remains open until RightKit repair-helper candidate is delivered, installer-registered, exercised against `Modified, NeedsRemediation`, relaunch & data-integrity checks, then recorded in a fresh package receipt. Existing recovery receipts prove only manual Repair/redeploy paths; they do not close W08.

## Known pre-resume script receipt

Archived takeover receipt records parser failure in `preflight-ps1.ps1` block-comment delimiters (`<#!` / `#!>`); working tree now uses valid `<#` / `#>`. Root's direct `Parser::ParseFile` guard may run before copying this helper. Preserve archived r1 scripts & manifest; use corrected file only in next reviewed override set.
