#!/usr/bin/env python3
"""Stamps the Mac capture host into <case>/mac-source and copies the case's Windows-package Witness.swift into it byte-for-byte.
usage: stamp-mac.py <case-dir> --witness 'Witness_x()'"""
import argparse, shutil
from pathlib import Path
HERE = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument("case"); ap.add_argument("--witness", required=True); a = ap.parse_args()
case = Path(a.case).resolve()
src = case / "mac-source/Sources/FactoryProbe"; src.mkdir(parents=True, exist_ok=True)
shutil.copy(case / "package/Sources/FactoryProbe/Witness.swift", src / "Witness.swift")
(src / "CaptureHost.swift").write_text((HERE / "CaptureHost.template.swift").read_text().replace("@@WITNESS@@", a.witness))
print("stamped", src)
