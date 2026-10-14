#!/usr/bin/env python3
"""Move everything except report.json, *report.json, build.json, diff-01*.png, mac/run-01*.png, windows/native-01*.png out of untracked run dirs into ~/.Trash/<tag> (never deletes)."""
import os, re, shutil, subprocess, sys, time
T = os.path.expanduser("~/.Trash/sr1-trim-" + time.strftime("%H%M%S")); n = 0
files = [l[3:] for l in subprocess.check_output(["git", "status", "--short", "-uall"], text=True).splitlines() if l.startswith("??")]
def keep(rel):
    b, d = os.path.basename(rel), os.path.dirname(rel)
    return (b == "build.json" or b.endswith("report.json") or re.fullmatch(r"diff-01(-f\d+)?\.png", b)
            or (d.endswith("/mac") and re.fullmatch(r"run-01(-f\d+)?\.png", b)) or (d.endswith("/windows") and re.fullmatch(r"native-01(-f\d+)?\.png", b)))
for f in files:
    if "/runs/" not in f or keep(f): continue
    dst = os.path.join(T, f); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.move(f, dst); n += 1
print("moved", n, "to", T)
