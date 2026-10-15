#!/usr/bin/env python3
"""Creates (or re-stamps) every blocks-26-34 case (SR1 round 5, closing the Pulse hub's Windows gaps): blocks 26 swiftui.text-views, 27 swiftui.layout-priority, ... (see README.md).
Witness text lives here, once per case; new-case.py writes package/ + mac-source/ (Witness byte-identical) and pair.json.
usage: make_cases.py [case-substring ...]

Geometry shared by the interaction cases (E-series decisions in docs/sr1-decisions.md): the witness is a 240 x 200 pt frame centred in the 320 x 240 pt viewport, so
its origin is (40, 20) pt and a point (x, y) inside it is the client pixel ((40 + x) * 2.5, (20 + y) * 2.5). Rows have fixed frames; a Button is clicked at the
centre of its fixed frame. Text rows and Button rows are excluded from the pixel gate by name (Segoe UI vs SF glyphs, decision 2; Button width, decision 11) and are
gated by the semantic tree; the colour squares are gated by pixels."""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n\n"
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


def build(name, typename, body, plan, text_rows, button_rows, extra_exclude=(), extra_cfg=None):
    steps, labels = phase_steps(plan)
    pair = semantic(labels, text_rows, button_rows, extra_exclude)
    if extra_cfg: pair.update(extra_cfg)
    case(name, typename, body, pair, steps)




def btn(label, action, h=32):   # 32 pt: the 24 pt button centres 4 pt in, so its label lands on whole even points
    return f'Button("{label}") {{ {action} }}.frame(width: 240, height: {h})'


def static(name, typename, body):
    name = name if "/" in name else "swiftui.text-views/" + name
    case(name, typename, f"""struct {typename}: View {{
    var body: some View {{
{body}
    }}
}}""")


R = "Rectangle().fill(Color.red)"
B = "Rectangle().fill(Color.blue)"
G = "Rectangle().fill(Color.green)"
SQUARES = "HStack(spacing: 0) { ForEach(0..<%s, id: \\.self) { _ in Rectangle().fill(%s).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)"

# =====================================================================================================================================================================
# block 26: swiftui.text-views (Text(verbatim:), AnyView, Color.clear, Color.opacity, State(initialValue:), single-child ViewBuilder, View.id, ViewModifier)
# =====================================================================================================================================================================
T = "Witness_tv_"
# Text(verbatim:) shows the string as written: no Markdown, no interpolation syntax. Glyphs are excluded (decision 2); the tree's names decide.
build("swiftui.text-views/text-verbatim-v1", T + "verbatim", r"""struct Witness_tv_verbatim: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "**bold** and *em* 100%").frame(width: 240, height: 20, alignment: .leading)
            Text(verbatim: "\\(x) {y} %@ [z](u)").frame(width: 240, height: 20, alignment: .leading)
            Text(verbatim: "plain").frame(width: 240, height: 20, alignment: .leading)
            Rectangle().fill(Color.red).frame(width: 240, height: 20)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}""", [("start", None)], [("a", 0, 20, 0), ("b", 20, 40, 0), ("c", 40, 60, 0)], [])

# Color.clear is invisible and has no ink: in a ZStack over colour, as a fill, as a background and as an overlay it changes nothing
static("color-clear-v1", T + "clear", f"""        ZStack(alignment: .topLeading) {{
            VStack(spacing: 0) {{ {R}.frame(width: 120, height: 40); {B}.frame(width: 120, height: 40); {G}.frame(width: 120, height: 40) }}
            Color.clear.frame(width: 120, height: 120)
            Rectangle().fill(Color.clear).frame(width: 60, height: 50)
            Rectangle().fill(Color.red).frame(width: 30, height: 20).overlay {{ Color.clear }}
        }}.frame(width: 240, height: 200, alignment: .topLeading)""")

# Color.opacity returns a Color: the fill takes it; alpha over white, over colour and stacked (0.5 * 0.5), semantic and rgb colours, and Color as a view
static("color-opacity-v1", T + "opacity", f"""        VStack(spacing: 0) {{
            HStack(spacing: 0) {{
                Rectangle().fill(Color.black.opacity(0.1)).frame(width: 60, height: 40)
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: 60, height: 40)
                Rectangle().fill(Color.red.opacity(0.5)).frame(width: 60, height: 40)
                Rectangle().fill(Color.blue.opacity(0.5).opacity(0.5)).frame(width: 60, height: 40)
            }}
            ZStack {{ {B}.frame(width: 240, height: 40); Rectangle().fill(Color.white.opacity(0.5)).frame(width: 120, height: 40); Color.black.opacity(0.3).frame(width: 60, height: 40) }}
            HStack(spacing: 0) {{
                Rectangle().fill(Color(red: 1, green: 0.5, blue: 0).opacity(0.5)).frame(width: 80, height: 40)
                Color.green.opacity(0.25).frame(width: 80, height: 40)
                Color.red.opacity(0).frame(width: 80, height: 40)
            }}
            Color.primary.opacity(0.1).frame(width: 240, height: 40)
        }}.frame(width: 240, height: 200, alignment: .topLeading)""")

# State(initialValue:)
build("swiftui.text-views/state-initial-v1", T + "state_initial", r"""struct Witness_tv_state_initial_inner: View {
    @State private var n: Int
    init(start: Int) { _n = State(initialValue: start) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Text("n=\(n)").frame(width: 240, height: 20, alignment: .leading)
            Button("Add") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_state_initial: View {
    var body: some View { Witness_tv_state_initial_inner(start: 3).frame(width: 240, height: 200, alignment: .top) }
}""", [("start", None), ("c1", (120, 46)), ("c2", (120, 46))], [("n", 10, 30, 0)], [(30, 62)])

# a single-child builder returns the child: a generic container whose default trailing view is built by { Trailing() }, laid out like the explicit form
case("swiftui.text-views/builder-single-v1", T + "builder_single", r"""struct Witness_tv_NoTrailing: View { var body: some View { Rectangle().fill(Color.red).frame(width: 20, height: 20) } }

struct Witness_tv_Header<Trailing: View>: View {
    let width: CGFloat
    let trailing: Trailing
    init(width: CGFloat, @ViewBuilder trailing: () -> Trailing) { self.width = width; self.trailing = trailing() }
    var body: some View {
        HStack(spacing: 0) { Rectangle().fill(Color.blue).frame(width: width, height: 20); Spacer(); trailing }.frame(width: 240, height: 20)
    }
}

extension Witness_tv_Header where Trailing == Witness_tv_NoTrailing {
    init(width: CGFloat) { self.init(width: width) { Witness_tv_NoTrailing() } }
}

struct Witness_tv_builder_single: View {
    var body: some View {
        VStack(spacing: 10) {
            Witness_tv_Header(width: 60)
            Witness_tv_Header(width: 100) { Rectangle().fill(Color.green).frame(width: 40, height: 20) }
            Witness_tv_Header(width: 30) { Rectangle().fill(Color.green).frame(width: 40, height: 20); Rectangle().fill(Color.red).frame(width: 10, height: 20) }
        }.frame(width: 240, height: 200, alignment: .top)
    }
}""")

# View.id(_:): the same id keeps @State, a new id restarts it (squares = the child's count)
build("swiftui.text-views/view-id-v1", T + "view_id", r"""struct Witness_tv_Tally: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Button("Tally") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_view_id: View {
    @State private var gen = 0
    @State private var other = 0
    var body: some View {
        VStack(spacing: 0) {
            Witness_tv_Tally().id(gen)
            Button("New id") { gen += 1 }.frame(width: 240, height: 32)
            Button("Same id") { other += 1 }.frame(width: 240, height: 32)
            Text("gen=\(gen) other=\(other)").frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}""", [("start", None), ("t1", (120, 26)), ("t2", (120, 26)), ("sameid", (120, 90)), ("t3", (120, 26)), ("newid", (120, 58)), ("t4", (120, 26))],
      [("g", 106, 126, 0)], [(10, 42), (42, 74), (74, 106)])

# AnyView: transparent; the same wrapped type keeps its state when the parent re-evaluates, another type is a new view (state restarts)
build("swiftui.text-views/anyview-v1", T + "anyview", r"""struct Witness_tv_CounterA: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Button("A+") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_CounterB: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.blue).frame(width: 8, height: 10) } }.frame(width: 240, height: 10, alignment: .leading)
            Button("B+") { n += 1 }.frame(width: 240, height: 32)
        }
    }
}

struct Witness_tv_anyview: View {
    @State private var useB = false
    @State private var bump = 0
    var body: some View {
        let shown: AnyView = useB ? AnyView(Witness_tv_CounterB()) : AnyView(Witness_tv_CounterA())
        return VStack(spacing: 0) {
            shown
            Button("Swap") { useB.toggle() }.frame(width: 240, height: 32)
            Button("Bump") { bump += 1 }.frame(width: 240, height: 32)
            Text("bump=\(bump)").frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}""", [("start", None), ("a1", (120, 26)), ("a2", (120, 26)), ("bump", (120, 90)), ("swapB", (120, 58)), ("b1", (120, 26)), ("swapA", (120, 58)), ("a0", None)],
      [("bump", 106, 126, 0)], [(10, 42), (42, 74), (74, 106)])

# ViewModifier: a modifier that pads and puts the content on a coloured ground; a modifier with a branch; one inside another
static("view-modifier-v1", T + "modifier", f"""        VStack(spacing: 10) {{
            {R}.frame(width: 40, height: 20).modifier(Witness_tv_Chip(ground: Color.blue, inset: 8))
            {G}.frame(width: 40, height: 20).modifier(Witness_tv_Maybe(on: true)).modifier(Witness_tv_Chip(ground: Color.red, inset: 4))
            {G}.frame(width: 40, height: 20).modifier(Witness_tv_Maybe(on: false))
        }}.frame(width: 240, height: 200, alignment: .top)""")
CASES["swiftui.text-views/view-modifier-v1"]["body"] = """struct Witness_tv_Chip: ViewModifier {
    let ground: Color
    let inset: CGFloat
    func body(content: Content) -> some View {
        ZStack { Rectangle().fill(ground).frame(width: 64, height: 40); content.padding(inset) }
    }
}

struct Witness_tv_Maybe: ViewModifier {
    let on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.opacity(0.5) } else { content }
    }
}

""" + CASES["swiftui.text-views/view-modifier-v1"]["body"]


# =====================================================================================================================================================================
# block 27: swiftui.layout-priority
# =====================================================================================================================================================================
# Flexible fixed-colour views (min 20, ideal 100, max 150) so the sizes are visible in pixels without text. The stacks are 200 pt along the main axis.
P = "Witness_lp_"
FLEX = "Rectangle().fill(%s).frame(minWidth: 20, idealWidth: 100, maxWidth: 150, minHeight: 20, idealHeight: 20, maxHeight: 20)"
FLEXV = "Rectangle().fill(%s).frame(minWidth: 40, idealWidth: 40, maxWidth: 40, minHeight: 20, idealHeight: 100, maxHeight: 150)"


def lp(name, rows, v=False):
    flex = FLEXV if v else FLEX
    body = "\n".join(rows)
    case("swiftui.layout-priority/" + name, P + name.replace("-", "_").replace("_v1", ""), f"""struct {P}{name.replace("-", "_").replace("_v1", "")}: View {{
    var body: some View {{
        VStack(spacing: 10) {{
{body}
        }}.frame(width: 240, height: 200, alignment: .top)
    }}
}}""")


def hrow(*items, spacing=0, width=200):
    return f"            HStack(spacing: {spacing}) {{ " + "; ".join(items) + f" }}.frame(width: {width}, height: 20)"


Rr, Bb, Gg, Oo = (FLEX % c for c in ("Color.red", "Color.blue", "Color.green", "Color.orange"))
lp("two-views-v1", [
    hrow(Rr, Bb),
    hrow(Rr, Bb + ".layoutPriority(1)"),
    hrow(Rr + ".layoutPriority(1)", Bb),
    hrow(Rr + ".layoutPriority(1)", Bb + ".layoutPriority(1)"),
    hrow(Rr + ".layoutPriority(-1)", Bb),
])
lp("three-levels-v1", [
    hrow(Rr, Bb, Gg),
    hrow(Rr + ".layoutPriority(2)", Bb + ".layoutPriority(1)", Gg),
    hrow(Rr, Bb + ".layoutPriority(2)", Gg + ".layoutPriority(1)"),
    hrow(Rr + ".layoutPriority(1)", Bb, Gg + ".layoutPriority(1)", Oo),
])
lp("fits-v1", [   # everything fits: a priority changes nothing
    hrow(Rr, Bb, width=300),
    hrow(Rr, Bb + ".layoutPriority(1)", width=300),
    hrow(Rr + ".layoutPriority(3)", Bb, spacing=8, width=300),
])
lp("through-wrappers-v1", [
    hrow(Rr, Bb + ".padding(4).layoutPriority(1)"),
    hrow(Rr, "Witness_lp_Wrapped()"),
    hrow(Rr, "ZStack { " + Bb + " }.layoutPriority(1)"),
    hrow(Rr + ".layoutPriority(1).padding(4)", Bb),
    hrow(Rr, Bb + ".layoutPriority(1).opacity(0.99)"),
    hrow(Rr, Bb + ".layoutPriority(1).frame(maxWidth: .infinity)"),
    hrow(Rr, Bb + ".layoutPriority(1).onAppear {}"),
])
CASES["swiftui.layout-priority/through-wrappers-v1"]["body"] = f"""struct Witness_lp_Wrapped: View {{
    var body: some View {{ {Bb}.layoutPriority(1) }}
}}

""" + CASES["swiftui.layout-priority/through-wrappers-v1"]["body"]
case("swiftui.layout-priority/vertical-v1", P + "vertical", f"""struct {P}vertical: View {{
    var body: some View {{
        HStack(spacing: 20) {{
            VStack(spacing: 0) {{ {FLEXV % "Color.red"}; {FLEXV % "Color.blue"}.layoutPriority(1) }}.frame(width: 40, height: 120)
            VStack(spacing: 0) {{ {FLEXV % "Color.red"}.layoutPriority(1); {FLEXV % "Color.blue"} }}.frame(width: 40, height: 120)
            VStack(spacing: 4) {{ {FLEXV % "Color.red"}; {FLEXV % "Color.blue"}; {FLEXV % "Color.green"}.layoutPriority(2) }}.frame(width: 40, height: 160)
        }}.frame(width: 240, height: 200, alignment: .top)
    }}
}}""")
# spacers and layout priority: a Spacer keeps its place (priority 0); a prioritised view takes what it asks for before the spacer
lp("with-spacer-v1", [
    hrow(Rr, "Spacer()", Bb + ".layoutPriority(1)"),
    hrow(Rr + ".layoutPriority(1)", "Spacer()", Bb),
    hrow(Rr, "Spacer(minLength: 30)", Bb + ".layoutPriority(1)", width=240),
    hrow(Rr, "Spacer()", Bb),
    hrow(Rr, "Spacer()", Bb, Gg),
    hrow(Rr, Bb, "Spacer()"),
    hrow(Rr, "Spacer()", Bb + ".layoutPriority(1)", Gg + ".layoutPriority(1)"),
])


# =====================================================================================================================================================================
# block 28: swiftui.system-font (Font.system(size:weight:), the text styles, nine weights, Font.width, lineLimit(n), truncation)
# =====================================================================================================================================================================
# Glyph pixels are excluded by name (decision 2: Segoe UI vs SF); the text gate is the position gate of decision 19 per row (first glyph top and baseline, first ink column, ink bbox,
# colour) with tolerances measured per row and carried with a reason (decision F1), plus the line count and "the ink stays in its frame" (F2). Rows are 240 pt wide and
# leading aligned, each row's frame taller than its font's line so no two rows' ink meets.
SF = "Witness_sf_"
TXT = "Hxg Overview"


def font_rows(name, typename, rows, row_h, tolerance=None, lines=False, max_right=None, reason="", frame_w=240):
    """rows: [(font expr, text, extra modifiers)]; row i is the text in a frame_w x row_h frame, leading. One position region per row."""
    n = len(rows)
    body = ",\n".join(f'            Text("{t}"){f}{m}.frame(width: {frame_w}, height: {row_h}, alignment: .leading)'.replace(",\n", "\n") for f, t, m in rows)
    body = "\n".join(f'            Text("{t}"){f}{m}.frame(width: {frame_w}, height: {row_h}, alignment: .leading)' for f, t, m in rows)
    case("swiftui.system-font/" + name, SF + name.replace("-", "_").replace("_v1", ""), f"""struct {SF}{name.replace("-", "_").replace("_v1", "")}: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 0) {{
{body}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}""")
    regions = [{"name": f"row {i}", "rect": rect(0, i * row_h, frame_w, (i + 1) * row_h), "align": "leading"} for i in range(n)]
    pos = {"align": "leading", "reason": reason or "Segoe UI vs SF (decision 2): measured per row, see decision F1"}
    pos.update({"firstInkYTolerancePx": 5, "baselineTolerancePx": 5, "inkCentreYTolerancePx": 5, "firstInkXTolerancePx": 3})
    if lines: pos["lines"] = True
    if max_right is not None: pos["maxInkRightPx"] = rect(max_right, 0, max_right, 0)[0]
    ex = [{"name": f"row {i} glyph region (Segoe UI vs SF, decision 2); gated by the position gate of decision 19", "rect": rg["rect"]} for i, rg in enumerate(regions)]
    CASES["swiftui.system-font/" + name]["pair"] = {"textColourGate": {"tolerance": 40, "regions": regions, "position": pos}, "excludeRects": ex,
        "semanticGate": {"fields": ["role", "name", "count", "order"], "scope": "main", "phases": [""]}}
    CASES["swiftui.system-font/" + name]["steps"] = [{"op": "wait", "ms": 600}]


def f(size, weight="regular"):
    return f'.font(Font.system(size: {size}, weight: .{weight}))'


font_rows("sizes-v1", None, [(f(s), TXT, "") for s in (11, 12, 13, 15, 18)], 40)
font_rows("sizes-large-v1", None, [(f(s), TXT, "") for s in (24, 28, 32)], 60)
font_rows("weights-v1", None, [(f(18, w), TXT, "") for w in ("ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black")], 22)
font_rows("fractional-v1", None, [(f(s, w), TXT, "") for s, w in ((11.5, "regular"), (12.5, "regular"), (11.5, "semibold"), (13, "medium"))], 40)
font_rows("styles-large-v1", None, [(f"{'.font(.' + st + ')'}", TXT, "") for st in ("largeTitle", "title", "title2", "title3", "headline")], 36)
font_rows("styles-small-v1", None, [(f"{'.font(.' + st + ')'}", TXT, "") for st in ("subheadline", "body", "callout", "footnote", "caption", "caption2")], 24)
font_rows("style-weight-v1", None, [(".font(.body.weight(.bold))", TXT, ""), (".font(.headline.weight(.regular))", TXT, ""), (".font(.title3.weight(.semibold))", TXT, "")], 40)
LONG = "Overview of memory pressure and swap activity across every running process"
font_rows("truncate-v1", None, [(f(12), LONG, ".lineLimit(1)"), (f(11.5), LONG, ".lineLimit(1)"), (f(13, "semibold"), LONG, ".lineLimit(1)"), (f(18), LONG, ".lineLimit(1)"),
                               (f(12), "Short", ".lineLimit(1)")], 40, max_right=240)
CASES["swiftui.system-font/truncate-v1"]["body"] = CASES["swiftui.system-font/truncate-v1"]["body"].replace('Text("%s").font(Font.system(size: 12, weight: .regular)).lineLimit(1).frame(width: 240' % LONG, 'Text("%s").font(Font.system(size: 12, weight: .regular)).lineLimit(1).frame(width: 240' % LONG, 1)
font_rows("line-limit-v1", None, [(f(12), LONG, ".lineLimit(2)"), (f(12), LONG, ".lineLimit(3)"), (f(12), "Overview of memory pressure", ".lineLimit(3)")], 60, lines=True, max_right=110, frame_w=110)


# =====================================================================================================================================================================
# block 31: swiftui.paint-states (transparent fills, dark Divider); full-viewport witnesses (320 x 240) on the blocks-17-20 style host, light and dark
# =====================================================================================================================================================================
PS = "Witness_ps_"


def full(name, typename, content, dark=False):
    """a 320 x 240 witness filling the viewport with the window background; dark: the host's darkAqua window and the root colour scheme dark"""
    scheme = ".environment(\\.colorScheme, .dark)" if dark else ""
    case("swiftui.paint-states/" + name, typename, f"""struct {typename}: View {{
    var body: some View {{
        ZStack(alignment: .topLeading) {{
            Rectangle().fill(.background)
{content}
        }}
        .frame(width: 320, height: 240){scheme}
    }}
}}""", dark=("darkAqua", "dark") if dark else ("aqua", "light"))


# transparent fills must leave what is beneath them untouched (Color.clear, alpha 0 and 0.001, the hit area under a plain Button) and draw nothing of their own
TRANSPARENT = """            VStack(spacing: 0) {
                Rectangle().fill(Color.red).frame(width: 300, height: 30)
                ZStack { Rectangle().fill(Color.blue).frame(width: 300, height: 30); Color.clear.frame(width: 300, height: 30) }
                ZStack { Rectangle().fill(Color.green).frame(width: 300, height: 30); Rectangle().fill(Color.black.opacity(0.001)).frame(width: 300, height: 30) }
                ZStack { Rectangle().fill(Color.orange).frame(width: 300, height: 30); Color.red.opacity(0).frame(width: 300, height: 30) }
                ZStack { Rectangle().fill(Color.purple).frame(width: 300, height: 30); Rectangle().fill(Color.clear).frame(width: 150, height: 30) }
                ZStack { Rectangle().fill(Color.gray).frame(width: 300, height: 30); Color.black.opacity(0.01).frame(width: 300, height: 30) }
                Button { } label: { ZStack { Color.black.opacity(0.001); Rectangle().fill(Color.pink).frame(width: 40, height: 20) }.frame(width: 300, height: 30) }.buttonStyle(.plain)
                Color.clear.frame(width: 300, height: 30)
            }.padding(10)"""
full("transparent-fills-v1", PS + "transparent", TRANSPARENT)
full("transparent-fills-dark-v1", PS + "transparent_dark", TRANSPARENT, dark=True)
DIV = """            VStack(spacing: 10) {
                Divider().frame(width: 200)
                ZStack { Rectangle().fill(Color.blue).frame(width: 200, height: 40); Divider() }.frame(width: 200, height: 40)
                ZStack { Color.white.frame(width: 200, height: 40); Divider() }.frame(width: 200, height: 40)
                HStack(spacing: 10) { Rectangle().fill(Color.red).frame(width: 60, height: 40); Divider(); Rectangle().fill(Color.green).frame(width: 60, height: 40) }.frame(height: 40)
            }.padding(10)"""
full("divider-dark-v1", PS + "divider_dark", DIV, dark=True)
full("divider-light-v1", PS + "divider_light", DIV)


# =====================================================================================================================================================================
# block 30: swiftui.continuous-shape-large (pill and large radii, zero-size shapes). Gate: the shape edge band of decision 5 (edge-AA 32), exact elsewhere.
# =====================================================================================================================================================================
CS = "Witness_cl_"


def shp(name, typename, body):
    case("swiftui.continuous-shape-large/" + name, typename, f"""struct {typename}: View {{
    var body: some View {{
{body}
    }}
}}""")


def rr(r, w, h, fill="Color.blue", stroke=None):
    s = f"RoundedRectangle(cornerRadius: {r}, style: .continuous)"
    s = f"{s}.stroke({stroke}, lineWidth: 1)" if stroke else f"{s}.fill({fill})"
    return f"{s}.frame(width: {w}, height: {h})"


shp("pill-v1", CS + "pill", f"""        VStack(spacing: 8) {{
            {rr(99, 200, 40, "Color.red")}
            {rr(99, 200, 24, "Color.blue")}
            {rr(99, 200, 10, "Color.green")}
            {rr(99, 60, 60, "Color.orange")}
            {rr(99, 120, 6, "Color.purple")}
        }}.frame(width: 240, height: 200)""")
shp("radius-range-v1", CS + "range", f"""        VStack(spacing: 6) {{
            {rr(13.1, 100, 40, "Color.red")}
            {rr(15, 100, 40, "Color.blue")}
            {rr(18, 100, 40, "Color.green")}
            {rr(20, 100, 40, "Color.orange")}
            {rr(14, 100, 30, "Color.purple")}
        }}.frame(width: 240, height: 200)""")
shp("pill-stroke-v1", CS + "pill_stroke", f"""        VStack(spacing: 10) {{
            {rr(99, 200, 40, stroke="Color.red")}
            {rr(99, 200, 24, stroke="Color.blue")}
            {rr(99, 60, 60, stroke="Color.green")}
            {rr(15, 100, 40, stroke="Color.orange")}
        }}.frame(width: 240, height: 200)""")
shp("zero-size-v1", CS + "zero", f"""        VStack(spacing: 8) {{
            HStack(spacing: 4) {{ {rr(3, 0, 8)}; {rr(3, 20, 8, "Color.red")}; {rr(3, 0, 8, "Color.green")}; {rr(3, 20, 8, "Color.orange")} }}
            {rr(99, 100, 0, "Color.purple")}
            {rr(99, 100, 10, "Color.blue")}
            {rr(5, 0, 0)}
        }}.frame(width: 240, height: 200)""")


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
