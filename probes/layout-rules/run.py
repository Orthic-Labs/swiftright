#!/usr/bin/env python3
"""Builds and runs Probe.swift offscreen on the Mac through the factory's own build roots (factory/tools/cache_paths.py: compile on /Volumes/D, launch from the internal run root).
usage: run.py [text|stack|all] > out.jsonl"""
import subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "factory/tools")); import cache_paths
here = Path(__file__).resolve().parent
lane = "layout-rules"
cache_paths.preflight("layout-rules probe")
build = cache_paths.build_root(lane); run = cache_paths.run_root(lane)
(build / "mc").mkdir(parents=True, exist_ok=True); (run / "bin").mkdir(exist_ok=True)
r = subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-O", "-module-cache-path", str(build / "mc"), "-o", str(run / "bin/probe"), str(here / "Probe.swift")], capture_output=True, text=True)
if r.returncode: sys.exit(r.stdout + r.stderr)
r = subprocess.run([str(run / "bin/probe"), *(sys.argv[1:] or ["all"])], capture_output=True, text=True, timeout=300)
sys.stdout.write(r.stdout); sys.stderr.write(r.stderr[-2000:])
cache_paths.finish_lane(lane, ok=(r.returncode == 0))
