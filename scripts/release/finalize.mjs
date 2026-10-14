// right-git releaseChain entry points for SliceApp: signs and finalizes the EXACT unsigned candidate built earlier in the same run.
//   windows   unpack the unsigned MSIX candidate, verify it against its seal, re-pack and sign it with @rightkit/release (buildMsix -> sign-windows)
//   macos     extract the unsigned .app from the candidate DMG, sign + notarize + staple it, rebuild the DMG, sign + notarize + staple that
//   qualify   verify the finalized Windows package (seal, Authenticode via RightKit) and install/uninstall it on the runner
//   verify-evidence | publish   fail closed: SliceApp candidates never publish (admission forces publish=false)
// This file only orchestrates. Signing, notarization, stapling, DMG and MSIX mechanics all come from @rightkit/release.
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const env = process.env;
const repo = path.resolve(import.meta.dirname, "..", "..");
const appRoot = path.join(repo, "examples", "SliceApp");
const release = path.join(repo, "node_modules", "@rightkit", "release");
const mode = process.argv[2];

const need = (name) => { const v = env[name]; if (!v) throw new Error(`${name} is not set`); return v; };
const sha256 = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
const rk = (name) => import(pathToFileURL(path.join(release, name)).href);
const run = (cmd, args, options = {}) => {
  const r = spawnSync(cmd, args, { stdio: "inherit", ...options });
  if (r.error || r.status !== 0) throw new Error(`${path.basename(cmd)} ${args.slice(0, 2).join(" ")} failed (${r.status ?? r.error?.message})`);
};
const capture = (cmd, args) => {
  const r = spawnSync(cmd, args, { encoding: "utf8" });
  if (r.error || r.status !== 0) throw new Error(`${path.basename(cmd)} ${args.slice(0, 2).join(" ")} failed: ${r.stderr || r.stdout || r.error?.message}`);
  return r.stdout;
};
const findFile = (root, name) => {
  const hits = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name === name) hits.push(full);
    }
  };
  if (existsSync(root)) walk(root);
  if (hits.length !== 1) throw new Error(`expected exactly one ${name} under ${root}, found ${hits.length}`);
  return hits[0];
};
const tmp = (label) => mkdtempSync(path.join(env.RUNNER_TEMP || env.TMPDIR || "/tmp", `${label}-`));
const log = (message) => console.log(`finalize: ${message}`);
const writeJson = (file, value) => { mkdirSync(path.dirname(file), { recursive: true }); writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`); };

// buildMsix reads the signer subject with Get-AuthenticodeSignature, which cannot read .msix on the hosted runner (empty subject).
// Read the same subject from the package's AppxSignature.p7x (PKCX header + PKCS#7) instead; buildMsix still compares it with the manifest Publisher.
const readMsixSignerSubject = (file) => {
  const script = [
    "$ErrorActionPreference = 'Stop'",
    "Add-Type -AssemblyName System.IO.Compression.FileSystem",
    `$zip = [System.IO.Compression.ZipFile]::OpenRead('${file.replace(/'/g, "''")}')`,
    "try { $entry = $zip.GetEntry('AppxSignature.p7x'); if (-not $entry) { throw 'AppxSignature.p7x missing' }",
    "$ms = New-Object System.IO.MemoryStream; $s = $entry.Open(); $s.CopyTo($ms); $s.Dispose(); $b = $ms.ToArray() } finally { $zip.Dispose() }",
    "$cms = New-Object System.Security.Cryptography.Pkcs.SignedCms",
    "$cms.Decode($b[4..($b.Length - 1)])",
    "Write-Output $cms.SignerInfos[0].Certificate.Subject",
  ].join("; ");
  const r = spawnSync("pwsh", ["-NoProfile", "-NonInteractive", "-Command", script], { encoding: "utf8" });
  if (r.status !== 0) console.error(`signer subject read failed: ${r.stderr || r.stdout}`);
  console.log(`MSIX signer subject: ${String(r.stdout ?? "").trim()}`);
  return r.status === 0 ? String(r.stdout ?? "").trim() : "";
};

async function finalizeWindows() {
  const unsignedRoot = need("RIGHT_GIT_UNSIGNED_CANDIDATE_ROOT");
  const outRoot = path.resolve(need("RIGHT_GIT_FINALIZED_WINDOWS_ROOT"));
  const revision = need("RIGHT_GIT_SOURCE_REVISION");
  const msix = findFile(unsignedRoot, "SliceApp_0.1.1.0_x64.msix");
  const seal = JSON.parse(readFileSync(findFile(unsignedRoot, "msix-seal.json"), "utf8"));
  const identity = JSON.parse(readFileSync(findFile(unsignedRoot, "build-identity.json"), "utf8"));
  const unsignedSha = sha256(msix);
  if (seal.signed !== false) throw new Error("candidate seal says signed; expected an unsigned candidate");
  if (unsignedSha !== seal.msix.sha256 || unsignedSha !== identity.msixSha256) throw new Error(`unsigned MSIX sha256 ${unsignedSha} differs from the candidate seal/identity`);
  if (identity.sourceRevision !== revision) throw new Error(`candidate was built from ${identity.sourceRevision}, expected ${revision}`);
  log(`exact unsigned candidate ${path.basename(msix)} sha256 ${unsignedSha}`);

  const sdkTools = env.AZURE_SIGNTOOL_PATH ? path.dirname(env.AZURE_SIGNTOOL_PATH) : null;
  const makeappx = env.MAKEAPPX_PATH || (sdkTools && existsSync(path.join(sdkTools, "makeappx.exe")) ? path.join(sdkTools, "makeappx.exe") : null);
  const found = makeappx ? { toolPath: makeappx } : (await rk("preflight.mjs")).findWindowsSdkTool("makeappx.exe");
  if (!found?.toolPath) throw new Error("makeappx.exe not found on the signing runner");
  env.MAKEAPPX_PATH = found.toolPath;

  // Unpack the candidate and prove its payload is byte-identical to what the candidate job sealed.
  const unpacked = path.join(tmp("unsigned-msix"), "payload");
  run(found.toolPath, ["unpack", "/p", msix, "/d", unpacked, "/o"]);
  for (const entry of seal.payload) {
    const file = path.join(unpacked, ...entry.name.split("/"));
    if (!existsSync(file) || sha256(file) !== entry.sha256) throw new Error(`unpacked candidate differs from its seal at ${entry.name}`);
  }
  log(`candidate payload matches the seal (${seal.payload.length} files)`);

  // RightKit re-packs from a flat stage directory: the payload files exactly as sealed.
  const stage = path.join(tmp("msix-stage"), "stage");
  mkdirSync(stage, { recursive: true });
  const sealed = new Set(seal.payload.map((entry) => entry.name));
  for (const entry of readdirSync(unpacked, { withFileTypes: true })) {
    if (entry.isFile() && sealed.has(entry.name) && entry.name !== "AppxManifest.xml") cpSync(path.join(unpacked, entry.name), path.join(stage, entry.name));
  }

  const config = (await import(pathToFileURL(path.join(appRoot, "right-release.config.mjs")).href)).default;
  const { msixBuildOptions } = await rk("msix-target.mjs");
  const { buildMsix } = await rk("msix-build.mjs");
  const receipts = path.join(outRoot, "receipts");
  const out = path.join(outRoot, path.basename(msix));
  const options = msixBuildOptions({ root: appRoot, target: config.targets.win, app: config.app, sign: true, receipts: { dir: receipts } });
  const built = buildMsix({
    ...options,
    stageDir: stage,
    out,
    workDir: path.join(tmp("msix-root"), "root"),
    appInstaller: { ...options.appInstaller, out: path.join(outRoot, "SliceApp.appinstaller.placeholder-uris") },
  }, { log: (event) => console.log(JSON.stringify(event)), readSubject: readMsixSignerSubject });

  // The re-packed package must differ from the candidate only by signatures.
  const signedSeal = JSON.parse(readFileSync(built.seal, "utf8"));
  const before = new Map(seal.payload.map((entry) => [entry.name, entry.sha256]));
  const changed = [];
  for (const entry of signedSeal.payload) {
    if (!before.has(entry.name)) throw new Error(`signed package has a file the candidate lacked: ${entry.name}`);
    if (before.get(entry.name) !== entry.sha256) changed.push(entry.name);
  }
  if (signedSeal.payload.length !== seal.payload.length) throw new Error("signed package payload file count differs from the candidate");
  const nonPe = changed.filter((name) => !/\.(exe|dll)$/i.test(name));
  if (nonPe.length) throw new Error(`non-PE files differ from the candidate: ${nonPe.join(", ")}`);
  log(`only signed PE files changed (${changed.length}); identity ${signedSeal.identity.name} ${signedSeal.identity.version}`);

  writeJson(path.join(outRoot, "finalize-evidence.json"), {
    schema: 1, platform: "windows", architecture: "x86_64", sourceRevision: revision,
    unsignedCandidate: { file: path.basename(msix), sha256: unsignedSha },
    signed: { file: path.basename(out), sha256: sha256(out), sizeBytes: statSync(out).size },
    signedPeFiles: changed,
    authenticode: "verified by sign-windows.mjs (signtool verify /pa, subject Damned Ventures LLC, timestamped) for each signed PE and the MSIX",
    receipts: readdirSync(receipts).sort(),
  });
  log(`signed ${path.basename(out)} sha256 ${sha256(out)}`);
}

async function finalizeMacos() {
  const unsignedRoot = need("RIGHT_GIT_UNSIGNED_CANDIDATE_ROOT");
  const outRoot = path.resolve(need("RIGHT_GIT_FINALIZED_MACOS_ROOT"));
  const revision = need("RIGHT_GIT_SOURCE_REVISION");
  const dmg = findFile(unsignedRoot, "SliceApp_0.1.1_arm64.dmg");
  const identity = JSON.parse(readFileSync(findFile(unsignedRoot, "build-identity.json"), "utf8"));
  const unsignedSha = sha256(dmg);
  if (unsignedSha !== identity.dmgSha256) throw new Error(`unsigned DMG sha256 ${unsignedSha} differs from the candidate identity ${identity.dmgSha256}`);
  if (identity.sourceRevision !== revision) throw new Error(`candidate was built from ${identity.sourceRevision}, expected ${revision}`);
  log(`exact unsigned candidate ${path.basename(dmg)} sha256 ${unsignedSha}`);

  const work = tmp("mac-finalize");
  const mount = path.join(work, "mnt");
  mkdirSync(mount);
  const app = path.join(work, "SliceApp.app");
  run("hdiutil", ["attach", dmg, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount]);
  try { run("/usr/bin/ditto", [path.join(mount, "SliceApp.app"), app]); }
  finally { spawnSync("hdiutil", ["detach", mount, "-force"], { stdio: "inherit" }); }
  const exeSha = sha256(path.join(app, "Contents", "MacOS", "SliceApp"));
  if (exeSha !== identity.executableSha256) throw new Error(`candidate app executable ${exeSha} differs from the candidate identity ${identity.executableSha256}`);
  log("candidate app executable matches the candidate identity");

  const receipts = path.join(outRoot, "receipts");
  mkdirSync(receipts, { recursive: true });
  const { signAndNotarizeMacApp, discoverNestedCode } = await rk("swift-mac-app.mjs");
  // Inside-out Developer ID signing, then notarize and staple the app before it is packaged (RightKit's swiftpm mac order).
  const result = signAndNotarizeMacApp({
    app, nested: discoverNestedCode(app, "SliceApp"), entitlements: path.join(appRoot, "Mac", "SliceApp.entitlements"),
    receiptDir: receipts, notarize: true,
  });
  if (result.zip) rmSync(result.zip, { force: true });
  run("xcrun", ["stapler", "validate", app]);

  const finalDmg = path.join(outRoot, path.basename(dmg));
  const rr = path.join(release, "cli", "right-release.mjs");
  run(process.execPath, [rr, "dmg", "build", "--app", app, "--out", finalDmg, "--volname", "SliceApp", "--background", path.join(appRoot, "Mac/dmg/background.tiff"),
    "--icon-size", "128", "--app-position", "158,231", "--applications-position", "492,231", "--window", "660,400"]);
  run(process.execPath, [path.join(release, "sign-macos.mjs"), "--receipt", path.join(receipts, "dmg-sign.receipt.json"), finalDmg]);
  run(process.execPath, [path.join(release, "notarize-macos.mjs"), "--receipt", path.join(receipts, "dmg-notarize.receipt.json"), finalDmg]);

  const { validateNotarizationReceipt } = await rk("macos-notarization.mjs");
  validateNotarizationReceipt({ receiptPath: path.join(receipts, "dmg-notarize.receipt.json"), archive: finalDmg });
  run("codesign", ["--verify", "--strict", "--verbose=2", finalDmg]);
  run("xcrun", ["stapler", "validate", finalDmg]);
  // Open the finished DMG and assess the app Gatekeeper would run.
  const check = path.join(work, "final-mnt");
  mkdirSync(check);
  run("hdiutil", ["attach", finalDmg, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", check]);
  try {
    const mounted = path.join(check, "SliceApp.app");
    run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", mounted]);
    run("spctl", ["--assess", "--type", "execute", "--verbose=4", mounted]);
    run("xcrun", ["stapler", "validate", mounted]);
  } finally { spawnSync("hdiutil", ["detach", check, "-force"], { stdio: "inherit" }); }

  writeJson(path.join(outRoot, "finalize-evidence.json"), {
    schema: 1, platform: "macos", architecture: "arm64", sourceRevision: revision,
    unsignedCandidate: { file: path.basename(dmg), sha256: unsignedSha, executableSha256: exeSha },
    signed: { file: path.basename(finalDmg), sha256: sha256(finalDmg), sizeBytes: statSync(finalDmg).size },
    checks: ["codesign --verify --strict (dmg)", "stapler validate (app, dmg)", "codesign --verify --deep --strict (app in dmg)", "spctl --assess --type execute (app in dmg)", "notarization receipts validated by RightKit"],
    receipts: readdirSync(receipts).sort(),
  });
  log(`signed ${path.basename(finalDmg)} sha256 ${sha256(finalDmg)}`);
}

async function qualify() {
  const root = path.resolve(need("RIGHT_GIT_FINALIZED_WINDOWS_ROOT"));
  const evidenceRoot = path.resolve(need("RIGHT_GIT_QUALIFICATION_EVIDENCE_ROOT"));
  const msix = findFile(root, "SliceApp_0.1.1.0_x64.msix");
  const seal = JSON.parse(readFileSync(findFile(root, "msix-seal.json"), "utf8"));
  const sha = sha256(msix);
  if (seal.signed !== true || sha !== seal.msix.sha256) throw new Error(`finalized MSIX sha256 ${sha} does not match its signed seal`);
  run(process.execPath, [path.join(release, "sign-windows.mjs"), "--verify-only", msix]);
  const name = seal.identity.name;
  const script = [
    "$ErrorActionPreference = 'Stop'",
    `Add-AppxPackage -Path '${msix.replace(/'/g, "''")}'`,
    `$p = Get-AppxPackage -Name '${name}'`,
    "if (-not $p) { throw 'package not registered after install' }",
    "if (-not (Test-Path (Join-Path $p.InstallLocation 'SliceApp.exe'))) { throw 'SliceApp.exe missing from the install location' }",
    "Write-Output ('installed ' + $p.PackageFullName)",
    "Remove-AppxPackage -Package $p.PackageFullName",
    `if (Get-AppxPackage -Name '${name}') { throw 'package still registered after removal' }`,
  ].join("; ");
  run("pwsh", ["-NoProfile", "-NonInteractive", "-Command", script]);
  writeJson(path.join(evidenceRoot, "installed-qualification.json"), {
    schema: 1, sourceRevision: need("RIGHT_GIT_SOURCE_REVISION"), version: need("RIGHT_GIT_RELEASE_VERSION"),
    msix: { file: path.basename(msix), sha256: sha }, authenticode: "verified by sign-windows.mjs --verify-only",
    installed: true, uninstalled: true, launched: false,
  });
}

if (mode === "windows") await finalizeWindows();
else if (mode === "macos") await finalizeMacos();
else if (mode === "qualify") await qualify();
else if (mode === "verify-evidence" || mode === "publish") throw new Error("SliceApp release candidates are never published; admission forces publish=false");
else throw new Error(`usage: finalize.mjs windows|macos|qualify|verify-evidence|publish (got ${mode})`);
