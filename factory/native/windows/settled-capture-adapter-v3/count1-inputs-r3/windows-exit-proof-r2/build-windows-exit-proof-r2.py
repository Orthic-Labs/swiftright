#!/usr/bin/env python3
"""Attach byte-bound exit proof to fetched r7 captures.

v2 keeps reader paths equal to production raw names, binds runtime source tree
rows to 21 source files, keeps two module archives separate, and records every
source byte used by proof. Missing/invalid facts remain blocked diagnostics.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROLES = (
    "outcome", "observation", "owned", "close", "plan", "compile", "witness",
    "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr",
)
ROLE_PATHS = {
    "outcome": "capture-outcome.json",
    "observation": "native-observation.json",
    "owned": "owned-process.json",
    "close": "owned-close.json",
    "plan": "plan.json",
    "compile": "observation.json",
    "witness": "Witness.swift",
    "exe": "FactoryProbe.exe",
    "renderer": "swiftright_render.dll",
    "runtimeReceipt": "runtime-source-receipt.json",
    "runtimeTree": "runtime-source-tree.json",
    "stdout": "host.stdout.txt",
    "stderr": "host.stderr.txt",
}


def read(path: Path):
    return json.loads(path.read_bytes().decode("utf-8-sig"))


def sha(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def source_ref(item, root: Path):
    if not isinstance(item, dict) or not isinstance(item.get("path"), str):
        raise ValueError("source ref shape")
    path = (root / item["path"]).resolve(strict=True)
    raw = path.read_bytes()
    digest = sha(raw)
    if item.get("sha256") != digest or item.get("bytes") != len(raw):
        raise ValueError(f"source ref drift:{item['path']}")
    return path, digest, len(raw)


def put(archive, key, path, digest, size):
    if key in archive:
        old = archive[key]
        if old["sourcePath"] != str(path) or old["sha256"] != digest:
            raise ValueError(f"archive path collision:{key}")
        return
    archive[key] = {"sourcePath": str(path), "sha256": digest, "bytes": size}


def gate_result(capture, archive, root):
    gate_file = root / "factory/native/windows/remaining-five-hosts-v5/dependencies/windows_exit_admission.py"
    spec = importlib.util.spec_from_file_location("r2_windows_exit_gate", gate_file)
    if spec is None or spec.loader is None:
        raise ValueError("production gate unavailable")
    gate = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(root))
    spec.loader.exec_module(gate)

    def reader(path):
        if path not in archive:
            raise ValueError(f"archive reader missing:{path}")
        source = Path(archive[path]["sourcePath"])
        raw = source.read_bytes()
        if sha(raw) != archive[path]["sha256"]:
            raise ValueError(f"archive source drift:{path}")
        return raw

    return gate.verify_windows_exit_admission(capture, read_bytes=reader)


def build(args):
    root = args.source_root.resolve(strict=True)
    inputs = read(args.input_map)
    payload = read(args.captures)
    captures = payload.get("captures") if isinstance(payload, dict) else None
    if not isinstance(captures, list) or len(captures) not in (1, 20):
        raise ValueError("Count1/Count20 captures required")
    if len(inputs.get("runs", [])) != len(captures):
        raise ValueError("run/capture count mismatch")
    compiler = source_ref(inputs["compiler"], root)
    output = {
        "schema": "windows-exit-proof-bundle-v2",
        "status": "blocked",
        "typedStatus": payload.get("typedStatus"),
        "captures": [],
        "archiveBindings": {},
        "sourceFacts": {"roles": len(ROLES), "hostRows": 0, "runtimeRows": 0, "runtimeModuleRows": 0, "nativeRawRows": 0},
        "gateResults": [],
        "issues": [],
    }
    for index, capture in enumerate(captures, 1):
        archive = {}
        try:
            if not isinstance(capture, dict) or capture.get("platform") != "windows":
                raise ValueError("Windows capture required")
            run = inputs["runs"][index - 1]
            role_entries = inputs["roles"]
            role_values = {
                "outcome": run["outcome"], "observation": run["observation"], "owned": run["owned"],
                "close": run["close"], "plan": role_entries["plan"], "compile": role_entries["compile"],
                "witness": inputs["roles"]["witness"],
                "exe": role_entries["exe"], "renderer": role_entries["renderer"],
                "runtimeReceipt": inputs["roles"]["runtimeReceipt"],
                "runtimeTree": inputs["roles"]["runtimeTree"],
                "stdout": run["stdout"], "stderr": run["stderr"],
            }
            proof_files = {}
            for role in ROLES:
                path, digest, size = source_ref(role_values[role], root)
                dest = ROLE_PATHS[role]
                put(archive, dest, path, digest, size)
                proof_files[role] = {"path": dest, "hash": digest}
            plan_path, _, _ = source_ref(role_values["plan"], root)
            plan = read(plan_path)
            for row in plan.get("sourceBindings", []):
                rel = row.get("path")
                host_item = next((x["source"] for x in inputs.get("hostSourceBindings", []) if x.get("path") == rel), None)
                if host_item is None:
                    raise ValueError(f"missing host source:{rel}")
                path, digest, size = source_ref(host_item, root)
                if digest != row.get("sha256"):
                    raise ValueError(f"host source byte mismatch:{rel}")
                put(archive, f"host/{rel}", path, digest, size)
                output["sourceFacts"]["hostRows"] += 1
            tree_path, _, _ = source_ref(inputs["roles"]["runtimeTree"], root)
            tree = read(tree_path)
            if len(tree) != 21:
                raise ValueError("runtime source tree must contain 21 rows")
            for row in tree:
                rel = row["path"]
                runtime_item = next((x for x in inputs["runtimeTreeBindings"] if x["path"] == rel), None)
                if runtime_item is None:
                    raise ValueError(f"runtime tree source missing:{rel}")
                path, digest, size = source_ref(runtime_item["source"], root)
                if digest != row["sha256"]:
                    raise ValueError(f"runtime source byte mismatch:{rel}")
                put(archive, f"runtime/{rel}", path, digest, size)
                output["sourceFacts"]["runtimeRows"] += 1
            for n, item in enumerate(inputs.get("runtimeModules", {}).values(), 1):
                path, digest, size = source_ref(item, root)
                put(archive, f"runtime-modules/{n:03d}-{path.name}", path, digest, size)
                output["sourceFacts"]["runtimeModuleRows"] += 1
            path, digest, size = compiler
            put(archive, "tool/compiler.bin", path, digest, size)
            native_obs_path, _, _ = source_ref(role_values["observation"], root)
            native_obs = read(native_obs_path)
            native_dir = native_obs_path.parent / "native-01"
            raw_names = set()
            for row in native_obs.get("files", []):
                rel = row.get("path")
                if not isinstance(rel, str) or rel in raw_names:
                    raise ValueError("native raw row duplicate/invalid")
                raw_names.add(rel)
                raw_path = (native_dir / rel).resolve(strict=True)
                raw = raw_path.read_bytes()
                digest = sha(raw)
                expected = "sha256:" + str(row.get("sha256", "")).removeprefix("sha256:")
                if digest != expected:
                    raise ValueError(f"native raw byte mismatch:{rel}")
                put(archive, rel, raw_path, digest, len(raw))
                output["sourceFacts"]["nativeRawRows"] += 1
            if output["sourceFacts"]["nativeRawRows"] != 24:
                raise ValueError("exact native raw closure required")
            enriched = json.loads(json.dumps(capture))
            enriched.setdefault("meta", {}).setdefault("conditions", {})["windowsExitProof"] = {"version": 1, "files": proof_files}
            output["captures"].append(enriched)
            output["archiveBindings"][str(index)] = archive
            if args.verify_gate:
                output["gateResults"].append(gate_result(enriched, archive, root))
        except (ValueError, KeyError, TypeError, OSError, UnicodeError, ImportError) as exc:
            output["issues"].append(f"run{index}:{exc}")
    if not output["issues"]:
        output["status"] = "proofs-attached"
        output["typedStatus"] = "normalized-observational"
    if args.output.exists():
        raise ValueError("output must be fresh")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": output["status"], "proofCount": len(output["captures"]), "issues": output["issues"], "gate": output["gateResults"]}, sort_keys=True))
    return 0 if output["status"] == "proofs-attached" else 2


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-root", type=Path, default=Path("."))
    ap.add_argument("--captures", type=Path, required=True)
    ap.add_argument("--input-map", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--verify-gate", action="store_true")
    return build(ap.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
