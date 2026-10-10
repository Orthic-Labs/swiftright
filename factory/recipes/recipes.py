"""Load checked-in recipe drafts and verify witness source hashes."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from factory.core.artifacts import file_hash, load_artifact, validate_artifact

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
WITNESSES = ROOT / "witnesses"


def load_recipes() -> list[dict[str, Any]]:
    """Load recipes in stable ID order and verify their schema & source bindings."""
    recipes = [load_artifact(path) for path in sorted(DATA.glob("*.json"))]
    for recipe in recipes:
        validate_artifact(recipe)
        for witness in recipe["witnesses"]:
            path = WITNESSES / f'{witness["id"]}.swift'
            actual = file_hash(path)
            if actual != witness["sourceHash"]:
                raise ValueError(f"witness source hash mismatch: {path}")
            for resource in witness.get("resources", []):
                if resource["hash"] != actual:
                    raise ValueError(f"witness resource hash mismatch: {path}")
        for negative in recipe.get("negativeCases", []):
            path = WITNESSES / f'{negative["id"]}.swift'
            if file_hash(path) != negative.get("sourceHash"):
                raise ValueError(f"negative witness source hash mismatch: {path}")
    ids = [recipe["id"] for recipe in recipes]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate recipe ID")
    return recipes


def recipe_by_id(recipe_id: str) -> dict[str, Any]:
    """Return one recipe by artifact ID or block ID."""
    for recipe in load_recipes():
        if recipe["id"] == recipe_id or recipe["block"] == recipe_id:
            return recipe
    raise KeyError(f"unknown recipe: {recipe_id}")
