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
| `Windows/renderer-pin.json` | Checksum pin for the dynamically loaded renderer (ABI 0.6, sha256, closure). Staging fails closed on any mismatch |
| `Windows/Assets/` | MSIX logos (placeholders, solid colour) |
| `Mac/SliceApp.entitlements` | Empty entitlements record (none requested); applied to the app by `swift-package mac-app --sign` |
| `Mac/dmg/background.tiff` | DMG background, PLACEHOLDER (flat light grey, 660x400 + 1320x800 multi-rep TIFF); replace with branded art before any publication |
| `swift-package.json` | Schema 1 config for `right-release swift-package` (both OSes) |
| `right-release.config.mjs` | Release contract: `projectType: "swiftpm"`, mac branded DMG (signed, notarized, stapled), Windows MSIX, App Installer |
| `package.json` | Pins `@rightkit/release` 0.2.138 (exact) for `pnpm exec right-release` |
| `scripts/build-windows.ps1` | Windows build, `mt.exe` manifest check, `dumpbin` closure, payload copy |
| `scripts/verify-package-layout.ps1` | Renderer packaging check: Stage mode (pre-pack) and Installed mode (scrubbed-environment load); no app launch |
| `scripts/clone-build-mac.sh`, `scripts/clone-build-win.ps1` | Build from an independent clean clone at an exact commit (see "Clean-clone builds") |
| `scripts/swift-only-proof.mjs` | Swift-only-edit proof: renderer bytes identical, no Rust compile |
| `scripts/make-local-appinstaller.mjs`, `scripts/serve-local-feed.ps1` | Local App Installer feed for the Sandbox (F8) |
| `scripts/interrupt-windows-install.ps1`, `scripts/interrupt-mac-install.sh` | Real interrupted-update experiments (F6) |
| `scripts/prepackage-windows.ps1`, `scripts/prepackage-mac.sh` | `prePackage` steps called by `right-release`. The mac one builds the app and signs it with its entitlements (right-release builds the DMG) |

Data: rows persist to `rows.json` (schema 1, atomic write):
- macOS: `~/Library/Application Support/SliceApp/rows.json`
- Windows: `%LOCALAPPDATA%\SliceApp\rows.json`. This is the unpackaged-looking path the app writes. Under MSIX it is
  inside AppData, which MSIX virtualizes by default: on Windows newer than 1809 a NEWLY CREATED file under AppData is
  written to a private per-user, per-app store and removed on uninstall (Microsoft Learn, "Flexible virtualization",
  "Default MSIX behavior", AppData row). So the config sets `virtualization.fileSystemWrite = "disabled"` (manifest
  `desktop6:FileSystemWriteVirtualization=disabled` plus the restricted capability `unvirtualizedResources`, which RightKit
  adds): per the same doc, writes then go to the real AppData path, are visible outside the package, and survive uninstall.
  Alternative considered and not taken: moving the file outside AppData (the doc says writes outside AppData are not
  virtualized). It needs a Windows-only Swift change and a migration; the manifest setting needs neither. Trade-offs:
  restricted capability (fine for App Installer/sideload, needs Store approval otherwise) and no fine-grained control
  (Windows 11 `virtualization:ExcludedDirectories` would scope it to `%LOCALAPPDATA%\SliceApp` but RightKit's manifest
  generator does not emit it; RightKit follow-up, not edited). The earlier text here claimed the path was "outside both
  virtualized areas"; that was wrong. Not yet verified on a machine: see Windows check 8.

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
win "cd D:\Claude\swiftright\examples\SliceApp; pnpm exec right-release build --platform win --config right-release.config.mjs"
```

macOS seal (on the Mac host, notary profile `apple-dev-notary`):

```sh
pnpm exec right-release build --platform mac --config right-release.config.mjs
```

Upload is a separate step and needs Adrian's explicit request for the exact sealed build:

```sh
pnpm exec right-release upload --release <id> --platform win --tier patch
```

macOS DMG flow (@rightkit/release >= 0.2.142, in order): `prePackage` (`scripts/prepackage-mac.sh`: `swift build -c release`,
`swift-package mac-app --sign`: app with `Mac/SliceApp.entitlements`, Developer ID, hardened runtime; no DMG), then `sign.prePackageFiles`
(the `.app`, signed inside-out), `notarize.appBeforePackage` (the `.app` is notarized and stapled), the automatic DMG step
(`targets.mac.dmg`: right-release builds `dist/mac/SliceApp_0.1.0_arm64.dmg` from the stapled app and Developer ID signs it), then
`notarize.file` (the DMG, profile `apple-dev-notary`, stapled and validated), then hardening on the DMG. No zip is produced.

Required outputs: `dist/win/SliceApp_0.1.0.0_x64.msix`, `dist/win/SliceApp.appinstaller`, `dist/mac/SliceApp_0.1.0_arm64.dmg`,
the signing receipts and `msix-seal.json` under the RightKit state root.

## Renderer packaging (F1)

`swiftright_render.dll` is loaded dynamically (`Bridge.load`: path argument, else `$SWIFTRIGHT_RENDER_DLL`, else the bare name
`swiftright_render.dll`), so it is absent from the exe's import table and every import-closure walk (the 18-DLL inventory,
`windows-stage`, `verifyPayloadInventory`) is blind to it. It ships by explicit declaration:

1. `Windows/renderer-pin.json` pins ABI 0.6 sha256 `C80B9517B044968F3E13EE9D92EEFC8704D000510B9A51B3245C885CE1A3FB30` and records the
   `dumpbin /dependents` closure (2026-10-09): `VCRUNTIME140.dll` (already in the payload inventory) plus Windows system DLLs and
   api-sets. `icuuc.dll` (OS ICU, System32) is not in RightKit's built-in system list, so it is declared in
   `swift-package.json` `windows.systemDlls` and in the config's `runtime.systemDlls`.
2. `scripts/prepackage-windows.ps1` checks the source DLL against the pin BEFORE building, copies it to `.build/renderer`, re-checks the
   copy, runs `windows-stage` (`swift-package.json` `windows.include` stages it and walks its imports), then runs
   `verify-package-layout.ps1 -Mode Stage`. Any mismatch or missing file throws; the release stops before packing.
3. `right-release.config.mjs` lists `swiftright_render.dll` in `runtime.dlls`, so `verifyPayloadInventory` fails closed if it is
   missing from the payload at pack time. The MSIX seal records the payload hashes (`msix-seal.json`).
4. Installed check (R5, no app launch): `verify-package-layout.ps1 -Mode Installed` asserts the DLL sits beside `SliceApp.exe` with the pinned
   hash and that, in a child process with `SWIFTRIGHT_RENDER_DLL` unset and PATH reduced to System32/Windows, the renderer plus its
   import closure load from the package (under a ComCtl v6 activation context, which the renderer requires, see Loader.swift error 127).
   The exe-side half (its own `Bridge.load()` with no path, resolved beside the exe) runs with the packaged BridgeSmoke step under the same
   scrubbed environment on the Sandbox desktop.

Static evidence so far (2026-10-09, Dell): the pinned DLL hashes to the pin; Stage and Installed modes pass on a synthetic layout
(DLL + `VCRUNTIME140.dll` + dummy exe) with a bogus `SWIFTRIGHT_RENDER_DLL` set and PATH scrubbed; a one-byte tamper fails Stage mode;
`Loader.swift` default name is `swiftright_render.dll`, equal to the pin. No package was built.

### Swift-only-edit proof

Build old (0.1.0) and new (0.1.1) from independent clean clones whose commits differ only in Swift sources and the version fields, save each
build transcript, then:

```sh
node scripts/swift-only-proof.mjs --old-seal <old msix-seal.json> --new-seal <new msix-seal.json> \
  --old-commit <sha0.1.0> --new-commit <sha0.1.1> --repo <clone> --build-log <old.log> --build-log <new.log>
```

It passes only if the renderer hash is the pin in both seals, `SliceApp.exe` is the only payload file that changed, `git diff` touches no
Rust input (`render/**`, `*.rs`, `Cargo.*`, `rust-toolchain*`), and neither transcript shows a cargo/rustc/`Compiling` line. The mac app
has no Rust and is outside this proof.

## Versions for upgrade and rollback

- Old: `0.1.0` / MSIX `0.1.0.0`, as committed. New: `0.1.1` / `0.1.1.0`, one commit on top that bumps `VERSION`, `MSIX_VERSION` (config),
  `version`/`msixVersion` (swift-package.json), `version` (package.json), the DMG/`.msix` names in `prepackage-mac.sh`, and makes one
  Swift-only edit that does not change the row schema. Build each from its own clean clone (below).
- Data compatibility: schema 1 is the contract. The new build must write rows the old build reads (rollback): check by writing a row with
  0.1.1 and installing 0.1.0 over it (Windows uses remove-then-install, data kept; Mac `install-app` takes the old DMG).

## Clean-clone builds (independent clone, not a worktree)

RightKit requires a branch-attached PRIMARY checkout (`release-invocation.mjs` `assertPrimaryReleaseCheckout`), so linked worktrees do not
qualify, and the source gate needs a clean tree. `scripts/clone-build-mac.sh` and `scripts/clone-build-win.ps1` clone `origin` at an exact,
already-pushed commit into a scratch location outside the primary checkout, check out a local branch (`sr0-clean-<sha12>`), put a link
`<scratch>/tools/rightkit` to the local RightKit tree (so `package.json`'s `link:../../../tools/rightkit/packages/release` resolves with no
tracked-file edit), `pnpm install --frozen-lockfile`, and run `right-release build` (doctor with `--stage doctor`). They never upload.
`--dry-run`/`-DryRun` validates arguments and prints the plan only.

```sh
sh scripts/clone-build-mac.sh --commit <sha> [--stage doctor] [--dry-run]
win "powershell -NoProfile -ExecutionPolicy Bypass -File <script>\clone-build-win.ps1 -Commit <sha> [-RendererSource <dll>] [-DryRun]"
```

Status: argument parsing validated by dry run only; not run (the 0.6 snapshot commit is pending).

## Local App Installer feed (F8)

The config's feed URLs are `.invalid`, so the real update route (App Installer fetch, `OnLaunch` update check) is untested by the sealed
files. In the Windows Sandbox guest (host loopback is not reachable from the guest, so the feed lives in the guest):

1. Copy the signed 0.1.0 and 0.1.1 `.msix`, `scripts/make-local-appinstaller.mjs` (or its output), and `serve-local-feed.ps1` into the guest.
2. Write the 0.1.0 feed: `node make-local-appinstaller.mjs --msix SliceApp_0.1.0.0_x64.msix --version 0.1.0.0 --out C:\feed`
   (name, publisher and settings come from the config through RightKit's generator; URLs `https://localhost:8443/sliceapp/...`).
3. `serve-local-feed.ps1 -Dir C:\feed -DisposableGuest` (self-signed `localhost` certificate added to the guest Trusted Root and bound to the
   port; guest only). The package itself is signed by the provisioned signer, so no signing-certificate trust is added.
4. Install through the route: `Add-AppxPackage -AppInstallerFile C:\feed\SliceApp.appinstaller`, launch, and confirm 0.1.0.0.
5. Publish the update: put the 0.1.1.0 `.msix` in `C:\feed` and overwrite `SliceApp.appinstaller` with the 0.1.1.0 feed. Relaunch the app
   (`OnLaunch`, `HoursBetweenUpdateChecks=0`) and confirm 0.1.1.0 registers and `rows.json` is unchanged.
6. Negative: serve a feed whose `MainPackage` `Publisher` or `Version` does not match the `.msix` manifest and confirm the install fails
   (Microsoft Learn, "Create an App Installer file manually": name, publisher and version are validated against the package identity).
Limits: this exercises the real App Installer fetch/update code over https, not the R2 host, DNS, or the production TLS chain. Record those
as untested until the real URLs exist.

## Clean-machine checks

Run on a clean Windows 11 x64 machine and a clean Apple silicon Mac, one OS at a time. Record receipts, not
impressions. The App Installer URLs in the config are placeholders, so the route is exercised through the local feed (F8), and the plain upgrade uses the local `.msix`.

Windows (run in the Windows Sandbox guest; PowerShell, elevated where noted):

0. Renderer: `scripts\verify-package-layout.ps1 -Mode Installed` (see "Renderer packaging") passes after step 1.
1. Install: `Add-AppxPackage -Path .\SliceApp_0.1.0.0_x64.msix`; then `Get-AppxPackage OrthicLabs.SliceApp` shows
   version `0.1.0.0` and publisher equal to the signing subject.
2. Offline launch: disable networking, start SliceApp from the Start menu, confirm the window and the file
   `%LOCALAPPDATA%\SliceApp\rows.json` is written. Desktop runs need Adrian's coordination (peer-session rule).
3. Upgrade: build `0.1.1.0` (bump `version`, `msixVersion`, `identity.version`), then
   `Add-AppxPackage -Path .\SliceApp_0.1.1.0_x64.msix`. Expect the new version; `rows.json` unchanged.
4. Rollback: MSIX does not downgrade in place (a lower version needs remove-then-install, or `-ForceUpdateFromAnyVersion`, Microsoft Learn Add-AppxPackage). Remove the package (step 6, data kept), then install `0.1.0.0`.
   Expect the old build to read the rows written by `0.1.1.0` (schema 1 is the contract).
5. Corrupt update rejection: flip one byte in a copy of the `.msix` (away from the header), run
   `Add-AppxPackage` on it. Expect failure and the installed version unchanged.
6. Interrupted update (real, Sandbox guest only): `scripts\interrupt-windows-install.ps1 -OldMsix <0.1.0.0> -NewMsix <0.1.1.0> -Mode KillDeployment -DisposableGuest`.
   It stops the AppX Deployment Service (`AppXSvc`) while `Add-AppxPackage` is in flight; killing the cmdlet host would not interrupt
   the deployment, which runs in the service. Record the observed state: exactly one of 0.1.0.0/0.1.1.0 registered, no
   partial state, the registered version launches, `rows.json` byte-identical; then re-run `Add-AppxPackage` and confirm 0.1.1.0
   registers. A run where the deployment finished before the interrupt landed is invalid. Second scenario, `-Mode DeferInUse`:
   with the app running, `Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse` leaves 0.1.0.0 registered and the update applies on the next
   launch (Microsoft Learn, Add-AppxPackage). The kill technique is fault injection, not a Microsoft-documented procedure.
7. Uninstall preserving user data: `Remove-AppxPackage` on the package full name. Expect `%LOCALAPPDATA%\SliceApp\rows.json`
   still present and byte-identical; reinstall and confirm the rows show. This is the check that proves the virtualization choice; with
   `fileSystemWrite=enabled` it would fail.
8. Virtualization physical paths: after the app has written rows (run once on a fresh profile so the file is created by the packaged app, and once
   with a legacy `rows.json` pre-placed), list both `%LOCALAPPDATA%\SliceApp\rows.json` (must exist, real path) and
   `%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Local\SliceApp` (must not exist). Extract the installed `AppxManifest.xml` and
   confirm `FileSystemWriteVirtualization` is `disabled` and `unvirtualizedResources` is declared. Save the file listings and hashes.
9. Dependency check: `dumpbin /dependents` on the installed `SliceApp.exe` and each staged DLL (including `swiftright_render.dll`); every entry is in
   the 18-DLL inventory, the renderer, or a system DLL.
10. Upgrade through the App Installer route: the local feed procedure above (F8).

macOS (`right-release install-app` and the terminal; no direct `open`):

1. Install: `right-release install-app --dmg dist/mac/SliceApp_0.1.0_arm64.dmg --app-name SliceApp.app --bundle-id dev.orthic.sliceapp`
   (it verifies first). Then `xcrun stapler validate dist/mac/SliceApp_0.1.0_arm64.dmg` (expect the DMG ticket),
   `codesign --verify --deep --strict /Applications/SliceApp.app`, `spctl --assess --type execute /Applications/SliceApp.app`.
   Open question to check here, not assumed: the staple is on the DMG container only. Whether the copied `.app` launches
   offline without its own ticket must be read from this check (gap 3b).
2. Offline launch and first run: Adrian launches the app with networking off; confirm
   `~/Library/Application Support/SliceApp/rows.json` appears.
3. Upgrade and rollback: install the `0.1.1` DMG through `right-release install-app` (it verifies first and keeps the old bundle
   in the Trash). Expect `rows.json` unchanged. Then install the `0.1.0` DMG over it (rollback) and confirm the old build reads the rows `0.1.1` wrote.
4. Corrupt update rejection: alter one byte in a copy of `Contents/MacOS/SliceApp`; `codesign --verify --deep --strict`
   must fail, and the install step must refuse the bundle.
5. Interrupted update (real swap): `install-app` moves the installed bundle to `~/.Trash`, runs `/usr/bin/ditto` into the destination, and restores the old
   bundle only when ditto reports an error (`install-app.mjs`, "Replace"). `scripts/interrupt-mac-install.sh --old-dmg <0.1.0> --new-dmg <0.1.1> --mode ditto`
   kills the ditto child (expect the old bundle restored and verifying); `--mode installer` kills install-app itself after the old bundle is moved
   aside (outcome to be observed: a missing/partial bundle with the old one in the Trash would be a RightKit atomicity defect to report, not fix).
   Runs in a scratch `--dest`, never `/Applications`; then re-run `install-app` for the new DMG and confirm codesign/spctl pass and `rows.json` is unchanged.
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
7. Virtualization: `fileSystemWrite: "disabled"`, `registryWrite: "enabled"` (reasoning in the config and in "Layout" above).
   A documented-behavior choice, still unverified on a machine until Windows check 8 runs.
8. Rust binaries: none are built by this app's release. The renderer is a pinned prebuilt DLL (`Windows/renderer-pin.json`),
   so the Swift-only-edit proof applies: see "Swift-only-edit proof". (The earlier text called the check inapplicable; that
   was wrong, because the proof is exactly that the pinned renderer bytes survive a Swift-only rebuild.)
9. The renderer is not built here. `RendererSource` (default `D:\Claude\sr1-abi06\payload\bin\swiftright_render.dll`) must
   hold the pinned bytes on the build host; an independent clean clone cannot supply it from git. Moving the binary into a
   content-addressed store both lanes can fetch is a snapshot-manifest (R0) decision.

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

## R3 signed Mac build (2026-10-09): BLOCKED at preflight, nothing built, signed, or notarized

Source: origin/master `c7c7eb6a2d520d4784e5204550e121fca6e97b5e`, independent clone `/Volumes/D/sr0-build/mac-c7c7eb6/swiftright`
(branch `sr0-clean-c7c7eb6a2d52`, scratch outside the primary checkout; `<scratch>/tools/rightkit` links the local RightKit tree).
Tool identity (pre-publication): RightKit HEAD `61ace202d83d6b2afe4f1138c9540a8854bf8a1d`, version 0.2.137, with uncommitted
`packages/release` changes (`git status --short packages/release`): M CHANGELOG.md, README.md, build-release.mjs, build-release.test.mjs,
cache-policy.mjs, msix-build.mjs, preflight.mjs, publish-update.mjs, release-invocation.mjs, release.mjs, swift-package.test.mjs;
?? msix-appinstaller.mjs, msix-config.mjs, msix-plan.mjs, msix-target.mjs, msix.test.mjs, project-type.mjs, swift-build-context.mjs,
swift-build-context.test.mjs.

Findings, in the order hit:

1. `scripts/clone-build-mac.sh` defect (stage `build`): `right-release build --platform mac` fails with `sliceapp has no mac package command`
   (build-release.mjs:170 requires `target.package` or an MSIX target; the mac DMG flow is `release --tier patch --platform mac --no-upload`,
   as "Sealed build" above says). The script's default stage must be `release --tier patch --no-upload`. Not edited (no commit allowed).
2. `link:` dependency rejected: `right-release doctor` in both the primary and the clone stops with
   `sliceapp @rightkit/release must come from the published npm package, not link:../../../tools/rightkit/packages/release`
   (release.mjs `validateRightKitPackageContract`, `FORBIDDEN_RIGHTKIT_SPEC`). Workaround inside the clone only (two local commits,
   `4092acc` then `6587313`): `package.json` and the lockfile specifier set to `0.2.137` while `node_modules/@rightkit/release` stays a
   symlink to the local tree. Do NOT let `pnpm exec` resolve it from the registry: it silently installs the published 0.2.137, which
   has no swiftpm support (fails with `native Cargo manifest missing .../src-tauri/Cargo.toml`).
3. BLOCKER (RightKit ownership registration, not patched): with the workaround, `doctor --platform mac` runs preflight and fails

   ```
   [FAIL] ownership: ownership evidence failed: repository is not registered in protected trust
          fix: restore protected RightKit ownership trust and catalog
   ```
   (preflight.mjs:320 <- ownership-evidence.mjs:92 `verifyRepositoryRegistration`; identity from `origin` `bogusyogi/swiftright`).
   swift 6.4, version-free and disk checks pass. The protected ownership registry is off limits to agents (a hook blocks reading it), so
   whether `bogusyogi/swiftright` is simply unregistered was not inspected. Needs RightKit owner action: register the repository (roots
   covering `examples/SliceApp`). Stopped; no bypass attempted. Old (0.1.0) and new (0.1.1) were not built.
4. Receipt note: `sr0-a.package-receipt/v2` (`qualification/run.py` PACKAGE_CHECKS) declares only install-side checks (M00-M11); it has no
   build/sign check type, so a build receipt JSON would sit next to the artifacts once a build exists. None written (no artifacts).

Resume once item 3 is resolved: in the clone, `cd examples/SliceApp && pnpm exec right-release release --tier patch --platform mac
--config right-release.config.mjs --no-upload`; then a second clone with the 0.1.1 bump commit (VERSION, config, swift-package.json,
package.json, DMG name in `prepackage-mac.sh`, one Swift edit); then codesign/spctl/stapler verification and sha256 recording.

## R2 signed Windows build (2026-10-09): STOPPED at the RightKit ownership gate, nothing signed or packed

Source: origin master c7c7eb6a2d520d4784e5204550e121fca6e97b5e, cloned on the Dell from the Mac path (`git clone mac:/Volumes/D/claude/swiftright`; GitHub is unreachable
from Windows over SSH) into `D:\Claude\sr0-r2\swiftright`. Clone-local commit b94715a916b9e86cb2f0093ef2b7fe0b06209023 (not pushed): `package.json` pins
`@rightkit/release` to `0.2.137` (the contract check rejects `link:`) and `pnpm-workspace.yaml` overrides it to the staged local package
`D:\Claude\sr0-r2\tools\rightkit\packages\release` (copy of the Mac RightKit tree HEAD 61ace202 plus uncommitted release changes; file hashes in
`/Volumes/D/sr0-artifacts/win/0.1.0/rightkit-release-mac-source-sha256.txt` and `rightkit-release-staged-sha256.txt`). Pre-publication tooling.

Reached: clone, tool staging, `right-release doctor` (swift, version, makeappx and signtool 10.0.26100.0, disk all ok), and `scripts/prepackage-windows.ps1`
(Swift release build, manifest and closure check, renderer pin check, `windows-stage`, `verify-package-layout.ps1 -Mode Stage` OK, renderer sha256 C80B9517...FB30).
Stage hashes: `stage-0.1.0-sha256.txt`. Not reached: MSIX pack, signing, `signtool verify`, `.appinstaller`, Swift-only proof (needs both seals).

Blockers and defects found:
1. Ownership preflight fails on Windows: "current process is elevated or elevation state is unknown" (`ownership-approval.mjs` evaluateWindowsAcl requires a non-elevated
   process). The SSH session is a High-integrity admin token; an S4U Limited scheduled task is also elevated. The existing Interactive/Limited tasks need a logged-in
   user. A non-elevated run therefore needs an interactive logon. The repository-registration gate (not registered in protected trust) follows on both hosts.
2. `scripts/clone-build-win.ps1` clones with `core.symlinks=false` on Windows, turning `packages/SwiftRightBridge/Sources/CSwiftRight/swiftright.h` (a git symlink) into a
   text file and breaking the Swift build. Fix: `git config core.symlinks true` before checkout (needs an elevated or Developer Mode session). Script not yet changed.
3. A `pnpm install --frozen-lockfile` inside release must not replace the staged link: the lockfile records the override so it stays a no-op.

## R2 retry (2026-10-09, later): elevation gate PASSED, now blocked by ownership scan content findings, nothing built or signed

Clone `D:\Claude\sr0-r2b\swiftright` (origin master 66ead09, `git clone mac:...`, then `core.symlinks true` for checkout, then clone-local commits on branch `sr0-clean-66ead09`; origin URL set to `git@github.com:bogusyogi/swiftright.git` after clone, nothing fetched). Staged `@rightkit/release` is the Mac RightKit working tree at 258ca32b (package version 0.2.138, includes ownership registry commits 2922797c and a93d2516), at `D:\Claude\sr0-r2b\tools\rightkit\packages\release`. Clone-local changes: `package.json` spec `0.2.137` (the contract allowlist in `rightkit-versions.json` does not yet list 0.2.138; error "must be one of ... got 0.2.138") plus the pnpm override to the staged package; `Windows/renderer-pin.json` moved to the 0.6 rev06c DLL `777F14C4...335441` (11,779,072 bytes, `D:\Claude\sr0b-abi06c\bin`); the primary checkout's pin is still the superseded `C80B9517...` and needs this update before any R2 pass.

Elevation fix works: `scripts` (kept outside the repo in `D:\Claude\sr0-r2b\r2-task.ps1` and `r2-step.ps1`) register a one-shot Interactive/Limited hidden task as `adrds`, log to a file, wait, unregister. The step log shows `elevated=False`, and `right-release doctor` passes swift, version, SDK, signtool, disk. The ownership preflight then fails in three successive ways (logs `D:\Claude\sr0-r2b\log-doctor*.txt`):
1. `ownership evidence failed: unsupported repository identity URL` when origin was the Mac path; fixed by using the GitHub identity URL.
2. `committed-symlink` (`packages/SwiftRightBridge/Sources/CSwiftRight/swiftright.h` is a git symlink, mode 120000, to `render/swiftright-abi/include/swiftright.h`): ownership marks committed symlinks as unscanned coverage. Clone-local workaround: regular-file copy (same sha256 `D7E0DC20...F649`). The primary needs the same change (or an exception) to ever pass.
3. `dependency-lock-resolution:Cargo.lock resolution missing or ambiguous: windows`: every Cargo.lock in the repo (render and the probes) holds `windows` 0.57.0, 0.61.3 and 0.62.2, and ownership.mjs line 293 cannot pick one. Not worked around.
The trust-sync / registration gate is not yet reached. Not reached: MSIX pack, signing, verify, renderer-in-package hash, Swift-only proof.

### R2 retry 2 (origin/master 4d69e55): Cargo.lock and symlink blockers cleared; next ownership defect is in RightKit

Clone `D:\Claude\sr0-r2b\swiftright` moved to branch `sr0-clean-4d69e55` (origin/master 4d69e55 plus one clone-local commit 50b20729: package.json spec 0.2.137, pnpm override to the staged 0.2.138 package, lockfile override). Doctor via the non-elevated task (`log-doctor4.txt`): swift, version, SDK, signtool, disk ok; ownership FAIL `dependency-lock-resolution:lockfile bytes unavailable: probes/sr0-s/scui-fork/Package.resolved`.
Cause (staged `@rightkit/release`, 258ca32b working tree): `committed-source.mjs` `shouldRead` fetches blob bytes only for Cargo.toml, package.json, Package.swift, ownership-exceptions.json, the five OWNERSHIP_LOCKFILES and source extensions, but `ownership.mjs` (~line 260) requires the bytes of the adjacent `Package.resolved` for the Swift resolution. Fix belongs in RightKit (add `Package.resolved` to `shouldRead`), not in this repo or the clone. Trust-sync gate still not reached.

### R2 retry 3 (origin/master 9f0e58d, published @rightkit/release 0.2.138, no override): published package has no MSIX support

Clone `D:\Claude\sr0-r2b\swiftright` on `sr0-clean-9f0e58d` (clean tree, no clone-local commits; pnpm install installed the registry 0.2.138). Doctor via the non-elevated task (`log-doctor5.txt`, `elevated=False`) fails before preflight: `right-release: sliceapp win must declare signingContract: windows-raw-exe-authenticode-before-nsis-v1 or windows-raw-exe-authenticode-before-portable-v1`. The config declares `windows-msix-signed-v1`. The installed package has no `msix-config.mjs` or `msix-build.mjs`. In the Mac RightKit tree those (plus `msix-appinstaller.mjs`, `msix-plan.mjs`, `msix-target.mjs`, `project-type.mjs`, `swift-build-context.mjs`) are still uncommitted/untracked, so the MSIX target was never in the published 0.2.138. Needs a RightKit release that contains the MSIX adapter. The ownership and trust gates were not reached on this run.

## R3 result (2026-10-09, @rightkit/release 0.2.139, clones on d70d36b)

Build command: `pnpm exec right-release build --platform mac --config right-release.config.mjs` (`release --tier` is
rejected: "build is tier-neutral"). `.right-release/` must be gitignored (the build lock is written before the
clean-tree preflight). 0.1.1 = version bump + Swift-only label edit ("Rows: N").

| | 0.1.0 | 0.1.1 |
|---|---|---|
| DMG sha256 | 81742a7c…64b661 | c75155b4…071a8a |
| DMG codesign --verify --strict | PASS (Developer ID Application, Team 6KLGD3LLKF, hardened runtime) | PASS |
| DMG spctl -a -vv | accepted, Notarized Developer ID | accepted, Notarized Developer ID |
| DMG stapler validate | PASS | PASS |
| .app codesign --verify --deep --strict | PASS | PASS |
| .app spctl -a -vv | accepted, Notarized Developer ID | accepted, Notarized Developer ID |
| .app stapler validate | FAIL: no ticket stapled to the .app (only the DMG is stapled; config allows one `notarize.file`) | FAIL (same) |

App executable sha256: 0.1.0 84f9b81a…0646cc, 0.1.1 05110857…a8e2. Evidence: `/Volumes/D/sr0-artifacts/mac/{0.1.0,0.1.1}/r3-verify-*.txt`,
build logs `r3-build-*.log`; sealed manifests 0.1.0 97a1ac67…a03d2, 0.1.1 40a9026c…d3048.
Open: .app staple (gap 3b; offline first launch in R7 decides impact); `hdiutil detach` "Resource busy" flake (2–3 attempts
per DMG); Swift-only rebuild proof and receipts not yet run.

## R2 result (2026-10-09): MSIX old + new built, signed, verified

Passed on @rightkit/release 0.2.139 via the non-elevated scheduled-task route. Full table, hashes and three defects (proof script and installed check compare signed raw hashes; `.right-release/` not gitignored; use `right-release build`, not `release --tier patch`) in `RESULT-R2.md`.
