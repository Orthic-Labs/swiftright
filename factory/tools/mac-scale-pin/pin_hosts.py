#!/usr/bin/env python3
"""Idempotent patcher (decision C12): makes a Mac capture host pin the window's backing scale / SwiftUI displayScale to the capture scale and report it through
ScalePin (factory/tools/mac-scale-pin/ScalePin.swift, compiled in by pair.py). usage: pin_hosts.py FILE... ; prints one line per file: patched|already|skipped (reason)."""
import re, sys
from pathlib import Path

def patch(t):
    if "ScalePin." in t:
        return None, "already"
    if "@main" not in t:
        return None, "skipped (no @main)"
    o = t
    has_window = re.search(r"^[ \t]*window\.contentView = host[ \t]*$", t, re.M)
    if "PinnedScaleWindow" in t:        # blocks 18/19 hosts (decision C11): keep the window class, report through ScalePin, default the static hosts to the capture scale
        t = re.sub(r"^[ \t]*let screens = NSScreen\.screens.*\n", "", t, flags=re.M)
        t = re.sub(r"^[ \t]*print\(\"MAC_ENV .*\n", "", t, flags=re.M)
        t = t.replace('Double(value("--display-scale") ?? "2") ?? 2', 'Double(value("--display-scale") ?? "") ?? scale')
    elif "override var backingScaleFactor: CGFloat { captureScale }" in t:
        t = t.replace("override var backingScaleFactor: CGFloat { captureScale }", "override var backingScaleFactor: CGFloat { ScalePin.scale }")
    elif re.search(r"\bNSWindow\(contentRect: host\.frame", t):
        t = re.sub(r"\bNSWindow\(contentRect: host\.frame", "ScalePinnedWindow(contentRect: host.frame", t)
    elif has_window:
        return None, "skipped (window of an unknown class)"
    if has_window:
        if len(re.findall(r"^[ \t]*window\.contentView = host[ \t]*$", t, re.M)) != 1:
            return None, "skipped (several windows)"
        t = re.sub(r"^([ \t]*)window\.contentView = host[ \t]*$", lambda m: m.group(0) + f"\n{m.group(1)}ScalePin.report(window: window)", t, count=1, flags=re.M)
    else:
        m = re.search(r"renderer\.scale = (\w+)", t)
        if not m:
            return None, "skipped (no window and no ImageRenderer scale)"
        ln = re.search(r"^([ \t]*)(?:let|var) renderer = ImageRenderer\(content:", t, re.M)
        if not ln:
            return None, "skipped (ImageRenderer not bound to `renderer`)"
        t = t[:ln.start()] + f"{ln.group(1)}ScalePin.reportRenderer(scale: {m.group(1)})\n" + t[ln.start():]
    return t, "patched"

for f in sys.argv[1:]:
    p = Path(f); new, why = patch(p.read_text())
    if new is not None: p.write_text(new)
    print(why, f)
