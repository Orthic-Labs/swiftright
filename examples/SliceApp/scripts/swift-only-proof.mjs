#!/usr/bin/env node
// Swift-only-edit proof for SliceApp (F1/R2). Shows that a Swift-only change between the old (0.1.0) and new (0.1.1)
// package left the renderer untouched and compiled no Rust. Pure file checks; runs anywhere with node.
//
//   node swift-only-proof.mjs --old-seal <msix-seal.json> --new-seal <msix-seal.json> \
//        --old-commit <sha> --new-commit <sha> --repo <clone dir> --build-log <old.log> --build-log <new.log> \
//        [--pin ../Windows/renderer-pin.json]
// Passes only when ALL hold:
//   1. both seals list swiftright_render.dll with the same sha256, equal to the pin;
//   2. every other payload file except SliceApp.exe is byte-identical between the two seals (runtime DLLs unchanged);
//      SliceApp.exe must differ (otherwise the edit never reached the package);
//   3. `git diff --name-only old..new` touches no Rust inputs (render/**, *.rs, Cargo.toml, Cargo.lock, rust-toolchain*);
//   4. no build log mentions a Rust compile (cargo, rustc, "Compiling <crate>" lines).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

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
const payload = (file) => new Map(JSON.parse(readFileSync(file, "utf8")).payload.map((e) => [e.name.toLowerCase(), e.sha256.toLowerCase()]));
const a = payload(oldSeal), b = payload(newSeal);
const rname = pin.file.toLowerCase();
for (const [label, m] of [["old", a], ["new", b]]) {
  if (m.get(rname) !== pin.sha256.toLowerCase()) failures.push(`${label} seal: ${pin.file} is ${m.get(rname) ?? "ABSENT"}, pin is ${pin.sha256.toLowerCase()}`);
}
const names = new Set([...a.keys(), ...b.keys()]);
const changed = [];
for (const n of [...names].sort()) {
  if (a.get(n) !== b.get(n)) changed.push(n);
}
for (const n of changed) if (n !== "sliceapp.exe") failures.push(`payload file changed or added/removed between old and new: ${n}`);
if (!changed.includes("sliceapp.exe")) failures.push("SliceApp.exe is identical in both seals: the Swift edit did not reach the package");

const diff = execFileSync("git", ["-C", repo, "diff", "--name-only", `${oldCommit}..${newCommit}`], { encoding: "utf8" }).split("\n").filter(Boolean);
const rustInput = (f) => /^render\//.test(f) || /\.rs$/.test(f) || /(^|\/)Cargo\.(toml|lock)$/.test(f) || /(^|\/)rust-toolchain/.test(f);
for (const f of diff.filter(rustInput)) failures.push(`diff touches a Rust input: ${f}`);

for (const log of logs) {
  const text = readFileSync(log, "utf8");
  const hit = text.split("\n").find((l) => /\b(cargo|rustc)(\.exe)?\b/i.test(l) || /^\s*Compiling\s+\S+\s+v\d/.test(l));
  if (hit) failures.push(`${log}: Rust compile evidence: ${hit.trim().slice(0, 160)}`);
}

console.log(JSON.stringify({ renderer: { file: pin.file, sha256: pin.sha256.toLowerCase() }, changedPayload: changed, changedSources: diff, buildLogs: logs, ok: failures.length === 0, failures }, null, 2));
process.exit(failures.length === 0 ? 0 : 1);
