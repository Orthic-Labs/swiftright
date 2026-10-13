#!/usr/bin/env python3
"""Creates (or re-stamps) every blocks-11-16 case (lane A: block 11 swiftui.button, block 16 swiftui.list). Witness text lives here, once per case;
new-case.py writes package/ + mac-source/ (Witness byte-identical) and pair.json. Run from anywhere. usage: make_cases.py [case-substring ...]"""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n\n"
CASES = {}


def case(name, typename, body, pair=None, steps=None):
    CASES[name] = dict(type=typename, body=body, pair=pair, steps=steps)


# ---- block 11: swiftui.button -------------------------------------------------------------------------------------------------------------------------------------------
BUTTON_GATE = {"buttonGate": {"capPx": 28, "yTolerancePx": 0, "labelCentreTolerancePx": 3, "labelColourTolerance": 40, "edgeAA": 32}}
# "Run" label, 24 x 16 pt, centred in the 320 x 240 pt viewport: ink (372, 289)-(427, 314) px on the Mac
LABEL_RECT = [360, 280, 440, 325]
LABEL_GATE = {"excludeRects": [{"name": "'Run' label glyph region (Segoe UI vs SF, sr1-decisions #2); colour gated by factory/tools/pair_textcolour_report.py", "rect": LABEL_RECT}],
              "textColourGate": {"tolerance": 24, "regions": [{"name": "Run", "rect": LABEL_RECT}]}}


def text_button(name, typename, modifiers, gate):
    case(f"swiftui.button/{name}", typename, f"""struct {typename}: View {{
    var body: some View {{
        Button("Run") {{}}{modifiers}.frame(width: 100, height: 40)
    }}
}}""", gate)


text_button("bordered-v1", "Witness_button_bordered", ".buttonStyle(.bordered)", BUTTON_GATE)
text_button("prominent-v1", "Witness_button_prominent", ".buttonStyle(.borderedProminent)", BUTTON_GATE)
text_button("prominent-disabled-v1", "Witness_button_prominent_disabled", ".buttonStyle(.borderedProminent).disabled(true)", BUTTON_GATE)
text_button("default-action-v1", "Witness_button_default_action", ".keyboardShortcut(.defaultAction)", BUTTON_GATE)
text_button("destructive-v1", "Witness_button_destructive", "", BUTTON_GATE)   # role below
CASES["swiftui.button/destructive-v1"]["body"] = CASES["swiftui.button/destructive-v1"]["body"].replace('Button("Run") {}', 'Button("Run", role: .destructive) {}')
text_button("borderless-v1", "Witness_button_borderless", ".buttonStyle(.borderless)", LABEL_GATE)
text_button("borderless-disabled-v1", "Witness_button_borderless_disabled", ".buttonStyle(.borderless).disabled(true)", LABEL_GATE)
text_button("plain-v1", "Witness_button_plain", ".buttonStyle(.plain)", LABEL_GATE)
text_button("plain-disabled-v1", "Witness_button_plain_disabled", ".buttonStyle(.plain).disabled(true)", LABEL_GATE)
text_button("borderless-red-v1", "Witness_button_borderless_red", ".buttonStyle(.borderless).foregroundStyle(Color.red)", LABEL_GATE)

# a label without text has the same size on both sides, so the whole button is gated by pixels (edge-aa, decision 5)
for style, mod in (("bordered", ""), ("prominent", ".buttonStyle(.borderedProminent)"), ("borderless", ".buttonStyle(.borderless)"), ("plain", ".buttonStyle(.plain)")):
    t = f"Witness_button_view_label_{style}"
    case(f"swiftui.button/view-label-{style}-v1", t, f"""struct {t}: View {{
    var body: some View {{
        Button(action: {{}}) {{ Rectangle().fill(Color.red).frame(width: 30, height: 10) }}{mod}
    }}
}}""")

COUNTER = """struct %(t)s: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { ForEach(0..<n, id: \\.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 200, height: 10)
            Text("Count \\(n)").frame(width: 200, height: 16)
            %(button)s
        }
        .frame(width: 200, height: 120, alignment: .top)
    }
}"""
# The counter squares (pixels) and the tree (Count n, Add) gate; the button (width differs, decision 2) and the count text are excluded from the pixels and gated by the
# semantic comparator and by bordered-v1.
SEMANTIC = {"semanticGate": {"fields": ["role", "name", "enabled", "count", "order"], "scope": "main", "phases": [""]},
            "excludeRects": [{"name": "'Count n' text glyph region (Segoe UI vs SF, sr1-decisions #2); gated by the semantic tree", "rect": [200, 195, 600, 245]},
                             {"name": "button width and label glyphs (Segoe UI vs SF, decision 2); the button artwork is gated by swiftui.button/bordered-v1, its action by the tree and the counter squares", "rect": [200, 260, 600, 330]}]}
CLICK = [{"op": "wait", "ms": 600}, {"op": "click", "x": 400, "y": 295}, {"op": "wait", "ms": 400}]
case("swiftui.button/click-increments-v1", "Witness_button_click",
     COUNTER % dict(t="Witness_button_click", button='Button("Add") { n += 1 }'), SEMANTIC, CLICK)
case("swiftui.button/click-twice-v1", "Witness_button_click_twice",
     COUNTER % dict(t="Witness_button_click_twice", button='Button("Add") { n += 1 }'), SEMANTIC, CLICK + [{"op": "click", "x": 400, "y": 295}, {"op": "wait", "ms": 400}])
case("swiftui.button/click-disabled-v1", "Witness_button_click_disabled",
     COUNTER % dict(t="Witness_button_click_disabled", button='Button("Add") { n += 1 }.disabled(true)'), SEMANTIC, CLICK)
case("swiftui.button/click-prominent-v1", "Witness_button_click_prominent",
     COUNTER % dict(t="Witness_button_click_prominent", button='Button("Add") { n += 1 }.buttonStyle(.borderedProminent)'), SEMANTIC, CLICK)
case("swiftui.button/return-default-action-v1", "Witness_button_return_default",
     COUNTER % dict(t="Witness_button_return_default", button='Button("Add") { n += 1 }.keyboardShortcut(.defaultAction)'), SEMANTIC,
     [{"op": "wait", "ms": 600}, {"op": "key", "key": "Enter"}, {"op": "wait", "ms": 400}])


# ---- block 16: swiftui.list ---------------------------------------------------------------------------------------------------------------------------------------------
# The List is 200 x 160 pt at (150, 100) px in the 800 x 600 capture; its rows are 60 px tall from y = 125 (a 10 pt inset, 24 pt rows) with the content 40 px in.
ROW_TOP, ROW_H = 125, 60


def list_gate(rows, text=True, plain=False, extra=None):
    top = 100 if plain else ROW_TOP
    cfg = {"listGate": {"rowsTopPx": top, "rowHeightPx": ROW_H, "listRect": [150, 100, 650, 500], "textColourTolerance": 40, "rows": rows}}
    if text:
        cfg["excludeRects"] = [{"name": f"row {i} label glyph region (Segoe UI vs SF, sr1-decisions #2); ink colour gated by pair_list_report.py",
                                "rect": [(170 if plain else 190), top + ROW_H * i + 12, 340, top + ROW_H * i + 48]} for i in range(rows)]
    if extra: cfg.update(extra)
    return cfg


def rows_view(t, selection="", style="", body_rows='ForEach(0..<5, id: \\.self) { i in Text("Row \\(i)")%s }', tag=False, state=""):
    rows = body_rows % (".tag(i)" if tag else "")
    head = f"List(selection: $sel) {{ {rows} }}" if selection else f"List {{ {rows} }}"
    return f"""struct {t}: View {{
    {state}
    var body: some View {{
        {head}{style}.frame(width: 200, height: 160)
    }}
}}"""


T = "Witness_list_"
case("swiftui.list/five-rows-v1", T + "five", rows_view(T + "five"), list_gate(5))
case("swiftui.list/selection-initial-v1", T + "selection_initial", rows_view(T + "selection_initial", "sel", tag=True, state="@State private var sel: Int? = 2"), list_gate(5))
KEYS = [{"op": "wait", "ms": 600}, {"op": "key", "key": "Down"}, {"op": "wait", "ms": 200}, {"op": "key", "key": "Down"}, {"op": "wait", "ms": 400}]
case("swiftui.list/arrow-keys-v1", T + "arrow_keys", rows_view(T + "arrow_keys", "sel", tag=True, state="@State private var sel: Int? = nil"), list_gate(5), KEYS)
case("swiftui.list/arrow-up-v1", T + "arrow_up", rows_view(T + "arrow_up", "sel", tag=True, state="@State private var sel: Int? = nil"), list_gate(5),
     KEYS + [{"op": "key", "key": "Down"}, {"op": "wait", "ms": 200}, {"op": "key", "key": "Up"}, {"op": "wait", "ms": 400}])
case("swiftui.list/click-selects-v1", T + "click_selects", rows_view(T + "click_selects", "sel", tag=True, state="@State private var sel: Int? = nil"), list_gate(5),
     [{"op": "wait", "ms": 600}, {"op": "click", "x": 400, "y": ROW_TOP + ROW_H * 3 + 30}, {"op": "wait", "ms": 400}])
case("swiftui.list/plain-v1", T + "plain", rows_view(T + "plain", style=".listStyle(.plain)"), list_gate(5, plain=True))
case("swiftui.list/plain-selected-v1", T + "plain_selected", rows_view(T + "plain_selected", "sel", style=".listStyle(.plain)", tag=True, state="@State private var sel: Int? = 1"), list_gate(5, plain=True))
case("swiftui.list/plain-arrow-keys-v1", T + "plain_arrow_keys", rows_view(T + "plain_arrow_keys", "sel", style=".listStyle(.plain)", tag=True, state="@State private var sel: Int? = nil"), list_gate(5, plain=True), KEYS)
VAR = """struct %(t)s: View {
    %(state)s
    var body: some View {
        List%(sel)s {
            Rectangle().fill(Color.red).frame(width: 30, height: 10)%(tag0)s
            Rectangle().fill(Color.red).frame(width: 30, height: 40)%(tag1)s
            Rectangle().fill(Color.red).frame(width: 30, height: 24)%(tag2)s
        }.frame(width: 200, height: 160)
    }
}"""
case("swiftui.list/variable-rows-v1", T + "variable", VAR % dict(t=T + "variable", state="", sel="", tag0="", tag1="", tag2=""), list_gate(3, text=False))
case("swiftui.list/variable-rows-selected-v1", T + "variable_selected", VAR % dict(t=T + "variable_selected", state="@State private var sel: Int? = nil", sel="(selection: $sel)", tag0=".tag(0)", tag1=".tag(1)", tag2=".tag(2)"),
     dict(list_gate(3, text=False), listGate=dict(list_gate(3, text=False)["listGate"], rowHeights=[60, 120, 80])), [{"op": "wait", "ms": 600}, {"op": "click", "x": 400, "y": ROW_TOP + 60 + 60}, {"op": "wait", "ms": 400}])
DEL = """struct %(t)s: View {
    @State private var items = [0, 1, 2, 3, 4]
    @State private var sel: Int? = nil
    var body: some View {
        List(selection: $sel) {
            ForEach(items, id: \\.self) { i in Text("Row \\(i)").tag(i) }%(mods)s
        }.frame(width: 200, height: 160)
    }
}"""
case("swiftui.list/delete-key-v1", T + "delete_key", DEL % dict(t=T + "delete_key", mods="\n            .onDelete { offsets in items.remove(atOffsets: offsets) }"), list_gate(4),
     [{"op": "wait", "ms": 600}, {"op": "click", "x": 400, "y": ROW_TOP + ROW_H * 2 + 30}, {"op": "wait", "ms": 300}, {"op": "key", "key": "Delete"}, {"op": "wait", "ms": 500}])
case("swiftui.list/onmove-down-v1", T + "onmove_down", DEL % dict(t=T + "onmove_down", mods="\n            .onMove { source, destination in items.move(fromOffsets: source, toOffset: destination) }"), list_gate(5),
     [{"op": "wait", "ms": 600}, {"op": "click", "x": 400, "y": ROW_TOP + ROW_H * 1 + 30}, {"op": "wait", "ms": 300}, {"op": "key", "key": "Down", "mods": ["alt"]}, {"op": "wait", "ms": 500}])
case("swiftui.list/onmove-up-v1", T + "onmove_up", DEL % dict(t=T + "onmove_up", mods="\n            .onMove { source, destination in items.move(fromOffsets: source, toOffset: destination) }"), list_gate(5),
     [{"op": "wait", "ms": 600}, {"op": "click", "x": 400, "y": ROW_TOP + ROW_H * 3 + 30}, {"op": "wait", "ms": 300}, {"op": "key", "key": "Up", "mods": ["alt"]}, {"op": "wait", "ms": 500}])


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
            subprocess.check_call(cmd)


if __name__ == "__main__":
    main()
