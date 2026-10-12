#!/usr/bin/env python3
"""Emit source-bound Image Windows plan; performs no compile/native action."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
COMPILER = "1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"
RENDERER = "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RECIPE_ID = "swiftui.image.baseline.recipe"

def regular(path: Path, limit: int) -> None:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")

def digest(path: Path, limit: int = MAX_FILE) -> str:
    regular(path, limit); h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return h.hexdigest()

def load(path: Path) -> object:
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding="utf-8-sig"))

def canonical(value: object) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return "sha256:" + hashlib.sha256(payload).hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=("prebuild", "final"), required=True)
    ap.add_argument("--package", type=Path, required=True)
    ap.add_argument("--runtime-package", type=Path, required=True)
    ap.add_argument("--bridge-package", type=Path, required=True)
    ap.add_argument("--compiler", type=Path, required=True)
    ap.add_argument("--renderer", type=Path, required=True)
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("--recipe", type=Path, required=True)
    ap.add_argument("--runtime-tree", type=Path, required=True)
    ap.add_argument("--runtime-source-receipt", type=Path, required=True)
    ap.add_argument("--runtime-verifier", type=Path, required=True)
    ap.add_argument("--source-bindings", type=Path, required=True)
    ap.add_argument("--bridge-bindings", type=Path, required=True)
    ap.add_argument("--helper", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--case", type=Path)
    ap.add_argument("--expected-host-hash")
    args = ap.parse_args()
    if args.phase == "final" and (args.case is None or not args.expected_host_hash):
        raise SystemExit("final phase requires fresh case & measured host hash")
    if args.output.exists(): raise SystemExit("output must be fresh")
    recipe = load(args.recipe)
    if recipe.get("kind") != "recipe" or recipe.get("id") != RECIPE_ID or recipe.get("block") != "swiftui.image":
        raise SystemExit("Image recipe identity mismatch")
    if recipe.get("inputs") != {"symbol":"star.fill","resizable":True,"fit":"contain","foreground":"yellow","colorScheme":"light","frame":{"width":32,"height":32}}:
        raise SystemExit("Image recipe inputs mismatch")
    compiler_hash, renderer_hash = digest(args.compiler, 512 * 1024 * 1024), digest(args.renderer)
    if compiler_hash != COMPILER or renderer_hash != RENDERER: raise SystemExit("compiler/renderer hash drift")
    runtime_tree_hash = "sha256:" + digest(args.runtime_tree, MAX_JSON)
    runtime_receipt_hash = "sha256:" + digest(args.runtime_source_receipt, MAX_JSON)
    plan = {"kind":"factory-image-compiler-plan-v1","version":1,"phase":args.phase,"candidate":"swiftui.image.baseline.pilot-next","block":"swiftui.image","packagePath":str(args.package.resolve()),"runtimePackagePath":str(args.runtime_package.resolve()),"bridgePackagePath":str(args.bridge_package.resolve()),"compilerPath":str(args.compiler.resolve()),"compilerHash":compiler_hash,"rendererPath":str(args.renderer.resolve()),"rendererSha256":renderer_hash,"runtimeSourceCommit":RUNTIME,"runtimeSourceTreeHash":runtime_tree_hash,"runtimeSourceReceiptHash":runtime_receipt_hash,"runtimeVerifierHash":digest(args.runtime_verifier),"sourceHash":"sha256:"+digest(args.source),"recipe":{"id":RECIPE_ID,"hash":canonical(recipe)},"sourceBindings":load(args.source_bindings),"bridgeBindings":load(args.bridge_bindings),"compileRequest":{"packagePath":str(args.package.resolve()),"scratchPath":str((args.package/"build-bound-r1"/"scratch").resolve()),"target":"windows-x86_64","configuration":"release","jobs":1,"maxParallelJobs":1},"image":recipe["inputs"],"executionEligible":False,"hostMode":"renderer","dispatch":{"first":{"count":1},"repeat":{"count":20}},"nativeParity":"hold","qualification":"source-bound observation only"}
    if args.phase == "final":
        case = load(args.case); case = case.get("case", case)
        if not str(case.get("id","")).startswith("swiftui.image.baseline.recipe.pilot-next.image-baseline-light.") or case.get("recipe",{}).get("hash") != plan["recipe"]["hash"]: raise SystemExit("fresh Image case join mismatch")
        if not isinstance(args.expected_host_hash,str) or not args.expected_host_hash.startswith("sha256:") or len(args.expected_host_hash) != 71: raise SystemExit("measured host hash malformed")
        plan["case"] = case; plan["expectedHostHash"] = args.expected_host_hash
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8", newline="\n") as stream: json.dump(plan, stream, ensure_ascii=False, sort_keys=True, indent=2); stream.write("\n")
    print(json.dumps({"phase":args.phase,"output":str(args.output),"sourceHash":plan["sourceHash"],"recipeHash":plan["recipe"]["hash"]},sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
