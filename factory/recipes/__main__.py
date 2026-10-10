"""Command line entry point: ``python -m factory.recipes``."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from factory.core.artifacts import load_artifact, write_artifact
from .cases import expand_cases, validate_case_manifest
from .recipes import DATA, load_recipes, recipe_by_id


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Load recipe drafts or expand a measured case manifest")
    parser.add_argument("--list", action="store_true", help="list recipe IDs and review state")
    parser.add_argument("--recipe", help="recipe artifact ID or block ID")
    parser.add_argument("--tuple", dest="tuple_path", help="path to measured schema 0.1 tuple JSON")
    parser.add_argument("--seed", type=int, default=0, help="deterministic pairwise generator seed")
    parser.add_argument("--snapshot-created-at", help="explicit RFC 3339 timestamp for deterministic case provenance")
    parser.add_argument("--out", help="write manifest and cases as canonical JSON")
    parser.add_argument("--out-dir", help="write manifest.json and one canonical case JSON per case")
    args = parser.parse_args(argv)
    try:
        if args.list:
            value = [{"id": recipe["id"], "block": recipe["block"],
                      "review": recipe["provenance"].get("review", {}).get("decision", "pending")}
                     for recipe in load_recipes()]
            print(json.dumps(value, ensure_ascii=False, indent=2))
            return 0
        if not args.recipe or not args.tuple_path:
            parser.error("--recipe & --tuple are required unless --list is used")
        recipe = recipe_by_id(args.recipe)
        tuple_value = load_artifact(args.tuple_path)
        expansion = expand_cases(recipe, tuple_value, seed=args.seed,
                                 snapshot_created_at=args.snapshot_created_at)
        validate_case_manifest(expansion)
        if args.out and args.out_dir:
            parser.error("use only one of --out or --out-dir")
        if args.out:
            write_artifact(args.out, expansion)
        elif args.out_dir:
            output_dir = Path(args.out_dir)
            write_artifact(output_dir / "manifest.json", expansion["manifest"])
            for case in expansion["cases"]:
                filename = case["id"].replace("/", "--") + ".json"
                write_artifact(output_dir / filename, case)
        else:
            print(json.dumps(expansion, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError) as exc:
        print(f"factory.recipes: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
