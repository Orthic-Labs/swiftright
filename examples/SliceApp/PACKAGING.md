# SliceApp packaging (SR0-P prep)

Status: prep only. Nothing here has been signed, packaged, sealed, or uploaded. The Windows build proof ran
(see "Verified so far"). The sealed build and the clean-machine checks wait for `@rightkit/release` 0.2.138.

Rules that apply (workspace): build and sign on the native host; Windows through `win`; release commands run from
the primary checkout with the manifest-pinned pnpm; build (seal) and upload stay separate; upload only an exact
build Adrian names; never run `osascript`, `open`, `screencapture`, or `notifyutil -p` directly on Mac (use
`right-release install-app` or hand the step to Adrian).

## Layout

| Path | Role |
|---|---|
| `Package.swift` | One executable target; path dependencies on `probes/sr0-s/fresh-runtime` and `packages/SwiftRightBridge` (Windows only) |
| `Sources/SliceApp/Shared/` | Model, row store, and the shared screen (same source on both OSes) |
| `Sources/SliceApp/Entry/` | macOS SwiftUI `App` (one `Window`) and the Windows `@main` bootstrap |
| `Sources/SliceApp/Windows/` | Windows bootstrap (renderer load, typed startup errors) and the bridge backend |
| `Windows/SliceApp.manifest` | ComCtl v6 + PerMonitorV2 DPI, embedded by the linker |
| `Windows/Assets/` | MSIX logos (placeholders, solid colour) |
| `Mac/SliceApp.entitlements` | Empty entitlements record (none requested); applied to the app by `swift-package mac-app --sign` |
| `Mac/dmg/background.tiff` | DMG background, PLACEHOLDER (flat light grey, 660x400 + 1320x800 multi-rep TIFF); replace with branded art before any publication |
| `swift-package.json` | Schema 1 config for `right-release swift-package` (both OSes) |
| `right-release.config.mjs` | Release contract: `projectType: "swiftpm"`, mac branded DMG (signed, notarized, stapled), Windows MSIX, App Installer |
| `package.json` | Pins `@rightkit/release` 0.2.138 (exact) for `pnpm exec right-release` |
| `scripts/build-windows.ps1` | Windows build, `mt.exe` manifest check, `dumpbin` closure, payload copy |
| `scripts/prepackage-windows.ps1`, `scripts/prepackage-mac.sh` | `prePackage` steps called by `right-release`. The mac one builds the app, signs it with its entitlements, and builds the DMG |

Data: rows persist to `rows.json` (schema 1, atomic write):
- macOS: `~/Library/Application Support/SliceApp/rows.json`
- Windows: `%LOCALAPPDATA%\SliceApp\rows.json` (outside the MSIX install folder)

## Dev build

macOS (unsigned, not sealed):

```sh
cd examples/SliceApp
swift build -c release
```

Windows (build proof, run through `win`; the Windows host has no repository checkout, so stage the sources first):

```sh
# Mac: stage source (dereferenced, no .build) and the committed runtime, then copy to the host.
tar --exclude='.build' -chf sliceapp-src.tar examples/SliceApp packages/SwiftRightBridge render/swiftright-abi/include/swiftright.h
git archive --format=tar -o fresh-runtime-head.tar HEAD probes/sr0-s/fresh-runtime
scp sliceapp-src.tar fresh-runtime-head.tar win:"D:/Claude/"
win 'New-Item -ItemType Directory -Force D:\Claude\sliceapp-sr0p | Out-Null; tar -xf D:\Claude\sliceapp-src.tar -C D:\Claude\sliceapp-sr0p; tar -xf D:\Claude\fresh-runtime-head.tar -C D:\Claude\sliceapp-sr0p'
# Host: build, verify the manifest, print the Swift runtime inventory.
win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sliceapp-sr0p\examples\SliceApp\scripts\build-windows.ps1"
```

Stage the committed runtime, not the working tree: `probes/sr0-s/fresh-runtime` is under active edit by another
session (uncommitted `Controls`, `Keyboard`, `Presentation`, `Selection`), and the working tree does not build on
Windows at the time of writing. Pin the runtime to a commit before sealing (see Gaps).

## Sealed build (after `@rightkit/release` 0.2.138 is published)

Run from the primary checkout, with the exact version named in the request:

```sh
cd examples/SliceApp
pnpm install                                    # resolves @rightkit/release 0.2.138 (exact), writes the lockfile
pnpm exec right-release doctor --platform win --config right-release.config.mjs   # preflight, no build
pnpm exec right-release doctor --platform mac --config right-release.config.mjs
```

Windows seal (on the Windows host, native signer; no `az login`):

```sh
win "cd D:\Claude\swiftright\examples\SliceApp; pnpm exec right-release release --tier patch --platform win --config right-release.config.mjs --no-upload"
```

macOS seal (on the Mac host, notary profile `apple-dev-notary`):

```sh
pnpm exec right-release release --tier patch --platform mac --config right-release.config.mjs --no-upload
```

Upload is a separate step and needs Adrian's explicit request for the exact sealed build:

```sh
pnpm exec right-release upload --release <id> --platform win --tier patch
```

macOS DMG flow (what the mac target runs, in order): `prePackage` (`scripts/prepackage-mac.sh`: `swift build -c release`,
`swift-package mac-app --sign` (app with `Mac/SliceApp.entitlements`, Developer ID, hardened runtime), `right-release dmg build`
into `dist/mac/SliceApp_0.1.0_arm64.dmg`), then `sign.prePackageFiles` (the DMG container, Developer ID), then `notarize.file`
(the DMG, submitted with profile `apple-dev-notary`; `notarize-macos.mjs` staples the DMG and validates it), then hardening
on the DMG. No zip is produced.

Required outputs: `dist/win/SliceApp_0.1.0.0_x64.msix`, `dist/win/SliceApp.appinstaller`, `dist/mac/SliceApp_0.1.0_arm64.dmg`,
the signing receipts and `msix-seal.json` under the RightKit state root.

## Clean-machine checks

Run on a clean Windows 11 x64 machine and a clean Apple silicon Mac, one OS at a time. Record receipts, not
impressions. The App Installer URLs in the config are placeholders, so the upgrade check uses the local `.msix`.

Windows (PowerShell, elevated where noted):

1. Install: `Add-AppxPackage -Path .\SliceApp_0.1.0.0_x64.msix`; then `Get-AppxPackage OrthicLabs.SliceApp` shows
   version `0.1.0.0` and publisher equal to the signing subject.
2. Offline launch: disable networking, start SliceApp from the Start menu, confirm the window and the file
   `%LOCALAPPDATA%\SliceApp\rows.json` is written. Desktop runs need Adrian's coordination (peer-session rule).
3. Upgrade: build `0.1.1.0` (bump `version`, `msixVersion`, `identity.version`), then
   `Add-AppxPackage -Path .\SliceApp_0.1.1.0_x64.msix`. Expect the new version; `rows.json` unchanged.
4. Rollback: MSIX does not downgrade in place. Remove the package (step 6, data kept), then install `0.1.0.0`.
   Expect the old build to read the rows written by `0.1.1.0` (schema 1 is the contract).
5. Corrupt update rejection: flip one byte in a copy of the `.msix` (away from the header), run
   `Add-AppxPackage` on it. Expect failure and the installed version unchanged.
6. Interrupted update: start `Add-AppxPackage` of `0.1.1.0`, stop the installer process mid-install
   (`Get-Process AppInstaller, Add-AppxPackage -ErrorAction SilentlyContinue | Stop-Process`). Expect either the old
   or the new version, never a broken package; launch succeeds; `rows.json` intact.
7. Uninstall preserving user data: `Remove-AppxPackage` on the package full name. Expect `%LOCALAPPDATA%\SliceApp\rows.json`
   still present and byte-identical; reinstall and confirm the rows show.
8. Virtualization check: confirm the app's data writes land in `%LOCALAPPDATA%\SliceApp` and not in the install folder
   or the package registry hive (inspect with Process Monitor from Adrian's session; no automated pass yet).
9. Dependency check: `dumpbin /dependents` on the installed `SliceApp.exe` and each staged DLL; every entry is in
   the 18-DLL inventory or a system DLL.

macOS (`right-release install-app` and the terminal; no direct `open`):

1. Install: `right-release install-app --dmg dist/mac/SliceApp_0.1.0_arm64.dmg --app-name SliceApp.app --bundle-id dev.orthic.sliceapp`
   (it verifies first). Then `xcrun stapler validate dist/mac/SliceApp_0.1.0_arm64.dmg` (expect the DMG ticket),
   `codesign --verify --deep --strict /Applications/SliceApp.app`, `spctl --assess --type execute /Applications/SliceApp.app`.
   Open question to check here, not assumed: the staple is on the DMG container only. Whether the copied `.app` launches
   offline without its own ticket must be read from this check (gap 3b).
2. Offline launch and first run: Adrian launches the app with networking off; confirm
   `~/Library/Application Support/SliceApp/rows.json` appears.
3. Upgrade: install the `0.1.1` DMG through `right-release install-app` (it verifies first and keeps the old bundle
   in the Trash). Expect `rows.json` unchanged.
4. Corrupt update rejection: alter one byte in a copy of `Contents/MacOS/SliceApp`; `codesign --verify --deep --strict`
   must fail, and the install step must refuse the bundle.
5. Interrupted update: kill `ditto` mid-copy in a scratch directory (never the installed copy). Expect the installed
   bundle untouched (`install-app` restores the old bundle on failure).
6. Uninstall preserving user data: move `/Applications/SliceApp.app` to the Trash; `rows.json` still present.
7. Eject the DMG volume after testing (`hdiutil detach /Volumes/SliceApp* -force`); the build folder copy of the app is
   removed by the DMG build's cleanup. Unregister stray copies with RightKit's `lsclean.sh` if any show in Spotlight.

## Verified so far

- macOS: `swift build -c release` passes (Xcode 27 RC toolchain; Swift version not recorded).
- `right-release.config.mjs` mac target (prep, 2026-10-09): the preconditions `release.mjs` enforces for the mac branch
  (signingContract, prePackage, sign.prePackageFiles, notarize.file) hold, `notarize.file` is the signed DMG, and the
  DMG build arguments parse with RightKit's `parseDmgArguments` (read-only import of the local 0.2.137 tree). There is no
  pure mac/DMG config validator in RightKit; the mac check is the inline one in `release.mjs`. The win target still
  reports no problems from `validateMsixTarget`.
- Windows: `build-windows.ps1` passes on the host against the committed runtime (`git archive HEAD`).
  - `mt.exe` reads the embedded manifest: ComCtl v6 and PerMonitorV2 present.
  - Import closure resolves with no unresolved entries. The exe sha256 is recorded in the build output.
- `right-release.config.mjs`: RightKit's own pure validator (`msix-config.mjs`, local 0.2.137 tree) reports no
  problems for the win target; `resolveProjectType` returns `swiftpm` for both targets.
- The Swift runtime DLL inventory (18 entries, `dumpbin /dependents` closure): `_FoundationICU`, `BlocksRuntime`,
  `dispatch`, `Foundation`, `FoundationEssentials`, `FoundationInternationalization`, `MSVCP140`,
  `swift_Concurrency`, `swift_RegexParser`, `swift_StringProcessing`, `swiftCore`, `swiftCRT`, `swiftDispatch`,
  `swiftObservation`, `swiftSynchronization`, `swiftWinSDK`, `VCRUNTIME140`, `VCRUNTIME140_1`.
  System imports are api-sets plus `KERNEL32`, `USER32`, `ole32`, and similar. They are not shipped.
- Not verified: launch, rendering, input, the stage and MSIX pack, signing, notarization, install, upgrade. These are
  the packaged-qualification stage.

## Gaps and open items

1. `@rightkit/release` 0.2.138 is not published. The local tree is 0.2.137. The config was checked only against
   0.2.137's validators.
2. Publisher and App Installer URLs are placeholders (`TODO` in the config). The publisher must equal the signing
   subject exactly, and the URLs must not reach R2 until real.
3. Entitlements (RightKit gap, not edited): the mac target has no entitlements key. `release.mjs` signs the DMG
   container through `sign-macos.mjs` without `--entitlements`, which is correct for a container. The app's entitlements
   are applied by `swift-package mac-app --sign` in prePackage, which reads `swift-package.json` `mac.entitlements`. So
   this app's empty entitlements are honored, but a release-level entitlements declaration is still missing from
   `release.mjs`; a future entitlement must go through that path. Record for RightKit Mac.
3b. Stapling (resolved for the container, open for the app): the mac target now ships a DMG, and
   `notarizeMacosArtifact` staples a `.dmg` archive itself. The `.app` inside is not separately notarized or stapled.
   `release.mjs` takes one `notarize.file`, so notarizing the app first (zip, staple the app) and then the DMG is not
   expressible in this config. Whether offline first launch of the copied app passes Gatekeeper on the DMG ticket alone
   is unverified; the macOS offline-launch check (install step 1 and step 2) decides it. If it fails, the fix is a
   RightKit change (two-stage notarize) and not an edit here.
3c. The DMG background is a placeholder. The DMG build does not run without a background, but a plain DMG is not a
   shippable look (workspace `docs/BRANDED-SIGNED-DMG.md`); replace `Mac/dmg/background.tiff` before publication.
3d. The DMG name is arm64 (`SliceApp_0.1.0_arm64.dmg`) because the build is host-architecture. A universal build needs
   a universal `swift build` and a rename; not decided here.
4. Windows contract name: the workspace text says the Windows screen imports `SwiftRightUI`. The tree has no such
   module; the runtime is `SwiftRightRuntime`, which the screen imports on Windows. The contract text needs the
   module name settled.
5. Path dependency on a moving tree: `probes/sr0-s/fresh-runtime` has uncommitted edits by another session. A seal
   must pin the runtime to a commit (or a published package) first.
6. `windows.searchDirs` hard-codes the Swift 6.4.0 runtime path on this host. A release host with a different
   toolchain needs its own `swift-package.json`.
7. Virtualization is set to `enabled` for both areas (reasoning in `right-release.config.mjs`). This is a choice to
   confirm during the packaged qualification, not a verified fact.
8. Rust binaries: none. The "unchanged Rust binaries after a Swift-only edit" check does not apply to this app.

## SR0-P pre-publication build (2026-10-09): BLOCKED before build, nothing built or signed

Intended source: RightKit working tree at `9f3ec2d48689fb7a7c73d269fe67490f0874369e` plus uncommitted `packages/release`
changes (msix-appinstaller/config/plan/target, project-type, swift-build-context, build-release, release,
release-invocation, publish-update, cache-policy, preflight, msix-build; 0.2.137 in package.json). PRE-PUBLICATION.

Prepared (uncommitted):
- `package.json`: `@rightkit/release` is `link:../../../tools/rightkit/packages/release` (pnpm install resolves the local tree;
  `pnpm exec right-release` runs it; lockfile `pnpm-lock.yaml` records the link). Revert to the exact `0.2.138` pin after publication.
- Publisher in `right-release.config.mjs` and `swift-package.json` set to the provisioned signer subject, read from the valid
  Authenticode signature of a sealed CodeRight installer on the Dell: `CN=Damned Ventures LLC, O=Damned Ventures LLC, L=new york, S=New York, C=US`.
  App Installer URLs stay `.invalid`.

Blocker: `right-release doctor/build` refuses to run: `dirty release config cannot be executed` (build-release.mjs:127,
release.mjs:113), and build also requires a clean whole-repository tree (`assertCleanSource`, source-gate.mjs) at the primary
checkout, with config and build inputs matching HEAD. The swiftright tree has the above SliceApp edits plus unrelated uncommitted
`probes/sr0-s/fresh-on-bridge` and `probes/sr1-pulse-probe` work from other sessions. Resolution needs Adrian's commit of the
SliceApp prep (and the other sessions' work committed or removed); no bypass was attempted.
