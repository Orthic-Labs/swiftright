#!/usr/bin/env python3
"""Build probe.swift (module cache on /Volumes/D, binary on the internal disk; see cache_paths.py) and run it. No window, no TCC."""
import subprocess, sys
from pathlib import Path
here = Path(__file__).resolve().parent
sys.path.insert(0, str(here.parent)); import cache_paths
cache_paths.preflight("appkit-probe")
lane = f"appkit-probe-{__import__('os').getpid()}"
build, cache = cache_paths.build_root("appkit-probe"), cache_paths.run_root(lane)   # module cache on /Volumes/D, the probe binary internal
(build / "mc").mkdir(parents=True, exist_ok=True)
subprocess.run(["/usr/bin/xcrun", "swiftc", "-O", "-module-cache-path", str(build / "mc"), "-o", str(cache / "probe"), str(here / "probe.swift")], check=True)
rc = subprocess.run([str(cache / "probe")]).returncode
cache_paths.finish_lane(lane, ok=rc == 0)
sys.exit(rc)
