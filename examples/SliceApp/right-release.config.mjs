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
//   - mac: release.mjs signs `sign.prePackageFiles` without `--entitlements`, and its mac branch requires a
//     notarized archive (`notarize.file`) produced by `package`. The app needs no entitlements (no sandbox), so
//     the empty Mac/SliceApp.entitlements is only a record of that.
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

const WIN_APPX = path.join("dist", "win", `SliceApp_${MSIX_VERSION}_x64.msix`);
const MAC_APP = path.join("dist", "mac", "SliceApp.app");
const MAC_ZIP = path.join("dist", "mac", "SliceApp.zip");

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
      // Build the executable and assemble SliceApp.app (Info.plist from swift-package.json). No signing here.
      prePackage: { cmd: "sh", args: ["scripts/prepackage-mac.sh"] },
      sign: { prePackageFiles: [MAC_APP] },
      // Zip after signing (package runs after sign), then notarize and staple the archive.
      package: { cmd: "ditto", args: ["-c", "-k", "--keepParent", MAC_APP, MAC_ZIP] },
      notarize: { file: MAC_ZIP, profile: "apple-dev-notary" },
      artifacts: [MAC_ZIP],
      hardening: [MAC_ZIP],
      installer: { artifacts: [{ file: MAC_ZIP, key: "sliceapp/installers/mac/current/SliceApp.zip" }] },
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
          publisher: "CN=Damned Ventures LLC, O=Damned Ventures LLC, L=TODO-confirm, S=TODO-confirm, C=US",
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
        // Virtualization is explicit (required by the schema). Both are "enabled" on purpose:
        //  - fileSystemWrite "enabled": the app never writes its install folder; if an install-folder write ever
        //    happens, the write lands in the per-package store (removed on uninstall) instead of failing or
        //    needing the restricted unvirtualizedResources capability, which "disabled" would add.
        //  - registryWrite "enabled": the app writes no registry values. Any registry write stays inside the
        //    package hive and is removed on uninstall.
        //  User data is in %LOCALAPPDATA%\SliceApp, outside both virtualized areas, so it survives uninstall.
        virtualization: { fileSystemWrite: "enabled", registryWrite: "enabled" },
        assets: {
          storeLogo: "Windows/Assets/StoreLogo.png",
          square150: "Windows/Assets/Square150x150Logo.png",
          square44: "Windows/Assets/Square44x44Logo.png",
        },
        runtime: { dlls: SWIFT_RUNTIME_DLLS, systemDlls: [] },
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
