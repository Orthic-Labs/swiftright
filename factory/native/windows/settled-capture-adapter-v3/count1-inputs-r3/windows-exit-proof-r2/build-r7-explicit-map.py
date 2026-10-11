#!/usr/bin/env python3
"""Build explicit, byte-checked r7 proof inputs from fetched production refs.

This only joins existing files. It never rewrites native observations or
creates fallback/source substitutes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def read(path: Path):
    return json.loads(path.read_bytes().decode("utf-8-sig"))


def digest(path: Path) -> tuple[str, int]:
    raw = path.read_bytes()
    return "sha256:" + hashlib.sha256(raw).hexdigest(), len(raw)


def ref(value, root: Path) -> dict:
    if isinstance(value, str):
        path = value
        expected = None
    elif isinstance(value, dict) and isinstance(value.get("path"), str):
        path = value["path"]
        expected = value.get("sha256")
    else:
        raise ValueError("invalid source reference")
    local = (root / path).resolve(strict=True)
    actual, size = digest(local)
    if expected is not None and actual != expected:
        raise ValueError(f"source byte mismatch:{path}")
    return {"path": path, "sha256": actual, "bytes": size}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-root", type=Path, default=Path("."))
    ap.add_argument("--actual-map", type=Path, required=True)
    ap.add_argument("--adapter-inputs", type=Path, required=True)
    ap.add_argument("--compiler-ref", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    root = args.source_root.resolve(strict=True)
    actual = read(args.actual_map)
    adapter = read(args.adapter_inputs)
    if len(actual.get("runs", [])) != 1:
        raise ValueError("r7 Count1 map required")
    source = adapter.get("source", {})
    roles = adapter.get("roles", {})
    run = adapter["runs"][0]
    base = root / "factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7"
    # All thirteen roles are explicit. compile is compile receipt; observation
    # is native observation, as required by reader's run/host checks.
    role_values = {
        "outcome": run["outcome"],
        "observation": run["observation"],
        "owned": run["owned"],
        "close": run["close"],
        "plan": roles["plan"],
        "compile": roles["compile"],
        "witness": source["Sources/FactoryProbe/Witness.swift"],
        "exe": roles["exe"],
        "renderer": roles["renderer"],
        "runtimeReceipt": source["runtime-source-receipt.json"],
        "runtimeTree": source["runtime-source-tree.json"],
        "stdout": run["stdout"],
        "stderr": run["stderr"],
    }
    bound_roles = {name: ref(value, root) for name, value in role_values.items()}
    plan = read(root / bound_roles["plan"]["path"])
    compile_record = read(root / bound_roles["compile"]["path"])
    tree = read(root / bound_roles["runtimeTree"]["path"])
    receipt = read(root / bound_roles["runtimeReceipt"]["path"])
    if not isinstance(tree, list) or len(tree) != 21:
        raise ValueError("runtime tree must contain exact 21 rows")
    if len(receipt.get("sourceBindings", [])) != 21:
        raise ValueError("runtime receipt must contain exact 21 source rows")
    # Host source bindings are plan-bound and separately checked against actual
    # source map entries. Runtime tree is resolved to source package files,
    # never to runtime-module archives.
    host = []
    for row in plan.get("sourceBindings", []):
        rel = row.get("path")
        if rel not in source:
            raise ValueError(f"missing host source map row:{rel}")
        item = ref(source[rel], root)
        if item["sha256"] != row.get("sha256"):
            raise ValueError(f"host source plan mismatch:{rel}")
        host.append({"path": rel, "source": item})
    runtime_root = Path("factory/native/windows/module-origin-37429120-20261011/runtime")
    runtime = []
    for row in tree:
        rel = row.get("path")
        if not isinstance(rel, str):
            raise ValueError("runtime tree path missing")
        item = ref({"path": str(runtime_root / rel)}, root)
        if item["sha256"] != row.get("sha256"):
            raise ValueError(f"runtime source tree mismatch:{rel}")
        runtime.append({"path": rel, "source": item, "sha256": row["sha256"]})
    modules = {}
    for archive_path, value in adapter.get("runtimeModules", {}).items():
        item = ref(value, root)
        modules[archive_path] = item
    if len(modules) != 2:
        raise ValueError("exact two runtime module refs required")
    compiler_ref = read(args.compiler_ref)
    compiler = ref(compiler_ref, root)
    if compiler["sha256"] != compiler_ref.get("sha256"):
        raise ValueError("compiler ref byte mismatch")
    native_obs = read(root / bound_roles["observation"]["path"])
    native_dir = Path(bound_roles["observation"]["path"]).parent / "native-01"
    raw = []
    for row in native_obs.get("files", []):
        rel = row.get("path")
        local = native_dir / rel
        item = ref({"path": str(local)}, root)
        expected = "sha256:" + str(row.get("sha256", "")).removeprefix("sha256:")
        if item["sha256"] != expected:
            raise ValueError(f"native raw mismatch:{rel}")
        raw.append({"path": rel, "source": item, "sha256": expected})
    if len(raw) != 24:
        raise ValueError("exact 24 native observation raw rows required")
    compile_raw = []
    for row in compile_record.get("files", []):
        # Successful compile output is already bound as exe; stream files are
        # optional fetched refs and are recorded only when present.
        rel = row.get("path")
        candidate = Path(bound_roles["compile"]["path"]).parent / rel
        if candidate.is_file():
            item = ref({"path": str(candidate)}, root)
            compile_raw.append({"path": rel, "source": item, "sha256": row.get("sha256")})
    output = {
        "schema": "windows-exit-proof-explicit-inputs-v2",
        "status": "source-bound",
        "actualMap": str(args.actual_map),
        "adapterInputs": str(args.adapter_inputs),
        "runs": [run],
        "roles": bound_roles,
        "hostSourceBindings": host,
        "runtimeTreeBindings": runtime,
        "runtimeModules": modules,
        "compiler": compiler,
        "compilerRef": str(args.compiler_ref),
        "nativeObservationRaw": raw,
        "compileObservationRaw": compile_raw,
        "sourceFacts": {
            "runtimeSourceCommit": receipt["sourceCommit"],
            "runtimeSourceTreeHash": receipt["sourceTreeHash"],
            "runtimeTreeRows": len(runtime),
            "hostRows": len(host),
            "nativeRawRows": len(raw),
            "compileRawRows": len(compile_raw),
        },
    }
    if args.output.exists():
        raise ValueError("output must be fresh")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": output["status"], "hostRows": len(host), "runtimeRows": len(runtime), "rawRows": len(raw)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
