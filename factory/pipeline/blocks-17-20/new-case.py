#!/usr/bin/env python3
"""new-case.py <block-dir/case> <Witness.swift> 'Witness_x()' [--appearance aqua|darkAqua|none] [--scheme light|dark|none] [--settle S]
Creates package/ (Windows: Witness.swift + the stamped shared host, not centred, white viewport) and mac-source/ (Witness byte-identical + the blocks-17-20 Mac host)."""
import argparse, subprocess, sys
from pathlib import Path
H = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument("case"); ap.add_argument("witness_file"); ap.add_argument("expr")
ap.add_argument("--appearance", default="aqua", choices=["aqua", "darkAqua", "none"]); ap.add_argument("--scheme", default="light", choices=["light", "dark", "none"]); ap.add_argument("--settle", default="0.3"); ap.add_argument("--alert-host", action="store_true", help="Windows host with the dialog coordinator (blocks-17-20/shared-windows-host); Mac host: see mac-alert.py")
a = ap.parse_args()
case = H / a.case; w = Path(a.witness_file).read_bytes()
(case / "package/Sources/FactoryProbe").mkdir(parents=True, exist_ok=True)
(case / "mac-source/Sources/MacHost").mkdir(parents=True, exist_ok=True)
(case / "package/Sources/FactoryProbe/Witness.swift").write_bytes(w)
(case / "mac-source/Sources/MacHost/Witness.swift").write_bytes(w)
t = (H / "shared-mac-host/CaptureHost.template.swift").read_text()
(case / "mac-source/Sources/MacHost/CaptureHost.swift").write_text(t.replace("@@WITNESS@@", a.expr).replace("@@SETTLE@@", a.settle).replace("@@APPEARANCE@@", a.appearance).replace("@@SCHEME@@", a.scheme).replace("@@ALERTS@@", "yes" if a.alert_host else "no"))
subprocess.check_call([sys.executable, str(H.parent / "pilot-delivery-five-v1/shared-windows-host/stamp-case.py"), str(case), "--witness", a.expr])
if a.alert_host:
    import shutil
    src = case / "package/Sources/FactoryProbe"
    (src / "main.swift").write_text((H / "shared-windows-host/CaptureHost.template.swift").read_text().replace("@@WITNESS@@", a.expr).replace("@@CENTERED@@", "false").replace("@@DARK@@", "false"))
    shutil.copy(H / "shared-windows-host/FactoryViewport.swift", src / "FactoryViewport.swift")
