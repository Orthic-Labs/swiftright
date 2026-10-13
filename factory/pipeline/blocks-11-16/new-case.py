#!/usr/bin/env python3
"""new-case.py <block-dir/case> <Witness.swift> 'Witness_x()' [--settle S] [--steps steps.json] [--pair-json extra.json]
Creates package/ (Windows: Witness.swift + the blocks-11-16 host, root centred through the runtime in the viewport) and mac-source/ (Witness byte-identical + the blocks-11-16 Mac host).
--steps: interaction steps (the F2 vocabulary, factory/tools/sandbox/guest/job-interact.ps1); written to pair.json "steps" (Windows Sandbox) and "macArgs" (--steps, the Mac host).
--pair-json: a JSON object merged into pair.json (gates, excludeRects)."""
import argparse, json, shutil, subprocess, sys
from pathlib import Path
H = Path(__file__).resolve().parent
ap = argparse.ArgumentParser(); ap.add_argument("case"); ap.add_argument("witness_file"); ap.add_argument("expr")
ap.add_argument("--settle", default="0.3"); ap.add_argument("--steps"); ap.add_argument("--pair-json")
a = ap.parse_args()
case = H / a.case; w = Path(a.witness_file).read_bytes()
(case / "package/Sources/FactoryProbe").mkdir(parents=True, exist_ok=True)
(case / "mac-source/Sources/MacHost").mkdir(parents=True, exist_ok=True)
(case / "package/Sources/FactoryProbe/Witness.swift").write_bytes(w)
(case / "mac-source/Sources/MacHost/Witness.swift").write_bytes(w)
t = (H / "shared-mac-host/CaptureHost.template.swift").read_text()
(case / "mac-source/Sources/MacHost/CaptureHost.swift").write_text(t.replace("@@WITNESS@@", a.expr).replace("@@SETTLE@@", a.settle))
subprocess.check_call([sys.executable, str(H.parent / "pilot-delivery-five-v1/shared-windows-host/stamp-case.py"), str(case), "--witness", a.expr, "--centered"], stdout=subprocess.DEVNULL)
src = case / "package/Sources/FactoryProbe"
# centre through the runtime (ZStack in a viewport-sized frame, as the Mac hosts do), never by translating the finished tree (blocks-6-10/pixel-ties/README.md)
centred = "ZStack(alignment: .center) { " + a.expr + " }.frame(width: CGFloat(metrics.width) / CGFloat(scale), height: CGFloat(metrics.height) / CGFloat(scale), alignment: .center)"
(src / "main.swift").write_text((H / "shared-windows-host/CaptureHost.template.swift").read_text().replace("@@WITNESS@@", centred).replace("@@CENTERED@@", "false").replace("@@DARK@@", "false"))
shutil.copy(H / "shared-windows-host/FactoryViewport.swift", src / "FactoryViewport.swift")
cfg = {}
if a.pair_json: cfg.update(json.loads(Path(a.pair_json).read_text()))
if a.steps:
    steps = json.loads(Path(a.steps).read_text()); steps = steps["steps"] if isinstance(steps, dict) else steps
    cfg["steps"] = steps; cfg["macArgs"] = ["--steps", json.dumps(steps, separators=(",", ":"))]
if cfg: (case / "pair.json").write_text(json.dumps(cfg, indent=1) + "\n")
print("stamped", case)
