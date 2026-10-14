#!/usr/bin/env python3
"""new-case.py <block-dir/case> <Witness.swift> 'Witness_x()' [--settle S] [--dark]: creates package/ + mac-source/ for a blocks-6-10 case (Witness byte-identical in both), stamps the shared Windows host."""
import argparse, json, subprocess, sys
from pathlib import Path
H = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument("case"); ap.add_argument("witness_file"); ap.add_argument("expr")
ap.add_argument("--clock", help="F1 manual clock: comma-separated seconds; writes pair.json {\"clock\":[..]} and uses the Mac clock host (MacClockHost.template.swift)");
ap.add_argument("--settle", default="0.3"); ap.add_argument("--centered", action="store_true", default=True)  # centres through the runtime (stamp-case.py), not by translating the tree
a = ap.parse_args()
case = H / a.case; w = Path(a.witness_file).read_bytes()
(case / "package/Sources/FactoryProbe").mkdir(parents=True, exist_ok=True)
(case / "mac-source/Sources/MacHost").mkdir(parents=True, exist_ok=True)
(case / "package/Sources/FactoryProbe/Witness.swift").write_bytes(w)
(case / "mac-source/Sources/MacHost/Witness.swift").write_bytes(w)
mac_template = (H / ("MacClockHost.template.swift" if a.clock else "MacHost.template.swift")).read_text()
assert "ScalePin." in mac_template, "Mac host template does not pin the window/displayScale (decision C12; factory/tools/mac-scale-pin/pin_hosts.py)"
(case / "mac-source/Sources/MacHost/CaptureHost.swift").write_text(mac_template.replace("@@WITNESS@@", a.expr).replace("@@SETTLE@@", a.settle))
subprocess.check_call([sys.executable, str(H.parent / "pilot-delivery-five-v1/shared-windows-host/stamp-case.py"), str(case), "--witness", a.expr, "--centered"])
if a.clock:
    pj = case / "pair.json"; cfg = json.loads(pj.read_text()) if pj.is_file() else {}
    cfg["clock"] = [float(t) for t in a.clock.split(",")]
    pj.write_text(json.dumps(cfg, indent=1) + "\n")
