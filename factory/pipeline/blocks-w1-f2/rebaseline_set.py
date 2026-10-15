#!/usr/bin/env python3
"""Builds rebaseline-set.json: the cases F2 reruns at N=3 because body text moves from 12 to 13 DIP, system fonts take the Mac line metrics and every run is kerned
(decisions G40, G70+). A case is in the set when its latest Windows host log shows a TEXT_MEASURE line, or (no run log kept) its witness draws Text, Button, Toggle, TextField,
Label, List, Picker, an alert, a menu, a section or sets a font. Scope: the SR1 closure N=3 regression set (closure/run_closure.py JOBS) plus the round 4 and round 5 blocks
(21-25, 26-34, the cases that draw text). Not in the set: the F0 E14c measurement cases (custom font, not gated), the F2 cases, cases of other lanes (I2, T0 image cases)."""
import glob, json, os, re
from pathlib import Path
PIPE = Path(__file__).resolve().parents[1]; os.chdir(PIPE)
pat = re.compile(r'\bText\(|Button\(|Toggle\(|TextField|Label\(|\bList\b|Picker|\.alert|confirmationDialog|Menu\(|SecureField|\.font\(|Section\(')


def src_text(c):
    out = ""
    for p in glob.glob(c + "/package/Sources/**/*.swift", recursive=True) + glob.glob(c + "/mac-source/Sources/**/*.swift", recursive=True):
        if os.path.basename(p) in ("main.swift", "CaptureHost.swift", "FactoryViewport.swift"): continue
        out += open(p, errors="replace").read()
    return out


def draws_text(c):
    runs = sorted(glob.glob(c + "/runs/*/windows/host-01.stdout.txt"))
    return bool(runs and "TEXT_MEASURE" in open(runs[-1], errors="replace").read()) or bool(pat.search(src_text(c)))


src = open("closure/run_closure.py").read().rsplit("\nmain()", 1)[0]
ns = {"__file__": os.path.abspath("closure/run_closure.py")}; exec(src, ns)
chosen = [c for l, c, n in ns["JOBS"] if draws_text(c)]
for blk in ("blocks-21-23", "blocks-24-25", "blocks-26-34"):
    for p in sorted(glob.glob(f"{blk}/*/*/mac-source")):
        c = os.path.dirname(p)
        if c not in chosen and draws_text(c): chosen.append(c)
(Path(__file__).parent / "rebaseline-set.json").write_text(json.dumps(chosen, indent=0) + "\n")
print(len(chosen), "cases")
