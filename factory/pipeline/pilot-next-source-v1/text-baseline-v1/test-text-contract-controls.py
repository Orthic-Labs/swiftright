#!/usr/bin/env python3
"""Pure source controls for Text baseline; no compiler, GUI, or native action."""
from __future__ import annotations
import copy, hashlib, json, re
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAX_JSON = 2 * 1024 * 1024
HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")

def read_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded JSON required: {path}")
    return json.loads(path.read_bytes())

def file_hash(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded source required: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return "sha256:" + h.hexdigest()

def validate(contract: dict, recipe: dict, witness_hash: str) -> None:
    inputs = contract["inputs"]
    font = inputs["font"]
    if contract["candidate"] != "swiftui.text.layout.baseline.pilot-next": raise ValueError("candidate drift")
    if inputs != {"text":"Aa","font":{"family":"system","size":24,"weight":"regular","design":"default"},"foreground":"primary","colorScheme":"light","viewport":{"width":120,"height":48,"alignment":"center"}}: raise ValueError("Text contract drift")
    if contract["recipe"]["hash"] != "sha256:f36beada372c117f860413ddfedb3645b11292a0ab8d2c71d9dc781ef6f8f12d": raise ValueError("recipe hash drift")
    if contract["witness"]["sha256"] != witness_hash or not HASH.fullmatch(witness_hash): raise ValueError("witness hash drift")
    if font["size"] != 24 or contract["assertions"]["frame"] != {"width":120,"height":48}: raise ValueError("font/viewport drift")

def validate_source_recipe_join(source_inputs: dict) -> None:
    """Source manifest stores naked recipeHash; refs store sha256-prefixed hash."""
    expected = "ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d"
    if source_inputs["recipeHash"] != expected:
        raise ValueError("source recipeHash drift")
    if source_inputs["recipeRef"]["sha256"] != "sha256:" + source_inputs["recipeHash"]:
        raise ValueError("source recipe reference/hash join mismatch")

def expect_reject(name: str, value: dict, recipe: dict, witness_hash: str, mutate) -> dict:
    changed = copy.deepcopy(value); mutate(changed)
    try: validate(changed, recipe, witness_hash)
    except ValueError: return {"name": name, "rejected": True}
    raise AssertionError(f"fault accepted: {name}")

def expect_source_reject(name: str, value: dict, mutate) -> dict:
    changed = copy.deepcopy(value); mutate(changed)
    try: validate_source_recipe_join(changed)
    except (KeyError, ValueError): return {"name": name, "rejected": True}
    raise AssertionError(f"fault accepted: {name}")

def main() -> int:
    contract = read_json(HERE / "case-inputs.json")
    recipe = read_json(HERE / "recipe.json")
    witness_hash = file_hash(HERE / "witness.swift")
    validate(contract, recipe, witness_hash)
    source_inputs = {
        "recipeHash": "ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d",
        "recipeRef": {"sha256": "sha256:ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d"},
    }
    validate_source_recipe_join(source_inputs)
    faults = [
        expect_reject("font-size", contract, recipe, witness_hash, lambda x: x["inputs"]["font"].__setitem__("size", 25)),
        expect_reject("viewport", contract, recipe, witness_hash, lambda x: x["inputs"]["viewport"].__setitem__("width", 121)),
        expect_reject("text", contract, recipe, witness_hash, lambda x: x["inputs"].__setitem__("text", "Ab")),
        expect_reject("witness", contract, recipe, witness_hash, lambda x: x["witness"].__setitem__("sha256", "sha256:" + "0" * 64)),
        expect_source_reject("naked-recipe-hash", source_inputs, lambda x: x.__setitem__("recipeHash", "sha256:" + x["recipeHash"])),
    ]
    print(json.dumps({"kind":"factory-text-contract-controls-v1","status":"SOURCE_CONTROLS_DEFINED","faultControls":faults}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
