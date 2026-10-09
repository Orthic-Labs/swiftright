#!/usr/bin/env python3
"""SR0-A local native qualification runner (python3 stdlib only).

Run with:  python3 -I qualification/run.py <command> [options]

Commands
  run     execute stages in the declared order: mac-oracle, win-replay, compare, smoke, package
  seed    create the first accepted baseline for a fixture from repeat-run evidence (needs --approved-by)
  promote replace an accepted baseline with a candidate (needs --approved-by)

Rules (docs/architecture.md AD7 and section 11)
  * A Mac observation that differs from its accepted trace is written to conformance/candidates/<F>/<ts>/
    with a diff. It is never written to conformance/accepted/ by run.
  * Only `promote --approved-by <name>` changes accepted traces. The approver is recorded.
  * Every stage emits JSON lines {ts, stage, event, fixture, artifact_ids, reason} to stdout and to
    qualification/out/<run>/events.jsonl. event is start|pass|fail|skip.
  * Every stage named in `run` is required. Exit 0 only when no fail event was emitted, no stage was skipped
    and every stage emitted a pass; a skip or missing evidence is a failure (exit 1). --dry-run prints plans,
    emits skip events and exits 0; it is never qualification evidence. 2 is for usage errors.
  * --stages runs in the order given. compare consumes the Windows trace produced by an earlier win-replay in
    the same run; a historical file needs an explicit --win-candidate and may not precede its replay.
  * Windows pass records carry windows_exe, windows_renderer and windows_trace sha256 artifact ids.
  * Canonical digest form sr0-a.canonical/v2: group by step, then node; per-node event order is significant.
  * win-replay drives Windows GUI jobs. It runs only with --confirm-windows-gui, or as --dry-run plan.
"""
import argparse
import difflib
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

QUAL_DIR = Path(__file__).resolve().parent
REPO = QUAL_DIR.parent
OUT_ROOT = QUAL_DIR / "out"
BUILD_ROOT = QUAL_DIR / ".build"
ACCEPTED_ROOT = REPO / "conformance" / "accepted"
CANDIDATE_ROOT = REPO / "conformance" / "candidates"
FIXTURES_PKG = REPO / "probes" / "sr0-o" / "fixtures"
COMPARATOR_PKG = REPO / "probes" / "sr0-o" / "comparator"
REPEAT_DIR = FIXTURES_PKG / "out" / "repeat20"
MATRIX_SCRIPT = REPO / "probes" / "sr0-s" / "fresh-on-bridge" / "scripts" / "run-matrix.sh"
SMOKE_SCRIPT = REPO / "examples" / "BridgeSmoke" / "scripts" / "schedule-smoke.ps1"

STAGES = ("mac-oracle", "win-replay", "compare", "smoke", "package", "seed", "promote")
RUN_STAGES = ("mac-oracle", "win-replay", "compare", "smoke", "package")  # default declared order
WINDOWS_PASS_IDS = ("windows_exe", "windows_renderer", "windows_trace")
WINDOWS_STAGES = ("win-replay", "smoke")
PACKAGE_RECEIPT_SCHEMA = "sr0-a.package-receipt/v1"
PACKAGE_PLATFORMS = ("windows-x64", "macos-arm64")  # scope revision 1
PACKAGE_RECEIPT_DIR = QUAL_DIR / "receipts" / "package"
WIN_TRACE_FILE = "win-trace-v0.json"
SMOKE_BASE = "D:\\Claude\\sr0b-abi0"
SHA_HEX_RE = re.compile(r"^[0-9a-f]{64}$")
ARTIFACTS_LINE_RE = re.compile(r"^ARTIFACTS exe=([0-9a-f]{64}) renderer=([0-9a-f]{64}) trace=([0-9a-f]{64})\s*$", re.M)
EVENTS = ("start", "pass", "fail", "skip")
EVENT_KEYS = {"ts", "stage", "event", "fixture", "artifact_ids", "reason"}
TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")
F3_VARIANTS = ("list-1s", "list-3s", "vstack-1s", "vstack-3s", "lazy-1s", "lazy-3s")
# Allow-list of config ids. Config id = accepted directory name = REPEAT20 file stem.
# Value = (FixtureApp --fixture value, flags placed before --self-test). Plain F3 is the original list-0s config.
CONFIGS = {f"F{n}": (f"F{n}", ()) for n in range(1, 10)}
CONFIGS.update({f"F3-{v}": ("F3", ("--f3-variant", v)) for v in F3_VARIANTS})
CONFIGS["F6-reduced"] = ("F6", ("--reduced-motion-variant",))
FIXTURE_RE = re.compile(r"^(?:" + "|".join(re.escape(c) for c in CONFIGS) + r")$")
SHA_REF_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
VERDICT_RE = re.compile(r"^SELFTEST (F[1-9][^\s:]*)(?: variant=([a-z0-9-]+))?: (PASS|FAIL)(?: \((\d+)/(\d+)\))?", re.M)
APPROVER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._@-]{0,63}$")
DEFAULT_MATRIX_CONFIGS = ("F1:none", "F2:none")
DEFAULT_FIXTURES = tuple(CONFIGS)  # full manifest: all 16 SR0 configs


def config_spec(config):
    if config not in CONFIGS:
        raise ValueError(f"unknown config {config!r}; allowed: {', '.join(CONFIGS)}")
    return CONFIGS[config]


def self_test_argv(binary, config, events_path):
    """FixtureApp argv for one config. Variant flags come before --self-test, which stays last
    (AppKit treats a trailing bare path as a document and suppresses the window)."""
    base, flags = config_spec(config)
    return [str(binary), "--fixture", base, "--events", str(events_path), *flags, "--self-test"]


def verdict_passes(verdict, config):
    """Exact config match. parse_verdict folds 'SELFTEST F3 variant=lazy-1s' into 'F3-lazy-1s'."""
    config_spec(config)
    return bool(verdict) and verdict[1] == "PASS" and verdict[0] == config


class TraceError(Exception):
    pass


class AcceptedError(Exception):
    pass


class BuildError(Exception):
    pass


class ApprovalError(ValueError):
    pass


# ---------------------------------------------------------------- time, hashing, identity

def utc_now():
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def stamp():
    now = datetime.now(timezone.utc)
    return now.strftime("%Y%m%dT%H%M%S.") + f"{now.microsecond // 1000:03d}Z"


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha_ref(hex_digest):
    return "sha256:" + hex_digest


def read_normalized(path):
    """Same normalization as probes/sr0-o/fixtures/scripts/normalize-hash.py: drop mono_ns, sort keys."""
    path = Path(path)
    if not path.exists():
        raise TraceError(f"trace missing: {path.name}")
    lines = []
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if not raw:
                continue
            try:
                event = json.loads(raw)
            except json.JSONDecodeError as exc:
                raise TraceError(f"invalid JSON in {path.name}: {exc}") from exc
            event.pop("mono_ns", None)
            lines.append(json.dumps(event, sort_keys=True, separators=(",", ":")))
    if not lines:
        raise TraceError(f"no events in {path.name}")
    return lines


def raw_digest(lines):
    return sha256_text("\n".join(lines))


CANONICAL_FORM = "sr0-a.canonical/v2"


def canonical_body(lines):
    """Canonical form v2 (CONTRACT section 3): group by driver step (steps keep their order), then by node.
    Nodes inside a step may permute, so node groups are sorted; each node's event sequence keeps its
    recorded order, so reversing two events of one node (e.g. onDisappear vs task-cancel) changes the digest.
    Keep identical to probes/sr0-o/fixtures/scripts/normalize-hash.py --canonical."""
    steps = {}
    for line in lines:
        event = json.loads(line)
        nodes = steps.setdefault(event.get("step", ""), {})
        nodes.setdefault(event.get("node_id", ""), []).append(line)
    parts = [CANONICAL_FORM]
    for step, nodes in steps.items():
        groups = sorted(("\n".join(seq) for seq in nodes.values()))
        parts.append(f"#{step}\n" + "\n".join(groups))
    return "\n".join(parts)


def canonical_digest(lines):
    return sha256_text(canonical_body(lines))


def identity(lines):
    return {"raw_sha256": raw_digest(lines), "canonical_sha256": canonical_digest(lines), "event_count": len(lines)}


def write_lines(path, lines):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def host_identity():
    def sw_vers(flag):
        try:
            return subprocess.run(["sw_vers", flag], capture_output=True, text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return "unknown"
    return {"os": "macOS" if sys.platform == "darwin" else sys.platform,
            "product_version": sw_vers("-productVersion"), "build": sw_vers("-buildVersion"),
            "arch": platform.machine()}


# ---------------------------------------------------------------- events

def validate_event(record):
    if set(record) != EVENT_KEYS:
        raise ValueError(f"event keys {sorted(record)} != {sorted(EVENT_KEYS)}")
    if record["stage"] not in STAGES:
        raise ValueError(f"unknown stage {record['stage']!r}")
    if record["event"] not in EVENTS:
        raise ValueError(f"unknown event {record['event']!r}")
    if not isinstance(record["ts"], str) or not TS_RE.match(record["ts"]):
        raise ValueError(f"bad ts {record['ts']!r}")
    if record["fixture"] is not None and not (isinstance(record["fixture"], str) and FIXTURE_RE.match(record["fixture"])):
        raise ValueError(f"bad fixture {record['fixture']!r}")
    ids = record["artifact_ids"]
    if not isinstance(ids, dict) or not all(isinstance(k, str) and isinstance(v, str) and SHA_REF_RE.match(v)
                                            for k, v in ids.items()):
        raise ValueError(f"artifact_ids must map names to sha256:<64 hex>: {ids!r}")
    if record["reason"] is not None and not isinstance(record["reason"], str):
        raise ValueError("reason must be a string or null")
    if record["event"] in ("fail", "skip") and not (record["reason"] or "").strip():
        raise ValueError(f"{record['event']} needs a reason")
    if record["event"] == "pass" and record["stage"] in WINDOWS_STAGES:
        missing = [k for k in WINDOWS_PASS_IDS if k not in ids]
        if missing:
            raise ValueError(f"{record['stage']} pass needs artifact ids {', '.join(missing)}")


class EventLog:
    def __init__(self, path, echo=True):
        self.path = Path(path)
        self.echo = echo
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._handle = open(self.path, "a", encoding="utf-8")
        self.failures = 0
        self.skips = 0
        self.passes = {}

    def emit(self, stage, event, fixture=None, artifact_ids=None, reason=None):
        record = {"ts": utc_now(), "stage": stage, "event": event, "fixture": fixture,
                  "artifact_ids": dict(artifact_ids or {}), "reason": reason}
        validate_event(record)
        if event == "fail":
            self.failures += 1
        elif event == "skip":
            self.skips += 1
        elif event == "pass":
            self.passes[stage] = self.passes.get(stage, 0) + 1
        line = json.dumps(record, sort_keys=True)
        if self.echo:
            print(line, flush=True)
        self._handle.write(line + "\n")
        self._handle.flush()
        return record

    def close(self):
        self._handle.close()


# ---------------------------------------------------------------- building products

def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, timeout=120)


def committed_package(package_rel):
    """Exports the committed tree of package_rel (git archive HEAD) under qualification/.build/src/<tree>/.
    The oracle tests committed source only: uncommitted edits to the shared working tree are reported, not built."""
    rel = str(Path(package_rel))
    tree = git("rev-parse", f"HEAD:{rel}")
    if tree.returncode != 0:
        raise BuildError(f"cannot resolve committed tree for {rel}: {tree.stderr.strip()[:160]}")
    tree_sha = tree.stdout.strip()
    dest = BUILD_ROOT / "src" / tree_sha
    package = dest / rel
    if not (package / "Package.swift").exists():
        archive = subprocess.run(["git", "-C", str(REPO), "archive", "--format=tar", "HEAD", "--", rel],
                                 capture_output=True, timeout=300)
        if archive.returncode != 0:
            raise BuildError(f"git archive failed for {rel}")
        import io
        import tarfile
        dest.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
            tar.extractall(dest, filter="data")
    dirty = git("status", "--porcelain", "--", rel)
    uncommitted = len([line for line in dirty.stdout.splitlines() if line.strip()])
    return package, tree_sha, uncommitted


def swift_product(package, scratch, product):
    base = ["swift", "build", "--package-path", str(package), "--scratch-path", str(scratch)]
    built = subprocess.run(base + ["--product", product], capture_output=True, text=True)
    if built.returncode != 0:
        tail = (built.stderr or built.stdout).strip().splitlines()[-3:]
        raise BuildError(f"swift build {product} failed rc={built.returncode}: {' | '.join(tail)}")
    bin_dir = subprocess.run(base + ["--show-bin-path"], capture_output=True, text=True).stdout.strip()
    path = Path(bin_dir) / product
    if not path.exists():
        raise BuildError(f"built product missing: {path}")
    return path


# ---------------------------------------------------------------- Mac self-test launcher

def launch_self_test(binary, fixture, events_path, stdout_path, timeout_s=30, appear_s=8, attempts=8):
    """Mirrors probes/sr0-o/fixtures/scripts/run-self-test.sh. Relaunches only when root-appear is
    absent (window not presented). A launched run that fails its assertions is never retried.
    --self-test stays last (AppKit treats a trailing bare path as a document)."""
    log = []
    proc = None
    appeared = False
    for attempt in range(1, attempts + 1):
        Path(events_path).unlink(missing_ok=True)
        with open(stdout_path, "w", encoding="utf-8") as out:
            proc = subprocess.Popen(self_test_argv(binary, fixture, events_path),
                                    stdout=out, stderr=subprocess.STDOUT)
        for _ in range(appear_s):
            if Path(events_path).exists() and '"root-appear"' in Path(events_path).read_text(errors="replace"):
                appeared = True
                break
            if proc.poll() is not None:
                break
            time.sleep(1)
        if appeared:
            log.append(f"attempt {attempt}: root-appear")
            break
        log.append(f"attempt {attempt}: no root-appear within {appear_s} s, relaunch")
        proc.kill()
        proc.wait()
    if not appeared:
        return {"rc": None, "stdout": Path(stdout_path).read_text(errors="replace"), "attempts": log}
    try:
        rc = proc.wait(timeout=timeout_s)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        rc = 124
        log.append("HUNG after 30 s, killed")
    return {"rc": rc, "stdout": Path(stdout_path).read_text(errors="replace"), "attempts": log}


def parse_verdict(stdout):
    match = VERDICT_RE.search(stdout or "")
    if not match:
        return None
    fixture, variant, status, passed, total = match.groups()
    if variant:
        fixture = f"{fixture}-{variant}"  # F3 variant verdicts name the config id, e.g. F3-lazy-1s
    return fixture, status, int(passed or 0), int(total or 0)


# ---------------------------------------------------------------- accepted baselines and candidates

def load_accepted(root, fixture):
    fixture_dir = Path(root) / fixture
    manifest_path = fixture_dir / "manifest.json"
    if not manifest_path.exists():
        return None
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    try:
        lines = read_normalized(fixture_dir / manifest["trace_file"])
    except TraceError as exc:
        raise AcceptedError(str(exc)) from exc
    if manifest.get("canonical_form") != CANONICAL_FORM:
        raise AcceptedError(f"{fixture}: manifest canonical_form {manifest.get('canonical_form')!r} "
                            f"is not {CANONICAL_FORM} (recompute digests offline, with provenance)")
    ident = identity(lines)
    if ident["canonical_sha256"] != manifest["canonical_sha256"] or ident["raw_sha256"] != manifest["raw_sha256"]:
        raise AcceptedError(f"{fixture}: accepted trace digest does not match manifest")
    return {"manifest": manifest, "lines": lines, **ident}


def unique_dir(parent, name):
    candidate = parent / name
    suffix = 2
    while candidate.exists():
        candidate = parent / f"{name}-{suffix}"
        suffix += 1
    candidate.mkdir(parents=True)
    return candidate


def write_candidate(candidate_root, fixture, lines, accepted_lines, meta):
    """Writes a candidate. It is never promoted here."""
    directory = unique_dir(Path(candidate_root) / fixture, stamp().replace(":", ""))
    write_lines(directory / "candidate.jsonl", lines)
    diff = difflib.unified_diff(accepted_lines or [], lines, "accepted", "candidate", lineterm="", n=1)
    (directory / "diff.txt").write_text("\n".join(diff) + "\n", encoding="utf-8")
    body = {"status": "candidate-not-promoted", "fixture": fixture, "created_ts": utc_now(),
            "candidate_raw_sha256": raw_digest(lines), "candidate_canonical_sha256": canonical_digest(lines),
            "accepted_canonical_sha256": meta.get("accepted_canonical_sha256"),
            "binary_sha256": meta.get("binary_sha256"), "host": meta.get("host"), "run": meta.get("run"),
            "source_tree": meta.get("source_tree"),
            "approval": None,
            "promote_hint": f"python3 -I qualification/run.py promote --fixture {fixture} "
                            f"--candidate {directory.relative_to(REPO)} --approved-by <name>"}
    (directory / "candidate.json").write_text(json.dumps(body, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return directory


def write_accepted(fixture_dir, lines, extra):
    identity_block = identity(lines)
    write_lines(fixture_dir / "trace.jsonl", lines)
    manifest = {"schema": "sr0-a.accepted/v1", "fixture": fixture_dir.name, "trace_file": "trace.jsonl",
                "canonical_form": CANONICAL_FORM, **identity_block, **extra}
    (fixture_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def append_history(fixture_dir, action, record):
    with open(fixture_dir / "PROMOTIONS.jsonl", "a", encoding="utf-8") as handle:
        handle.write(json.dumps({"ts": utc_now(), "action": action, **record}, sort_keys=True) + "\n")


def check_approver(name):
    name = (name or "").strip()
    if not APPROVER_RE.match(name):
        raise ApprovalError("--approved-by must be a name (letters, digits, space, . _ @ -), not empty")
    return name


# ---------------------------------------------------------------- mac-oracle stage

def oracle_fixture(fixture, runs, launcher, binary, accepted_root, candidate_root, workdir, log, source_tree=None):
    stage = "mac-oracle"
    log.emit(stage, "start", fixture, reason=f"{runs} runs of FixtureApp --fixture {fixture} --self-test")
    bin_sha = sha256_file(binary)
    host = host_identity()
    try:
        accepted = load_accepted(accepted_root, fixture)
    except AcceptedError as exc:
        log.emit(stage, "fail", fixture, {"fixture_binary": sha_ref(bin_sha)}, f"accepted baseline corrupt: {exc}")
        return False

    results = []
    for run in range(1, runs + 1):
        events = Path(workdir) / fixture / f"run{run}.jsonl"
        stdout = Path(workdir) / fixture / f"run{run}.stdout"
        events.parent.mkdir(parents=True, exist_ok=True)
        result = launcher(binary, fixture, events, stdout)
        verdict = parse_verdict(result.get("stdout", ""))
        verdict_ok = verdict_passes(verdict, fixture)
        ids = {"fixture_binary": sha_ref(bin_sha)}
        try:
            lines = read_normalized(events)
            ident = identity(lines)
            ids["trace_raw"] = sha_ref(ident["raw_sha256"])
            ids["trace_canonical"] = sha_ref(ident["canonical_sha256"])
            trace_note = f"trace events={ident['event_count']}"
        except TraceError as exc:
            lines, ident, trace_note = None, None, f"trace error: {exc}"
        vtext = f"{verdict[1]} ({verdict[2]}/{verdict[3]})" if verdict else "no verdict line"
        ok = verdict_ok and result.get("rc") == 0 and lines is not None
        if ok:
            log.emit(stage, "pass", fixture, ids, f"run {run}/{runs}: self-test {vtext}; {trace_note}; "
                                                 f"attempts={len(result.get('attempts', []))}")
        else:
            log.emit(stage, "fail", fixture, ids, f"run {run}/{runs}: self-test {vtext}, rc={result.get('rc')}; "
                                                 f"{trace_note}")
        results.append({"run": run, "ok": ok, "lines": lines, "ident": ident})

    accepted_c = accepted["canonical_sha256"] if accepted else None
    traced = [r for r in results if r["ok"]]
    distinct = {r["ident"]["canonical_sha256"] for r in traced}
    differing = {}
    for result in traced:
        digest = result["ident"]["canonical_sha256"]
        if digest != accepted_c and digest not in differing:
            differing[digest] = result
    candidate_paths = []
    for digest, result in differing.items():
        candidate_paths.append(write_candidate(
            candidate_root, fixture, result["lines"], accepted["lines"] if accepted else None,
            {"accepted_canonical_sha256": accepted_c, "binary_sha256": bin_sha, "host": host, "run": result["run"],
             "source_tree": source_tree}))

    problems = []
    if not all(r["ok"] for r in results):
        problems.append(f"{sum(not r['ok'] for r in results)} of {runs} runs failed self-test or produced no trace")
    if len(distinct) > 1:
        problems.append(f"runs disagree: {len(distinct)} distinct canonical traces (nondeterministic)")
    if accepted is None:
        problems.append("no accepted baseline (seed first)")
    elif distinct and distinct != {accepted_c}:
        problems.append("trace differs from accepted baseline")
    if candidate_paths:
        problems.append("candidate written, NOT promoted: " + ", ".join(str(p.relative_to(REPO)) for p in candidate_paths))

    ids = {"fixture_binary": sha_ref(bin_sha)}
    if accepted:
        ids["accepted_canonical"] = sha_ref(accepted_c)
    if traced:
        ids["trace_canonical"] = sha_ref(traced[0]["ident"]["canonical_sha256"])
    if problems:
        log.emit(stage, "fail", fixture, ids, "; ".join(problems))
        return False
    log.emit(stage, "pass", fixture, ids,
             f"{runs}/{runs} runs PASS; canonical trace equals accepted baseline "
             f"(raw {accepted['raw_sha256'][:12]}..., canonical {accepted_c[:12]}...)")
    return True


def cmd_mac_oracle_real(log, fixtures, runs, workdir):
    stage = "mac-oracle"
    log.emit(stage, "start", None, reason="build FixtureApp from committed source")
    try:
        package, tree_sha, uncommitted = committed_package(FIXTURES_PKG.relative_to(REPO))
        binary = swift_product(package, BUILD_ROOT / "fixtures" / tree_sha[:12], "FixtureApp")
    except BuildError as exc:
        log.emit(stage, "fail", None, reason=str(exc))
        return
    log.emit(stage, "pass", None, {"fixture_binary": sha_ref(sha256_file(binary))},
             f"built {binary.name} from committed tree {tree_sha[:12]}; "
             f"{uncommitted} uncommitted change(s) under probes/sr0-o/fixtures NOT built")
    for fixture in fixtures:
        oracle_fixture(fixture, runs, launch_self_test, binary, ACCEPTED_ROOT, CANDIDATE_ROOT, workdir, log,
                       source_tree=tree_sha)


def mac_oracle_dry(log, fixtures, runs):
    for fixture in fixtures:
        log.emit("mac-oracle", "start", fixture, reason="dry-run")
        log.emit("mac-oracle", "skip", fixture, reason=(
            f"dry-run plan: build FixtureApp (scratch {BUILD_ROOT / 'fixtures'}), run "
            f"--fixture {fixture} --events <run>.jsonl --self-test x{runs}, normalize, compare with "
            f"{ACCEPTED_ROOT / fixture / 'manifest.json'}"))


# ---------------------------------------------------------------- compare stage (Mac accepted vs Windows candidate)

def compare_stage(log, fixture, accepted_v0, candidate_v0, adapt, out_dir):
    stage = "compare"
    log.emit(stage, "start", fixture, reason=f"sr0o-trace compare {accepted_v0.name} vs {candidate_v0.name}")
    try:
        package, tree_sha, _ = committed_package(COMPARATOR_PKG.relative_to(REPO))
        comparator = swift_product(package, BUILD_ROOT / "comparator" / tree_sha[:12], "sr0o-trace")
    except BuildError as exc:
        log.emit(stage, "fail", fixture, reason=str(exc))
        return False
    ids = {"comparator_binary": sha_ref(sha256_file(comparator))}
    for label, path in (("accepted_v0", accepted_v0), ("candidate_v0", candidate_v0), ("adapt", adapt)):
        if not path.exists():
            log.emit(stage, "fail", fixture, ids, f"{label} missing: {path}")
            return False
        ids[label] = sha_ref(sha256_file(path))
    report = out_dir / f"compare-{fixture}.json"
    result = subprocess.run([str(comparator), "compare", str(accepted_v0), str(candidate_v0), "--adapt", str(adapt)],
                            capture_output=True, text=True)
    report.write_text(result.stdout, encoding="utf-8")
    if result.returncode == 0:
        log.emit(stage, "pass", fixture, ids, f"0 diffs; report {report.name}")
        return True
    if result.returncode == 1:
        try:
            diffs = len(json.loads(result.stdout).get("diffs", []))
        except (json.JSONDecodeError, AttributeError):
            diffs = "?"
        log.emit(stage, "fail", fixture, ids, f"comparator reported {diffs} diffs; report {report.name}")
        return False
    log.emit(stage, "fail", fixture, ids, f"comparator error rc={result.returncode}: {result.stderr.strip()[:200]}")
    return False


# ---------------------------------------------------------------- smoke and win-replay

def parse_windows_artifacts(text):
    """The Windows scripts must print `ARTIFACTS exe=<sha256> renderer=<sha256> trace=<sha256>` for each run.
    Returns (exe, renderer, trace) of the last such line, or None."""
    found = ARTIFACTS_LINE_RE.findall(text or "")
    return found[-1] if found else None


def windows_ids(exes, renderers, traces):
    """Artifact ids for one Windows pass record. Exe and renderer must be a single build across runs."""
    if len(set(exes)) != 1 or len(set(renderers)) != 1:
        raise ValueError(f"runs used {len(set(exes))} exe and {len(set(renderers))} renderer builds, expected one each")
    return {"windows_exe": sha_ref(exes[0]), "windows_renderer": sha_ref(renderers[0]),
            "windows_trace": sha_ref(sha256_text("\n".join(sorted(set(traces)))))}


def smoke_plan(tag):
    script = f"{SMOKE_BASE}\\examples\\BridgeSmoke\\scripts\\schedule-smoke.ps1"
    return {"command": ["win", f"powershell -NoProfile -ExecutionPolicy Bypass -File {script} -Tag {tag}"],
            "transport": "win bridge (ssh) starting one interactive scheduled task",
            "desktop": "interactive Windows desktop session required",
            "pass_markers": ["AUTOMATIONID PASS", "run: ok"],
            "evidence": "ARTIFACTS exe=<sha256> renderer=<sha256> trace=<sha256> line in the result text"}


def smoke_stage(log, out_dir, dry_run, confirmed, runner=subprocess.run, which=shutil.which):
    """Dispatches BridgeSmoke on Windows. Required: skip and missing evidence are failures outside --dry-run."""
    stage = "smoke"
    tag = "qual-" + stamp().replace(":", "").replace(".", "")
    plan = smoke_plan(tag)
    log.emit(stage, "start", None, reason="BridgeSmoke ABI smoke on Windows")
    if dry_run:
        print("PLAN " + json.dumps(plan, indent=2), file=sys.stderr)
        log.emit(stage, "skip", None, reason="dry-run: BridgeSmoke plan printed to stderr; no Windows job started")
        return True
    if not confirmed:
        log.emit(stage, "fail", None, reason="refused: Windows GUI jobs need --confirm-windows-gui (desktop is busy)")
        return False
    if which("win") is None:
        log.emit(stage, "fail", None, reason="win bridge not on PATH")
        return False
    result = runner(plan["command"], capture_output=True, text=True)
    text = (result.stdout or "") + (result.stderr or "")
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "smoke.txt").write_text(text, encoding="utf-8")
    markers_ok = all(m in text for m in plan["pass_markers"])
    artifacts = parse_windows_artifacts(text)
    if result.returncode != 0 or not markers_ok:
        log.emit(stage, "fail", None, reason=f"BridgeSmoke did not PASS (rc={result.returncode}, markers_ok={markers_ok})")
        return False
    if artifacts is None:
        log.emit(stage, "fail", None, reason="BridgeSmoke PASS lacks an ARTIFACTS line (exe, renderer, trace sha256)")
        return False
    log.emit(stage, "pass", None, windows_ids([artifacts[0]], [artifacts[1]], [artifacts[2]]),
             "BridgeSmoke PASS with artifact ids")
    return True


def win_plan(configs, runs, out_dir):
    return {"configs": list(configs), "runs_per_config": runs,
            "command": ["bash", str(MATRIX_SCRIPT), *configs],
            "env": {"OUT_DIR": str(out_dir / "win-matrix"), "RUNS": str(runs)},
            "transport": "win bridge (ssh) starting one interactive scheduled task per run",
            "desktop": "interactive Windows desktop session required"}


def win_stage(log, configs, runs, out_dir, dry_run, confirmed, runner=subprocess.run, which=shutil.which):
    stage = "win-replay"
    plan = win_plan(configs, runs, out_dir)
    log.emit(stage, "start", None, reason=f"{len(configs)} configs x {runs} runs")
    if dry_run:
        print("PLAN " + json.dumps(plan, indent=2), file=sys.stderr)
        log.emit(stage, "skip", None, reason="dry-run: plan printed to stderr; no Windows job started")
        return True
    if not confirmed:
        log.emit(stage, "fail", None, reason="refused: Windows GUI jobs need --confirm-windows-gui (desktop is busy)")
        return False
    if which("win") is None:
        log.emit(stage, "fail", None, reason="win bridge not on PATH")
        return False
    matrix_dir = out_dir / "win-matrix"
    matrix_dir.mkdir(parents=True, exist_ok=True)
    result = runner(plan["command"], env={**os.environ, **plan["env"]}, capture_output=True, text=True)
    (out_dir / "win-matrix.log").write_text((result.stdout or "") + (result.stderr or ""), encoding="utf-8")
    lines = [l for l in (result.stdout or "").splitlines() if " run" in l]
    expected = len(configs) * runs
    passed = [l for l in lines if "PASS" in l and "FAIL" not in l]
    if result.returncode != 0 or len(passed) != expected:
        log.emit(stage, "fail", None, reason=f"{len(passed)}/{expected} Windows runs PASS, rc={result.returncode}")
        return False
    exes, renderers, traces, missing = [], [], [], []
    for config in configs:
        fixture, _, variant = config.partition(":")
        for run in range(1, runs + 1):
            record = matrix_dir / f"{fixture}-{variant}-r{run}.txt"
            artifacts = parse_windows_artifacts(record.read_text(encoding="utf-8", errors="replace")
                                                if record.exists() else "")
            if artifacts is None:
                missing.append(record.name)
            else:
                exes.append(artifacts[0]); renderers.append(artifacts[1]); traces.append(artifacts[2])
    if missing:
        log.emit(stage, "fail", None, reason=f"{len(missing)} PASS runs lack ARTIFACTS evidence "
                                             f"(exe, renderer, trace sha256): {', '.join(missing[:4])}")
        return False
    try:
        ids = windows_ids(exes, renderers, traces)
    except ValueError as exc:
        log.emit(stage, "fail", None, reason=str(exc))
        return False
    log.emit(stage, "pass", None, ids, f"{len(passed)}/{expected} Windows runs PASS with artifact ids")
    return True


# ---------------------------------------------------------------- package stage (package-verification receipts)

def validate_package_receipt(receipt, repo=REPO):
    """Receipt schema sr0-a.package-receipt/v1, produced by the packaging lanes (see docs/qualification.md):
    {schema, product, platform in PACKAGE_PLATFORMS, created_ts, verdict "PASS"|"FAIL", source_rev,
     artifacts: {name: {sha256, path?}}, checks: [{name, result "PASS"|"FAIL"}]}.
    A PASS needs at least one artifact and one check, every check PASS. Returns the problem list."""
    problems = []
    if not isinstance(receipt, dict):
        return ["receipt is not a JSON object"]
    if receipt.get("schema") != PACKAGE_RECEIPT_SCHEMA:
        problems.append(f"schema != {PACKAGE_RECEIPT_SCHEMA}")
    if receipt.get("platform") not in PACKAGE_PLATFORMS:
        problems.append(f"platform not in {PACKAGE_PLATFORMS}")
    for key in ("product", "created_ts", "source_rev"):
        if not isinstance(receipt.get(key), str) or not receipt[key].strip():
            problems.append(f"{key} missing")
    if receipt.get("verdict") != "PASS":
        problems.append(f"verdict is {receipt.get('verdict')!r}, not PASS")
    artifacts = receipt.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        problems.append("artifacts missing")
    else:
        for name, info in artifacts.items():
            if not isinstance(info, dict) or not SHA_HEX_RE.match(str(info.get("sha256", ""))):
                problems.append(f"artifact {name}: sha256 missing or malformed")
            elif info.get("path"):
                path = Path(info["path"])
                path = path if path.is_absolute() else Path(repo) / path
                if not path.is_file():
                    problems.append(f"artifact {name}: path {info['path']} missing")
                elif sha256_file(path) != info["sha256"]:
                    problems.append(f"artifact {name}: sha256 does not match {info['path']}")
    checks = receipt.get("checks")
    if not isinstance(checks, list) or not checks:
        problems.append("checks missing")
    else:
        failed = [c.get("name") if isinstance(c, dict) else c for c in checks
                  if not (isinstance(c, dict) and c.get("result") == "PASS")]
        if failed:
            problems.append(f"checks not PASS: {failed}")
    return problems


def package_stage(log, receipt_paths, dry_run=False, repo=REPO):
    """Consumes package-verification receipts. Fails when none exist, any is invalid, or a required
    platform has no valid PASS receipt."""
    stage = "package"
    log.emit(stage, "start", None, reason=f"package receipts for {', '.join(PACKAGE_PLATFORMS)}")
    if dry_run:
        log.emit(stage, "skip", None, reason=f"dry-run: would read receipts {', '.join(str(p) for p in receipt_paths)}")
        return True
    files = []
    for path in receipt_paths:
        path = Path(path)
        if path.is_dir():
            files.extend(sorted(path.glob("*.json")))
        elif path.exists():
            files.append(path)
    if not files:
        log.emit(stage, "fail", None, reason="no package-verification receipts found "
                                             f"(looked in {', '.join(str(p) for p in receipt_paths)})")
        return False
    covered, ok = {}, True
    for file in files:
        try:
            receipt = json.loads(Path(file).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            log.emit(stage, "fail", None, reason=f"{Path(file).name}: unreadable receipt: {exc}")
            ok = False
            continue
        problems = validate_package_receipt(receipt, repo)
        if problems:
            log.emit(stage, "fail", None, {"package_receipt": sha_ref(sha256_file(file))},
                     f"{Path(file).name}: {'; '.join(problems)}")
            ok = False
            continue
        covered[receipt["platform"]] = file
        ids = {"package_receipt": sha_ref(sha256_file(file))}
        ids.update({f"artifact_{n}": sha_ref(i["sha256"]) for n, i in sorted(receipt["artifacts"].items())})
        log.emit(stage, "pass", None, ids, f"{Path(file).name}: {receipt['product']} {receipt['platform']} PASS")
    absent = [p for p in PACKAGE_PLATFORMS if p not in covered]
    if absent:
        log.emit(stage, "fail", None, reason=f"no valid PASS receipt for platform(s): {', '.join(absent)}")
        return False
    return ok


# ---------------------------------------------------------------- seed and promote

def cmd_seed(args, log, accepted_root=ACCEPTED_ROOT):
    stage, fixture = "seed", args.fixture
    try:
        approver = check_approver(args.approved_by)
        if (accepted_root / fixture / "manifest.json").exists():
            raise ApprovalError(f"{fixture} already has an accepted baseline; use promote")
        source = Path(args.source_dir)
        digests, lines_first = set(), None
        raw_digests = set()
        for run in range(1, args.runs + 1):
            stdout = (source / f"{fixture}-run{run}.stdout").read_text(encoding="utf-8", errors="replace")
            verdict = parse_verdict(stdout)
            if not verdict_passes(verdict, fixture):
                raise ApprovalError(f"run {run}: self-test verdict is not PASS for {fixture}")
            lines = read_normalized(source / f"{fixture}-run{run}.jsonl")
            digests.add(canonical_digest(lines))
            raw_digests.add(raw_digest(lines))
            lines_first = lines_first or lines
        if len(digests) != 1:
            raise ApprovalError(f"{fixture}: {len(digests)} distinct canonical traces across {args.runs} runs")
    except (ApprovalError, TraceError, OSError) as exc:
        log.emit(stage, "fail", fixture, reason=str(exc))
        return False
    fixture_dir = accepted_root / fixture
    fixture_dir.mkdir(parents=True, exist_ok=True)
    source_tree = git("rev-parse", f"{args.source_rev}:probes/sr0-o/fixtures").stdout.strip() or None
    extra = {"source": "seeded from repeat-run evidence", "source_dir": str(source.relative_to(REPO))
             if source.is_relative_to(REPO) else str(source), "runs_verified": args.runs,
             "source_rev": args.source_rev, "source_tree": source_tree,
             "distinct_raw_traces": len(raw_digests), "distinct_canonical_traces": 1,
             "approved_by": approver, "seeded_ts": utc_now(), "seeded_on_host": host_identity()}
    manifest = write_accepted(fixture_dir, lines_first, extra)
    if args.v0_trace:
        shutil.copyfile(args.v0_trace, fixture_dir / "trace-v0.json")
        if args.adapt:
            shutil.copyfile(args.adapt, fixture_dir / "adapt-v0.json")
    append_history(fixture_dir, "seed", {"approved_by": approver, "canonical_sha256": manifest["canonical_sha256"]})
    log.emit(stage, "pass", fixture, {"accepted_canonical": sha_ref(manifest["canonical_sha256"])},
             f"accepted baseline created from {args.runs} PASS runs; approved_by={approver}")
    return True


def cmd_promote(args, log, accepted_root=ACCEPTED_ROOT):
    stage, fixture = "promote", args.fixture
    candidate = Path(args.candidate).resolve()
    try:
        approver = check_approver(args.approved_by)
        meta = json.loads((candidate / "candidate.json").read_text(encoding="utf-8"))
        if meta.get("status") != "candidate-not-promoted" or meta.get("fixture") != fixture:
            raise ApprovalError("candidate.json is not an unpromoted candidate for this fixture")
        lines = read_normalized(candidate / "candidate.jsonl")
        if canonical_digest(lines) != meta["candidate_canonical_sha256"]:
            raise ApprovalError("candidate.jsonl does not match candidate.json digest")
    except (ApprovalError, TraceError, OSError, KeyError, json.JSONDecodeError) as exc:
        log.emit(stage, "fail", fixture, reason=str(exc))
        return False
    fixture_dir = accepted_root / fixture
    fixture_dir.mkdir(parents=True, exist_ok=True)
    previous = None
    if (fixture_dir / "manifest.json").exists():
        previous = json.loads((fixture_dir / "manifest.json").read_text(encoding="utf-8"))
        archive = unique_dir(fixture_dir / "history", utc_now().replace(":", "").replace(".", ""))
        shutil.copyfile(fixture_dir / "trace.jsonl", archive / "trace.jsonl")
        shutil.copyfile(fixture_dir / "manifest.json", archive / "manifest.json")
    extra = {"source": "promoted candidate", "candidate": str(candidate.relative_to(REPO))
             if candidate.is_relative_to(REPO) else str(candidate), "approved_by": approver,
             "promoted_ts": utc_now(), "binary_sha256": meta.get("binary_sha256"),
             "source_tree": meta.get("source_tree"),
             "previous_canonical_sha256": previous["canonical_sha256"] if previous else None}
    manifest = write_accepted(fixture_dir, lines, extra)
    append_history(fixture_dir, "promote", {"approved_by": approver, "candidate": extra["candidate"],
                                            "previous_canonical_sha256": extra["previous_canonical_sha256"],
                                            "new_canonical_sha256": manifest["canonical_sha256"]})
    meta.update({"status": "promoted", "approval": {"approved_by": approver, "ts": extra["promoted_ts"]}})
    (candidate / "candidate.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    log.emit(stage, "pass", fixture, {"accepted_canonical": sha_ref(manifest["canonical_sha256"])},
             f"promoted; approved_by={approver}")
    return True


# ---------------------------------------------------------------- run

def out_dir_for(command):
    directory = OUT_ROOT / f"{stamp()}-{command}"
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def run_stage_order(args):
    """Declared order, validated. Returns (stages, error)."""
    stages = list(args.stages or RUN_STAGES)
    if len(set(stages)) != len(stages):
        return stages, "a stage is named twice"
    if "compare" in stages and "win-replay" in stages and stages.index("compare") < stages.index("win-replay"):
        return stages, "compare is declared before win-replay and would compare a historical file; reorder"
    return stages, None


def cmd_run(args):
    stages, error = run_stage_order(args)
    if error:
        print(f"usage error: {error}", file=sys.stderr)
        return 2
    out_dir = out_dir_for("run")
    log = EventLog(out_dir / "events.jsonl")
    dry = args.dry_run
    try:
        for stage in stages:
            if stage == "mac-oracle":
                if dry:
                    mac_oracle_dry(log, args.fixtures, args.runs)
                else:
                    cmd_mac_oracle_real(log, args.fixtures, args.runs, out_dir / "mac-oracle")
            elif stage == "win-replay":
                win_stage(log, args.configs, args.win_runs, out_dir, dry, args.confirm_windows_gui)
            elif stage == "compare":
                run_compare(log, args, stages, out_dir, dry)
            elif stage == "smoke":
                smoke_stage(log, out_dir, dry, args.confirm_windows_gui)
            elif stage == "package":
                package_stage(log, args.package_receipts or [PACKAGE_RECEIPT_DIR], dry)
        if not dry:
            for stage in stages:
                if not log.passes.get(stage):
                    log.emit(stage, "fail", None, reason="required stage produced no pass (skip or missing evidence)")
    finally:
        log.close()
    print(f"events: {log.path}", file=sys.stderr)
    if dry:
        print("dry-run: plans only, not qualification evidence", file=sys.stderr)
        return 1 if log.failures else 0
    return 1 if (log.failures or log.skips) else 0


def run_compare(log, args, stages, out_dir, dry):
    if dry:
        log.emit("compare", "skip", "F1", reason="dry-run: compare needs a built comparator and a Windows trace; plan only")
        return
    if "win-replay" in stages:
        candidate = out_dir / "win-matrix" / WIN_TRACE_FILE
        origin = "fresh from win-replay"
    elif args.win_candidate:
        candidate, origin = args.win_candidate, "historical file named by --win-candidate"
    else:
        log.emit("compare", "fail", "F1", reason="no Windows trace: run win-replay first or name --win-candidate")
        return
    if not Path(candidate).exists():
        log.emit("compare", "fail", "F1", reason=f"Windows trace missing ({origin}): {candidate}")
        return
    compare_stage(log, "F1", ACCEPTED_ROOT / "F1" / "trace-v0.json", Path(candidate),
                  ACCEPTED_ROOT / "F1" / "adapt-v0.json", out_dir)


def cmd_single(args, command):
    out_dir = out_dir_for(command)
    log = EventLog(out_dir / "events.jsonl")
    try:
        if command == "seed":
            ok = cmd_seed(args, log)
        else:
            ok = cmd_promote(args, log)
    finally:
        log.close()
    print(f"events: {log.path}", file=sys.stderr)
    return 0 if ok and not log.failures else 1


def build_parser():
    parser = argparse.ArgumentParser(description="SR0-A local native qualification runner")
    sub = parser.add_subparsers(dest="command", required=True)

    run_p = sub.add_parser("run", help="run stages")
    run_p.add_argument("--stages", nargs="+", choices=list(RUN_STAGES),
                       help="stages in the order given (default: all, in declared order)")
    run_p.add_argument("--fixtures", nargs="+", default=list(DEFAULT_FIXTURES), type=validate_fixture)
    run_p.add_argument("--runs", type=int, default=3, help="Mac oracle runs per config")
    run_p.add_argument("--dry-run", action="store_true", help="print plans; start no GUI or Windows job")
    run_p.add_argument("--confirm-windows-gui", action="store_true", help="required to start Windows GUI matrix runs")
    run_p.add_argument("--configs", nargs="+", default=list(DEFAULT_MATRIX_CONFIGS))
    run_p.add_argument("--win-runs", type=int, default=3)
    run_p.add_argument("--win-candidate", type=Path, default=None,
                       help="historical Windows schema-v0 trace for compare when win-replay is not in this run")
    run_p.add_argument("--package-receipts", nargs="+", type=Path,
                       help=f"receipt files or directories (default {PACKAGE_RECEIPT_DIR})")

    seed_p = sub.add_parser("seed", help="create first accepted baseline from repeat-run evidence")
    seed_p.add_argument("--fixture", required=True, type=validate_fixture)
    seed_p.add_argument("--source-dir", type=Path, default=REPEAT_DIR)
    seed_p.add_argument("--runs", type=int, default=20)
    seed_p.add_argument("--source-rev", default="4ff202f",
                        help="commit whose probes/sr0-o/fixtures produced the evidence (default: the 20-run commit)")
    seed_p.add_argument("--approved-by", required=True)
    seed_p.add_argument("--v0-trace", type=Path, help="schema-v0 Mac trace for the comparator")
    seed_p.add_argument("--adapt", type=Path, help="comparator adaptations for the v0 trace")

    promote_p = sub.add_parser("promote", help="replace an accepted baseline with a candidate")
    promote_p.add_argument("--fixture", required=True, type=validate_fixture)
    promote_p.add_argument("--candidate", required=True, type=Path)
    promote_p.add_argument("--approved-by", required=True)
    return parser


def validate_fixture(value):
    if not FIXTURE_RE.match(value):
        raise argparse.ArgumentTypeError(f"bad fixture {value!r}")
    return value


def main(argv):
    args = build_parser().parse_args(argv)
    if args.command == "run":
        return cmd_run(args)
    return cmd_single(args, args.command)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
