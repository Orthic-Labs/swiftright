#!/usr/bin/env python3
"""Source controls for rectangle pixel reader; mutations must reject before native work."""
from __future__ import annotations
import argparse, copy, json
from pathlib import Path
from compare_rectangle_pixels import ComparisonError, bounded_json, canonical_hash, canonical_json, compare_manifest, ref_file, validate_canonical_source_joins

def expect_reject(base: dict, repo: Path, label: str, mutate, needle: str):
    candidate = copy.deepcopy(base); mutate(candidate)
    try:
        compare_manifest(candidate, repo)
    except ComparisonError as exc:
        reason = str(exc)
        if needle not in reason:
            raise AssertionError(f"{label}: wrong reason {reason!r}")
        return {"name": label, "accepted": False, "reason": reason, "nativeActions": 0}
    raise AssertionError(f"{label}: mutation admitted")

def expect_join_reject(base: dict, repo: Path, label: str, mutate, needle: str):
    # Keep source binding coherent with each mutated canonical case so control
    # reaches intended nested join, instead of failing earlier case hash check.
    source = copy.deepcopy(base["source"])
    docs = {
        "tuple": canonical_json(ref_file(repo, source["tupleRef"], f"{label}.tuple")),
        "case": canonical_json(ref_file(repo, source["caseRef"], f"{label}.case")),
        "recipe": canonical_json(ref_file(repo, source["recipeRef"], f"{label}.recipe")),
    }
    mutate(docs, source)
    try:
        validate_canonical_source_joins(source, docs["tuple"], docs["case"], docs["recipe"])
    except ComparisonError as exc:
        reason = str(exc)
        if needle not in reason:
            raise AssertionError(f"{label}: wrong reason {reason!r}")
        return {"name": label, "accepted": False, "reason": reason, "nativeActions": 0}
    raise AssertionError(f"{label}: mutation admitted")

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--manifest", type=Path, required=True); ap.add_argument("--repo-root", type=Path, required=True); ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args(); base = bounded_json(args.manifest); repo = args.repo_root.resolve(); controls = []
    controls.append(expect_reject(base, repo, "mac-frame", lambda m: m["mac"]["images"][0]["framePx"].update(y=31), "measured framePx mismatch"))
    controls.append(expect_reject(base, repo, "windows-viewport", lambda m: m["windows"]["images"][0]["viewportPx"].update(width=801), "measured viewportPx mismatch"))
    controls.append(expect_reject(base, repo, "windows-viewport-dip", lambda m: m["windows"]["images"][0]["viewportDip"].update(width=321), "measured viewportDip mismatch"))
    controls.append(expect_reject(base, repo, "color", lambda m: m["mac"]["images"][0].update(dominantRGBA=[0, 255, 0, 255]), "dominant-red-color"))
    controls.append(expect_reject(base, repo, "placement", lambda m: m["mac"]["images"][0].update(placement="center"), "measured placement mismatch"))
    controls.append(expect_reject(base, repo, "clipping", lambda m: m["mac"]["images"][0].update(clip={"bottomRoundedCorners": False}), "measured clip mismatch"))
    controls.append(expect_reject(base, repo, "raw-evidence", lambda m: m["windows"]["images"][0]["rawEvidence"]["geometryRef"].update(sha256="sha256:" + "0" * 64), "byte/hash drift"))
    controls.append(expect_reject(base, repo, "raw-geometry-join", lambda m: m["mac"]["images"][0]["rawEvidence"]["geometryRef"].update(bytes=1), "byte/hash drift"))
    controls.append(expect_reject(base, repo, "source-join", lambda m: m["windows"]["images"][0].update(sourceHash="sha256:" + "0" * 64), "source join mismatch"))
    controls.append(expect_reject(base, repo, "image-hash", lambda m: m["mac"]["images"][0]["image"].update(sha256="sha256:" + "0" * 64), "byte/hash drift"))
    controls.append(expect_reject(base, repo, "canonical-tuple-hash", lambda m: m["source"].update(tupleHash="sha256:" + "0" * 64), "canonical tuple hash mismatch"))
    controls.append(expect_reject(base, repo, "canonical-case-hash", lambda m: m["source"].update(caseHash="sha256:" + "0" * 64), "canonical case hash mismatch"))
    controls.append(expect_reject(base, repo, "canonical-recipe-hash", lambda m: m["source"].update(recipeHash="sha256:" + "0" * 64), "canonical recipe hash mismatch"))
    controls.append(expect_reject(base, repo, "case-recipe-id", lambda m: m["source"].update(recipeID="mutated.recipe"), "source tuple/case/recipe identity mismatch"))
    controls.append(expect_join_reject(base, repo, "case-tuple-join", lambda d, s: (d["case"].update(tuple={"id": "wrong-tuple"}), s.update(caseHash=canonical_hash(d["case"]))), "case tuple join mismatch"))
    controls.append(expect_join_reject(base, repo, "case-recipe-join", lambda d, s: (d["case"].update(recipe={"id": d["recipe"]["id"], "hash": "sha256:" + "0" * 64}), s.update(caseHash=canonical_hash(d["case"]))), "case recipe join mismatch"))
    result = {"kind": "factory-rectangle-pixel-pair-controls-v1", "status": "passed", "controls": controls, "nativeActions": 0}
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n"); print(json.dumps(result, sort_keys=True)); return 0

if __name__ == "__main__":
    raise SystemExit(main())
