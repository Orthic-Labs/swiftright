// right-git release-candidate lane entry points for SliceApp (see .rightgit.json "candidate").
//   admit    admission job: exact checkout, reachable from origin/master, version matches SliceApp, no publication
//   summary  per-stage summary json (init / finalize) with the sha256 of every file under the evidence root
//   build    candidate job: Windows x64 MSIX + macOS arm64 DMG, both UNSIGNED
//   check    candidate job: re-read the packaged artifact
// Hosted CI only. Signing (windows-sign, macos-sign) is separate and needs the `release` environment secrets and the
// Azure federated credential; until those exist those jobs fail at their login/identity steps, by design.
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const env = process.env;
if (env.GITHUB_ACTIONS !== "true") throw new Error("Release execution requires generated hosted CI");
const action = process.argv[2];
const revision = env.RIGHT_GIT_SOURCE_REVISION;
const repo = path.resolve(import.meta.dirname, "..", "..");

const run = (cmd, args, options = {}) => {
  const r = spawnSync(cmd, args, { stdio: "inherit", ...options });
  if (r.status !== 0) throw new Error(`${cmd} ${args.slice(0, 3).join(" ")} failed (${r.status ?? r.error})`);
  return r.stdout;
};

if (action === "admit") {
  const version = env.RIGHT_GIT_RELEASE_VERSION;
  const head = run("git", ["rev-parse", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] }).trim();
  if (!/^[a-f0-9]{40}$/.test(revision) || head !== revision) throw new Error("Exact checkout required");
  run("git", ["merge-base", "--is-ancestor", revision, "origin/master"]);
  const appVersion = JSON.parse(readFileSync(path.join(repo, "examples/SliceApp/package.json"), "utf8")).version;
  if (version !== appVersion) throw new Error(`Version ${version} does not match examples/SliceApp/package.json ${appVersion}`);
  if (env.RIGHT_GIT_PUBLISH === "true") throw new Error("Publication is disabled for SliceApp candidates");
  const fields = { version, source_revision: revision, signed_qualification: env.RIGHT_GIT_SIGNED_QUALIFICATION, publish: "false", dry_run: env.RIGHT_GIT_DRY_RUN, artifact_suffix: `${version}-${revision}` };
  appendFileSync(env.GITHUB_OUTPUT, Object.entries(fields).map(([k, v]) => `${k}=${v}\n`).join(""));
} else if (action === "summary") {
  const { sha256File } = await import(pathToFileURL(path.join(repo, "node_modules", "@rightkit", "release", "native-release-finalization.mjs")).href);
  const root = env.RIGHT_GIT_STAGE_ROOT;
  mkdirSync(root, { recursive: true });
  const evidenceRoot = env.RIGHT_GIT_STAGE_EVIDENCE_ROOT;
  const artifacts = [];
  const walk = (dir) => {
    if (!existsSync(dir)) return;
    for (const name of readdirSync(dir)) {
      const file = path.join(dir, name);
      if (statSync(file).isDirectory()) walk(file);
      else artifacts.push({ file: path.relative(evidenceRoot, file).split(path.sep).join("/"), size_bytes: statSync(file).size, sha256: sha256File(file) });
    }
  };
  if (env.RIGHT_GIT_STAGE_ACTION === "finalize") walk(evidenceRoot);
  writeFileSync(path.join(root, "stage-summary.json"), `${JSON.stringify({ schema_version: 1, stage: env.RIGHT_GIT_STAGE, producer: env.RIGHT_GIT_STAGE_PRODUCER, status: env.RIGHT_GIT_STAGE_STATUS || "STARTED", version: env.RIGHT_GIT_RELEASE_VERSION, source_revision: revision, platform: env.RIGHT_GIT_RELEASE_PLATFORM, architecture: env.RIGHT_GIT_RELEASE_ARCHITECTURE, run_id: env.RIGHT_GIT_RUN_ID, run_attempt: env.RIGHT_GIT_RUN_ATTEMPT, artifacts }, null, 2)}\n`);
} else if (action === "build" || action === "check") {
  if (process.platform === "win32") {
    run("pwsh", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path.join(repo, "scripts/release/windows-candidate.ps1"), "-Action", action]);
  } else if (process.platform === "darwin") {
    run("bash", [path.join(repo, "scripts/release/mac-candidate.sh"), action]);
  } else throw new Error(`No candidate lane for ${process.platform}`);
} else throw new Error(`Unknown action: ${action}`);
