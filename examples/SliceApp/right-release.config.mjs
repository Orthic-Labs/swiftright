// SliceApp release contract (examples/SliceApp). Project type: swiftpm. Swift steps run from
// Package.swift and swift-package.json; right-release owns sign, MSIX pack, App Installer route, and seal.
//
// Status: PREP, not yet run. Written against @rightkit/release 0.2.138, which is not published yet (the local
// tools tree is 0.2.137). Nothing here signs, packages, or uploads by itself. Every TODO must be settled before
// a sealed build; the publisher and the App Installer URLs are placeholders and must not reach a real signer or R2.
//
// Commands: see PACKAGING.md.
//
// Shared-tooling gaps the release CLI still has for this app (see PACKAGING.md "Gaps"):
//   - mac: release.mjs has no entitlements key for the mac target and signs `sign.prePackageFiles` (the DMG
//     container) without `--entitlements`. The app's entitlements are applied in prePackage by
//     `swift-package mac-app --sign`, which reads swift-package.json `mac.entitlements`. SliceApp requests none, so
//     Mac/SliceApp.entitlements is an empty record. A future entitlement must be added to that path, not here.
import path from "node:path";

const VERSION = "0.1.0";
const MSIX_VERSION = "0.1.0.0";

// Swift 6.4.0 Windows toolchain used for the build-proof on the Windows host (2026-10-09).
const SWIFT_RUNTIME_BIN = "C:\\Users\\adrds\\AppData\\Local\\Programs\\Swift\\Runtimes\\6.4.0\\usr\\bin";

// Swift runtime DLL inventory: the import closure of SliceApp.exe, derived with `dumpbin /dependents`
// (scripts/build-windows.ps1, output "swift runtime DLLs"). Each one must ship in the MSIX payload, and the
// stage fails closed on any import that is neither here, nor a Windows system DLL, nor a declared dependency.
// Re-derive this list whenever the toolchain or the imports change.
const SWIFT_RUNTIME_DLLS = [
  "_FoundationICU.dll",
  "BlocksRuntime.dll",
  "dispatch.dll",
  "Foundation.dll",
  "FoundationEssentials.dll",
  "FoundationInternationalization.dll",
  "MSVCP140.dll",
  "swift_Concurrency.dll",
  "swift_RegexParser.dll",
  "swift_StringProcessing.dll",
  "swiftCore.dll",
  "swiftCRT.dll",
  "swiftDispatch.dll",
  "swiftObservation.dll",
  "swiftSynchronization.dll",
  "swiftWinSDK.dll",
  "VCRUNTIME140.dll",
  "VCRUNTIME140_1.dll",
];

// The renderer is loaded dynamically (Bridge.load: path arg, $SWIFTRIGHT_RENDER_DLL, else "swiftright_render.dll",
// resolved beside the exe), so it is never in the exe's import table and the closure walk cannot find it. It ships
// by explicit declaration: scripts/prepackage-windows.ps1 hash-checks it against Windows/renderer-pin.json and stages
// it via swift-package.json windows.include (which also walks its import closure). Declaring it here makes
// verifyPayloadInventory fail closed if it is ever missing from the payload.
const RENDERER_DLL = "swiftright_render.dll";
const PAYLOAD_DLLS = [...SWIFT_RUNTIME_DLLS, RENDERER_DLL];
// Windows-owned DLL the renderer imports that RightKit's built-in system list does not include (OS ICU, System32).
const EXTRA_SYSTEM_DLLS = ["icuuc.dll"];

const WIN_APPX = path.join("dist", "win", `SliceApp_${MSIX_VERSION}_x64.msix`);
const MAC_APP = path.join("dist", "mac", "SliceApp.app");
const MAC_DMG = path.join("dist", "mac", `SliceApp_${VERSION}_arm64.dmg`);

export default {
  schema: 1,
  app: "sliceapp",
  displayName: "SliceApp",
  version: VERSION,
  projectType: "swiftpm",
  packageManager: "pnpm",
  // SliceApp is an example. Private products publish to R2 through RightApps; this placeholder is not a decision.
  distribution: { provider: "r2-rightapps" },
  buildInputs: {
    include: [
      "right-release.config.mjs",
      "swift-package.json",
      "package.json",
      "Package.swift",
      "Sources/**",
      "Windows/**",
      "Mac/**",
      "scripts/**",
    ],
    exclude: [".build/**", "dist/**", "**/*.test.*"],
  },
  checks: [],
  targets: {
    mac: {
      signed: true,
      signingContract: "macos-developer-id-notarized-portable-v1",
      // Order (@rightkit/release >= 0.2.142): prePackage (swift build, assemble + Developer ID sign the .app with its
      // entitlements via swift-package mac-app --sign; no DMG here, preflight rejects a prePackage DMG) -> sign the
      // .app inside-out (sign.prePackageFiles) -> notarize + staple the .app (appBeforePackage) -> right-release builds
      // the DMG itself from the stapled app (targets.mac.dmg), signs it, then notarizes + staples the DMG.
      prePackage: { cmd: "sh", args: ["scripts/prepackage-mac.sh"] },
      sign: { prePackageFiles: [MAC_APP] },
      dmg: {
        volname: "SliceApp",
        background: "Mac/dmg/background.tiff",
        window: "660,400",
        iconSize: 128,
        appPosition: "158,231",
        applicationsPosition: "492,231",
      },
      // release.mjs notarizes this file; notarize-macos.mjs staples a .dmg container itself.
      notarize: { app: MAC_APP, appBeforePackage: true, file: MAC_DMG, profile: "apple-dev-notary" },
      artifacts: [MAC_DMG],
      hardening: [MAC_DMG],
      installer: { artifacts: [{ file: MAC_DMG, key: "sliceapp/installers/mac/current/SliceApp.dmg" }] },
    },
    win: {
      signed: true,
      signingContract: "windows-msix-signed-v1",
      projectType: "swiftpm",
      // Build + mt.exe + dumpbin closure check, then `swift-package windows-stage` into .build/msix-stage.
      // Runs on the Windows host only (native-host invariant).
      prePackage: {
        cmd: "powershell",
        args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "scripts/prepackage-windows.ps1"],
        timeoutMs: 40 * 60 * 1000,
      },
      msix: {
        stageDir: path.join(".build", "msix-stage"),
        out: WIN_APPX,
        identity: {
          // Package identity name: letters, digits, '.' and '-' only (validateMsixIdentity).
          name: "OrthicLabs.SliceApp",
          // TODO(identity): replace with the exact subject of the provisioned Azure Artifact Signing certificate,
          // confirmed natively on the signing host. MSIX requires Publisher to equal the signer subject byte for
          // byte. The CN must stay "CN=Damned Ventures LLC" (msix-build.mjs MSIX_SIGNER_SUBJECT).
          publisher: "CN=Damned Ventures LLC, O=Damned Ventures LLC, L=new york, S=New York, C=US",
          publisherDisplayName: "Orthic Labs",
          displayName: "SliceApp",
          description: "SwiftRight packaging example: shared editor screen on macOS and Windows.",
          version: MSIX_VERSION,
          architecture: "x64",
          executable: "SliceApp.exe",
        },
        // No capabilities: the app reads and writes only %LOCALAPPDATA%\SliceApp (runFullTrust is added by the tool).
        capabilities: [],
        minWindowsVersion: "10.0.19041.0",
        maxWindowsVersionTested: "10.0.26100.0",
        // Virtualization is explicit (required by the schema).
        //  - fileSystemWrite "disabled": REQUIRED for the data contract. Per Microsoft's flexible-virtualization doc
        //    (learn.microsoft.com/windows/msix/desktop/flexible-virtualization, "Default MSIX behavior", AppData
        //    row), on Windows > 1809 every NEWLY CREATED file under the user's AppData is written to a private
        //    per-user, per-app location and is REMOVED ON UNINSTALL. rows.json is created by the app under
        //    %LOCALAPPDATA%\SliceApp, so with "enabled" it would be virtualized and deleted on uninstall (the earlier
        //    claim here was wrong). "disabled" (FilesystemWriteVirtualization=disabled with the restricted capability
        //    unvirtualizedResources, which msix-build.mjs adds) sends AppData writes to the real path, visible
        //    outside the package and NOT cleaned up on uninstall: the behaviour the doc describes for save data.
        //    Cost: restricted capability (fine for sideload/App Installer distribution, needs Store approval
        //    otherwise) and it is not fine-grained. Windows 11's finer ExcludedDirectories is not emitted by
        //    RightKit's manifest generator; revisit if it is added. Verified only by the physical-path checks
        //    in PACKAGING.md (R5), not yet run.
        //  - registryWrite "enabled": the app writes no registry values; any write stays in the package hive.
        virtualization: { fileSystemWrite: "disabled", registryWrite: "enabled" },
        assets: {
          storeLogo: "Windows/Assets/StoreLogo.png",
          square150: "Windows/Assets/Square150x150Logo.png",
          square44: "Windows/Assets/Square44x44Logo.png",
        },
        runtime: { dlls: PAYLOAD_DLLS, systemDlls: EXTRA_SYSTEM_DLLS },
        appInstaller: {
          // TODO(updater): placeholder R2 public host. Replace with the RightApps R2 public URL for SliceApp before
          // any publication. Both URLs must be https (validator). Do not publish this placeholder.
          uri: "https://TODO-R2-PUBLIC-HOST.invalid/sliceapp/windows/SliceApp.appinstaller",
          msixUri: `https://TODO-R2-PUBLIC-HOST.invalid/sliceapp/windows/SliceApp_${MSIX_VERSION}_x64.msix`,
          out: path.join("dist", "win", "SliceApp.appinstaller"),
          hoursBetweenUpdateChecks: 8,
          showPrompt: false,
          updateBlocksActivation: false,
        },
      },
      updater: { kind: "appinstaller", artifacts: [] },
      // Do not declare sign.prePackageFiles or sign.files for MSIX: the msix step signs payload PE files and the
      // package itself (validateMsixTarget rejects both keys).
      artifacts: [WIN_APPX, path.join("dist", "win", "SliceApp.appinstaller")],
      hardening: [WIN_APPX],
      installer: { artifacts: [{ file: WIN_APPX, key: "sliceapp/installers/windows/current/SliceApp_x64.msix" }] },
    },
  },
};
