#!/usr/bin/env python3
"""Wave 0 / F0 block cases (docs/probes/f0-renderer-text-facts.md): the E14c measurement cases, a custom-font (bundled Tinos Regular) title-size sweep, Mac vs Windows.
Stamped through new-case.py (ScalePin-pinned Mac host, byte-identical Witness). Not a gate: the cases exist so the Windows and Mac ink boxes of every row can be read
(factory/pipeline/blocks-f0/ink_rows.py); pair.json carries a wide text gate only so the run records a verdict.
usage: make_cases.py [case-substring ...]
Rows are Text("Pulse Hub") in Tinos-Regular at SIZE with a frame height of line height + EXTRA, line height = round(ascent) + round(descent) of the hhea table (decision E12).
The witness is a 260 x 200 pt frame top-leading in the 320 x 240 pt viewport: its origin is (30, 20) pt = client pixel (75, 50) at scale 2.5."""
import json, math, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
ROOT = H.parents[2]
FONT_FILE = str((ROOT / "factory/resources/fonts/Tinos-Regular.ttf").resolve())
FONT_NAME = "Tinos-Regular"
ASC, DESC, UPEM = 1825, 443, 2048   # Tinos hhea ascent, descent (abs), unitsPerEm


def lh(size):
    r = lambda v: math.floor(v + 0.5)
    return r(ASC / UPEM * size) + r(DESC / UPEM * size)


# case -> rows (size, extra points on top of the line height)
CASES = {
    "title-sweep-a-v1": [(24, 4), (26, 4), (27, 4), (28, 4), (29, 4)],
    "title-sweep-b-v1": [(30, 4), (31, 4), (32, 4), (36, 4), (20, 4)],
    "title-28-extra-v1": [(28, 0), (28, 1), (28, 2), (28, 3), (28, 4)],
}


def witness(name, rows):
    t = "Witness_f0_" + name.replace("-", "_")
    body = "\n".join(f'            Text("Pulse Hub").font(.custom("{FONT_NAME}", size: {s})).frame(width: 240, height: {lh(s) + e}, alignment: .leading)' for s, e in rows)
    src = f"""#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct {t}_inner: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 0) {{
{body}
        }}
    }}
}}

struct {t}: View {{
    var body: some View {{ {t}_inner().frame(width: 260, height: 200, alignment: .topLeading) }}
}}
"""
    return t, src


def main():
    only = sys.argv[1:]
    for name, rows in CASES.items():
        if only and not any(o in name for o in only):
            continue
        t, src = witness(name, rows)
        case = f"swiftui.font-custom/{name}"
        (H / case).mkdir(parents=True, exist_ok=True)
        pair = {"textGate": {"helper": "factory/tools/pair_text_report.py", "rect": [75, 50, 725, 550], "edgeTolerancePx": 4, "ink": "half-coverage (luminance<=127)"},
                "excludeRects": [{"name": "E14c measurement case: every row's glyph region is measured per row by blocks-f0/ink_rows.py, not gated (decision G10)", "rect": [75, 50, 725, 550]}]}
        with tempfile.TemporaryDirectory() as d:
            w = Path(d) / "Witness.swift"; w.write_text(src); pj = Path(d) / "pair.json"; pj.write_text(json.dumps(pair))
            subprocess.check_call([sys.executable, str(H / "new-case.py"), case, str(w), f"{t}()", "--font", FONT_FILE, "--pair-json", str(pj)])
    print("rows (size: line height):", {s: lh(s) for s in (20, 24, 26, 27, 28, 29, 30, 31, 32, 36)})


main()
