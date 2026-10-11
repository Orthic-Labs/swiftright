#!/usr/bin/env python3
"""Replayable compiler control; outputs stay in fresh internal scratch."""
from __future__ import annotations
import argparse
import importlib.util
import os
import shutil
from pathlib import Path

def repo_root() -> Path:
    injected = os.environ.get("SWIFTRIGHT_REPO_ROOT")
    candidates = [Path(injected).expanduser().resolve()] if injected else []
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        if (candidate / "factory/core/artifacts.py").is_file() and (candidate / "factory/oracle").is_dir():
            return candidate
    raise RuntimeError("repository root marker factory/core/artifacts.py not found")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch", required=True, type=Path)
    args = parser.parse_args()
    scratch = args.scratch.expanduser().resolve()
    allowed = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory").resolve()
    scratch != allowed and scratch.is_relative_to(allowed) or parser.error("scratch must be fresh internal cache child")
    if scratch.exists():
        parser.error("scratch already exists; refusing output overwrite")
    root = repo_root()
    source = root / "factory/oracle/mac/seed-origin-v4/positive-control/source"
    source.is_dir() or parser.error("positive source directory missing")
    work = scratch / "work"
    evidence = scratch / "evidence"
    work.mkdir(parents=True)
    evidence.mkdir()
    for name in ("Witness.swift", "CaptureHost.swift"):
        shutil.copy2(source / name, work / name)
    module_path = root / "factory/oracle/mac/seed-origin-v4/capture_origin.py"
    spec = importlib.util.spec_from_file_location("seed_origin_v4_collector", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("collector unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result, receipt = module.compiler_build(work, evidence, work / "capture-host")
    print({"returncode": result.returncode, "status": receipt.get("status"), "compilerExit": (receipt.get("compiler") or {}).get("exitCode"), "binary": (receipt.get("compiler") or {}).get("outputBinary"), "sourceDir": str(source), "collector": str(module_path)}, flush=True)
    return result.returncode

if __name__ == "__main__":
    raise SystemExit(main())
