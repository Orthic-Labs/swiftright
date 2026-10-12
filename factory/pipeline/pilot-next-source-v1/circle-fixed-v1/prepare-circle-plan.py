#!/usr/bin/env python3
"""Create bounded Circle plan metadata; never compiles or launches hosts."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024

def regular(path: Path, limit: int) -> Path:
    st = path.stat()
    if path.is_symlink() or not path.is_file() or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return path

def sha(path: Path, limit: int) -> str:
    regular(path, limit)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()

def json_file(path: Path) -> dict:
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding="utf-8"))

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--recipe", type=Path, required=True)
    parser.add_argument("--case", type=Path, required=True)
    parser.add_argument("--witness", type=Path, required=True)
    parser.add_argument("--runtime-shapes", type=Path, required=True)
    parser.add_argument("--host-branch", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    recipe = json_file(args.recipe)
    case = json_file(args.case)
    if recipe.get("id") != "swiftui.circle.fixed.recipe": raise ValueError("unexpected recipe")
    if recipe.get("inputs", {}).get("frameDip") != {"width": 40, "height": 40}: raise ValueError("frame")
    inputs = recipe.get("inputs", {})
    if inputs.get("viewportDip") != {"width": 320, "height": 240}: raise ValueError("viewportDip")
    if recipe.get("inputs", {}).get("semanticColor") != "system.blue": raise ValueError("color")
    if case.get("candidate") != "swiftui.circle.fixed.pilot-next": raise ValueError("case candidate")
    if case.get("recipe", {}).get("sha256") != sha(args.recipe, MAX_JSON): raise ValueError("case recipe hash")
    files = {
        "recipe": (str(args.recipe), sha(args.recipe, MAX_JSON)),
        "caseInputs": (str(args.case), sha(args.case, MAX_JSON)),
        "witness": (str(args.witness), sha(args.witness, MAX_SOURCE)),
        "runtimeShapes": (str(args.runtime_shapes), sha(args.runtime_shapes, MAX_SOURCE)),
        "hostBranch": (str(args.host_branch), sha(args.host_branch, MAX_SOURCE)),
    }
    expected = recipe.get("witness", {}).get("path")
    supplied = args.witness.as_posix()
    if expected and not (supplied == Path(expected).as_posix() or supplied.endswith("/" + Path(expected).as_posix())):
        raise ValueError("recipe witness path mismatch")
    payload = {
        "kind": "factory-circle-fixed-plan-v1",
        "candidate": "swiftui.circle.fixed.pilot-next",
        "status": "SOURCE_ONLY",
        "runtimeCommit": recipe["provenance"]["runtimeCommit"],
        "runtimeSourceTreeHash": recipe["provenance"]["runtimeSourceTreeHash"],
        "inputs": recipe["inputs"],
        "files": {key: {"path": value[0], "sha256": value[1]} for key, value in files.items()},
        "effects": {"compilerActions": 0, "nativeActions": 0, "guiActions": 0, "remoteActions": 0, "lockActions": 0},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return 0

if __name__ == "__main__": raise SystemExit(main())
