#!/usr/bin/env python3
"""Build probe.swift on the internal disk (same lane as pair.py: xcrun swiftc, module cache under ~/Library/Caches) and run it. No window, no TCC."""
import subprocess, sys
from pathlib import Path
here = Path(__file__).resolve().parent
cache = Path.home() / "Library/Caches/SwiftRightFactory/appkit-probe"; (cache / "mc").mkdir(parents=True, exist_ok=True)
subprocess.run(["/usr/bin/xcrun", "swiftc", "-O", "-module-cache-path", str(cache / "mc"), "-o", str(cache / "probe"), str(here / "probe.swift")], check=True)
sys.exit(subprocess.run([str(cache / "probe")]).returncode)
