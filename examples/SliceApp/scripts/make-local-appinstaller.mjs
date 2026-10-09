#!/usr/bin/env node
// F8: write a LOCAL .appinstaller feed file for SliceApp so the Windows Sandbox can exercise the real App Installer
// update route (install via the .appinstaller, then OnLaunch update check finds a newer feed) without touching R2.
//
//   node make-local-appinstaller.mjs --msix <SliceApp_0.1.1.0_x64.msix> --version 0.1.1.0 --out <feed dir> \
//        [--base https://localhost:8443/sliceapp] [--hours 0]
// Writes <out>/SliceApp.appinstaller (Uri = <base>/SliceApp.appinstaller, MainPackage Uri = <base>/<msix file name>) and
// copies nothing else: place the .msix next to it yourself. Name, publisher, architecture and update settings come
// from right-release.config.mjs through RightKit's own generateAppInstaller (read-only import), so the feed matches
// the sealed package identity. Local feed uses https because the generator (and the config validator) require it.
// It never uploads anything.
import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const one = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const msix = one("--msix"), version = one("--version"), out = one("--out");
if (!msix || !version || !out) { console.error("usage: make-local-appinstaller.mjs --msix <file> --version <a.b.c.d> --out <dir> [--base <https url>]"); process.exit(2); }
const base = one("--base", "https://localhost:8443/sliceapp").replace(/\/$/, "");
const rightkit = process.env.RIGHTKIT_RELEASE_DIR ?? path.resolve(here, "../../../../tools/rightkit/packages/release");
const { generateAppInstaller } = await import(pathToFileURL(path.join(rightkit, "msix-appinstaller.mjs")).href);
const config = (await import(pathToFileURL(path.join(here, "..", "right-release.config.mjs")).href)).default;
const win = config.targets.win.msix;
const file = path.basename(msix);
const xml = generateAppInstaller({
  uri: `${base}/SliceApp.appinstaller`,
  msixUri: `${base}/${file}`,
  name: win.identity.name, publisher: win.identity.publisher, version, architecture: win.identity.architecture,
  hoursBetweenUpdateChecks: Number(one("--hours", "0")),
  showPrompt: win.appInstaller.showPrompt, updateBlocksActivation: win.appInstaller.updateBlocksActivation,
});
mkdirSync(out, { recursive: true });
writeFileSync(path.join(out, "SliceApp.appinstaller"), xml);
console.log(`wrote ${path.join(out, "SliceApp.appinstaller")} (version ${version}, MainPackage ${base}/${file})`);
