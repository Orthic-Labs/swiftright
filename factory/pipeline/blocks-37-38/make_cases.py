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


def case(name, typename, body, pair=None, steps=None, dark=None, clock=None):
    """dark: None, or (appearance, scheme): the blocks-17-20 style full-viewport host (the witness fills 320 x 240 itself), e.g. ("darkAqua", "dark")"""
    CASES[name] = dict(type=typename, body=body, pair=pair, steps=steps, dark=dark, clock=clock)


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
    pair["hazeTolerance"] = 2 if dark else 1   # the thumb's soft shadow: 8-bit rounding of a faint translucent layer (decision H4); two levels over the dark thumb's double translucency
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


def interact(name, typename, body, plan, small_change, gate_extra=None, stepped_rows=(), exclude=()):
    steps, labels = sl_phases(plan)
    sg = slider_gate(small_change, {"phases": labels + [""]})
    if gate_extra: sg.update(gate_extra)
    pair = {"semanticGate": sg, "phaseShots": labels, "hazeTolerance": 1}
    if stepped_rows: pair["excludeRects"] = [tick_band(i) for i in stepped_rows]
    if exclude: pair["excludeRects"] = pair.get("excludeRects", []) + list(exclude)
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
        }}.frame(width: 320, height: 240).environment(\\.colorScheme, .dark)
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
        }}.frame(width: 320, height: 240).environment(\\.colorScheme, .dark)
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
LBL_EX = [{"name": "the four label rows (labels, value labels and where the track starts: Segoe UI vs SF text widths, decision 2; tick marks of the stepped row, H6); the sliders are gated by value, range, order and name, the artwork by the unlabelled cases", "rect": rect(0, 0, 240, 92)}]
static("swiftui.slider/labels-v1", T + "labels", LBL, {"semanticGate": slider_gate([10, 10, 10, 10], {"ignoreNames": []}), "excludeRects": LBL_EX})

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
}}""", [("start", []), ("click-max", [{"op": "invoke", "name": "100"}]), ("click-min", [{"op": "invoke", "name": "0"}]), ("click-max-twice", [{"op": "invoke", "name": "100"}, {"op": "invoke", "name": "100"}])], [10],
    {"fields": ["role", "name", "enabled", "value", "range", "count", "order"]},
    exclude=[{"name": "the labelled row (label, value labels and where the track starts: Segoe UI vs SF text widths, decision 2); the slider is gated by value and range", "rect": rect(0, 0, 240, 20)}])


# =====================================================================================================================================================================
# block 38: swiftui.on-hover (.onHover, .onTapGesture and the SwiftCrossUI #789 family, docs/prior-art.md section 2)
# =====================================================================================================================================================================
# The Mac side has NO pointer: AppKit drops synthetic mouse events for an offscreen window (window.sendEvent, NSApp.postEvent, NSHostingView.mouseDown / mouseMoved /
# mouseEntered were all tried: SwiftUI's gestures and hover did not move). The Witness therefore registers what the pointer would do on the Mac (`HoverStandIn`, below,
# on `FactoryStandIn` of the Mac host): the specified semantics (decisions H6-H8), not a measurement of SwiftUI. Windows gets real posted pointer messages.
PRELUDE = r'''#if !os(Windows)
import Observation
#endif

@Observable final class HoverProbe {
    var hovered: String? = nil
    var log: [String] = []
    var taps: [String: Int] = [:]
    func record(_ id: String, _ inside: Bool) { log.append(id + (inside ? "+" : "-")); if inside { hovered = id } else if hovered == id { hovered = nil } }
    func tap(_ id: String) { taps[id, default: 0] += 1 }
}
nonisolated(unsafe) let probe = HoverProbe()

/// One square per event, in order: a view's entry is its bright colour, its exit the dark one.
func hoverEventColor(_ e: String) -> Color {
    let up = e.hasSuffix("+")
    switch e.first {
    case "A": return up ? Color.green : Color(red: 0, green: 0.4, blue: 0)
    case "B": return up ? Color.blue : Color(red: 0, green: 0, blue: 0.45)
    case "C": return up ? Color.orange : Color(red: 0.5, green: 0.25, blue: 0)
    case "D": return up ? Color.purple : Color(red: 0.25, green: 0, blue: 0.3)
    default: return Color.gray
    }
}

struct HoverStrip: View {
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<probe.log.count, id: \.self) { i in Rectangle().fill(hoverEventColor(probe.log[i])).frame(width: 10, height: 10) } }
            .frame(width: 240, height: 10, alignment: .leading)
    }
}

struct TapCounter: View {
    let id: String
    var body: some View {
        let n = probe.taps[id, default: 0]     // read in the body: an observation read inside a ForEach row closure is not tracked by the Windows runtime (decision H10)
        HStack(spacing: 2) { ForEach(0..<4, id: \.self) { i in Rectangle().fill(n > i ? Color.black : Color(white: 0.85)).frame(width: 8, height: 8) } }
    }
}

#if !os(Windows)
@MainActor enum HoverStandIn {
    static var frames: [(String, CGRect)] = []
    static var hoverable: Set<String> = [], tappable: Set<String> = [], inside: Set<String> = []
    static func install(_ frames: [(String, CGRect)], hover: [String] = [], tap: [String] = []) {
        self.frames = frames; hoverable = Set(hover); tappable = Set(tap); inside = []
        FactoryStandIn.move = { p in update(p) }
        FactoryStandIn.leave = { update(nil) }
        FactoryStandIn.click = { p in if let hit = HoverStandIn.frames.last(where: { HoverStandIn.tappable.contains($0.0) && $0.1.contains(p) }) { probe.tap(hit.0) } }
    }
    /// exits first, then entries, each in tree order (decision H6)
    static func update(_ p: CGPoint?) {
        let now = Set(frames.filter { hoverable.contains($0.0) && p != nil && $0.1.contains(p!) }.map { $0.0 })
        for (id, _) in frames where inside.contains(id) && !now.contains(id) { probe.record(id, false) }
        for (id, _) in frames where !inside.contains(id) && now.contains(id) { probe.record(id, true) }
        inside = now
    }
}
#endif
'''


def hv_witness(typename, frames, hover, tap, body, extra=""):
    fr = "[" + ", ".join(f'("{n}", CGRect(x: {r[0]}, y: {r[1]}, width: {r[2]}, height: {r[3]}))' for n, r in frames) + "]"
    ini = f"    init() {{\n#if !os(Windows)\n        HoverStandIn.install({fr}, hover: {json.dumps(list(hover))}, tap: {json.dumps(list(tap))})\n#endif\n    }}\n"
    return PRELUDE + "\n" + extra + f"struct {typename}: View {{\n{ini}    var body: some View {{\n{body}\n    }}\n}}"


def mv(x, y): cx, cy = px(x, y); return {"op": "move", "x": cx, "y": cy, "real": True}   # the real cursor: posted moves leave it elsewhere and the window then reports a leave at once
LEAVE = {"op": "leave", "real": True}


def pixel_case(name, typename, witness, plan, gate=None):
    steps, labels = sl_phases(plan)
    pair = {"phaseShots": labels, "hazeTolerance": 1}   # 1 level on the continuous corner of a RoundedRectangle (block 30 tolerance class)
    if gate: pair.update(gate)
    case(name, typename, witness, pair, steps)


HV = "Witness_hv_"
pixel_case("swiftui.on-hover/rows-v1", HV + "rows", hv_witness(HV + "rows", [("A", (0, 0, 200, 28)), ("B", (0, 36, 200, 28)), ("C", (0, 72, 200, 28)), ("D", (0, 108, 200, 40))], ["A", "B", "C", "D"], [], """        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(probe.hovered == "A" ? Color.blue : Color.gray).frame(width: 200, height: 28).onHover { probe.record("A", $0) }
            Rectangle().fill(probe.hovered == "B" ? Color.blue : Color.gray).frame(width: 200, height: 28).onHover { probe.record("B", $0) }
            Button(action: { }) { Rectangle().fill(probe.hovered == "C" ? Color.orange : Color(white: 0.7)).frame(width: 200, height: 28) }.buttonStyle(.plain).onHover { probe.record("C", $0) }
            RoundedRectangle(cornerRadius: 8).fill(probe.hovered == "D" ? Color.purple : Color(white: 0.6)).frame(width: 200, height: 40).onHover { probe.record("D", $0) }
            HoverStrip()
        }.frame(width: 240, height: 200, alignment: .topLeading)"""), [
    ("start", []), ("in-A", [mv(100, 14)]), ("still-in-A", [mv(120, 10)]), ("A-to-B", [mv(100, 50)]), ("in-the-gap", [mv(100, 68)]),
    ("to-button", [mv(100, 86)]), ("to-card", [mv(100, 128)]), ("leave", [LEAVE]), ("re-enter-A", [mv(10, 4)]), ("A-to-D-directly", [mv(190, 140)]),
])

pixel_case("swiftui.on-hover/adjacent-v1", HV + "adjacent", hv_witness(HV + "adjacent", [("A", (0, 0, 100, 28)), ("B", (100, 0, 100, 28))], ["A", "B"], [], """        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Rectangle().fill(probe.hovered == "A" ? Color.green : Color.gray).frame(width: 100, height: 28).onHover { probe.record("A", $0) }
                Rectangle().fill(probe.hovered == "B" ? Color.blue : Color(white: 0.7)).frame(width: 100, height: 28).onHover { probe.record("B", $0) }
            }
            HoverStrip()
        }.frame(width: 240, height: 200, alignment: .topLeading)"""), [
    ("start", []), ("in-A", [mv(50, 14)]), ("last-pixel-of-A", [mv(99.6, 14)]), ("cross-to-B", [mv(100.4, 14)]), ("back-to-A", [mv(60, 14)]),
    ("below", [mv(60, 40)]), ("in-B", [mv(150, 14)]), ("leave-from-B", [LEAVE]), ("again-B-to-A", [mv(150, 14), mv(20, 14)]),
])

# the SwiftCrossUI #789 family (docs/prior-art.md section 2): a body that ends in .onTapGesture, the same body wrapped in a VStack, an explicit-return body, a nested composite;
# a centre click adds 1 and an outside click adds 0; state survives an unrelated write (the counters are the evidence, one square per tap)
GS_VIEWS = r'''struct Witness_gs_ends: View {
    var body: some View {
        Rectangle().fill(Color.red).frame(width: 60, height: 24).onTapGesture { probe.tap("a") }
    }
}

struct Witness_gs_wrapped: View {
    var body: some View {
        VStack { Rectangle().fill(Color.red).frame(width: 60, height: 24).onTapGesture { probe.tap("b") } }
    }
}

struct Witness_gs_explicit: View {
    var body: some View {
        return Rectangle().fill(Color.red).frame(width: 60, height: 24).onTapGesture { probe.tap("c") }
    }
}

struct Witness_gs_inner: View {
    var body: some View { Rectangle().fill(Color.red).frame(width: 60, height: 24).onTapGesture { probe.tap("d") } }
}

struct Witness_gs_nested: View {
    var body: some View { Witness_gs_inner() }
}

struct Witness_gs_unrelated: View {
    var body: some View { Rectangle().fill(Color.blue).frame(width: 60, height: 24).onTapGesture { probe.tap("e") } }
}

'''
GS_FRAMES = [("a", (0, 0, 60, 24)), ("b", (0, 32, 60, 24)), ("c", (0, 64, 60, 24)), ("d", (0, 96, 60, 24)), ("e", (0, 128, 60, 24))]
GS_BODY = """        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { Witness_gs_ends(); TapCounter(id: "a") }
            HStack(spacing: 8) { Witness_gs_wrapped(); TapCounter(id: "b") }
            HStack(spacing: 8) { Witness_gs_explicit(); TapCounter(id: "c") }
            HStack(spacing: 8) { Witness_gs_nested(); TapCounter(id: "d") }
            HStack(spacing: 8) { Witness_gs_unrelated(); TapCounter(id: "e") }
        }.frame(width: 240, height: 200, alignment: .topLeading)"""


def ck(x, y): cx, cy = px(x, y); return {"op": "click", "x": cx, "y": cy}


pixel_case("swiftui.on-hover/body-ends-in-modifier-v1", "Witness_gs_all", hv_witness("Witness_gs_all", GS_FRAMES, [], ["a", "b", "c", "d", "e"], GS_BODY, GS_VIEWS), [
    ("first-commit", []), ("a-centre", [ck(30, 12)]), ("a-outside-gap", [ck(30, 28)]), ("a-outside-right", [ck(100, 12)]), ("b-centre", [ck(30, 44)]),
    ("c-centre", [ck(30, 76)]), ("d-centre", [ck(30, 108)]), ("a-twice", [ck(30, 12), ck(30, 12)]), ("unrelated-e", [ck(30, 140)]), ("a-after-unrelated", [ck(30, 12)]),
    ("corner-inside", [ck(0.2, 0.2)]), ("edge-outside", [ck(60.2, 12)]),
])

# a tap on a Button inside a view with a tap gesture runs the Button (the control takes the press), and a tap beside it runs the gesture
BT = r'''struct Witness_bt_all: View {
    init() {
#if !os(Windows)
        HoverStandIn.install([("g", CGRect(x: 0, y: 0, width: 200, height: 60))], hover: [], tap: ["g"])
#endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                Rectangle().fill(Color(white: 0.8)).frame(width: 200, height: 30)
                Rectangle().fill(Color(white: 0.6)).frame(width: 200, height: 30)
            }.onTapGesture { probe.tap("g") }
            TapCounter(id: "g")
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
pixel_case("swiftui.on-hover/tap-container-v1", "Witness_bt_all", PRELUDE + "\n" + BT, [
    ("start", []), ("top", [ck(100, 15)]), ("bottom", [ck(100, 45)]), ("outside", [ck(100, 70)]), ("again", [ck(10, 10)]),
])

# =====================================================================================================================================================================
# item 3c: a UIA walk over every delivered control kind (role, name, state flags, value; the full tree is walked with every pattern read, so a node that crashes the walk fails the run)
# =====================================================================================================================================================================
UIA = "Witness_uia_"
walk_a = f"""struct {UIA}a: View {{
    @State private var on = true
    @State private var off = false
    @State private var text = "Hello"
    @State private var v = 40.0
    var body: some View {{
        VStack(alignment: .leading, spacing: 6) {{
            Text("Title")
            HStack(spacing: 8) {{ Button("Add") {{ }}; Button("Plain") {{ }}.buttonStyle(.plain); Button("Off") {{ }}.disabled(true) }}
            Toggle("Switch", isOn: $on).toggleStyle(.switch)
            Toggle("Check", isOn: $off)
            TextField("Name", text: $text).frame(width: 160)
            Slider(value: $v, in: 0...100).frame(width: 160)
            Divider().frame(width: 160)
            Toggle("Disabled", isOn: $on).toggleStyle(.switch).disabled(true)
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}"""
walk_b = f"""struct {UIA}b: View {{
    @State private var sel: Int? = 1
    var body: some View {{
        VStack(alignment: .leading, spacing: 6) {{
            HStack(spacing: 8) {{ Image(systemName: "star.fill").frame(width: 16, height: 16); Text("Star") }}
            Image(systemName: "gear").frame(width: 16, height: 16).accessibilityLabel("Settings")
            Text("Hidden").accessibilityHidden(true)
            Slider(value: .constant(0.5), in: 0...1) {{ Text("Level") }}
            List(selection: $sel) {{ Text("One").tag(1); Text("Two").tag(2); Text("Three").tag(3) }}.frame(width: 180, height: 90)
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}"""
# controls-b's List (block 39, decision H16 as corrected 16 October): the semantic tree gates every field outside the rows (listRows pixels-only), and pair_list_report.py
# gates the rows (count, text, order, selected, frame within 1 px, label ink). The pixel gate DECIDES inside the list rect, outside the three row-label glyph boxes (Segoe
# UI vs SF, decision 2). Everything outside the list rect (Star, gear, Hidden, the Level slider, the empty margins) is named in excludeRects and reported, never gated: the
# case's pixels outside the list are report-only by named exclusion, as before. The list rect is the Windows List's bounds at scale 2.5 (client origin 112,96 px; 450 x 225 px).
LIST_RECT = [100, 270, 550, 495]
LIST_ROWS_EXCLUDE = [
    {"name": "outside the list rect: Star, gear, Hidden and the Level slider (glyphs and symbol artwork, Segoe vs SF, decision 2/3); reported, not gated", "rect": [0, 0, 800, 270]},
    {"name": "outside the list rect: below the list (reported, not gated)", "rect": [0, 495, 800, 600]},
    {"name": "outside the list rect: left margin (reported, not gated)", "rect": [0, 270, 100, 495]},
    {"name": "outside the list rect: right margin (reported, not gated)", "rect": [550, 270, 800, 495]},
    {"name": "row 0 label glyphs (Segoe UI vs SF, decision 2); text, order, selection and frame gated by pair_list_report.py", "rect": [136, 308, 206, 344]},
    {"name": "row 1 label glyphs (Segoe UI vs SF, decision 2); text, order, selection and frame gated by pair_list_report.py", "rect": [136, 369, 204, 403]},
    {"name": "row 2 label glyphs (Segoe UI vs SF, decision 2); text, order, selection and frame gated by pair_list_report.py", "rect": [136, 428, 230, 462]},
]
LIST_GATE = {"rowsTopPx": 295, "rowHeightPx": 60, "listRect": LIST_RECT, "rows": 3, "textColourTolerance": 40}
for nm, tn, body in (("a", UIA + "a", walk_a), ("b", UIA + "b", walk_b)):
    if nm == "a":
        pair = {"semanticGate": {"fields": ["role", "name", "enabled", "toggle", "value", "count", "order"], "scope": "main", "pixels": "report-only", "ignoreNames": []}}
    else:
        pair = {"semanticGate": {"fields": ["role", "name", "enabled", "toggle", "value", "count", "order"], "scope": "main", "ignoreNames": [], "listRows": "pixels-only"},
                "listGate": LIST_GATE, "excludeRects": LIST_ROWS_EXCLUDE}
    case(f"swiftui.uia-walk/controls-{nm}-v1", tn, body, pair,
         [{"op": "wait", "ms": 700}, {"op": "key", "key": "Tab"}, {"op": "wait", "ms": 300}, {"op": "wait", "ms": 200}])


# =====================================================================================================================================================================
# item 3a: a first batch of OpenSwiftUI's compatibility tests (MIT, github.com/OpenSwiftUIProject/OpenSwiftUI Tests/OpenSwiftUICompatibilityTests: the test view bodies and
# their expectations, not their source; the host there is a platform hosting controller with timers, here a Button or onAppear drives the same state change and the counts they
# `confirm()` are drawn as one square per count so the paired pixels carry them). Not ported: EquatableView (the upstream count is 1...3 across runs, "FIXME: CI sometimes 1 / 2 / 3")
# and animation completion (`withAnimation(_:completionCriteria:_:completion:)` is not in the runtime inventory: recorded as not delivered, decision H9).
# =====================================================================================================================================================================
CP = r'''#if !os(Windows)
import Observation
#endif

@Observable final class CompatProbe {
    var a = 0
    var b = 0
    var tasks = 0
    var values: [Int] = []
    var changes: [[Int]] = []
}
nonisolated(unsafe) let cp = CompatProbe()

struct CountStrip: View {
    let n: Int
    let color: Color
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<8, id: \.self) { i in Rectangle().fill(i < n ? color : Color(white: 0.88)).frame(width: 8, height: 8) } }
    }
}

'''
CO = "Witness_co_"
compat_id = CP + r'''struct Witness_co_id: View {
    @State private var showRed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Toggle") { showRed.toggle() }.frame(width: 100, height: 28)
            // id AFTER onAppear: a new id is a new view, so its onAppear runs again (counts 1, 2, 3)
            HStack(spacing: 8) {
                Color(red: showRed ? 1 : 0, green: 0, blue: showRed ? 0 : 1).frame(width: 40, height: 20).onAppear { cp.a += 1 }.id(showRed)
                CountStrip(n: cp.a, color: Color.green)
            }
            // id BEFORE onAppear: the onAppear belongs to the outer view, which keeps its identity (count stays 1)
            HStack(spacing: 8) {
                Color(red: showRed ? 1 : 0, green: 0, blue: showRed ? 0 : 1).frame(width: 40, height: 20).id(showRed).onAppear { cp.b += 1 }
                CountStrip(n: cp.b, color: Color.orange)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
BTN_Y = 14
case("swiftui.compat/id-modifier-order-v1", CO + "id", compat_id, {"phaseShots": ["start", "toggle", "toggle-again", "toggle-third"], "hazeTolerance": 0,
     "excludeRects": [{"name": "button label glyphs (Segoe UI vs SF, decision 2/11)", "rect": [round(OX * SCALE), round(OY * SCALE), round((OX + 100) * SCALE), round((OY + 28) * SCALE)]}]},
     sl_phases([("start", []), ("toggle", [{"op": "invoke", "name": "Toggle"}]), ("toggle-again", [{"op": "invoke", "name": "Toggle"}]), ("toggle-third", [{"op": "invoke", "name": "Toggle"}])])[0])

compat_state = CP + r'''struct Witness_co_state: View {
    @State private var value = 0
    var body: some View {
        let _ = cp.values.append(value)
        VStack(alignment: .leading, spacing: 8) {
            Color.white.frame(width: 20, height: 10)
                .onAppear {
                    value = 1
                    value = 2
                    withAnimation { value = 3; value = 4 }
                }
                .onChange(of: value) { oldValue, newValue in cp.changes.append([oldValue, newValue]) }
            // the values the body saw, one bar per evaluation (width 12 pt x value + 4): upstream expects [0, 2, 4]
            HStack(spacing: 2) { ForEach(0..<cp.values.count, id: \.self) { i in Rectangle().fill(Color.green).frame(width: CGFloat(cp.values[i]) * 12 + 4, height: 10) } }
            // the onChange pairs, a bar for the old value above a bar for the new: upstream expects [[0, 2], [2, 4]]
            HStack(spacing: 6) { ForEach(0..<cp.changes.count, id: \.self) { i in VStack(spacing: 2) { Rectangle().fill(Color.orange).frame(width: CGFloat(cp.changes[i][0]) * 12 + 4, height: 8); Rectangle().fill(Color.purple).frame(width: CGFloat(cp.changes[i][1]) * 12 + 4, height: 8) } } }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
case("swiftui.compat/state-nested-update-v1", CO + "state", compat_state, {"phaseShots": ["settled"], "hazeTolerance": 0},
     sl_phases([("settled", [])])[0])

compat_task = CP + r'''struct Witness_co_task: View {
    @State private var value = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Bump") { value += 1 }.frame(width: 100, height: 28)
            HStack(spacing: 8) {
                Color.red.frame(width: 40, height: 20).task(id: value) { cp.tasks += 1 }
                CountStrip(n: cp.tasks, color: Color.blue)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
case("swiftui.compat/task-id-v1", CO + "task", compat_task, {"phaseShots": ["start", "bump", "bump-again"], "hazeTolerance": 0,
     "excludeRects": [{"name": "button label glyphs (Segoe UI vs SF, decision 2/11)", "rect": [round(OX * SCALE), round(OY * SCALE), round((OX + 100) * SCALE), round((OY + 28) * SCALE)]}]},
     sl_phases([("start", []), ("bump", [{"op": "invoke", "name": "Bump"}]), ("bump-again", [{"op": "invoke", "name": "Bump"}])])[0])

compat_env = CP + r'''private struct CustomValueKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var customValue: Int { get { self[CustomValueKey.self] } set { self[CustomValueKey.self] = newValue } }
}

struct Witness_co_envsub: View {
    @Environment(\.customValue) private var value
    var body: some View { Rectangle().fill(Color.red).frame(width: CGFloat(value) * 20 + 10, height: 14) }
}

struct Witness_co_env: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Witness_co_envsub()                                        // the default (0): 10 pt wide
            Witness_co_envsub().environment(\.customValue, 1)           // upstream: the subview reads 1 (30 pt)
            Witness_co_envsub().environment(\.customValue, 2).environment(\.customValue, 3)   // the nearest write wins: 2 (50 pt)
            VStack(spacing: 4) { Witness_co_envsub(); Witness_co_envsub().environment(\.customValue, 4) }.environment(\.customValue, 1)   // 30 pt and 90 pt
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
case("swiftui.compat/environment-key-v1", CO + "env", compat_env, {"phaseShots": ["start"], "hazeTolerance": 0}, sl_phases([("start", [])])[0])

compat_any = r'''struct Witness_co_any: View {
    @State private var swap = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Swap") { swap.toggle() }.frame(width: 100, height: 28)
            // AnyView(EmptyView()) is a view with no content; AnyView of a changing concrete type
            AnyView(EmptyView()).frame(width: 40, height: 10)
            (swap ? AnyView(Color.green.frame(width: 40, height: 20)) : AnyView(Color.blue.frame(width: 60, height: 12)))
            Color.gray.frame(width: 80, height: 6)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
case("swiftui.compat/any-view-v1", CO + "any", compat_any, {"phaseShots": ["start", "swap", "swap-back"], "hazeTolerance": 0,
     "excludeRects": [{"name": "button label glyphs (Segoe UI vs SF, decision 2/11)", "rect": [round(OX * SCALE), round(OY * SCALE), round((OX + 100) * SCALE), round((OY + 28) * SCALE)]}]},
     sl_phases([("start", []), ("swap", [{"op": "invoke", "name": "Swap"}]), ("swap-back", [{"op": "invoke", "name": "Swap"}])])[0])

# Round 7: what a change made inside an onChange action animates with (three directions: plain trigger, animated trigger, and an inner withAnimation nested in an outer one). SwiftUI keeps each change's own transaction: a plain trigger snaps while the action's
# withAnimation write animates; an animated trigger keeps its animation while the action's withAnimation(nil) write snaps. The settled capture cannot show a frame
# in flight, so each direction records whether the transaction animated through its completion: a `withAnimation` completion that fires 0.3 s after a change
# that animated, and at once after one that did not (a green 40 pt bar = it ran late = animated, a red 8 pt bar = at once, a gray 8 pt bar = never ran).
# The expected values are whatever the Mac capture records; nothing here is asserted from SwiftUI documentation.
compat_onchg = CP + r'''@Observable final class OnchProbe {
    var markA = -1
    var markB = -1
    var markC1 = -1
    var markC2 = -1
    var t0 = Date()
    func late() -> Int { Date().timeIntervalSince(t0) > 0.15 ? 1 : 0 }
}
nonisolated(unsafe) let op = OnchProbe()

struct MarkBar: View {
    let mark: Int
    var body: some View { Rectangle().fill(mark < 0 ? Color.gray : (mark == 1 ? Color.green : Color.red)).frame(width: mark == 1 ? 40 : 8, height: 6) }
}

struct Witness_co_onchg: View {
    @State private var a = 0
    @State private var af = 0
    @State private var b = 0
    @State private var bf = 0
    @State private var c = 0
    @State private var cf = 0
    @State private var ct = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Plain") { op.t0 = Date(); a = 1 }.frame(width: 100, height: 28)
            Button("Animated") {
                op.t0 = Date()
                withAnimation(.linear(duration: 0.3)) { b = 1 } completion: { op.markB = op.late() }
            }.frame(width: 100, height: 28)
            Button("Nested") { op.t0 = Date(); c = 1 }.frame(width: 100, height: 28)
            // direction A: a plain trigger; its onChange writes under withAnimation. The follower (blue) animates, the trigger (orange, visible on the white background) snaps
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(a) * 20 + 10, height: 6)
                Color.blue.frame(width: CGFloat(af) * 20 + 10, height: 6)
            }
            .onChange(of: a) { _, new in
                withAnimation(.linear(duration: 0.3)) { af = new } completion: { op.markA = op.late() }
            }
            MarkBar(mark: op.markA)
            // direction B: an animated trigger; its onChange writes under withAnimation(nil). The trigger (orange) keeps its animation, the follower (red) snaps
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(b) * 20 + 10, height: 6)
                Color.red.frame(width: CGFloat(bf) * 20 + 10, height: 6)
            }
            .onChange(of: b) { _, new in
                withAnimation(nil) { bf = new }
            }
            MarkBar(mark: op.markB)
            // direction C: a plain trigger; its onChange nests an inner withAnimation (0.25 s) in an outer one (0.4 s). The outer completion (first bar) runs late
            // if the outer animation animated the follower; the inner completion (second bar) runs late only if the inner transaction governed the inner write
            // (third), at once if the outer one decided for it. Both are measured; neither is assumed. (Run 38913665384, Mac: both bars green, inner governs its own writes.)
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(c) * 20 + 10, height: 6)
                Color.blue.frame(width: CGFloat(cf) * 20 + 10, height: 6)
                Color.purple.frame(width: CGFloat(ct) * 20 + 10, height: 6)
            }
            .onChange(of: c) { _, new in
                withAnimation(.linear(duration: 0.4)) {
                    cf = new
                    withAnimation(.linear(duration: 0.25)) { ct = new } completion: { op.markC2 = op.late() }
                } completion: { op.markC1 = op.late() }
            }
            HStack(spacing: 4) { MarkBar(mark: op.markC1); MarkBar(mark: op.markC2) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
_btn_ex = [{"name": "button label glyphs (Segoe UI vs SF, decision 2/11)", "rect": [round(OX * SCALE), round((OY + y) * SCALE), round((OX + 100) * SCALE), round((OY + y + 28) * SCALE)]} for y in (0, 32, 64)]
# the completions run up to 0.4 s after the click: each phase settles for 800 ms before its dump (sl_phases settles 450 ms)
_onchg_steps = [{"op": "wait", "ms": 700}]
for _label, _op in (("start", None), ("plain", "Plain"), ("animated", "Animated"), ("nested", "Nested")):
    if _op: _onchg_steps += [{"op": "invoke", "name": _op}, {"op": "wait", "ms": 800}]
    _onchg_steps += [{"op": "dump", "label": _label}, {"op": "wait", "ms": 250}, {"op": "shot", "label": _label}, {"op": "wait", "ms": 150}]
case("swiftui.compat/onchange-animation-v1", CO + "onchg", compat_onchg, {"phaseShots": ["start", "plain", "animated", "nested"], "hazeTolerance": 0, "excludeRects": _btn_ex}, _onchg_steps)

compat_ctime = CP + r'''@Observable final class CtimeProbe {
    var markInner = -1
    var markOuter = -1
    var t0 = Date()
    func late() -> Int { Date().timeIntervalSince(t0) > 0.15 ? 1 : 0 }
}
nonisolated(unsafe) let ctp = CtimeProbe()

struct CtimeMark: View {
    let mark: Int
    var body: some View { Rectangle().fill(mark < 0 ? Color.gray : (mark == 1 ? Color.green : Color.red)).frame(width: mark == 1 ? 40 : 8, height: 6) }
}

struct Witness_co_ctime: View {
    @State private var x = 0
    @State private var y = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Run") {
                ctp.t0 = Date()
                withAnimation(.linear(duration: 1)) {
                    withAnimation(nil) { x = 1 } completion: { y = 2; ctp.markInner = ctp.late() }
                } completion: { ctp.markOuter = ctp.late() }
            }.frame(width: 100, height: 28)
            // x (orange) is written under the inner withAnimation(nil) and snaps. y (blue) is written by the inner completion: if SwiftUI runs that completion
            // after the outer transaction closes (asynchronously), y does not take the outer 1 s linear animation and is 50 pt at the mid sample; if it ran
            // inside the open outer transaction, y animates (about 26 pt at 0.4 s). The marks record when each completion ran (green = after 0.15 s, red = at once,
            // gray = never). Nothing here is asserted from SwiftUI documentation: the Mac capture is the reference.
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(x) * 20 + 10, height: 6)
                Color.blue.frame(width: CGFloat(y) * 20 + 10, height: 6)
            }
            HStack(spacing: 4) { CtimeMark(mark: ctp.markInner); CtimeMark(mark: ctp.markOuter) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}'''
_ctime_ex = [_btn_ex[0]]
# a mid-animation sample (after the Run step; the host pumps about 0.95 s on the Mac and waits for a settled frame on Windows, so this is a settled frame, not a mid-animation sample), then the settled state
_ctime_steps = [{"op": "wait", "ms": 700}, {"op": "dump", "label": "start"}, {"op": "wait", "ms": 250}, {"op": "shot", "label": "start"}, {"op": "wait", "ms": 150},
                {"op": "invoke", "name": "Run"}, {"op": "wait", "ms": 350}, {"op": "dump", "label": "mid"}, {"op": "shot", "label": "mid"}, {"op": "wait", "ms": 1200},
                {"op": "dump", "label": "end"}, {"op": "wait", "ms": 250}, {"op": "shot", "label": "end"}, {"op": "wait", "ms": 150}]
case("swiftui.compat/completion-timing-v1", CO + "ctime", compat_ctime, {"phaseShots": ["start", "mid", "end"], "hazeTolerance": 0, "excludeRects": _ctime_ex}, _ctime_steps)

# A manual-clock case (F1; the removal-fade cases of blocks 6-10 are the model): the action runs at clock time 0 on both hosts and the frames are held at t = 0 and
# t = 0.5 after it, so a removal the outer 1 s linear transaction governed shows a half-faded ghost at t = 0.5 and a plain removal shows none. An interaction case
# cannot discriminate here: the Windows settled-frame shot and the Mac pump both land after a 1 s fade has finished.
compat_settles = r'''// Block swiftui.compat, case settles-only-removal: an outer withAnimation(.linear(duration: 1)) whose only write is inside a nested withAnimation(nil), then a
// separate plain write that removes a view with an opacity transition. Whether the outer transaction governs that later removal is what the Mac capture decides:
// the blue bar fades (a ghost at half opacity at t = 0.5) if it does, and is gone at once if it does not. Nothing here is asserted from SwiftUI documentation.
struct Witness_co_settles: View {
    @State private var x = 0
    @State private var shown = true
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.orange.frame(width: CGFloat(x) * 20 + 10, height: 6)
            VStack(spacing: 0) {
                if shown { Color.blue.frame(width: 60, height: 20).transition(.opacity) }
            }.frame(width: 60, height: 20, alignment: .top)
        }
        .frame(width: 200, height: 80, alignment: .topLeading)
        .onAppear {
            FactoryClock.at(0) {
                withAnimation(FactoryAnim.wrap(.linear(duration: 1))) { withAnimation(nil) { x = 1 } }
                shown = false
            }
        }
    }
}'''
case("swiftui.compat/settles-only-removal-v1", CO + "settles", compat_settles, {"clockGate": {"tracks": [], "extentTolerancePx": 1.0, "progressTolerance": 0.004, "stripPx": 1}}, None, None, "0.0,0.5")

# A manual-clock case for issue #30 (an empty withAnimation {} with no writes and no nested block): at clock time 0 the empty block runs, then a separate plain write
# drives the orange bar (10 -> 50 pt). A second, blue bar is driven by a plain write with no withAnimation at all, so it is the always-plain reference. At t = 0.5 the orange
# bar is about 30 pt if the empty block's linear 1 s animation leaked to the next plain write, and 50 pt if it did not. Nothing here is asserted from SwiftUI documentation.
compat_empty = r'''// Block swiftui.compat, case empty-withanimation: an empty withAnimation(.linear(duration: 1)) {} (no writes, no nested block), then a separate plain write x = 1 that
// drives the orange bar from 10 to 50 pt. The blue bar is driven by a plain write y = 1 with no withAnimation at all (the always-plain reference). At t = 0.5 the orange bar
// is about 30 pt if the empty block's animation leaked to the next plain write, and 50 pt if it did not; the blue bar is 50 pt in both cases. Nothing here is asserted from SwiftUI documentation.
struct Witness_co_empty: View {
    @State private var x = 0
    @State private var y = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.orange.frame(width: CGFloat(x) * 40 + 10, height: 10)
            Color.blue.frame(width: CGFloat(y) * 40 + 10, height: 10)
        }
        .frame(width: 200, height: 80, alignment: .topLeading)
        .onAppear {
            FactoryClock.at(0) {
                withAnimation(FactoryAnim.wrap(.linear(duration: 1))) {}
                x = 1
                y = 1
            }
        }
    }
}'''
case("swiftui.compat/empty-withanimation-v1", CO + "empty", compat_empty, {"clockGate": {"tracks": [], "extentTolerancePx": 1.0, "progressTolerance": 0.004, "stripPx": 1}}, None, None, "0.0,0.5")

# =====================================================================================================================================================================
# Block swiftui.scroll (issue #31, lane L1): MEASUREMENT of how the Mac scrolls a 180 x 90 pt inset List and ScrollView (thumb geometry, wheel, keyboard, scroller value).
# The Mac host's scroll stand-ins (shared-mac-host/CaptureHost.template.swift, op "scroll") drive the NSScrollView and FAIL when an expected move does not happen; every step prints a
# MAC_SCROLL line (offset, contentHeight, viewportHeight, scroller value; mac-run-NN.log) and `dump` / `listdump` write ax-NN-<label>.json (AXScrollBar, AXValueIndicator frames and
# AXValue) and list-NN-<label>.json (outline row frames). The Windows side (shared-windows-host/CaptureHost.template.swift, job-interact.ps1 ops "wheel" and "drag") drives the same
# labels: WM_MOUSEWHEEL notches into the List / ScrollView and thumb drags on the legacy scroller, and prints one WIN_SCROLL line per settled scroll input (label=in<k>, k = the
# scroll inputs that had landed). Mac -> Windows label map: w0 = in0; w1 = in1; w3 = in3; w10 = in10 (wheel, cumulative from the top); o0 = in0, omid = in1, oend = in2 (thumb);
# s0 = in0, sax05 = in1, sdouble05 = in3 (reset in2), sax10 = in5 (reset in4). The pairs stay report-only by one named full-frame exclusion; nothing is gated against Windows.
# Rows are the default 24 pt rows (H21), so a document is 10 + 24 n + 10 pt: 3 rows = 92 pt, 8 rows = 212 pt (the nearest whole-row document to 200 pt), 25 rows = 620 pt (to 600 pt);
# a ScrollView (no insets) of 25 rows is 600 pt. Case list: ci-lists/scroll-31-measure.txt.
# =====================================================================================================================================================================
SCR = "Witness_sc_"
SCR_DOCS = [(3, 92), (8, 212), (25, 620)]
SCR_EXCLUDE = [{"name": "report-only: scroll measurement (issue #31). The Windows scroll values are the WIN_SCROLL lines, the Mac reference the MAC_SCROLL lines and the ax / list dumps; the pair is never compared pixel for pixel", "rect": [0, 0, 800, 600]}]
# Windows geometry (pt): the runtime centres the witness (new-case.py, ZStack in the 320 x 240 pt viewport), so the 180 x 90 pt scroller sits at (70, 75).
# The legacy scroller strip is 19 pt wide at the trailing edge; the thumb is 10.8 pt wide at x + 4.0; the track is the frame less 3.0 pt top and 3.2 pt bottom,
# and the thumb is max(20, track * 90 / content) long (ScrollerMetrics in ListStyles). A thumb drag moves the thumb by the pointer's distance, so a value change
# of v is a drag of (track - thumb) * v, in client px (SCALE 2.5).
SCR_OX, SCR_OY, SCR_W, SCR_H = 70, 75, 180, 90
SCR_TRACK = SCR_H - 3.0 - 3.2
SCR_THUMB_X = SCR_OX + SCR_W - 19 + 4.0 + 10.8 / 2
SCR_WHEEL = (SCR_OX + SCR_W / 2, SCR_OY + SCR_H / 2)   # the centre of the scroller, pt (the job-interact "wheel" op takes points)


def scr_wheel(n_from, n_to):
    """Windows steps for a wheel phase: the notches that take the scroller from n_from to n_to total (WHEEL_DELTA -120 = one notch down)."""
    if n_to <= n_from: return []
    return [{"op": "wheel", "x": SCR_WHEEL[0], "y": SCR_WHEEL[1], "delta": -120, "times": n_to - n_from}]


def scr_thumb(content, cur, target):
    """Windows steps for a thumb drag from value cur to value target (0...1) of a scroller whose document is content pt tall: press at the thumb centre,
    drag by the travel times the value change (the job-interact "drag" op, client px)."""
    if abs(target - cur) < 1e-9: return []
    length = min(SCR_TRACK, max(20.0, SCR_TRACK * SCR_H / content))
    travel = SCR_TRACK - length
    cx = round(SCR_THUMB_X * SCALE)
    cy = round((SCR_OY + 3.0 + travel * cur + length / 2) * SCALE)
    dy = round(travel * (target - cur) * SCALE)
    return [{"op": "drag", "x0": cx, "y0": cy, "x1": cx, "y1": cy + dy, "steps": 6}]


def sc_list(tn, rows, selection=False):
    head = "    @State private var sel: Int? = nil\n" if selection else ""
    lst = "List(selection: $sel)" if selection else "List"
    return f"""struct {tn}: View {{
{head}    var body: some View {{
        {lst} {{ ForEach(0..<{rows}, id: \\.self) {{ i in Text("Row \\(i)") }} }}.frame(width: 180, height: 90)
    }}
}}"""


def sc_view(tn, rows):
    return f"""struct {tn}: View {{
    var body: some View {{
        ScrollView {{ VStack(spacing: 0) {{ ForEach(0..<{rows}, id: \\.self) {{ i in Text("Row \\(i)").frame(width: 160, height: 24) }} }} }}.frame(width: 180, height: 90)
    }}
}}"""


def sc_op(how, label, **kw):
    return dict({"op": "scroll", "how": how, "label": label}, **kw)


def sc_case(name, typename, body, plan, scroller_png=False):
    """plan = [(label, [mac-only scroll ops]) or (label, [mac-only ops], [windows ops]), ...]. Mac steps: the ops, then dump + listdump + shot per label. Windows steps
    (pair.json "steps"): the windows ops (wheel / drag; none for the keys cases), then dump + shot, so both sides write the same labels."""
    mac, win, labels = [{"op": "wait", "ms": 700}], [{"op": "wait", "ms": 700}], []
    for entry in plan:
        label, ops = entry[0], entry[1]
        wops = entry[2] if len(entry) > 2 else []
        mac += ops + ([{"op": "wait", "ms": 300}, {"op": "scrollerpng", "label": label}] if scroller_png else []) + [{"op": "wait", "ms": 300}, {"op": "dump", "label": label}, {"op": "listdump", "label": label}, {"op": "wait", "ms": 250}, {"op": "shot", "label": label}]
        win += wops + [{"op": "wait", "ms": 300}, {"op": "dump", "label": label}, {"op": "wait", "ms": 250}, {"op": "shot", "label": label}]
        labels.append(label)
    mac.append({"op": "wait", "ms": 200}); win.append({"op": "wait", "ms": 200})
    case(name, typename, body, {"phaseShots": labels, "hazeTolerance": 1, "excludeRects": SCR_EXCLUDE}, win)
    CASES[name]["macSteps"] = mac


# M1 thumb geometry: an inset List of 3, 8 and 25 rows at the top, the middle and the end of its range
for _rows, _doc in SCR_DOCS:
    sc_case(f"swiftui.scroll/thumb-d{_doc}-v1", f"{SCR}thumb_d{_doc}", sc_list(f"{SCR}thumb_d{_doc}", _rows),
            [("o0", [sc_op("to", "o0-to", at="begin")], []),
             ("omid", [sc_op("to", "omid-to", at="mid")], scr_thumb(_doc, 0.0, 0.5)),
             ("oend", [sc_op("to", "oend-to", at="end")], scr_thumb(_doc, 0.5, 1.0))], scroller_png=True)

# M2 wheel: CGEvent line scroll (-1) sent once, three times and ten times to the NSScrollView, from the top each time; a List and a ScrollView of each document.
# Windows: the same notches, cumulative from the top (the launch is the top): 1, then 2 more (total 3), then 7 more (total 10), at the scroller's centre.
for _rows, _doc in SCR_DOCS:
    for _kind, _mk in (("list", sc_list), ("sv", sc_view)):
        _tn = f"{SCR}wheel_{_kind}_d{_doc}"
        sc_case(f"swiftui.scroll/wheel-{_kind}-d{_doc}-v1", _tn, _mk(_tn, _rows),
                [("w0", [sc_op("to", "w0-to", at="begin")], [])] +
                [(f"w{n}", [sc_op("to", f"w{n}-reset", at="begin"), sc_op("wheel", f"w{n}-wheel", delta=-1, times=n)], scr_wheel(_prev, n))
                 for _prev, n in ((0, 1), (1, 3), (3, 10))])

# M3 keyboard: a real key-down NSEvent (PageDown / End / Home) delivered to the outline (List) or the document view (ScrollView) after window.makeFirstResponder; the host tries keyDown,
# interpretKeyEvents, window.sendEvent and tryToPerform up the responder chain, and only as a last resort derives the paged offset (status=DERIVED, never an input). MAC_SCROLL carries
# pageAmount, verticalPageScroll and verticalLineScroll. For the List also the outline's moveDown(_:) past the viewport (a selection, then 5 and 15 rows down)
_kb = [("k0", [sc_op("to", "k0-to", at="begin")]),
       ("kpagedown", [sc_op("key", "kpagedown-key", key="PageDown")]),
       ("kpagedown2", [sc_op("key", "kpagedown2-key", key="PageDown")]),
       ("kend", [sc_op("key", "kend-key", key="End")]),
       ("kbegin", [sc_op("key", "kbegin-key", key="Home")])]
_tn = f"{SCR}keys_list"
sc_case("swiftui.scroll/keys-list-v1", _tn, sc_list(_tn, 25, selection=True),
        _kb + [("ksel0", [sc_op("to", "ksel0-reset", at="begin"), sc_op("select", "ksel0-sel", row=0)]),
               ("kdown5", [sc_op("moveDown", "kdown5-down", times=5)]), ("kdown15", [sc_op("moveDown", "kdown15-down", times=10)])])
_tn = f"{SCR}keys_sv"
sc_case("swiftui.scroll/keys-sv-v1", _tn, sc_view(_tn, 25), _kb)

# M4 the scroll bar's value: the vertical NSScroller's accessibility value set in process (0.5, then 1.0) and NSScroller.doubleValue + action (0.5), each from the top
for _kind, _mk in (("list", sc_list), ("sv", sc_view)):
    _tn = f"{SCR}scroller_{_kind}"
    _c = 620 if _kind == "list" else 600   # 25 rows: the List's document with its insets, the ScrollView's without
    sc_case(f"swiftui.scroll/scroller-{_kind}-v1", _tn, _mk(_tn, 25),
            [("s0", [sc_op("to", "s0-to", at="begin")], []),
             ("sax05", [sc_op("to", "sax05-reset", at="begin"), sc_op("axvalue", "sax05-ax", value=0.5)], scr_thumb(_c, 0.0, 0.5)),
             # Windows: the reset to the top is a drag back (the value is 0.5 after sax05); each later label starts from the top
             ("sdouble05", [sc_op("to", "sdouble05-reset", at="begin"), sc_op("scroller", "sdouble05-dv", value=0.5)],
              scr_thumb(_c, 0.5, 0.0) + scr_thumb(_c, 0.0, 0.5)),
             ("sax10", [sc_op("to", "sax10-reset", at="begin"), sc_op("axvalue", "sax10-ax", value=1.0)],
              scr_thumb(_c, 0.5, 0.0) + scr_thumb(_c, 0.0, 1.0))], scroller_png=True)


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
            if c.get("clock"): cmd += ["--clock", c["clock"]]
            if c.get("dark"): cmd += ["--dark-host", "--appearance", c["dark"][0], "--scheme", c["dark"][1]]
            subprocess.check_call(cmd)
            if c.get("macSteps"):    # the Mac host takes steps the Windows job-interact.ps1 does not know (op scroll / listdump): macArgs differ from the pair.json "steps" (issue #31)
                pj = H / name / "pair.json"; cfg = json.loads(pj.read_text()); cfg["macArgs"] = ["--steps", json.dumps(c["macSteps"], separators=(",", ":"))]; pj.write_text(json.dumps(cfg, indent=1) + "\n")


if __name__ == "__main__":
    main()
