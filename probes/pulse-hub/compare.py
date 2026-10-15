#!/usr/bin/env python3
"""usage: compare.py <windows interact dir> <mac ref dir (qa-evidence artifact)> <out dir> :
light: Tauri screenshot | Mac SwiftUI | Windows through SwiftRight; dark: Mac SwiftUI | Windows. All panels 900x600 (Windows 2250x1500 at scale 2.5 is downscaled).
PNGs are palette-quantised to stay far under 1 MB."""
import sys, os
from PIL import Image, ImageDraw
win, mac, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
secs = "overview activity storage cleanup monitor apps chat permissions accounts appearance notifications general".split()
tauri = {s: f"{mac}/screenshots/{n:02d}-{s}.png" for n, s in zip([1,2,3,4,5,6,12,7,8,9,10,11], secs)}
W, H, BAR = 900, 600, 26
def panel(path, label, size=(W, H)):
    im = Image.new("RGB", (W, H + BAR), (255, 255, 255)); d = ImageDraw.Draw(im); d.text((8, 7), label, fill=(0, 0, 0))
    if path and os.path.exists(path):
        p = Image.open(path).convert("RGB")
        im.paste(p.resize((W, H), Image.LANCZOS) if p.size != (W, H) else p, (0, BAR))
    else:
        d.rectangle([0, BAR, W, H + BAR], fill=(235, 235, 235)); d.text((W // 2 - 120, H // 2), "not rendered (see the render status table)", fill=(90, 0, 0))
    return im
n = 0
for k, s in enumerate(secs):
    for j, scheme in enumerate(("light", "dark")):
        i = 2 * k + j + 1
        wpath = f"{win}/native-{i:02d}-hub.png"
        panels = ([panel(tauri[s], f"Tauri hub (CI screenshot) - {s}")] if scheme == "light" else []) + [panel(f"{mac}/swiftui/{s}-{scheme}.png", f"Mac SwiftUI (CI) - {s} {scheme}"), panel(wpath, f"Windows, SwiftRight probe - {s} {scheme}")]
        sheet = Image.new("RGB", (W * len(panels), H + BAR), (255, 255, 255))
        for x, p in enumerate(panels): sheet.paste(p, (x * W, 0))
        f = f"{out}/{s}-{scheme}.png"; sheet.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)
        n += 1; print(f, os.path.getsize(f))
