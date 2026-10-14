#!/usr/bin/env python3
"""Creates (or re-stamps) every blocks-21-23 case (SR1 round 4): block 21 swiftui.observation, block 22 swiftui.task-asyncstream, block 23 swiftui.spacer-divider.
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


def case(name, typename, body, pair=None, steps=None):
    CASES[name] = dict(type=typename, body=body, pair=pair, steps=steps)


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


# =====================================================================================================================================================================
# block 21: swiftui.observation
# =====================================================================================================================================================================
# Box.stamp is a plain global the view bodies READ but observation does not track. A Button bumps it before it changes the model, so a body that re-ran after the click
# shows the new stamp (in a colour square and in its text) and a body that did not re-run still shows the old one: that is how "re-renders only the dependent views"
# is made visible, in pixels and in the tree, on both sides. Colours: stamp 0 grey, 1 red, 2 green, 3 blue, 4 orange, 5 purple.
STAMP = """enum Box { nonisolated(unsafe) static var stamp = 0 }

func swatch(_ s: Int) -> Color {
    switch s %% 6 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    case 4: return Color.orange
    case 5: return Color.purple
    default: return Color.gray
    }
}

"""
SQ = "Rectangle().fill(%s).frame(width: 40, height: 20)"


def row(expr_colour, text):
    return f'HStack(spacing: 0) {{ {SQ % expr_colour}; Text({text}).frame(width: 200, height: 20, alignment: .leading) }}.frame(width: 240, height: 20)'


def btn(label, action, h=32):   # 32 pt: the 24 pt button centres 4 pt in, so its label lands on whole even points (an odd offset puts the label on a half-pixel tie the Windows text-run match refuses)
    return f'Button("{label}") {{ {action} }}.frame(width: 240, height: {h})'


# 1. one property, one reader (invalidation at all): a meter of squares and a text follow the model
T = "Witness_obs_"
BODY = STAMP + """@Observable final class CounterModel { var a = 0 }

struct %(t)s: View {
    @State private var model = CounterModel()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(0..<model.a, id: \\.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 240, height: 10)
            Text("a=\\(model.a)").frame(width: 240, height: 20)
            Button("Add") { model.a += 1 }.frame(width: 240, height: 40)
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
build("swiftui.observation/property-render-v1", T + "property", BODY % dict(t=T + "property"),
      [("c1", (120, 50)), ("c2", (120, 50)), ("c3", (120, 50))],
      [("a text", 10, 30, 0)], [(30, 70)])

# 2. two readers of two properties of ONE model: changing b must not re-run the reader of a, and the reverse (the negative case: a view that must NOT update)
BODY = STAMP + """@Observable final class PairModel { var a = 0; var b = 0 }

struct ReaderA: View {
    let m: PairModel
    var body: some View { %(rowa)s }
}

struct ReaderB: View {
    let m: PairModel
    var body: some View { %(rowb)s }
}

struct %(t)s: View {
    @State private var m = PairModel()
    var body: some View {
        VStack(spacing: 0) {
            ReaderA(m: m)
            ReaderB(m: m)
            %(bb)s
            %(ba)s
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
rowa = row("swatch(Box.stamp)", '"A a=\\(m.a) s=\\(Box.stamp)"')
rowb = row("swatch(Box.stamp)", '"B b=\\(m.b) s=\\(Box.stamp)"')
build("swiftui.observation/independent-readers-v1", T + "independent",
      BODY % dict(t=T + "independent", rowa=rowa, rowb=rowb, bb=btn("B+", "Box.stamp += 1; m.b += 1"), ba=btn("A+", "Box.stamp += 1; m.a += 1")),
      [("start", None), ("b1", (120, 56)), ("a1", (120, 88)), ("b2", (120, 56))],
      [("A", 0, 20, 40), ("B", 20, 40, 40)], [(40, 72), (72, 104)])

# 3. nested models: the reader of outer.inner.v follows a swapped inner model; the retired inner model and an unread outer property change nothing
BODY = STAMP + """@Observable final class Inner { var v = 0; init(_ v: Int = 0) { self.v = v } }
@Observable final class Outer { var inner = Inner(); var other = 0 }

struct InnerReader: View {
    let o: Outer
    var body: some View { %(row)s }
}

struct %(t)s: View {
    @State private var o = Outer()
    @State private var retired: Inner? = nil
    var body: some View {
        VStack(spacing: 0) {
            InnerReader(o: o)
            %(b1)s
            %(b2)s
            %(b3)s
            %(b4)s
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
rown = row("swatch(Box.stamp)", '"inner=\\(o.inner.v) s=\\(Box.stamp)"')
build("swiftui.observation/nested-models-v1", T + "nested",
      BODY % dict(t=T + "nested", row=rown, b1=btn("Inner+", "Box.stamp += 1; o.inner.v += 1"), b2=btn("Other+", "Box.stamp += 1; o.other += 1"),
                  b3=btn("Swap", "Box.stamp += 1; retired = o.inner; o.inner = Inner(100)"), b4=btn("Old+", "Box.stamp += 1; retired?.v += 1")),
      [("start", None), ("inner", (120, 36)), ("other", (120, 68)), ("swap", (120, 100)), ("old", (120, 132)), ("new", (120, 36))],
      [("inner", 0, 20, 40)], [(20, 52), (52, 84), (84, 116), (116, 148)])

# 4. a collection of models: toggling one item re-runs that row only; appending re-runs the list, not the rows it already shows
BODY = STAMP + """@Observable final class Item { let id: Int; var done = false; init(_ id: Int) { self.id = id } }
@Observable final class Store { var items: [Item] = [Item(0), Item(1), Item(2)] }

struct ItemRow: View {
    let item: Item
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(item.done ? Color.green : Color.red).frame(width: 20, height: 20)
            Rectangle().fill(swatch(Box.stamp)).frame(width: 20, height: 20)
            Text("item \\(item.id) done=\\(item.done ? 1 : 0) s=\\(Box.stamp)").frame(width: 200, height: 20, alignment: .leading)
        }.frame(width: 240, height: 20)
    }
}

struct ItemList: View {
    let store: Store
    var body: some View {
        VStack(spacing: 0) { ForEach(store.items, id: \\.id) { item in ItemRow(item: item) } }
    }
}

struct %(t)s: View {
    @State private var store = Store()
    var body: some View {
        VStack(spacing: 0) {
            ItemList(store: store).frame(width: 240, height: 100, alignment: .top)
            %(b1)s
            %(b2)s
            %(b3)s
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
build("swiftui.observation/collection-of-models-v1", T + "collection",
      BODY % dict(t=T + "collection", b1=btn("Toggle 1", "Box.stamp += 1; store.items[1].done.toggle()"), b2=btn("Append", "Box.stamp += 1; store.items.append(Item(store.items.count))"),
                  b3=btn("Toggle 3", "Box.stamp += 1; store.items[3].done.toggle()")),
      [("start", None), ("t1", (120, 116)), ("append", (120, 148)), ("t3", (120, 180)), ("t1b", (120, 116))],
      [(f"row {i}", 20 * i, 20 * i + 20, 40) for i in range(5)], [(100, 132), (132, 164), (164, 196)])

# 5. @Bindable: `$s.on` is a binding into a model's property (Button here, not a Toggle: the interaction host presses Buttons); it writes the model and the readers of that property follow
BODY = STAMP + """@Observable final class Settings { var on = false; var count = 0 }

struct Editor: View {
    @Bindable var s: Settings
    var body: some View {
        let on = $s.on
        Button("Flip") { Box.stamp += 1; on.wrappedValue.toggle() }.frame(width: 240, height: 32)
    }
}

struct OnReader: View {
    let s: Settings
    var body: some View { %(r1)s }
}

struct CountReader: View {
    let s: Settings
    var body: some View { %(r2)s }
}

struct %(t)s: View {
    @State private var s = Settings()
    var body: some View {
        VStack(spacing: 0) {
            Editor(s: s)
            OnReader(s: s)
            CountReader(s: s)
            %(b)s
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
r1 = row("s.on ? Color.green : Color.red", '"on=\\(s.on ? 1 : 0) s=\\(Box.stamp)"')
r2 = row("swatch(Box.stamp)", '"count=\\(s.count) s=\\(Box.stamp)"')
build("swiftui.observation/bindable-binding-v1", T + "bindable",
      BODY % dict(t=T + "bindable", r1=r1, r2=r2, b=btn("Count+", "Box.stamp += 1; s.count += 1")),
      [("start", None), ("flip", (120, 16)), ("count", (120, 88)), ("flop", (120, 16))],
      [("on", 32, 52, 40), ("count", 52, 72, 40)], [(0, 32), (72, 104)])

# 6. a computed property reads its stored properties: the reader of `total` follows both, the reader of `a` follows only a
BODY = STAMP + """@Observable final class Sum { var a = 0; var b = 0; var total: Int { a + b } }

struct TotalReader: View {
    let m: Sum
    var body: some View { %(r1)s }
}

struct AReader: View {
    let m: Sum
    var body: some View { %(r2)s }
}

struct %(t)s: View {
    @State private var m = Sum()
    var body: some View {
        VStack(spacing: 0) {
            TotalReader(m: m)
            AReader(m: m)
            %(b1)s
            %(b2)s
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
build("swiftui.observation/computed-dependency-v1", T + "computed",
      BODY % dict(t=T + "computed", r1=row("swatch(Box.stamp)", '"total=\\(m.total) s=\\(Box.stamp)"'), r2=row("swatch(Box.stamp)", '"a=\\(m.a) s=\\(Box.stamp)"'),
                  b1=btn("B+", "Box.stamp += 1; m.b += 1"), b2=btn("A+", "Box.stamp += 1; m.a += 1")),
      [("start", None), ("b1", (120, 56)), ("a1", (120, 88)), ("b2", (120, 56))],
      [("total", 0, 20, 40), ("a", 20, 40, 40)], [(40, 72), (72, 104)])

# =====================================================================================================================================================================
# block 22: swiftui.task-asyncstream
# =====================================================================================================================================================================
# The event pump is manual and deterministic: a stream whose continuation is yielded only by a Button the host clicks (one step = one event; Burst = three yields
# inside one click). Nothing waits on a wall-clock timer; the host's settle waits only give the main actor time to run what the click made runnable.
FEED = """enum Feed {
    static let pair = AsyncStream<Int>.makeStream()
    nonisolated(unsafe) static var script = [3, 1, 2]
    nonisolated(unsafe) static var sent = 0
    static func send() { Feed.pair.continuation.yield(script[sent %% script.count]); sent += 1 }
    static func burst() { send(); send(); send() }
    static func finish() { Feed.pair.continuation.finish() }
}

func swatch(_ v: Int) -> Color {
    switch v %% 4 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    default: return Color.gray
    }
}

"""
FEED2 = (FEED % ()).replace("%", "%%")   # FEED is a plain string once; BODY templates below are %-formatted again
TT = "Witness_task_"
SQ4 = "ForEach(0..<log.count, id: \\.self) { i in Rectangle().fill(swatch(log[i])).frame(width: 40, height: 20) }"

BODY = FEED2 + """struct %(t)s: View {
    @State private var value = 0
    @State private var phase = "idle"
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("value=\\(value) phase=\\(phase)").frame(width: 240, height: 20)
            %(b)s
        }.frame(width: 240, height: 200, alignment: .top)
        .task { phase = "running"; for await v in Feed.pair.stream { value = v }; phase = "done" }
    }
}"""
build("swiftui.task-asyncstream/stream-drives-state-v1", TT + "drives", BODY % dict(t=TT + "drives", b=btn("Next", "Feed.send()", 40)),
      [("start", None), ("e1", (120, 60)), ("e2", (120, 60)), ("e3", (120, 60)), ("e4", (120, 60))], [("value", 20, 40, 0)], [(40, 80)])

BODY = FEED2 + """struct %(t)s: View {
    @State private var log: [Int] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { %(sq)s }.frame(width: 240, height: 20, alignment: .leading)
            Text("log=\\(log.map { String($0) }.joined(separator: ","))").frame(width: 240, height: 20)
            %(b)s
        }.frame(width: 240, height: 200, alignment: .top)
        .task { for await v in Feed.pair.stream { log.append(v) } }
    }
}"""
build("swiftui.task-asyncstream/ordering-clicks-v1", TT + "order_clicks", BODY % dict(t=TT + "order_clicks", sq=SQ4, b=btn("Next", "Feed.send()", 40)),
      [("start", None), ("e1", (120, 60)), ("e2", (120, 60)), ("e3", (120, 60)), ("e4", (120, 60))], [("log", 20, 40, 0)], [(40, 80)])

BODY = FEED2 + """struct %(t)s: View {
    @State private var log: [Int] = []
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { %(sq)s }.frame(width: 240, height: 20, alignment: .leading)
            Text("log=\\(log.map { String($0) }.joined(separator: ","))").frame(width: 240, height: 20)
            %(b1)s
            %(b2)s
        }.frame(width: 240, height: 200, alignment: .top)
        .task { for await v in Feed.pair.stream { log.append(v) } }
    }
}"""
build("swiftui.task-asyncstream/ordering-burst-v1", TT + "order_burst", BODY % dict(t=TT + "order_burst", sq=SQ4, b1=btn("Burst", "Feed.burst()", 40), b2=btn("Next", "Feed.send()", 40)),
      [("start", None), ("burst", (120, 60)), ("next", (120, 100)), ("burst2", (120, 60))], [("log", 20, 40, 0)], [(40, 80), (80, 120)])

# the negative case: a task cancelled because its view disappeared must not apply an event sent afterwards. The loop ends on cancellation and the statement after it
# still runs (SwiftUI cancels, it does not abort), so `ended` is written by the cancelled task and an event is not.
BODY = FEED2 + """struct Listener: View {
    @Binding var value: Int
    @Binding var phase: String
    var body: some View {
        Rectangle().fill(Color.gray).frame(width: 240, height: 20)
            .task { for await v in Feed.pair.stream { value = v }; phase = "ended" }
    }
}

struct %(t)s: View {
    @State private var value = 0
    @State private var phase = "listening"
    @State private var shown = true
    var body: some View {
        VStack(spacing: 0) {
            if shown { Listener(value: $value, phase: $phase) } else { Rectangle().fill(Color.black).frame(width: 240, height: 20) }
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("value=\\(value) phase=\\(phase) shown=\\(shown ? 1 : 0)").frame(width: 240, height: 20)
            %(b1)s
            %(b2)s
        }.frame(width: 240, height: 200, alignment: .top)
    }
}"""
build("swiftui.task-asyncstream/cancel-on-disappear-v1", TT + "cancel", BODY % dict(t=TT + "cancel", b1=btn("Next", "Feed.send()", 40), b2=btn("Hide", "shown = false", 40)),
      [("start", None), ("e1", (120, 80)), ("hide", (120, 120)), ("late", (120, 80)), ("late2", (120, 80))], [("value", 40, 60, 0)], [(60, 100), (100, 140)])

# task(id:) restarts on an id change: the old run's stream is abandoned (an event sent to it afterwards must not apply), the new run listens to its own stream
BODY = """enum Feeds {
    nonisolated(unsafe) static var streams: [Int: AsyncStream<Int>] = [:]
    nonisolated(unsafe) static var conts: [Int: AsyncStream<Int>.Continuation] = [:]
    nonisolated(unsafe) static var sent = 0
    static func stream(_ gen: Int) -> AsyncStream<Int> {
        if let s = streams[gen] { return s }
        let p = AsyncStream<Int>.makeStream()
        streams[gen] = p.stream; conts[gen] = p.continuation
        return p.stream
    }
    static func send(_ gen: Int) { _ = stream(gen); sent += 1; conts[gen]?.yield(sent) }
}

func swatch(_ v: Int) -> Color {
    switch v %% 4 {
    case 1: return Color.red
    case 2: return Color.green
    case 3: return Color.blue
    default: return Color.gray
    }
}

struct %(t)s: View {
    @State private var gen = 0
    @State private var value = 0
    @State private var started = "0"
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("gen=\\(gen) value=\\(value) started=\\(started)").frame(width: 240, height: 20)
            %(b1)s
            %(b2)s
            %(b3)s
        }.frame(width: 240, height: 200, alignment: .top)
        .task(id: gen) { if gen > 0 { started += "," + String(gen) }; for await v in Feeds.stream(gen) { value = v } }
    }
}"""
build("swiftui.task-asyncstream/task-id-restart-v1", TT + "restart", BODY % dict(t=TT + "restart", b1=btn("Send", "Feeds.send(gen)", 40), b2=btn("Restart", "gen += 1", 40), b3=btn("Old", "Feeds.send(gen - 1)", 40)),
      [("start", None), ("e1", (120, 60)), ("restart", (120, 100)), ("old", (120, 140)), ("e2", (120, 60))], [("value", 20, 40, 0)], [(40, 80), (80, 120), (120, 160)])

# finishing the stream ends the loop and the code after it runs
BODY = FEED2 + """struct %(t)s: View {
    @State private var value = 0
    @State private var phase = "idle"
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(swatch(value)).frame(width: 240, height: 20)
            Text("value=\\(value) phase=\\(phase)").frame(width: 240, height: 20)
            %(b1)s
            %(b2)s
        }.frame(width: 240, height: 200, alignment: .top)
        .task { phase = "running"; for await v in Feed.pair.stream { value = v }; phase = "done" }
    }
}"""
build("swiftui.task-asyncstream/stream-finish-v1", TT + "finish", BODY % dict(t=TT + "finish", b1=btn("Next", "Feed.send()", 40), b2=btn("Finish", "Feed.finish()", 40)),
      [("start", None), ("e1", (120, 60)), ("finish", (120, 100)), ("after", (120, 60))], [("value", 20, 40, 0)], [(40, 80), (80, 120)])

# =====================================================================================================================================================================
# block 23: swiftui.spacer-divider (pixels: exact / edge-aa under the existing rules, decisions 5 and 12-ties)
# =====================================================================================================================================================================
TS = "Witness_sd_"


def static(name, typename, body):
    case(f"swiftui.spacer-divider/{name}", typename, f"""struct {typename}: View {{
    var body: some View {{
{body}
    }}
}}""")


R = "Rectangle().fill(Color.red)"
B = "Rectangle().fill(Color.blue)"
G = "Rectangle().fill(Color.green)"
static("spacer-hstack-v1", TS + "spacer_hstack", f"        HStack(spacing: 0) {{ {R}.frame(width: 40, height: 40); Spacer(); {B}.frame(width: 40, height: 40) }}.frame(width: 200, height: 40)")
static("spacer-vstack-v1", TS + "spacer_vstack", f"        VStack(spacing: 0) {{ {R}.frame(width: 40, height: 40); Spacer(); {B}.frame(width: 40, height: 40) }}.frame(width: 40, height: 200)")
static("spacer-minlength-v1", TS + "spacer_minlength", f"""        VStack(spacing: 10) {{
            HStack(spacing: 0) {{ {R}.frame(width: 60, height: 20); Spacer(minLength: 50); {B}.frame(width: 60, height: 20) }}.frame(width: 150, height: 20)
            HStack(spacing: 0) {{ {R}.frame(width: 60, height: 20); Spacer(minLength: 10); {B}.frame(width: 60, height: 20) }}.frame(width: 200, height: 20)
            HStack(spacing: 0) {{ {R}.frame(width: 60, height: 20); Spacer(minLength: 100); {B}.frame(width: 60, height: 20) }}.frame(width: 200, height: 20)
        }}""")
static("spacer-flexible-v1", TS + "spacer_flexible", f"""        VStack(spacing: 10) {{
            HStack(spacing: 0) {{ Spacer(); {R}.frame(width: 30, height: 20); Spacer(); {B}.frame(width: 30, height: 20); Spacer(); {G}.frame(width: 30, height: 20); Spacer() }}.frame(width: 200, height: 20)
            HStack(spacing: 0) {{ {R}.frame(width: 30, height: 20); Spacer(); {B}.frame(width: 30, height: 20); Spacer(minLength: 40); {G}.frame(width: 30, height: 20) }}.frame(width: 200, height: 20)
            HStack(spacing: 0) {{ Spacer(); {R}.frame(width: 30, height: 20) }}.frame(width: 200, height: 20)
        }}""")
static("spacer-default-length-v1", TS + "spacer_default", f"""        VStack(spacing: 4) {{
            HStack {{ {R}.frame(width: 40, height: 20); Spacer(); {B}.frame(width: 40, height: 20) }}.frame(width: 100, height: 20)
            HStack {{ {R}.frame(width: 40, height: 20); Spacer(); {B}.frame(width: 40, height: 20) }}.frame(width: 84, height: 20)
            HStack {{ {R}.frame(width: 40, height: 20); Spacer(); {B}.frame(width: 40, height: 20) }}.frame(width: 80, height: 20)
            HStack(spacing: 0) {{ {R}.frame(width: 40, height: 20); Spacer(); {B}.frame(width: 40, height: 20) }}.frame(width: 80, height: 20)
            HStack {{ {R}.frame(width: 40, height: 20); Spacer(minLength: 0); {B}.frame(width: 40, height: 20) }}.frame(width: 80, height: 20)
            HStack {{ {R}.frame(width: 30, height: 20); {B}.frame(width: 30, height: 20); Spacer(minLength: 0); {G}.frame(width: 30, height: 20) }}.frame(width: 100, height: 20)
            VStack {{ {R}.frame(width: 20, height: 20); Spacer(); {B}.frame(width: 20, height: 20) }}.frame(width: 20, height: 44)
        }}""")
static("spacer-fixed-frame-v1", TS + "spacer_fixed", f"""        VStack(spacing: 10) {{
            HStack(spacing: 0) {{ {R}.frame(width: 40, height: 20); Spacer().frame(width: 30); {B}.frame(width: 40, height: 20); Spacer() }}.frame(width: 200, height: 20)
            HStack(spacing: 0) {{ Spacer().frame(width: 20, height: 20); {R}.frame(width: 40, height: 20); Spacer(); Spacer().frame(width: 20, height: 20) }}.frame(width: 200, height: 20)
        }}""")

static("spacer-spacing-v1", TS + "spacer_spacing", f"""        VStack(spacing: 10) {{
            HStack(spacing: 20) {{ {R}.frame(width: 40, height: 20); Spacer(); {B}.frame(width: 40, height: 20) }}.frame(width: 80, height: 20)
            HStack(spacing: 20) {{ {R}.frame(width: 30, height: 20); {B}.frame(width: 30, height: 20); Spacer(); {G}.frame(width: 30, height: 20) }}.frame(width: 200, height: 20)
            HStack(spacing: 20) {{ {R}.frame(width: 30, height: 20); Spacer(minLength: 0); {B}.frame(width: 30, height: 20); Spacer(minLength: 0); {G}.frame(width: 30, height: 20) }}.frame(width: 100, height: 20)
            HStack(spacing: 4) {{ {R}.frame(width: 30, height: 20); Spacer(minLength: 0); {B}.frame(width: 30, height: 20) }}.frame(width: 60, height: 20)
        }}""")
static("spacer-ties-v1", TS + "spacer_ties", f"""        VStack(spacing: 0) {{
            HStack(spacing: 0) {{ {R}.frame(width: 3, height: 10); Spacer().frame(width: 5); {B}.frame(width: 7, height: 10); Spacer(minLength: 9); {R}.frame(width: 1, height: 10); Spacer().frame(width: 27); {B}.frame(width: 11, height: 10) }}.frame(width: 200, alignment: .leading)
            Spacer().frame(height: 5)
            HStack(spacing: 0) {{ {R}.frame(width: 5, height: 10); Spacer(); {B}.frame(width: 9, height: 10); Spacer().frame(width: 13); {R}.frame(width: 3, height: 10) }}.frame(width: 111, alignment: .leading)
            Spacer().frame(height: 7)
            HStack(alignment: .top, spacing: 0) {{
                VStack(spacing: 0) {{ {R}.frame(width: 10, height: 3); Spacer().frame(height: 5); {B}.frame(width: 10, height: 7); Spacer(minLength: 9); {R}.frame(width: 10, height: 1) }}
                Spacer().frame(width: 7)
                VStack(spacing: 0) {{ {B}.frame(width: 10, height: 27); Spacer(); {R}.frame(width: 10, height: 11) }}.frame(height: 71)
            }}
        }}""")
static("divider-horizontal-v1", TS + "divider_horizontal", f"        VStack(spacing: 0) {{ {R}.frame(width: 200, height: 40); Divider(); {B}.frame(width: 200, height: 40) }}.frame(width: 200)")
static("divider-vertical-v1", TS + "divider_vertical", f"        HStack(spacing: 0) {{ {R}.frame(width: 60, height: 80); Divider(); {B}.frame(width: 60, height: 80) }}.frame(height: 80)")
static("divider-vertical-fill-v1", TS + "divider_vfill", f"        HStack(spacing: 0) {{ {R}.frame(width: 60, height: 80); Divider(); {B}.frame(width: 60, height: 80) }}")
static("divider-spacing-v1", TS + "divider_spacing", f"        VStack {{ {R}.frame(width: 200, height: 30); Divider(); {B}.frame(width: 200, height: 30) }}.frame(width: 200)")
static("divider-ties-v1", TS + "divider_ties", f"""        VStack(spacing: 0) {{ {R}.frame(width: 100, height: 3); Divider(); {B}.frame(width: 100, height: 5); Divider(); {R}.frame(width: 100, height: 7); Divider(); {B}.frame(width: 100, height: 9); Divider() }}.frame(width: 100)""")
static("divider-over-colour-v1", TS + "divider_over", f"""        VStack(spacing: 10) {{
            ZStack {{ {B}.frame(width: 100, height: 40); Divider() }}.frame(width: 100, height: 40)
            ZStack {{ Color.black.frame(width: 100, height: 40); Divider() }}.frame(width: 100, height: 40)
        }}""")
static("divider-colour-v1", TS + "divider_colour", f"""        VStack(spacing: 10) {{
            Divider().frame(width: 160)
            Divider().overlay {{ Color.red }}.frame(width: 160)
            Divider().frame(width: 160, height: 12)
            HStack(spacing: 10) {{ Divider(); Divider().overlay {{ Color.red }}; Divider().frame(width: 12) }}.frame(height: 60)
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
            subprocess.check_call(cmd)


if __name__ == "__main__":
    main()
