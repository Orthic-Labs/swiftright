#!/usr/bin/env python3
"""Fetch a factory-pairs.yml run's artifacts into the local factory layout. Builds and runs nothing.

  python3 factory/tools/ci_fetch.py <run-id> [--repo Orthic-Labs/swiftright] [--scratch /Volumes/D/claude/swiftright-ci-fetch]

1. Downloads every artifact of the run with `gh run download` into a NEW empty directory under --scratch (refuses an existing one).
2. Places each file under factory/pipeline/... of this checkout (paths must be relative, inside factory/pipeline, no "..").
   Existing files with different bytes are refused, never overwritten.
3. Appends the run's results.jsonl records to factory/pipeline/consolidation/results.jsonl (skipped when the same
   case, n and ts are already recorded), with `out` rewritten to the local runs/<ts> path.
Artifact contents are untrusted data: they are read as bytes and copied; nothing from them is executed."""
import argparse, json, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
RESULTS = REPO / "factory/pipeline/consolidation/results.jsonl"


def safe_rel(rel):
    p = Path(rel)
    if p.is_absolute() or ".." in p.parts or not p.parts or p.parts[0] != "factory":
        return None
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_id")
    ap.add_argument("--repo", default="Orthic-Labs/swiftright")
    ap.add_argument("--scratch", default="/Volumes/D/claude/swiftright-ci-fetch")
    a = ap.parse_args()
    tmp = Path(a.scratch) / f"run-{a.run_id}-{time_stamp()}"
    if tmp.exists():
        sys.exit(f"scratch dir exists, refusing to reuse it: {tmp}")
    tmp.mkdir(parents=True)
    subprocess.run(["gh", "run", "download", a.run_id, "--repo", a.repo, "--dir", str(tmp)], check=True)
    copied = skipped = 0
    results_lines = []
    for src in sorted(p for p in tmp.rglob("*") if p.is_file()):
        # gh run download puts each artifact in <tmp>/<artifact-name>/; inside it the paths are repository-relative
        inner = src.relative_to(tmp).parts[1:]
        if not inner:
            continue
        if inner == ("results.jsonl",):
            results_lines += [l for l in src.read_text(encoding="utf-8").splitlines() if l.strip()]
            continue
        target_rel = safe_rel(Path(*inner).as_posix())
        if target_rel is None:
            continue
        dst = REPO / target_rel
        if dst.exists():
            if dst.read_bytes() == src.read_bytes():
                skipped += 1
                continue
            sys.exit(f"refusing to overwrite a different local file: {dst}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        copied += 1
    print(f"copied {copied} files, {skipped} already identical; artifacts in {tmp}")
    added = 0
    existing = set()
    if RESULTS.is_file():
        for l in RESULTS.read_text().splitlines():
            try:
                j = json.loads(l)
                existing.add((j.get("case"), j.get("n"), j.get("ts")))
            except ValueError:
                pass
    with RESULTS.open("a") as f:
        for l in results_lines:
            j = json.loads(l)
            key = (j.get("case"), j.get("n"), j.get("ts"))
            if key in existing:
                continue
            j["out"] = str((REPO / j["case"] / "runs" / j["ts"]).resolve())
            f.write(json.dumps(j) + "\n"); existing.add(key); added += 1
    print(f"results: {len(results_lines)} in run, {added} appended to {RESULTS.relative_to(REPO)}")


def time_stamp():
    import time
    return time.strftime("%Y%m%d-%H%M%S", time.gmtime())


if __name__ == "__main__":
    main()
