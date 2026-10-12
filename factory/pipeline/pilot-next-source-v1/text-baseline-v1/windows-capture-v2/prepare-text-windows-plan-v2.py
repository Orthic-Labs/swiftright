#!/usr/bin/env python3
"""Emit measured Text SwiftPM Windows plan; does no compile or native action."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_COMPILER = 512 * 1024 * 1024
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RENDERER = "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
COMPILER = "1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a"

def read_json(path: Path):
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded regular JSON required: {path}")
    return json.loads(path.read_bytes())

def sha(path: Path, limit: int = MAX_FILE) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=("prebuild", "final"), required=True)
    ap.add_argument("--package", type=Path, required=True)
    ap.add_argument("--runtime-package", type=Path, required=True)
    ap.add_argument("--bridge-package", type=Path, required=True)
    ap.add_argument("--compiler", type=Path, required=True)
    ap.add_argument("--renderer", type=Path, required=True)
    ap.add_argument("--source", type=Path, required=True)
    ap.add_argument("--runtime-tree", type=Path, required=True)
    ap.add_argument("--runtime-source-tree-hash", required=True)
    ap.add_argument("--bridge-bindings", type=Path, required=True)
    ap.add_argument("--source-bindings", type=Path, required=True)
    ap.add_argument("--helper", type=Path, required=True)
    ap.add_argument("--runtime-source-receipt", type=Path, required=True)
    ap.add_argument("--runtime-verifier", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--case", type=Path)
    ap.add_argument("--expected-host-hash")
    args = ap.parse_args()
    if args.phase == "final" and (args.case is None or not args.expected_host_hash):
        raise SystemExit("--case & --expected-host-hash are required for final plan")
    if not isinstance(args.runtime_source_tree_hash, str) or not args.runtime_source_tree_hash.startswith("sha256:") or len(args.runtime_source_tree_hash) != 71:
        raise SystemExit("runtime source tree hash must be sha256:<64 hex>")
    package = args.package.resolve()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit("output must be fresh")
    compiler_hash = sha(args.compiler, MAX_COMPILER)
    renderer_hash = sha(args.renderer)
    if compiler_hash != COMPILER or renderer_hash != RENDERER:
        raise SystemExit("measured compiler/renderer hash mismatch")
    source_hash = "sha256:" + sha(args.source)
    runtime_tree_hash = "sha256:" + sha(args.runtime_tree, MAX_JSON)
    if runtime_tree_hash != args.runtime_source_tree_hash:
        raise SystemExit("runtime source tree manifest hash mismatch")
    runtime_receipt_hash = "sha256:" + sha(args.runtime_source_receipt, MAX_JSON)
    runtime_verifier_hash = sha(args.runtime_verifier)
    plan = {
        "kind": "factory-text-compiler-plan-v1", "version": 1, "phase": args.phase,
        "candidate": "swiftui.text.layout.baseline.pilot-next",
        "packagePath": str(package),
        "compileRequest": {"packagePath": str(package), "scratchPath": str(package / "build-bound-r1" / "scratch"), "kind": "swiftpm-windows-gui-release/1", "configuration": "release", "target": "windows-x86_64", "jobs": 1, "maxParallelJobs": 1},
        "runtimePackagePath": str(args.runtime_package.resolve()), "bridgePackagePath": str(args.bridge_package.resolve()),
        "compilerPath": str(args.compiler.resolve()), "compilerHash": compiler_hash,
        "rendererPath": str(args.renderer.resolve()), "rendererSha256": renderer_hash,
        "runtimeSourceCommit": RUNTIME, "runtimeSourceTreeHash": args.runtime_source_tree_hash,
        "runtimeSourceReceiptHash": runtime_receipt_hash, "runtimeVerifierHash": runtime_verifier_hash,
        "executionEligible": False, "hostMode": "renderer",
        "dispatch": {"first": {"count": 1}, "repeat": {"count": 20}},
        "sourceHash": source_hash, "sourceBindings": read_json(args.source_bindings),
        "bridgeBindings": read_json(args.bridge_bindings),
        "recipe": {"id": "swiftui.text.layout.baseline.recipe", "hash": "sha256:ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d"},
        "font": {"family": "system", "size": 24, "weight": "regular", "design": "default"},
        "viewport": {"width": 120, "height": 48, "alignment": "center"},
        "text": {"value": "Aa", "foreground": "primary", "colorScheme": "light"},
        "helperSha256": sha(args.helper),
    }
    if args.phase == "final":
        case = read_json(args.case)
        if case.get("candidate") != plan["candidate"]:
            raise SystemExit("case candidate mismatch")
        case_value = case.get("case", case)
        if not str(case_value.get("id", "")).startswith("swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light."):
            raise SystemExit("Text case prefix mismatch")
        if case_value.get("recipe", {}).get("hash") != "sha256:ebb561f9bd90022182328202879f7a6f5067c192823d519698d11a678653f73d":
            raise SystemExit("Text canonical recipe hash mismatch")
        plan["case"] = case_value
        if not isinstance(args.expected_host_hash, str) or not args.expected_host_hash.startswith("sha256:") or len(args.expected_host_hash) != 71:
            raise SystemExit("expected host hash must be sha256:<64 hex>")
        plan["expectedHostHash"] = args.expected_host_hash
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(plan, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"phase": args.phase, "output": str(output), "sourceHash": source_hash, "compilerHash": compiler_hash, "rendererHash": renderer_hash}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
