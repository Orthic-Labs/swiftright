#!/usr/bin/env python3
"""Fills the text gate rectangle of every swiftui.font-custom case from its Mac capture: the ink bounding box (any pixel that is not the white ground) plus a 6 px margin, the
excluded region (named; glyph AA differs by rasteriser, DirectWrite vs CoreText), and the colour gate region. usage: fit_text_regions.py [case-substring ...]
It runs the Mac side of each case once (`pair.py --skip-windows`) and rewrites <case>/pair.json; run it again whenever FONT_FILE / FONT_NAME or a witness changes."""
import json, re, subprocess, sys
from pathlib import Path
from PIL import Image
H = Path(__file__).resolve().parent
for case in sorted((H / "swiftui.font-custom").iterdir()):
    if len(sys.argv) > 1 and not any(a in case.name for a in sys.argv[1:]): continue
    r = subprocess.run([sys.executable, str(H.parent.parent / "tools/pair.py"), str(case), "--runs", "1", "--skip-windows"], capture_output=True, text=True)
    m = re.search(r"out=(\S+)", r.stdout)
    if not m: sys.exit(f"{case.name}: Mac capture failed\n{r.stdout[-400:]}{r.stderr[-400:]}")
    im = Image.open(Path(m.group(1)) / "mac/run-01.png").convert("RGB")
    bb = im.point(lambda v: 255 if v < 250 else 0).convert("L").getbbox()
    rect = [max(0, bb[0] - 6), max(0, bb[1] - 6), min(800, bb[2] + 6), min(600, bb[3] + 6)]
    pj = case / "pair.json"; cfg = json.loads(pj.read_text())
    cfg["textGate"]["rect"] = rect
    cfg["excludeRects"] = [{"name": f"glyph region {rect} (ink bbox mac {list(bb)}); AA only (DirectWrite grayscale vs CoreText, same font bytes); gated by factory/tools/pair_text_report.py: exact outside, half-coverage ink bbox within 1 px", "rect": rect}]
    cfg["textColourGate"] = {"tolerance": 24, "regions": [{"name": "custom font text", "rect": rect}]}
    pj.write_text(json.dumps(cfg, indent=1) + "\n")
    print(case.name, rect)
