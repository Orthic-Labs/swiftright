#!/usr/bin/env python3
"""Lane B text-input cases (blocks 13 swiftui.textfield, 14 swiftui.focus-state, 15 swiftui.ime-marked-text). Stamps, per case:
  <block>/<case>/package/{Package.swift, Sources/FactoryProbe/{Witness.swift, main.swift (text-hosts/windows), FactoryViewport.swift}}
  <block>/<case>/mac-source/Sources/MacHost/{Witness.swift (byte-identical), CaptureHost.swift (text-hosts/mac)}
  <block>/<case>/pair.json  (exclusions, semantic gate, interaction steps for the Windows F2 job and the Mac host, the in-process script)
usage: make-text-cases.py [case-substring ...]   (all cases when none is named)"""
import json, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
WINHOST = HERE.parent / "pilot-delivery-five-v1/shared-windows-host"
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\n#else\nimport SwiftUI\n#endif\n\n"
PACKAGE = (WINHOST / "stamp-case.py").read_text().split("PACKAGE = '''")[1].split("'''")[0].encode().decode("unicode_escape")

FIELD_RECT = [35, 30, 315, 80]   # text area of a 120 x 24 pt field padded by 10 pt, in capture px
# Field FRAMES in capture px for the text-origin gate (sr1-decisions #12): a 120 pt field padded by 10 pt (the 1 pt border is drawn outside the frame); a second field sits 8 pt below.
F1, F2 = [25, 25, 325, 85], [25, 105, 325, 165]
SEM = {"fields": ["role", "name", "value", "enabled"], "scope": "main", "roles": ["textfield", "text"]}


def cases():
    out = []
    def case(block, name, witness, wtype, **kw):
        kw.setdefault("origin", {"fields": [F1]})
        out.append(dict(block=block, name=name, witness=witness, wtype=wtype, **kw))
    pad = ".frame(width: 120).padding(10)"
    case("swiftui.textfield", "placeholder-v1", f'''struct Witness_tf_placeholder: View {{
    @State private var name = ""
    var body: some View {{ TextField("Name", text: $name).textFieldStyle(.roundedBorder){pad} }}
}}''', "Witness_tf_placeholder", exclude=[("placeholder 'Name' glyphs (Segoe UI vs SF, sr1-decisions #2)", FIELD_RECT)], sem=SEM)
    case("swiftui.textfield", "prompt-v1", f'''struct Witness_tf_prompt: View {{
    @State private var name = ""
    var body: some View {{ TextField("Name", text: $name, prompt: Text("Enter")).textFieldStyle(.roundedBorder){pad} }}
}}''', "Witness_tf_prompt", exclude=[("prompt 'Enter' glyphs", FIELD_RECT)], sem=SEM)
    case("swiftui.textfield", "filled-truncated-v1", '''struct Witness_tf_truncated: View {
    @State private var name = "HelloLongSentenceThatWillNotFit"
    var body: some View { TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 80).padding(10) }
}''', "Witness_tf_truncated", exclude=[("typed text glyphs, clipped at the field's text area", [35, 30, 215, 80])], sem=SEM, origin={"fields": [[25, 25, 225, 85]], "lastInk": True})
    case("swiftui.textfield", "plain-v1", '''struct Witness_tf_plain: View {
    @State private var name = "Hello"
    var body: some View { TextField("Name", text: $name).textFieldStyle(.plain).frame(width: 120).padding(10) }
}''', "Witness_tf_plain", exclude=[("plain field text (no bezel; the whole 16 pt line)", [25, 25, 325, 65])], sem=SEM, origin={"fields": [[25, 25, 325, 65]]})
    case("swiftui.textfield", "automatic-style-v1", f'''struct Witness_tf_automatic: View {{
    @State private var name = "Hello"
    var body: some View {{ TextField("Name", text: $name){pad} }}
}}''', "Witness_tf_automatic", exclude=[("typed text glyphs", FIELD_RECT)], sem=SEM)
    # --- block 13: the caret of a focused empty field starts at the text origin (the Mac draws no caret offscreen; its insertion point is read from the field editor, MAC_FACT caretXpx)
    case("swiftui.textfield", "caret-empty-v1", f'''struct Witness_tf_caret: View {{
    @State private var name = ""
    var body: some View {{ TextField("Name", text: $name).textFieldStyle(.roundedBorder){pad} }}
}}''', "Witness_tf_caret", steps=[{"op": "wait", "ms": 300}, {"op": "click", "x": 150, "y": 55}, {"op": "wait", "ms": 300}],
         sem=dict(SEM, pixels="report-only"), origin={"fields": [F1], "caret": "macFact", "caretTolerancePx": 0})
    # --- block 13, interaction: typing and Return (onSubmit commits the text the binding holds)
    click = {"op": "click", "x": 150, "y": 55}
    case("swiftui.textfield", "submit-v1", '''struct Witness_tf_submit: View {
    @State private var name = ""
    @State private var submitted = "none"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).onSubmit { submitted = name }
            Text("submitted: \\(submitted)")
            Text("typed: \\(name)")
        }.frame(width: 120).padding(10)
    }
}''', "Witness_tf_submit", steps=[click, {"op": "char", "text": "hi"}, {"op": "wait", "ms": 200}, {"op": "key", "key": "Enter"}, {"op": "wait", "ms": 300}],
         sem=dict(SEM, pixels="report-only"))
    # --- block 12 interaction: a click on a derived-binding switch writes the model; a constant-binding switch does not change
    case("swiftui.binding", "derived-click-v1", '''struct Witness_binding_click: View {
    @State private var count = 3
    var body: some View {
        let derived = Binding<Bool>(get: { count > 0 }, set: { count = $0 ? 1 : 0 })
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Derived", isOn: derived).labelsHidden().toggleStyle(.switch)
            Toggle("Constant", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
            Text("count: \\(count)")
        }
    }
}''', "Witness_binding_click", steps=[{"op": "wait", "ms": 300}, {"op": "click", "x": 60, "y": 30}, {"op": "wait", "ms": 250}, {"op": "dump", "label": "c1"}, {"op": "click", "x": 60, "y": 110}, {"op": "wait", "ms": 250}, {"op": "dump", "label": "c2"}, {"op": "wait", "ms": 200}],
         sem={"fields": ["role", "name", "toggle", "enabled"], "nameRoles": ["text"], "scope": "main", "roles": ["switch", "text"], "roleMap": {"AXCheckBox/AXToggle": "switch"}, "phases": ["c1", "c2", ""]},
         exclude=[("'count: 0' glyphs (Segoe UI vs SF, sr1-decisions #2)", [0, 150, 200, 215])], origin=None)
    # --- block 14 swiftui.focus-state: Tab order, programmatic focus, the Bool form. The Text shows the FocusState value (gated through the semantic tree).
    focus_tab = '''enum Field: Hashable { case first, second }

struct Witness_focus_tab: View {
    @State private var a = "one"
    @State private var b = "two"
    @FocusState private var focus: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("First", text: $a).textFieldStyle(.roundedBorder).focused($focus, equals: .first)
            TextField("Second", text: $b).textFieldStyle(.roundedBorder).focused($focus, equals: .second)
            Text("focus: \\(focus == .first ? "first" : focus == .second ? "second" : "none")")
        }.frame(width: 120).padding(10)
    }
}'''
    wait = lambda ms: {"op": "wait", "ms": ms}
    tab_steps = [wait(300), {"op": "key", "key": "Tab"}, wait(250), {"op": "dump", "label": "t1"}, {"op": "key", "key": "Tab"}, wait(250), {"op": "dump", "label": "t2"},
                 {"op": "key", "key": "Tab"}, wait(250), {"op": "dump", "label": "t3"}, {"op": "click", "x": 150, "y": 55}, wait(250), {"op": "dump", "label": "t4"},
                 {"op": "key", "key": "Tab"}, wait(250), {"op": "dump", "label": "t5"}, wait(200)]
    # t4 is a click on a field that is already editing with its whole text selected: the Mac harness leaves that selection (a synthetic mouseDown does not collapse it), Windows places the caret.
    # The final frame therefore follows a Tab (t5), where both sides show the second field selected; t4 stays a semantic phase.
    fsem = dict(SEM, pixels="report-only", phases=["t1", "t2", "t3", "t4", "t5", ""])
    case("swiftui.focus-state", "tab-order-v1", focus_tab, "Witness_focus_tab", steps=tab_steps, sem=fsem, origin={"fields": [F1, F2]})
    case("swiftui.focus-state", "shift-tab-v1", focus_tab.replace("Witness_focus_tab", "Witness_focus_shifttab"), "Witness_focus_shifttab",
         mac_steps=[{"op": "click", "x": 150, "y": 105}, wait(250), {"op": "key", "key": "Tab", "mods": ["shift"]}, wait(250)],
         win_steps=[wait(1800)], script=[{"op": "focus", "field": 1}, {"op": "key", "name": "tab", "mods": ["shift"]}], sem=fsem | {"phases": [""]}, origin={"fields": [F1, F2]})
    prog = '''enum Field: Hashable { case first, second }

struct Witness_focus_programmatic: View {
    @State private var a = "one"
    @State private var b = "two"
    @FocusState private var focus: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("First", text: $a).textFieldStyle(.roundedBorder).focused($focus, equals: .first)
            TextField("Second", text: $b).textFieldStyle(.roundedBorder).focused($focus, equals: .second)
            Text("focus: \\(focus == .first ? "first" : focus == .second ? "second" : "none")")
            Button("Second") { focus = .second }.frame(width: 100, height: 24)
            Button("Clear") { focus = nil }.frame(width: 100, height: 24)
            Button("First") { focus = .first }.frame(width: 100, height: 24)
        }.frame(width: 120).padding(10)
    }
}'''
    prog_steps = [wait(300), {"op": "click", "x": 150, "y": 275}, wait(250), {"op": "dump", "label": "p1"}, {"op": "click", "x": 150, "y": 345}, wait(250), {"op": "dump", "label": "p2"},
                  {"op": "click", "x": 150, "y": 415}, wait(250), {"op": "dump", "label": "p3"}, wait(200)]
    case("swiftui.focus-state", "programmatic-v1", prog, "Witness_focus_programmatic", steps=prog_steps, sem=dict(SEM, ignoreNames=["Second", "Clear", "First", "Focus", "Blur"], pixels="report-only", phases=["p1", "p2", "p3", ""]), origin={"fields": [F1, F2]})
    boolform = '''struct Witness_focus_bool: View {
    @State private var a = "one"
    @FocusState private var flag: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $a).textFieldStyle(.roundedBorder).focused($flag)
            Text("flag: \\(flag ? "true" : "false")")
            Button("Focus") { flag = true }.frame(width: 100, height: 24)
            Button("Blur") { flag = false }.frame(width: 100, height: 24)
        }.frame(width: 120).padding(10)
    }
}'''
    case("swiftui.focus-state", "bool-form-v1", boolform, "Witness_focus_bool",
         steps=[wait(300), {"op": "click", "x": 150, "y": 205}, wait(250), {"op": "dump", "label": "b1"}, {"op": "click", "x": 150, "y": 275}, wait(250), {"op": "dump", "label": "b2"}, wait(200)],
         sem=dict(SEM, ignoreNames=["Second", "Clear", "First", "Focus", "Blur"], pixels="report-only", phases=["b1", "b2", ""]))
    # --- block 15 swiftui.ime-marked-text: the binding during composition. Windows: in-process script (ime_replace_and_mark / ime_replace / unmark through the product TextStore);
    # Mac: NSTextInputClient on the field editor (setMarkedText / insertText), no input method involved.
    ime = '''struct Witness_ime: View {
    @State private var text = "ab"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $text).textFieldStyle(.roundedBorder)
            Text("bound: \\(text)")
        }.frame(width: 120).padding(10)
    }
}'''
    def imecase(name, script, mac):
        wt = "Witness_ime_" + name.split("-")[1]
        case("swiftui.ime-marked-text", name, ime.replace("Witness_ime", wt), wt, win_steps=[wait(2200)], script=script, mac_steps=[{"op": "click", "x": 150, "y": 55}, wait(250)] + mac + [wait(250)],
             sem=dict(SEM, pixels="report-only"))
    imecase("ime-composing-v1", [{"op": "focus", "field": 0}, {"op": "compose", "text": "ni"}], [{"op": "ime", "action": "compose", "text": "ni"}])
    imecase("ime-commit-v1", [{"op": "focus", "field": 0}, {"op": "compose", "text": "ni"}, {"op": "commit", "text": "\u4f60"}], [{"op": "ime", "action": "compose", "text": "ni"}, {"op": "ime", "action": "commit", "text": "\u4f60"}])
    imecase("ime-cancel-v1", [{"op": "focus", "field": 0}, {"op": "compose", "text": "ni"}, {"op": "cancel"}], [{"op": "ime", "action": "compose", "text": "ni"}, {"op": "ime", "action": "cancel"}])
    imecase("ime-recompose-v1", [{"op": "focus", "field": 0}, {"op": "compose", "text": "n"}, {"op": "compose", "text": "ni"}, {"op": "compose", "text": "\u4f60"}],
            [{"op": "ime", "action": "compose", "text": "n"}, {"op": "ime", "action": "compose", "text": "ni"}, {"op": "ime", "action": "compose", "text": "\u4f60"}])
    return out


def stamp(c):
    d = HERE / c["block"] / c["name"]
    pkg = d / "package/Sources/FactoryProbe"; mac = d / "mac-source/Sources/MacHost"
    pkg.mkdir(parents=True, exist_ok=True); mac.mkdir(parents=True, exist_ok=True)
    for old in list(pkg.glob("*.swift")) + list(mac.glob("*.swift")):
        old.unlink()
    witness = HEADER + c["witness"] + "\n"
    (pkg / "Witness.swift").write_text(witness); (mac / "Witness.swift").write_text(witness)
    script = json.dumps(c.get("script", []), separators=(",", ":"))
    expr = f'{c["wtype"]}()'
    win = (HERE / "text-hosts/windows/CaptureHost.template.swift").read_text()
    win = win.replace("@@WITNESS@@", expr).replace("@@CENTERED@@", "false").replace("@@DARK@@", "false").replace("@@SCRIPT@@", script.replace("\\", "\\\\").replace('"', '\\"'))
    assert "@@" not in win
    (pkg / "main.swift").write_text(win)
    shutil.copy(WINHOST / "FactoryViewport.swift", pkg / "FactoryViewport.swift")
    (d / "package/Package.swift").write_text(PACKAGE)
    m = (HERE / "text-hosts/mac/CaptureHost.template.swift").read_text().replace("@@WITNESS@@", expr).replace("@@SETTLE@@", "0.3")
    assert "@@" not in m
    (mac / "CaptureHost.swift").write_text(m)
    pj = {}
    if c.get("exclude"):
        pj["excludeRects"] = [{"name": n, "rect": r} for n, r in c["exclude"]]
    if c.get("sem"):
        pj["semanticGate"] = c["sem"]
    if c.get("origin"):
        pj["textOriginGate"] = c["origin"]
    win_steps = c.get("win_steps", c.get("steps")); mac_steps = c.get("mac_steps", c.get("steps"))
    if win_steps:
        pj["steps"] = win_steps
    if mac_steps:
        pj["macArgs"] = ["--steps", json.dumps(mac_steps, separators=(",", ":"))]
    if not win_steps and c.get("sem"):
        pj["steps"] = [{"op": "wait", "ms": 300}]   # the F2 interact job dumps the UIA tree for the semantic gate; the Mac side stays never-shown
    (d / "pair.json").write_text(json.dumps(pj, indent=1) + "\n")
    print("stamped", d.relative_to(HERE))


if __name__ == "__main__":
    want = sys.argv[1:]
    for c in cases():
        if not want or any(w in f'{c["block"]}/{c["name"]}' for w in want):
            stamp(c)
