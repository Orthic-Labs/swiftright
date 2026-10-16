#!/usr/bin/env python3
"""Fetch a factory-pairs.yml run's artifacts into the local factory layout. Builds and runs nothing.

  python3 factory/tools/ci_fetch.py <run-id> [--repo Orthic-Labs/swiftright] [--scratch /Volumes/D/claude/swiftright-ci-fetch]

1. Downloads every artifact of the run with `gh run download` into a NEW empty directory under --scratch (refuses an existing one).
2. Places each file under factory/pipeline/... of this checkout (paths must be relative, inside factory/pipeline, no "..").
   The same path can appear in several artifacts (mac-N, windows-N, compare-results). Identical bytes are copied once. When bytes differ,
   the compare-results copy is canonical: ci_pair.py compare merges the mac build.json with the Windows stage/renderer/windows keys
   and writes it there. A differing copy is accepted only when it is a JSON subset of the canonical one (every key it has, equal);
   anything else is refused. Existing local files with different bytes are refused, never overwritten.
3. Appends the run's results.jsonl records to factory/pipeline/consolidation/results.jsonl (skipped when the same
   case, n and ts are already recorded). Case keys are written pipeline-relative ("blocks-6-10/swiftui.animation/completion-v1"),
   the form the local results.jsonl uses, while the workflow takes repo-relative case paths ("factory/pipeline/..."). `out` is the local runs/<ts> path.
Artifact contents are untrusted data: they are read as bytes and copied; nothing from them is executed."""
import argparse, json, shutil, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PIPELINE = REPO / "factory" / "pipeline"
RESULTS = PIPELINE / "consolidation" / "results.jsonl"
CANONICAL_ARTIFACT = "compare-results"
REPO_CASE_PREFIX = "factory/pipeline/"


def safe_rel(rel):
    p = Path(rel)
    if p.is_absolute() or ".." in p.parts or not p.parts or p.parts[0] != "factory":
        return None
    return p


def pipeline_case(case):
    """Repository-relative case path (as the workflow takes it) -> pipeline-relative key (as results.jsonl stores it)."""
    c = case.strip("/")
    if not c.startswith(REPO_CASE_PREFIX):
        raise ValueError(f"case is not under {REPO_CASE_PREFIX}: {case!r}")
    return c[len(REPO_CASE_PREFIX):]


def record_for_local(j):
    """Rewrite one run record for the local results.jsonl: pipeline-relative case, local out path."""
    case = pipeline_case(j["case"])
    out = dict(j)
    out["case"] = case
    out["out"] = str((PIPELINE / case / "runs" / j["ts"]).resolve())
    return out


def json_subset(small, big):
    """True when every key (recursively) of `small` is present in `big` with an equal value."""
    if isinstance(small, dict):
        return isinstance(big, dict) and all(k in big and json_subset(v, big[k]) for k, v in small.items())
    if isinstance(small, list):
        return isinstance(big, list) and len(small) == len(big) and all(json_subset(a, b) for a, b in zip(small, big))
    return small == big


def choose_copy(rel, copies):
    """copies: [(artifact, src Path)] for one repository-relative path. Returns (src to copy, how) or raises SystemExit."""
    contents = {src: src.read_bytes() for _, src in copies}
    if len(set(contents.values())) == 1:
        return copies[0][1], "identical"
    canon = [src for art, src in copies if art == CANONICAL_ARTIFACT]
    if len(canon) != 1 or not rel.endswith(".json"):
        sys.exit(f"artifact copies of {rel} differ and no single {CANONICAL_ARTIFACT} JSON copy decides them: "
                 + ", ".join(f"{art}" for art, _ in copies))
    canon_src = canon[0]
    canon_obj = json.loads(contents[canon_src])
    for art, src in copies:
        if src == canon_src:
            continue
        if not json_subset(json.loads(contents[src]), canon_obj):
            sys.exit(f"{rel}: the {art} copy differs from the {CANONICAL_ARTIFACT} copy beyond the merged keys; refusing")
    return canon_src, "canonical-" + CANONICAL_ARTIFACT


def collect(tmp):
    """Walk a `gh run download` directory: each artifact is <tmp>/<artifact-name>/<repo-relative path>. Returns (artifact, inner Path, src) tuples."""
    entries = []
    for src in sorted(p for p in tmp.rglob("*") if p.is_file()):
        parts = src.relative_to(tmp).parts
        if len(parts) < 2:
            continue
        entries.append((parts[0], Path(*parts[1:]), src))
    return entries


def plan(entries):
    """-> (results_lines, {repo-relative rel: (src, how)}). Results come only from the compare-results artifact."""
    groups, results_lines = {}, []
    for art, inner, src in entries:
        if inner.as_posix() == "results.jsonl":
            if art == CANONICAL_ARTIFACT:
                results_lines += [l for l in src.read_text(encoding="utf-8").splitlines() if l.strip()]
            continue
        rel = safe_rel(inner.as_posix())
        if rel is None:
            continue
        groups.setdefault(rel.as_posix(), []).append((art, src))
    chosen = {rel: choose_copy(rel, copies) for rel, copies in sorted(groups.items())}
    return results_lines, chosen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id")
    ap.add_argument("--repo", default="Orthic-Labs/swiftright")
    ap.add_argument("--scratch", default="/Volumes/D/claude/swiftright-ci-fetch")
    a = ap.parse_args()
    tmp = Path(a.scratch) / f"run-{a.run_id}-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}"
    if tmp.exists():
        sys.exit(f"scratch dir exists, refusing to reuse it: {tmp}")
    tmp.mkdir(parents=True)
    subprocess.run(["gh", "run", "download", a.run_id, "--repo", a.repo, "--dir", str(tmp)], check=True)
    results_lines, chosen = plan(collect(tmp))
    copied = skipped = 0
    for rel, (src, how) in chosen.items():
        dst = REPO / rel
        if dst.exists():
            if dst.read_bytes() == src.read_bytes():
                skipped += 1
                continue
            sys.exit(f"refusing to overwrite a different local file: {dst}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        copied += 1
        if how != "identical":
            print(f"  {rel}: {how}")
    print(f"copied {copied} files, {skipped} already identical; artifacts in {tmp}")
    existing = set()
    if RESULTS.is_file():
        for l in RESULTS.read_text().splitlines():
            try:
                j = json.loads(l)
                existing.add((j.get("case"), j.get("n"), j.get("ts")))
            except ValueError:
                pass
    added = 0
    with RESULTS.open("a") as f:
        for l in results_lines:
            j = record_for_local(json.loads(l))
            key = (j["case"], j.get("n"), j.get("ts"))
            if key in existing:
                continue
            f.write(json.dumps(j) + "\n"); existing.add(key); added += 1
    print(f"results: {len(results_lines)} in run, {added} appended to {RESULTS.relative_to(REPO)}")


if __name__ == "__main__":
    main()
