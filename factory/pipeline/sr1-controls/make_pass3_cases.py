#!/usr/bin/env python3
"""Stamps the issue #60 pass 3 control cases (sidebar List, multi-line TextField) from the progress-determinate-v1 template: the capture hosts, viewport and package are the
template's, only the witness type name and file and pair.json differ. Re-running replaces the cases (a case's `runs/` is kept).
usage: make_pass3_cases.py [case-substring ...]"""
import json, shutil, sys
from pathlib import Path
H = Path(__file__).resolve().parent
TEMPLATE = H / "swiftui.progress" / "progress-determinate-v1"
TEMPLATE_TYPE = "Witness_p60_progress_determinate_v1"
HEADER = "#if os(Windows)\nimport Foundation\nimport SwiftRightRuntime\n#else\nimport SwiftUI\nimport CoreGraphics\n#endif\n\n"
CASES = {}

# ---- sidebar List -----------------------------------------------------------------------------------------------------------------------------------------------------
# The List is 200 x 160 pt centred in the 320 x 240 pt viewport: (150, 100) px at scale 2.5, as in the blocks 24-25 list cases. Sidebar rows are 32 pt = 80 px from the 10 pt (25 px) top inset.
ROW_TOP, ROW_H = 125, 80
rows = 5
CASES["swiftui.list-sidebar/sidebar-list-v1"] = dict(
    type="Witness_p60_sidebar_list_v1",
    body='''// Issue #60 pass 3, case sidebar-list-v1: `.listStyle(.sidebar)`: the grey ground, 32 pt rows, the rounded selection (row 2) and no separators. The row insets, the ground and the
// selection colours are ESTIMATES (E13 measured only the ground 229, the 32 pt rows and the rounded selection); this case is what measures them.
struct Witness_p60_sidebar_list_v1: View {
    @State private var selection: Int? = 2
    var body: some View {
        List(selection: $selection) { ForEach(0..<5, id: \\.self) { i in Text("Row \\(i)").tag(i) } }.listStyle(.sidebar).frame(width: 200, height: 160)
    }
}''',
    pair={
        "listGate": {"rowsTopPx": ROW_TOP, "rowHeightPx": ROW_H, "listRect": [150, 100, 650, 500], "textColourTolerance": 40, "rows": rows},
        "excludeRects": [{"name": f"row {i} label glyph region (Segoe UI vs SF, sr1-decisions #2); ink colour gated by pair_list_report.py",
                          "rect": [195, ROW_TOP + ROW_H * i + 16, 360, ROW_TOP + ROW_H * i + 64]} for i in range(rows)],
        "edgeAATolerance": {"levels": 32, "maxOverFraction": 0.02, "maxMeanAbs": 2,
                            "reason": "PROVISIONAL (issue #60 pass 3): the selection's rounded corners reuse the inset style's measured outline; the sidebar's own corner radius is not measured. Tighten to the first pair's measured stats."},
        "steps": [{"op": "wait", "ms": 600}],
        "macArgs": ["--steps", json.dumps([{"op": "wait", "ms": 600}], separators=(",", ":"))],
    })

# ---- multi-line TextField ---------------------------------------------------------------------------------------------------------------------------------------------
# Three vertical-axis fields 160 pt wide in a 240 x 200 pt frame centred in the viewport: (100, 50) px. Explicit line breaks keep the line count the same on both platforms (a wrap
# would depend on Segoe UI against SF glyph widths). Heights: 3 lines 8 + 3 x 16 = 56 pt, the same text limited to 2 lines 40 pt, an empty field 24 pt; 18 pt between them.
# The column is 56 + 18 + 40 + 18 + 24 = 156 pt, centred in 200: top at 20 + 22 = 42 pt = 105 px; the fields are 160 pt = 400 px wide from x = 200 px.
F1 = (105, 245); F2 = (290, 390); F3 = (435, 495)
CASES["swiftui.textfield/textfield-multiline-v1"] = dict(
    type="Witness_p60_textfield_multiline_v1",
    body='''// Issue #60 pass 3, case textfield-multiline-v1: `TextField(axis: .vertical)` grows one line at a time up to the `lineLimit`. The bezel heights 56 / 40 / 24 pt follow from the one-line
// field (8 pt of cell inset + 16 pt per line); this case measures them. The text and the placeholder are excluded from the pixel gate (Segoe UI against SF).
struct Witness_p60_textfield_multiline_v1: View {
    @State private var notes = "line one\\nline two\\nline three"
    @State private var empty = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Notes", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 160)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(2).textFieldStyle(.roundedBorder).frame(width: 160)
            TextField("Empty", text: $empty, axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 160)
        }
        .frame(width: 240, height: 200)
    }
}''',
    pair={
        "excludeRects": [{"name": f"field {i} text and placeholder glyph region (Segoe UI vs SF, sr1-decisions #2)", "rect": [212, y0 + 8, 590, y1 - 8]}
                         for i, (y0, y1) in enumerate([F1, F2, F3])],
        "edgeAATolerance": {"levels": 32, "maxOverFraction": 0.02, "maxMeanAbs": 2,
                            "reason": "PROVISIONAL (issue #60 pass 3): bezel corner anti-aliasing is the measured TextFieldArtwork's (block 13); the multi-line frames are unmeasured."},
    })


def stamp(name, spec):
    dest = H / name
    runs = None
    if (dest / "runs").exists():
        runs = dest.parent / (dest.name + ".runs-keep"); shutil.move(str(dest / "runs"), str(runs))
    if dest.exists(): shutil.rmtree(dest)
    shutil.copytree(TEMPLATE, dest, ignore=shutil.ignore_patterns("runs", "pair.json"))
    for f in dest.rglob("*.swift"):
        text = f.read_text()
        if TEMPLATE_TYPE in text: f.write_text(text.replace(TEMPLATE_TYPE, spec["type"]))
    for w in (dest / "mac-source/Sources/MacHost/Witness.swift", dest / "package/Sources/FactoryProbe/Witness.swift"):
        w.write_text(HEADER + spec["body"] + "\n")
    (dest / "pair.json").write_text(json.dumps(spec["pair"], indent=1) + "\n")
    if runs: shutil.move(str(runs), str(dest / "runs"))
    print("stamped", name)


if __name__ == "__main__":
    wanted = sys.argv[1:]
    for name, spec in CASES.items():
        if not wanted or any(w in name for w in wanted): stamp(name, spec)
