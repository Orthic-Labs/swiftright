#!/usr/bin/env python3
"""Creates (or re-stamps) every blocks-37-38 case (SR1 round 6): block 37 swiftui.slider, block 38 swiftui.on-hover (see README.md).
Witness text lives here, once per case; new-case.py writes package/ + mac-source/ (Witness byte-identical) and pair.json.
usage: make_cases.py [case-substring ...]

Geometry shared by the interaction cases (E-series decisions in docs/sr1-decisions.md): the witness is a 240 x 200 pt frame centred in the 320 x 240 pt viewport, so
its origin is (40, 20) pt and a point (x, y) inside it is the client pixel ((40 + x) * 2.5, (20 + y) * 2.5). Rows have fixed frames; a Button is clicked at the
centre of its fixed frame. Text rows and Button rows are excluded from the pixel gate by name (Segoe UI vs SF glyphs, decision 2; Button width, decision 11) and are
gated by the semantic tree; the colour squares are gated by pixels."""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\nimport Foundation\n#else\nimport SwiftUI\n#endif\n\n"
CASES = {}
SCALE = 2.5
OX, OY = 40, 20


def px(x, y):
    return round((OX + x) * SCALE), round((OY + y) * SCALE)


def rect(x0, y0, x1, y1):
    return [round((OX + x0) * SCALE), round((OY + y0) * SCALE), round((OX + x1) * SCALE), round((OY + y1) * SCALE)]


def case(name, typename, body, pair=None, steps=None, dark=None):
    """dark: None, or (appearance, scheme): the blocks-17-20 style full-viewport host (the witness fills 320 x 240 itself), e.g. ("darkAqua", "dark")"""
    CASES[name] = dict(type=typename, body=body, pair=pair, steps=steps, dark=dark)


def click(x, y):
    cx, cy = px(x, y)
    return [{"op": "click", "x": cx, "y": cy}, {"op": "wait", "ms": 450}]


def phase_steps(plan):
    """plan = [("label", (x, y) | None), ...]: wait, then per phase a click (None = no click), a dump and a shot, both labelled. Returns (steps, labels)."""
    steps, labels = [{"op": "wait", "ms": 700}], []
    for label, at in plan:
        if at is not None:
            steps += click(*at)
        else:
            steps += [{"op": "wait", "ms": 200}]
        steps += [{"op": "dump", "label": label}, {"op": "wait", "ms": 250}, {"op": "shot", "label": label}]   # the wait: one of 140 shots of the first N=20 run caught a black frame (PrintWindow during a present)
        labels.append(label)
    steps += [{"op": "wait", "ms": 200}]
    return steps, labels


def semantic(labels, text_rows, button_rows, extra_exclude=()):
    """text_rows: [(name, y0, y1, x0)] glyph rows excluded from pixels (x0 = where the text starts inside the 240 pt row); button_rows: [(y0, y1)]."""
    ex = [{"name": f"{n} text glyph region (Segoe UI vs SF, sr1-decisions #2); gated by the semantic tree", "rect": rect(x0, y0, 240, y1)} for n, y0, y1, x0 in text_rows]
    ex += [{"name": f"button row {i} width and label glyphs (Segoe UI vs SF, decision 2/11); the artwork is gated by swiftui.button, its action by the tree and the squares", "rect": rect(0, y0, 240, y1)}
           for i, (y0, y1) in enumerate(button_rows)]
    ex += list(extra_exclude)
    return {"semanticGate": {"fields": ["role", "name", "enabled", "count", "order"], "scope": "main", "phases": labels + [""]},
            "phaseShots": labels, "excludeRects": ex}


def build(name, typename, body, plan, extra_cfg=None, text_rows=()):
    steps, labels = phase_steps(plan)
    pair = semantic(labels, list(text_rows), [])
    if extra_cfg: pair.update(extra_cfg)
    case(name, typename, body, pair, steps)


def static(name, typename, body, extra_cfg=None, dark=None):
    """A case with no interaction: pixels and, in pair.json, the semantic gate on the final dump."""
    pair = {"semanticGate": {"fields": ["role", "name", "enabled", "value", "range", "count", "order"], "scope": "main", "phases": [""]}}
    if extra_cfg: pair.update(extra_cfg)
    case(name, typename, body, pair, [{"op": "wait", "ms": 700}, {"op": "wait", "ms": 200}], dark)


def slider_gate(small_change=None, extra=None):
    g = {"fields": ["role", "name", "enabled", "value", "range", "count", "order"], "scope": "main"}
    if small_change is not None: g["smallChange"] = small_change
    if extra: g.update(extra)
    return g


def rows(items, spacing=8, width=200):
    """A VStack of slider rows at the left edge of the 240 x 200 witness: items are Slider(...) source strings."""
    inner = "\n".join(f"            {s}.frame(width: {width})" for s in items)
    return f"        VStack(alignment: .leading, spacing: {spacing}) {{\n{inner}\n        }}.frame(width: 240, height: 200, alignment: .topLeading)"


def S(v, lo=0, hi=100, extra=""):
    return f"Slider(value: .constant({v}), in: {lo}...{hi}){extra}"


def SB(name, lo=0, hi=100, extra=""):
    return f"Slider(value: ${name}, in: {lo}...{hi}){extra}"


def row_y(i, spacing=8):
    return 8 + i * (16 + spacing)        # the centre of slider row i in witness points


# =====================================================================================================================================================================
# block 37: swiftui.slider
# =====================================================================================================================================================================
T = "Witness_sl_"

def sl_phases(plan):
    """plan = [(label, [ops]), ...]: wait, then per phase its ops (each followed by a settle), a dump and a shot, both labelled. Returns (steps, labels)."""
    steps, labels = [{"op": "wait", "ms": 700}], []
    for label, ops in plan:
        for op in ops: steps += [op, {"op": "wait", "ms": 450}]
        steps += [{"op": "dump", "label": label}, {"op": "wait", "ms": 250}, {"op": "shot", "label": label}, {"op": "wait", "ms": 150}]
        labels.append(label)
    return steps, labels


def clk(x, i):          # a click at witness x (pt) on slider row i
    cx, cy = px(x, row_y(i)); return {"op": "click", "x": cx, "y": cy}


def key(k): return {"op": "key", "key": k}


def drg(x0, x1, i):     # a drag along slider row i from witness x0 to x1 (pt)
    a, b = px(x0, row_y(i)), px(x1, row_y(i)); return {"op": "drag", "x0": a[0], "y0": a[1], "x1": b[0], "y1": b[1], "steps": 6}


def tick_band(i, spacing=8):
    """The rows where macOS draws a stepped slider's tick marks (the bottom 7 px of its 40 px frame): excluded by name from the pixel gate, decision H6."""
    y0 = round((OY + 24 * i) * SCALE) + 33
    return {"name": f"slider row {i}: tick marks of a stepped slider (not drawn on Windows, decision H6); the track, fill and thumb above are gated", "rect": [round(OX * SCALE), y0, round((OX + 200) * SCALE), y0 + 8]}


def interact(name, typename, body, plan, small_change, gate_extra=None, stepped_rows=()):
    steps, labels = sl_phases(plan)
    sg = slider_gate(small_change, {"phases": labels + [""]})
    if gate_extra: sg.update(gate_extra)
    pair = {"semanticGate": sg, "phaseShots": labels}
    if stepped_rows: pair["excludeRects"] = [tick_band(i) for i in stepped_rows]
    case(name, typename, body, pair, steps)


def stateful(typename, decls, items, spacing=8, width=200):
    inner = "\n".join(f"            {s}.frame(width: {width})" for s in items)
    d = "\n".join(f"    @State private var {n} = {v}" for n, v in decls)
    return f"""struct {typename}: View {{
{d}
    var body: some View {{
        VStack(alignment: .leading, spacing: {spacing}) {{
{inner}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}"""


# thumb offsets on a 200 pt (500 px) slider are floor(t * 450 + 0.5): even values are never ties (decision H2)
static("swiftui.slider/values-light-v1", T + "values", f"""struct {T}values: View {{
    var body: some View {{
{rows([S(0), S(20), S(50), S(80), S(100), S(36)])}
    }}
}}""", {"semanticGate": slider_gate([10] * 6)})

# dark: the witness fills the 320 x 240 viewport (rows 40 pt apart so the shadows do not meet), full-width sliders 200 pt wide centred
DARK_ROWS = lambda items: "\n".join(f"            {s}.frame(width: 200)" for s in items)
static("swiftui.slider/values-dark-v1", T + "values_dark", f"""struct {T}values_dark: View {{
    var body: some View {{
        ZStack {{
            Rectangle().fill(.background)
            VStack(spacing: 24) {{
{DARK_ROWS([S(0), S(20), S(50), S(80), S(100), S(36)])}
            }}
        }}.frame(width: 320, height: 240)
    }}
}}""", {"semanticGate": slider_gate([10] * 6)}, dark=("darkAqua", "dark"))

static("swiftui.slider/disabled-light-v1", T + "disabled", f"""struct {T}disabled: View {{
    var body: some View {{
{rows([S(30), S(30, extra=".disabled(true)"), S(70), S(70, extra=".disabled(true)"), S(100, extra=".disabled(true)"), S(0, extra=".disabled(true)")])}
    }}
}}""", {"semanticGate": slider_gate([10] * 6)})

static("swiftui.slider/disabled-dark-v1", T + "disabled_dark", f"""struct {T}disabled_dark: View {{
    var body: some View {{
        ZStack {{
            Rectangle().fill(.background)
            VStack(spacing: 24) {{
{DARK_ROWS([S(30), S(30, extra=".disabled(true)"), S(70), S(70, extra=".disabled(true)"), S(100, extra=".disabled(true)"), S(0, extra=".disabled(true)")])}
            }}
        }}.frame(width: 320, height: 240)
    }}
}}""", {"semanticGate": slider_gate([10] * 6)}, dark=("darkAqua", "dark"))

# other ranges: the value maps to the thumb through (value - lower) / (upper - lower); the UIA RangeValue carries the bounds
static("swiftui.slider/range-v1", T + "range", f"""struct {T}range: View {{
    var body: some View {{
{rows([S(0.4, 0, 1), S(15, 10, 20), S(20, -50, 50), S(4, 0, 10), S(75, 50, 100), S(8, 0, 8)])}
    }}
}}""", {"semanticGate": slider_gate([0.1, 1, 10, 1, 5, 0.8])})

# a wider and a narrower slider, fractional pixel travel: thumb offsets round half up
static("swiftui.slider/widths-v1", T + "widths", f"""struct {T}widths: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 8) {{
            Slider(value: .constant(60), in: 0...100).frame(width: 240)
            Slider(value: .constant(60), in: 0...100).frame(width: 120)
            Slider(value: .constant(60), in: 0...100).frame(width: 61)
            Slider(value: .constant(50), in: 0...100).frame(width: 30)
            Slider(value: .constant(90), in: 0...100).frame(width: 20.4)
            Slider(value: .constant(40), in: 0...100)
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}""", {"semanticGate": slider_gate([10] * 6)})

# an inactive-looking one over a coloured ground: the track and the shadow are translucent, the fill and the body are not
static("swiftui.slider/over-colour-v1", T + "over_colour", f"""struct {T}over_colour: View {{
    var body: some View {{
        VStack(spacing: 0) {{
            ZStack {{ Color(red: 0.2, green: 0.4, blue: 0.8); Slider(value: .constant(40), in: 0...100).frame(width: 200) }}.frame(width: 240, height: 48)
            ZStack {{ Color(red: 0.5, green: 0.5, blue: 0.5); Slider(value: .constant(60), in: 0...100).frame(width: 200) }}.frame(width: 240, height: 48)
            ZStack {{ Color.black; Slider(value: .constant(80), in: 0...100).frame(width: 200) }}.frame(width: 240, height: 48)
            ZStack {{ Color(red: 0.9, green: 0.8, blue: 0.3); Slider(value: .constant(20), in: 0...100).frame(width: 200).disabled(true) }}.frame(width: 240, height: 48)
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}""", {"semanticGate": slider_gate([10] * 6)})

# labels: a leading label, the value labels, both (decision 2: Segoe vs SF text; the slider is gated by its value, range, order and y; the rows are not compared pixel for pixel)
LBL = f"""struct {T}labels: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 4) {{
            Slider(value: .constant(40), in: 0...100) {{ Text("Volume") }}
            Slider(value: .constant(40), in: 0...100) {{ Text("Volume") }} minimumValueLabel: {{ Text("0") }} maximumValueLabel: {{ Text("100") }}
            Slider(value: .constant(60), in: 0...100, step: 10) {{ Text("Step") }} minimumValueLabel: {{ Text("Lo") }} maximumValueLabel: {{ Text("Hi") }}
            HStack {{ Text("A"); Slider(value: .constant(40), in: 0...100); Text("B") }}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}"""
LBL_EX = [{"name": f"row {i} (labels and track start: Segoe UI vs SF text widths, decision 2); the slider is gated by value, range, order and y", "rect": rect(0, y0, 240, y1)}
          for i, (y0, y1) in enumerate([(0, 18), (22, 40), (44, 66), (70, 90)])]
static("swiftui.slider/labels-v1", T + "labels", LBL, {"semanticGate": slider_gate([10, 10, 10, 10], {"fields": ["role", "name", "enabled", "value", "range", "count", "order", "boundsY"], "boundsYTolerancePt": 1.0, "ignoreNames": []}), "excludeRects": LBL_EX})

# ---- interaction (F2 steps; the Mac side sets the value through the accessibility value / increment: AppKit drops synthetic mouse events for an offscreen window, decision H5)
interact("swiftui.slider/click-track-v1", T + "click", stateful(T + "click", [("a", 20.0), ("b", 40.0), ("c", 0.5)],
         [SB("a"), "Slider(value: $b, in: 0...100, step: 5)", "Slider(value: $c, in: 0...1)"]), [
    ("a30", [clk(64, 0)]), ("b60", [clk(118, 1)]), ("c03", [clk(64, 2)]),
    ("a-clamp-lo", [clk(2, 0)]), ("a-clamp-hi", [clk(198, 0)]), ("b-snap", [clk(100, 1)]),
], [10, 5, 0.1], stepped_rows=[1])

interact("swiftui.slider/drag-v1", T + "drag", stateful(T + "drag", [("a", 20.0), ("b", 20.0), ("c", 0.0)],
         [SB("a"), "Slider(value: $b, in: 0...100, step: 10)", SB("c", 0, 1)]), [
    ("a-thumb-grab", [drg(50, 122, 0)]),        # press 4 pt right of the thumb centre (x = 46): no jump, the value follows by the same distance -> 60
    ("a-off-thumb", [drg(150, 28, 0)]),         # press on the empty track: the thumb jumps under the pointer, then follows -> 10
    ("b-stepped", [drg(46, 106, 1)]),           # 20 -> 56.7 raw -> snaps to 50 or 60: x = 106 -> centre 102 -> 51.1 -> 50
    ("c-end", [drg(10, 199, 2)]),
], [10, 10, 0.1], stepped_rows=[1])

interact("swiftui.slider/keys-v1", T + "keys", stateful(T + "keys", [("a", 20.0), ("b", 20.0)], [SB("a"), "Slider(value: $b, in: 0...100, step: 5)"]), [
    ("click", [clk(64, 0)]), ("right", [key("Right")]), ("right2", [key("Right")]), ("left", [key("Left")]), ("home", [key("Home")]),
    ("pageup", [key("PageUp")]), ("end", [key("End")]), ("pagedown", [key("PageDown")]), ("up", [key("Up")]), ("down", [key("Down"), key("Down")]),
    ("b-click", [clk(100, 1)]), ("b-right", [key("Right")]), ("b-left2", [key("Left"), key("Left")]), ("b-end", [key("End")]),
], [10, 5], stepped_rows=[1])

interact("swiftui.slider/disabled-input-v1", T + "disabled_input", stateful(T + "disabled_input", [("a", 30.0), ("b", 30.0)],
         [SB("a", extra=".disabled(true)"), SB("b")]), [
    ("click-disabled", [clk(118, 0)]), ("drag-disabled", [drg(40, 150, 0)]), ("key-disabled", [key("Right")]),
    ("click-enabled", [clk(118, 1)]), ("key-enabled", [key("Right")]),
], [10, 10])

# the value labels are buttons on the Mac: a press sets the bound
interact("swiftui.slider/value-labels-v1", T + "value_labels", f"""struct {T}value_labels: View {{
    @State private var a = 40.0
    var body: some View {{
        VStack(alignment: .leading, spacing: 8) {{
            Slider(value: $a, in: 0...100) {{ Text("Volume") }} minimumValueLabel: {{ Text("0") }} maximumValueLabel: {{ Text("100") }}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}""", [("start", []), ("click-max", [{"op": "invoke", "name": "100"}]), ("click-min", [{"op": "invoke", "name": "0"}])], [10],
    {"fields": ["role", "name", "enabled", "value", "range", "count", "order"]})

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
            if c.get("dark"): cmd += ["--dark-host", "--appearance", c["dark"][0], "--scheme", c["dark"][1]]
            subprocess.check_call(cmd)


if __name__ == "__main__":
    main()
