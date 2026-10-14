#!/usr/bin/env python3
"""Creates (or re-stamps) every blocks-24-25 case (SR1 round 4, extension requested by the Pulse hub track): block 24 swiftui.list-row-style, block 25 swiftui.font-custom.
usage: make_cases.py [case-substring ...]   (same shape as blocks-21-23/make_cases.py and blocks-11-16/make_cases.py)"""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n\n"
CASES = {}


def case(name, typename, body, pair=None, steps=None, fonts=()):
    if steps is None and name.startswith("swiftui.list-row-style/"): steps = [{"op": "wait", "ms": 600}]   # the list gate reads the UI Automation tree the interaction job dumps
    CASES[name] = dict(type=typename, body=body, pair=pair, steps=steps, fonts=list(fonts))


# ---- block 24: swiftui.list-row-style ------------------------------------------------------------------------------------------------------------------------------------
# The List is 200 x 160 pt at (150, 100) px in the 800 x 600 capture; rows are 60 px tall from y = 125 (inset) or 100 (plain).
ROW_TOP, ROW_H = 125, 60


def list_gate(rows=5, plain=False):
    top = 100 if plain else ROW_TOP
    cfg = {"listGate": {"rowsTopPx": top, "rowHeightPx": ROW_H, "listRect": [150, 100, 650, 500], "textColourTolerance": 40, "rows": rows}}
    cfg["excludeRects"] = [{"name": f"row {i} label glyph region (Segoe UI vs SF, sr1-decisions #2); ink colour gated by pair_list_report.py",
                            "rect": [(170 if plain else 190), top + ROW_H * i + 12, 340, top + ROW_H * i + 48]} for i in range(rows)]
    return cfg


T = "Witness_lrs_"


def case24(name, typename, body, plain=False):
    case(name, typename, body, list_gate(5, plain))


def lst(t, mods_per_row="", style="", selection=False, rows=5, per_row=None, list_mods=""):
    head = "List(selection: $sel)" if selection else "List"
    tag = ".tag(i)" if selection else ""
    state = "@State private var sel: Int? = 2" if selection else ""
    row = per_row or f'Text("Row \\(i)"){mods_per_row}'
    return f"""struct {t}: View {{
    {state}
    var body: some View {{
        {head} {{ ForEach(0..<{rows}, id: \\.self) {{ i in {row}{tag} }} }}{style}{list_mods}.frame(width: 200, height: 160)
    }}
}}"""


case24("swiftui.list-row-style/sep-hidden-all-v1", T + "sep_hidden_all", lst(T + "sep_hidden_all", ".listRowSeparator(.hidden)"))
case24("swiftui.list-row-style/sep-hidden-some-v1", T + "sep_hidden_some", lst(T + "sep_hidden_some", per_row='Text("Row \\(i)").listRowSeparator(i % 2 == 1 ? .hidden : .visible)'))
case24("swiftui.list-row-style/bg-colour-v1", T + "bg_colour", lst(T + "bg_colour", ".listRowBackground(Color.red)"))
case24("swiftui.list-row-style/bg-view-v1", T + "bg_view", lst(T + "bg_view", ".listRowBackground(Rectangle().fill(Color.blue))"))
case24("swiftui.list-row-style/plain-sep-hidden-v1", T + "plain_sep_hidden", lst(T + "plain_sep_hidden", ".listRowSeparator(.hidden)", style=".listStyle(.plain)"), plain=True)
case24("swiftui.list-row-style/plain-bg-colour-v1", T + "plain_bg_colour", lst(T + "plain_bg_colour", ".listRowBackground(Color.green)", style=".listStyle(.plain)"), plain=True)
case24("swiftui.list-row-style/selected-bg-v1", T + "selected_bg", lst(T + "selected_bg", ".listRowBackground(Color.red)", selection=True))
case24("swiftui.list-row-style/plain-selected-bg-v1", T + "plain_selected_bg", lst(T + "plain_selected_bg", ".listRowBackground(Color.red)", style=".listStyle(.plain)", selection=True), plain=True)
# .listStyle(.sidebar): measured on the Mac (grey 229 ground, 32 pt rows, rounded selection) but not drawn by the host: not delivered (decision E13)


# ---- block 25: swiftui.font-custom --------------------------------------------------------------------------------------------------------------------------------------
# Frame heights are the line height (round(ascent) + round(descent) of the font at that size) plus a multiple of 4 points, so the text's top edge is on a whole point: an odd
# remainder puts the baseline on a half point and the Windows glyphs sit 1-2 px off the Mac's (measured on title-28).
# The display font is a parameter: FONT_FILE is the bundled file (Windows registers it through the renderer, ABI 0.7; the Mac registers the same bytes for the process) and FONT_NAME the
# PostScript name `Font.custom` takes. Until the hub's real display font (file, licence and title style) arrives this is Tinos-Regular (factory/resources/fonts, the bundled-font pilot's
# font); the real one drops in by changing these two lines and re-running `make_cases.py` and `fit_text_regions.py`.
FONT_FILE = str((H.parent.parent / "resources/fonts/Tinos-Regular.ttf").resolve())
FONT_NAME = "Tinos-Regular"
F = "SwiftUI.Font"


def font_case(name, typename, body, semantic=False):
    # the witness sits top-leading in a 260 x 200 frame: its origin (30, 20) pt is on even whole points, so text rows whose frame height is the line height plus a multiple of 4 land on even points
    body = body.replace(f"struct {typename}: View", f"struct {typename}_inner: View", 1) + f"""

struct {typename}: View {{
    var body: some View {{ {typename}_inner().frame(width: 260, height: 200, alignment: .topLeading) }}
}}"""
    # the text gate (pair_text_report.py) needs the glyph rectangle: fit_text_regions.py fills it from the Mac capture; exact outside it
    case(f"swiftui.font-custom/{name}", typename, body, {"textGate": {"helper": "factory/tools/pair_text_report.py", "rect": [0, 0, 800, 600], "edgeTolerancePx": 1, "ink": "half-coverage (luminance<=127)"}, **({"semanticGate": {"fields": ["role", "name", "enabled", "count", "order"], "scope": "main", "phases": [""]}} if semantic else {})},
         [{"op": "wait", "ms": 600}] if semantic else None, [FONT_FILE])


TF = "Witness_fc_"
font_case("title-32-v1", TF + "title_32", f"""struct {TF}title_32: View {{
    var body: some View {{
        Text("Pulse Hub").font(.custom("{FONT_NAME}", size: 32)).frame(width: 240, height: 44, alignment: .leading)
    }}
}}""")
font_case("sizes-v1", TF + "sizes", f"""struct {TF}sizes: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 0) {{
            Text("Thirteen").font(.custom("{FONT_NAME}", size: 13)).frame(width: 240, height: 23, alignment: .leading)
            Text("Eighteen").font(.custom("{FONT_NAME}", size: 18)).frame(width: 240, height: 28, alignment: .leading)
            Text("Thirty-one").font(.custom("{FONT_NAME}", size: 31)).frame(width: 240, height: 43, alignment: .leading)
        }}
    }}
}}""")
font_case("uppercase-string-v1", TF + "upper_string", f"""struct {TF}upper_string: View {{
    var body: some View {{
        Text("PULSE HUB SETTINGS").font(.custom("{FONT_NAME}", size: 20)).frame(width: 260, height: 30, alignment: .leading)
    }}
}}""")
font_case("colour-v1", TF + "colour", f"""struct {TF}colour: View {{
    var body: some View {{
        Text("Pulse Hub").font(.custom("{FONT_NAME}", size: 24)).foregroundStyle(Color.red).frame(width: 240, height: 34, alignment: .leading)
    }}
}}""")
font_case("text-case-uppercase-v1", TF + "text_case", f"""struct {TF}text_case: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 0) {{
            Text("Pulse hub settings").font(.custom("{FONT_NAME}", size: 20)).textCase(.uppercase).frame(width: 260, height: 30, alignment: .leading)
            Text("PULSE Hub").font(.custom("{FONT_NAME}", size: 20)).textCase(.lowercase).frame(width: 260, height: 30, alignment: .leading)
        }}
    }}
}}""", semantic=True)
font_case("two-lines-v1", TF + "two_lines", f"""struct {TF}two_lines: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 0) {{
            Text("Pulse").font(.custom("{FONT_NAME}", size: 36)).frame(width: 240, height: 48, alignment: .leading)
            Text("Hub overview").font(.custom("{FONT_NAME}", size: 16)).frame(width: 240, height: 25, alignment: .leading)
        }}
    }}
}}""")


def main():
    only = sys.argv[1:]
    for name, c in CASES.items():
        if only and not any(o in name for o in only): continue
        with tempfile.TemporaryDirectory() as d:
            w = Path(d) / "Witness.swift"; w.write_text(HEADER + c["body"] + "\n")
            cmd = [sys.executable, str(H / "new-case.py"), name, str(w), c["type"] + "()"]
            if c["pair"]:
                p = Path(d) / "pair.json"; p.write_text(json.dumps(c["pair"])); cmd += ["--pair-json", str(p)]
            if c["steps"]:
                s = Path(d) / "steps.json"; s.write_text(json.dumps(c["steps"])); cmd += ["--steps", str(s)]
            for f in c["fonts"]: cmd += ["--font", f]
            subprocess.check_call(cmd)


if __name__ == "__main__":
    main()
