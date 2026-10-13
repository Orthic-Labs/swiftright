#!/usr/bin/env python3
"""make-case.py <case-dir> <WitnessTypeName>: Witness.swift is the case's own source (already in <case>/package/Sources/FactoryProbe/); copies it
byte-identically into mac-source and stamps both hosts (Windows: shared-windows-host/stamp-case.py; Mac: shared/MacHost.swift)."""
import subprocess, sys, shutil
from pathlib import Path
HERE = Path(__file__).resolve().parent
case = Path(sys.argv[1]).resolve(); w = sys.argv[2]
src = case / "package/Sources/FactoryProbe/Witness.swift"
assert src.is_file()
msrc = case / "mac-source/Sources/FactoryProbe"; msrc.mkdir(parents=True, exist_ok=True)
shutil.copy(src, msrc / "Witness.swift")
(msrc / "CaptureHost.swift").write_text((HERE / "MacHost.swift").read_text().replace("@@WITNESS@@", f"{w}()"))
stamp = HERE.parents[2] / "pilot-delivery-five-v1/shared-windows-host/stamp-case.py"
win = f"ZStack(alignment: .center) {{ {w}() }}.frame(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale), alignment: .center)"
subprocess.check_call([sys.executable, str(stamp), str(case), "--witness", win])
