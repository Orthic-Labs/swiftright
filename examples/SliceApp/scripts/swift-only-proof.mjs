#!/usr/bin/env node
// Swift-only-edit proof for SliceApp (F1/R2). Shows that a Swift-only change between the old (0.1.0) and new (0.1.1)
// package left the renderer untouched and compiled no Rust. File checks only; needs the SliceApp node_modules (@rightkit/release, zip reader).
//
//   node swift-only-proof.mjs --old-seal <msix-seal.json> --new-seal <msix-seal.json> \
//        --old-commit <sha> --new-commit <sha> --repo <clone dir> --build-log <old.log> --build-log <new.log> \
//        [--old-msix <0.1.0.msix> --new-msix <0.1.1.msix>] [--pin ../Windows/renderer-pin.json]
// RightKit Authenticode-signs every PE (exe/dll) before packing, so the raw sha256 of a packaged PE differs per build.
// With --old-msix/--new-msix, PE payload entries are compared by Authenticode digest (sha256 of the PE image excluding
// the CheckSum field, the Certificate Table directory entry and the certificate data; computed here, no deps) and
// every other entry by raw sha256. Without them the seals' raw hashes are used (only valid for unsigned payloads).
// Passes only when ALL hold:
//   1. both packages carry swiftright_render.dll with the same digest, equal to the pin's authenticodeSha256
//      (or sha256 when the package is unsigned);
//   2. every other payload file except SliceApp.exe and the version-bearing AppxManifest.xml is identical between the two (runtime DLLs unchanged);
//      SliceApp.exe must differ (otherwise the edit never reached the package);
//   3. `git diff --name-only old..new` touches no Rust inputs (render/**, *.rs, Cargo.toml, Cargo.lock, rust-toolchain*);
//   4. no build log mentions a Rust compile (cargo, rustc, "Compiling <crate>" lines).
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readZipEntry } from "@rightkit/release/msix-signer.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const one = (n) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : undefined; };
const many = (n) => args.flatMap((a, i) => (a === n ? [args[i + 1]] : []));
const need = (n, v) => { if (!v) { console.error(`swift-only-proof: ${n} is required`); process.exit(2); } return v; };
const oldSeal = need("--old-seal", one("--old-seal"));
const newSeal = need("--new-seal", one("--new-seal"));
const oldCommit = need("--old-commit", one("--old-commit"));
const newCommit = need("--new-commit", one("--new-commit"));
const repo = need("--repo", one("--repo"));
const logs = many("--build-log");
if (logs.length === 0) need("--build-log", undefined);
const pin = JSON.parse(readFileSync(one("--pin") ?? path.join(here, "..", "Windows", "renderer-pin.json"), "utf8"));

const failures = [];

// Authenticode digest of a PE/COFF image (SHA-256), per the Authenticode PE spec. Returns null if buf is not a PE.
// Kept local: the signature-independent PE hash has no RightKit owner yet (bogusyogi/rightkit#445). Remove when #445 lands.
export function authenticodeDigest(buf) {
  if (buf.length < 0x40 || buf.readUInt16LE(0) !== 0x5a4d) return null;
  const pe = buf.readUInt32LE(0x3c);
  if (pe + 24 > buf.length || buf.readUInt32LE(pe) !== 0x4550) return null;
  const nSec = buf.readUInt16LE(pe + 6), optSize = buf.readUInt16LE(pe + 20), opt = pe + 24;
  const magic = buf.readUInt16LE(opt);
  if (magic !== 0x10b && magic !== 0x20b) return null;
  const checksum = opt + 64, dirs = opt + (magic === 0x20b ? 112 : 96), certDir = dirs + 32;
  const sizeOfHeaders = buf.readUInt32LE(opt + 60);
  const certOff = buf.readUInt32LE(certDir), certSize = buf.readUInt32LE(certDir + 4);
  const h = createHash("sha256");
  h.update(buf.subarray(0, checksum));
  h.update(buf.subarray(checksum + 4, certDir));
  h.update(buf.subarray(certDir + 8, sizeOfHeaders));
  const secs = [];
  for (let i = 0; i < nSec; i++) {
    const o = opt + optSize + i * 40;
    secs.push({ size: buf.readUInt32LE(o + 16), ptr: buf.readUInt32LE(o + 20) });
  }
  secs.sort((x, y) => x.ptr - y.ptr);
  let hashed = sizeOfHeaders;
  for (const s of secs) {
    if (s.size === 0) continue;
    h.update(buf.subarray(s.ptr, s.ptr + s.size));
    hashed += s.size;
  }
  const end = certSize > 0 ? certOff : buf.length; // trailing data other than the certificate table
  if (end > hashed) h.update(buf.subarray(hashed, end));
  return h.digest("hex");
}

const sha = (b) => createHash("sha256").update(b).digest("hex");
// Entries are read through RightKit readZipEntry; its 4 MiB default cap is lifted because SwiftRight PEs exceed it.
const MAX_ENTRY_BYTES = 512 * 1024 * 1024;
const payload = (seal, msix) => new Map(JSON.parse(readFileSync(seal, "utf8")).payload.map((e) => {
  const buf = msix ? readZipEntry(msix, e.name, { maxBytes: MAX_ENTRY_BYTES }) : null;
  if (!buf) return [e.name.toLowerCase(), e.sha256.toLowerCase()];
  const ac = authenticodeDigest(buf);
  return [e.name.toLowerCase(), ac ? `authenticode:${ac}` : sha(buf)];
}));
const a = payload(oldSeal, one("--old-msix")), b = payload(newSeal, one("--new-msix"));
const rname = pin.file.toLowerCase();
const pinDigest = (pin.authenticodeSha256 ? `authenticode:${pin.authenticodeSha256.toLowerCase()}` : pin.sha256.toLowerCase());
for (const [label, m] of [["old", a], ["new", b]]) {
  if (m.get(rname) !== pinDigest) failures.push(`${label} package: ${pin.file} is ${m.get(rname) ?? "ABSENT"}, pin is ${pinDigest}`);
}
const names = new Set([...a.keys(), ...b.keys()]);
const changed = [];
for (const n of [...names].sort()) {
  if (a.get(n) !== b.get(n)) changed.push(n);
}
// AppxManifest.xml carries the package version, so it legitimately differs on a version bump.
for (const n of changed) if (n !== "sliceapp.exe" && n !== "appxmanifest.xml") failures.push(`payload file changed or added/removed between old and new: ${n}`);
if (!changed.includes("sliceapp.exe")) failures.push("SliceApp.exe is identical in both seals: the Swift edit did not reach the package");

const diff = execFileSync("git", ["-C", repo, "diff", "--name-only", `${oldCommit}..${newCommit}`], { encoding: "utf8" }).split("\n").filter(Boolean);
const rustInput = (f) => /^render\//.test(f) || /\.rs$/.test(f) || /(^|\/)Cargo\.(toml|lock)$/.test(f) || /(^|\/)rust-toolchain/.test(f);
for (const f of diff.filter(rustInput)) failures.push(`diff touches a Rust input: ${f}`);

for (const log of logs) {
  const text = readFileSync(log, "utf8");
  const hit = text.split("\n").find((l) => /\b(cargo|rustc)(\.exe)?\b/i.test(l) || /^\s*Compiling\s+\S+\s+v\d/.test(l));
  if (hit) failures.push(`${log}: Rust compile evidence: ${hit.trim().slice(0, 160)}`);
}

console.log(JSON.stringify({ renderer: { file: pin.file, sha256: pin.sha256.toLowerCase(), authenticodeSha256: pin.authenticodeSha256?.toLowerCase() }, changedPayload: changed, changedSources: diff, buildLogs: logs, ok: failures.length === 0, failures }, null, 2));
process.exit(failures.length === 0 ? 0 : 1);
