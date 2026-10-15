#!/usr/bin/env python3
"""Creates (or re-stamps) the block 29 cases (SR1 round 5, hub gap R1): swiftui.system-symbols. Every case is a grid of font-sized, NON-resizable
Image(systemName:) cells in the 240 x 200 pt witness frame (origin (40, 20) pt in the 320 x 240 pt viewport, scale 2.5). A cell is a fixed frame;
the symbol sits centred in it at the environment font (body 13 pt when none is set), tinted with foregroundStyle.
Gates (factory/tools/symbol-metrics/pair_symbols_report.py, pair.json "symbolGate"): per cell the Windows-logged Image frame, the half-coverage ink box
(Mac == Windows == the table's Mac measurement) and the tint colour; the glyph shape (Segoe Fluent Icons vs SF Symbols, decision 3) is reported, never gated.
The tree (role, count, order) is gated by pair.py's semantic gate with pixels report-only.
usage: make_cases_symbols.py [case-substring ...]"""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n\n"
SCALE, OX, OY = 2.5, 40, 20
CASES = {}
# system colours as the Mac renders them in the light appearance (HostPaint.semanticLight, read from SwiftUI renders at scale 2.5)
TINTS = [("Color.blue", (0, 136, 255)), ("Color.red", (255, 56, 60)), ("Color.green", (52, 199, 89)), ("Color.orange", (255, 141, 40)),
         ("Color.purple", (203, 48, 224)), ("Color.gray", (142, 142, 147))]
HUB = ["arrow.clockwise", "arrow.down", "arrow.up", "arrow.up.arrow.down", "checkmark", "checkmark.shield", "chevron.down", "chevron.right", "chevron.up",
       "circle.lefthalf.filled", "clock.arrow.circlepath", "doc", "doc.on.doc", "exclamationmark.triangle", "exclamationmark.triangle.fill", "externaldrive",
       "folder", "folder.badge.plus", "gauge.with.dots.needle.33percent", "gearshape", "hourglass", "info.circle", "info.circle.fill", "internaldrive",
       "magnifyingglass", "message", "minus", "minus.square.fill", "network", "pencil", "person.crop.circle", "plus", "sidebar.left", "sparkles",
       "square.dashed", "square.grid.2x2", "square.grid.3x3", "switch.2", "trash", "tray", "xmark", "xmark.circle", "xmark.circle.fill", "xmark.octagon.fill", "app.dashed"]
HUB_EXTRA = ["paintpalette", "bell", "checkmark.circle", "checkmark.circle.fill", "checkmark.square.fill", "link", "waveform.path.ecg", "cpu", "memorychip", "terminal", "textbox"]   # Settings sections and toasts (asked for by the hub run)


def pxr(x0, y0, x1, y1):
    return [round((OX + x0) * SCALE), round((OY + y0) * SCALE), round((OX + x1) * SCALE), round((OY + y1) * SCALE)]


def grid(name, typename, items, cols, cw, ch, font=None, frame_w=None, marker=False, tolerance=0, note=""):
    """items: [(symbol, size pt or None, font expr or None)]; cell = cw x ch pt (the Image frame(width: frame_w) when frame_w is given)."""
    rows = [items[i:i + cols] for i in range(0, len(items), cols)]
    lines, cells = [], []
    for r, row in enumerate(rows):
        cs = []
        for c, (sym, size, fexpr) in enumerate(row):
            tint_expr, tint = TINTS[(r + c) % len(TINTS)]
            f = f".font({fexpr})" if fexpr else ""
            w = frame_w or cw
            cs.append(f'Image(systemName: "{sym}"){f}.foregroundStyle({tint_expr}).frame(width: {w}, height: {ch})')
            x0 = c * (cw + (8 + 40 if marker else 0))
            cells.append(dict(name=sym, size=size if size else 13, cellPx=pxr(x0, r * ch, x0 + w, (r + 1) * ch), tint=list(tint)))
        if marker:   # the hub sidebar row: Image frame + 8 pt gap + a 40 x 6 marker (text stands in as a fixed rectangle: text is gated elsewhere)
            cs = [f'HStack(spacing: 8) {{ {x}; Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 6) }}' for x in cs]
        lines.append("            HStack(spacing: 0) { " + "; ".join(cs) + " }")
    body = f"""struct {typename}: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 0) {{
{chr(10).join(lines)}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}"""
    steps = [{"op": "wait", "ms": 700}, {"op": "dump", "label": "start"}, {"op": "wait", "ms": 250}, {"op": "shot", "label": "start"}, {"op": "wait", "ms": 200}]
    pair = {"semanticGate": {"fields": ["role", "count", "order"], "scope": "main", "phases": ["start", ""], "pixels": "report-only"},
            "phaseShots": ["start"], "excludeRects": [{"name": "symbol glyph shapes (Segoe Fluent Icons vs SF Symbols, sr1-decisions #3); gated by symbolGate", "rect": pxr(0, 0, 240, 200)}],
            "symbolGate": {"assets": "packages/SwiftRightHost/Assets/SystemImageAssets.json", "scale": SCALE, "outsetPx": 6, "tolerancePx": tolerance, "tintTolerance": 3,
                           "note": note, "cells": cells}}
    CASES["swiftui.system-symbols/" + name] = dict(type=typename, body=body, pair=pair, steps=steps)


def items(names, size=None, fexpr=None):
    return [(n, size, fexpr) for n in names]


S28 = "Font.system(size: 28, weight: .regular)"
# 1. every hub symbol at the default (body) font: 10 x 5 cells of 24 x 24 pt
grid("body-all-v1", "Witness_sym_body_all", items(HUB + HUB_EXTRA), 10, 24, 24)
# 2. the hub sidebar row: frame(width: 16), the Image alone in the row (a marker stands in for the label)
grid("frame16-v1", "Witness_sym_frame16", items(HUB[:24]), 3, 16, 24, frame_w=16, marker=True)
# 3. the hub card / search result row: frame(width: 20)
grid("frame20-v1", "Witness_sym_frame20", items(HUB[24:45]), 3, 20, 24, frame_w=20, marker=True)
# 4. the hub empty state: Font.system(size: 28, weight: .regular), tinted
grid("size28-v1", "Witness_sym_size28", items(HUB[:30], 28, S28), 6, 40, 40)
grid("size28-b-v1", "Witness_sym_size28b", items(HUB[30:] + HUB_EXTRA, 28, S28), 6, 40, 40)
# 5. other measured system sizes and the text styles that are regular system sizes
SIZES = [10, 11, 12, 15, 17, 20, 22]
grid("sizes-v1", "Witness_sym_sizes", [(s, z, f"Font.system(size: {z}, weight: .regular)") for s in ("gearshape", "doc", "chevron.right", "magnifyingglass") for z in SIZES], 7, 34, 34)
STYLES = [("callout", 12), ("subheadline", 11), ("footnote", 10), ("caption", 10), ("title3", 15), ("title2", 17), ("title", 22)]
grid("text-styles-v1", "Witness_sym_styles", [(s, z, "." + st) for s in ("gearshape", "doc", "sidebar.left") for st, z in STYLES], 7, 34, 34)
# 6. sizes that were not measured: the table interpolates between measured sizes; judged to 1 px (reported, not generalisation evidence)
grid("sizes-interpolated-v1", "Witness_sym_interp", [(s, z, f"Font.system(size: {z}, weight: .regular)") for s in ("gearshape", "doc", "sidebar.left") for z in (19, 21, 25, 27)],
     4, 40, 40, tolerance=1, note="interpolated sizes: the ink and frame are judged to 1 px; this case is not evidence of generalisation")


def main():
    only = sys.argv[1:]
    for name, c in CASES.items():
        if only and not any(o in name for o in only): continue
        with tempfile.TemporaryDirectory() as d:
            w = Path(d) / "Witness.swift"; w.write_text(HEADER + c["body"] + "\n")
            p = Path(d) / "pair.json"; p.write_text(json.dumps(c["pair"]))
            s = Path(d) / "steps.json"; s.write_text(json.dumps(c["steps"]))
            subprocess.check_call([sys.executable, str(H / "new-case.py"), name, str(w), c["type"] + "()", "--pair-json", str(p), "--steps", str(s)])


if __name__ == "__main__":
    main()
